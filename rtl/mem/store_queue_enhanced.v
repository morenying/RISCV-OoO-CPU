//=================================================================
// Module: store_queue_enhanced
// Description: Enhanced Store Queue (SQ)
//              16 entries (doubled from 8)
//              In-order store commitment
//              Store-to-load forwarding
//              Store buffer merging
// Requirements: 4.5, 4.6
//=================================================================

`timescale 1ns/1ps

module store_queue_enhanced #(
    parameter NUM_ENTRIES   = 16,
    parameter SQ_IDX_BITS   = 4,         // log2(16)
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Allocation Interface (from Rename stage)
    //=========================================================
    input  wire                     alloc_req_i,
    output wire                     alloc_ready_o,
    output wire [SQ_IDX_BITS-1:0]   alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  alloc_rob_idx_i,
    
    //=========================================================
    // Address Generation Interface (from AGU)
    //=========================================================
    input  wire                     agen_valid_i,
    input  wire [SQ_IDX_BITS-1:0]   agen_sq_idx_i,
    input  wire [ADDR_WIDTH-1:0]    agen_addr_i,
    input  wire [1:0]               agen_size_i,    // 00=byte, 01=half, 10=word
    
    //=========================================================
    // Data Ready Interface (from Execution)
    //=========================================================
    input  wire                     data_valid_i,
    input  wire [SQ_IDX_BITS-1:0]   data_sq_idx_i,
    input  wire [DATA_WIDTH-1:0]    data_value_i,
    
    //=========================================================
    // Store-to-Load Forwarding Interface (to Load Queue)
    //=========================================================
    input  wire                     fwd_req_valid_i,
    input  wire [ADDR_WIDTH-1:0]    fwd_req_addr_i,
    input  wire [1:0]               fwd_req_size_i,
    input  wire [ROB_IDX_BITS-1:0]  fwd_req_rob_idx_i,  // Load's ROB index
    
    output wire                     fwd_resp_valid_o,
    output wire [DATA_WIDTH-1:0]    fwd_resp_data_o,
    output wire                     fwd_resp_partial_o,  // Partial match
    output wire                     fwd_resp_match_o,    // Address match found
    
    //=========================================================
    // Commit Interface (from ROB)
    //=========================================================
    input  wire                     commit_valid_i,
    input  wire [SQ_IDX_BITS-1:0]   commit_sq_idx_i,
    
    //=========================================================
    // D-Cache Interface (for committed stores)
    //=========================================================
    output wire                     dcache_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    dcache_req_addr_o,
    output wire [DATA_WIDTH-1:0]    dcache_req_data_o,
    output wire [3:0]               dcache_req_byte_en_o,
    input  wire                     dcache_req_ready_i,
    
    output wire                     dcache_req_done_o,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire [ROB_IDX_BITS-1:0]  flush_rob_idx_i,
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     empty_o,
    output wire                     full_o,
    output wire [SQ_IDX_BITS:0]     count_o
);

    //=========================================================
    // Store Queue Entry State
    //=========================================================
    localparam STATE_INVALID    = 3'd0;
    localparam STATE_ALLOCATED  = 3'd1;
    localparam STATE_ADDR_VALID = 3'd2;
    localparam STATE_DATA_VALID = 3'd3;
    localparam STATE_READY      = 3'd4;  // Both addr and data valid
    localparam STATE_COMMITTED  = 3'd5;  // Ready to write to D-Cache
    localparam STATE_SENT       = 3'd6;  // Sent to D-Cache
    
    //=========================================================
    // Entry Storage
    //=========================================================
    reg [2:0]               state       [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    addr        [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    data        [0:NUM_ENTRIES-1];
    reg [1:0]               size        [0:NUM_ENTRIES-1];
    reg [3:0]               byte_en     [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  rob_idx     [0:NUM_ENTRIES-1];
    reg                     addr_valid  [0:NUM_ENTRIES-1];
    reg                     data_ready  [0:NUM_ENTRIES-1];
    
    //=========================================================
    // Queue Pointers
    //=========================================================
    reg [SQ_IDX_BITS-1:0] head;          // Commit/retire pointer
    reg [SQ_IDX_BITS-1:0] commit_ptr;    // Points to next committed store to send
    reg [SQ_IDX_BITS-1:0] tail;          // Allocation pointer
    reg [SQ_IDX_BITS:0]   count;
    
    wire [SQ_IDX_BITS-1:0] tail_plus_1 = (tail == NUM_ENTRIES - 1) ? 0 : tail + 1;
    wire [SQ_IDX_BITS-1:0] head_plus_1 = (head == NUM_ENTRIES - 1) ? 0 : head + 1;
    wire [SQ_IDX_BITS-1:0] commit_ptr_plus_1 = (commit_ptr == NUM_ENTRIES - 1) ? 0 : commit_ptr + 1;
    
    integer i;
    
    //=========================================================
    // Status Signals
    //=========================================================
    assign empty_o = (count == 0);
    assign full_o = (count >= NUM_ENTRIES - 1);
    assign count_o = count;
    assign alloc_ready_o = !full_o;
    assign alloc_idx_o = tail;
    
    //=========================================================
    // Byte Enable Generation
    //=========================================================
    function [3:0] gen_byte_en;
        input [1:0] store_size;
        input [1:0] byte_offset;
        begin
            case (store_size)
                2'b00: begin  // Byte
                    case (byte_offset)
                        2'b00: gen_byte_en = 4'b0001;
                        2'b01: gen_byte_en = 4'b0010;
                        2'b10: gen_byte_en = 4'b0100;
                        2'b11: gen_byte_en = 4'b1000;
                    endcase
                end
                2'b01: begin  // Halfword
                    case (byte_offset[1])
                        1'b0: gen_byte_en = 4'b0011;
                        1'b1: gen_byte_en = 4'b1100;
                    endcase
                end
                default: begin  // Word
                    gen_byte_en = 4'b1111;
                end
            endcase
        end
    endfunction
    
    //=========================================================
    // Store-to-Load Forwarding Logic
    //=========================================================
    // Search for matching stores (from newest to oldest, up to load's age)
    reg fwd_found;
    reg [SQ_IDX_BITS-1:0] fwd_idx;
    reg fwd_partial;
    
    always @(*) begin
        fwd_found = 0;
        fwd_idx = 0;
        fwd_partial = 0;
        
        if (fwd_req_valid_i) begin
            // Search from tail-1 (newest) backwards to head (oldest)
            // Only consider stores older than the requesting load
            for (i = NUM_ENTRIES - 1; i >= 0; i = i - 1) begin
                if (!fwd_found && 
                    state[(tail - 1 - i) % NUM_ENTRIES] >= STATE_ADDR_VALID &&
                    rob_idx[(tail - 1 - i) % NUM_ENTRIES] < fwd_req_rob_idx_i) begin
                    
                    // Check address match (word-aligned)
                    if (addr[(tail - 1 - i) % NUM_ENTRIES][ADDR_WIDTH-1:2] == 
                        fwd_req_addr_i[ADDR_WIDTH-1:2]) begin
                        fwd_found = 1;
                        fwd_idx = (tail - 1 - i) % NUM_ENTRIES;
                        
                        // Check for partial match (different byte enables)
                        if (byte_en[fwd_idx] != gen_byte_en(fwd_req_size_i, fwd_req_addr_i[1:0])) begin
                            fwd_partial = 1;
                        end
                    end
                end
            end
        end
    end
    
    // Forwarding response
    assign fwd_resp_match_o = fwd_found;
    assign fwd_resp_valid_o = fwd_found && data_ready[fwd_idx] && !fwd_partial;
    assign fwd_resp_data_o = data[fwd_idx];
    assign fwd_resp_partial_o = fwd_partial;
    
    //=========================================================
    // D-Cache Store Issue Logic
    //=========================================================
    // Issue committed stores to D-Cache in order
    wire head_committed = (state[head] == STATE_COMMITTED);
    wire head_sent = (state[head] == STATE_SENT);
    
    assign dcache_req_valid_o = head_committed;
    assign dcache_req_addr_o = addr[head];
    assign dcache_req_data_o = data[head];
    assign dcache_req_byte_en_o = byte_en[head];
    assign dcache_req_done_o = head_sent;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            commit_ptr <= 0;
            tail <= 0;
            count <= 0;
            
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                state[i] <= STATE_INVALID;
                addr[i] <= 0;
                data[i] <= 0;
                size[i] <= 0;
                byte_en[i] <= 0;
                rob_idx[i] <= 0;
                addr_valid[i] <= 0;
                data_ready[i] <= 0;
            end
        end else if (flush_i) begin
            // Selective flush: invalidate entries younger than flush point
            // But keep committed stores
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (state[i] != STATE_INVALID && 
                    state[i] < STATE_COMMITTED &&
                    rob_idx[i] >= flush_rob_idx_i) begin
                    state[i] <= STATE_INVALID;
                    addr_valid[i] <= 0;
                    data_ready[i] <= 0;
                end
            end
            // Reset tail on full flush, but keep head at committed stores
            if (flush_rob_idx_i == 0) begin
                tail <= commit_ptr;
                count <= 0;
            end
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_req_i && alloc_ready_o) begin
                state[tail] <= STATE_ALLOCATED;
                rob_idx[tail] <= alloc_rob_idx_i;
                addr_valid[tail] <= 0;
                data_ready[tail] <= 0;
                
                tail <= tail_plus_1;
                count <= count + 1;
            end
            
            //=================================================
            // Address Generation
            //=================================================
            if (agen_valid_i && state[agen_sq_idx_i] == STATE_ALLOCATED) begin
                addr[agen_sq_idx_i] <= agen_addr_i;
                size[agen_sq_idx_i] <= agen_size_i;
                byte_en[agen_sq_idx_i] <= gen_byte_en(agen_size_i, agen_addr_i[1:0]);
                addr_valid[agen_sq_idx_i] <= 1;
                
                if (data_ready[agen_sq_idx_i]) begin
                    state[agen_sq_idx_i] <= STATE_READY;
                end else begin
                    state[agen_sq_idx_i] <= STATE_ADDR_VALID;
                end
            end
            
            //=================================================
            // Data Ready
            //=================================================
            if (data_valid_i) begin
                data[data_sq_idx_i] <= data_value_i;
                data_ready[data_sq_idx_i] <= 1;
                
                if (addr_valid[data_sq_idx_i]) begin
                    state[data_sq_idx_i] <= STATE_READY;
                end else if (state[data_sq_idx_i] == STATE_ALLOCATED) begin
                    state[data_sq_idx_i] <= STATE_DATA_VALID;
                end
            end
            
            //=================================================
            // Handle address after data case
            //=================================================
            if (agen_valid_i && state[agen_sq_idx_i] == STATE_DATA_VALID) begin
                addr[agen_sq_idx_i] <= agen_addr_i;
                size[agen_sq_idx_i] <= agen_size_i;
                byte_en[agen_sq_idx_i] <= gen_byte_en(agen_size_i, agen_addr_i[1:0]);
                addr_valid[agen_sq_idx_i] <= 1;
                state[agen_sq_idx_i] <= STATE_READY;
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_i && state[commit_sq_idx_i] == STATE_READY) begin
                state[commit_sq_idx_i] <= STATE_COMMITTED;
                commit_ptr <= commit_ptr_plus_1;
            end
            
            //=================================================
            // D-Cache Store Issue
            //=================================================
            if (dcache_req_valid_o && dcache_req_ready_i) begin
                state[head] <= STATE_SENT;
            end
            
            //=================================================
            // Retire (after D-Cache ack)
            //=================================================
            if (state[head] == STATE_SENT) begin
                state[head] <= STATE_INVALID;
                addr_valid[head] <= 0;
                data_ready[head] <= 0;
                head <= head_plus_1;
                count <= count - 1;
            end
        end
    end

endmodule
