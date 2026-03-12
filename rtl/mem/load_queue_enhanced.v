//=================================================================
// Module: load_queue_enhanced
// Description: Enhanced Load Queue (LQ)
//              16 entries (doubled from 8)
//              Age-ordered load tracking
//              Store-to-load forwarding support
//              Memory disambiguation
//              Speculative load replay
// Requirements: 4.5, 4.6
//=================================================================

`timescale 1ns/1ps

module load_queue_enhanced #(
    parameter NUM_ENTRIES   = 16,
    parameter LQ_IDX_BITS   = 4,         // log2(16)
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 6,
    parameter PHYS_REG_BITS = 7
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Allocation Interface (from Rename stage)
    //=========================================================
    input  wire                     alloc_req_i,
    output wire                     alloc_ready_o,
    output wire [LQ_IDX_BITS-1:0]   alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  alloc_rob_idx_i,
    input  wire [PHYS_REG_BITS-1:0] alloc_dst_preg_i,
    
    //=========================================================
    // Address Generation Interface (from AGU)
    //=========================================================
    input  wire                     agen_valid_i,
    input  wire [LQ_IDX_BITS-1:0]   agen_lq_idx_i,
    input  wire [ADDR_WIDTH-1:0]    agen_addr_i,
    input  wire [1:0]               agen_size_i,    // 00=byte, 01=half, 10=word
    input  wire                     agen_signed_i,
    
    //=========================================================
    // Store-to-Load Forwarding Interface
    //=========================================================
    input  wire                     stq_fwd_valid_i,
    input  wire [LQ_IDX_BITS-1:0]   stq_fwd_lq_idx_i,
    input  wire [DATA_WIDTH-1:0]    stq_fwd_data_i,
    input  wire                     stq_fwd_partial_i,  // Partial match (needs load too)
    
    //=========================================================
    // D-Cache Interface
    //=========================================================
    output wire                     dcache_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    dcache_req_addr_o,
    output wire [LQ_IDX_BITS-1:0]   dcache_req_lq_idx_o,
    output wire [1:0]               dcache_req_size_o,
    input  wire                     dcache_req_ready_i,
    
    input  wire                     dcache_resp_valid_i,
    input  wire [LQ_IDX_BITS-1:0]   dcache_resp_lq_idx_i,
    input  wire [DATA_WIDTH-1:0]    dcache_resp_data_i,
    input  wire                     dcache_resp_hit_i,
    
    //=========================================================
    // Completion Interface (to CDB)
    //=========================================================
    output wire                     complete_valid_o,
    output wire [ROB_IDX_BITS-1:0]  complete_rob_idx_o,
    output wire [PHYS_REG_BITS-1:0] complete_dst_preg_o,
    output wire [DATA_WIDTH-1:0]    complete_data_o,
    output wire [LQ_IDX_BITS-1:0]   complete_lq_idx_o,
    
    //=========================================================
    // Commit Interface (from ROB)
    //=========================================================
    input  wire                     commit_valid_i,
    input  wire [LQ_IDX_BITS-1:0]   commit_lq_idx_i,
    
    //=========================================================
    // Memory Ordering Violation Detection
    //=========================================================
    input  wire                     store_commit_valid_i,
    input  wire [ADDR_WIDTH-1:0]    store_commit_addr_i,
    input  wire [ROB_IDX_BITS-1:0]  store_commit_rob_idx_i,
    
    output wire                     violation_detected_o,
    output wire [ROB_IDX_BITS-1:0]  violation_rob_idx_o,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire [ROB_IDX_BITS-1:0]  flush_rob_idx_i,  // Flush from this ROB index
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     empty_o,
    output wire                     full_o,
    output wire [LQ_IDX_BITS:0]     count_o
);

    //=========================================================
    // Load Queue Entry State
    //=========================================================
    localparam STATE_INVALID    = 3'd0;
    localparam STATE_ALLOCATED  = 3'd1;
    localparam STATE_ADDR_VALID = 3'd2;
    localparam STATE_EXECUTING  = 3'd3;
    localparam STATE_COMPLETE   = 3'd4;
    localparam STATE_COMMITTED  = 3'd5;
    
    //=========================================================
    // Entry Storage
    //=========================================================
    reg [2:0]               state       [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    addr        [0:NUM_ENTRIES-1];
    reg [1:0]               size        [0:NUM_ENTRIES-1];
    reg                     signed_ext  [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    data        [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  rob_idx     [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] dst_preg    [0:NUM_ENTRIES-1];
    reg                     forwarded   [0:NUM_ENTRIES-1];  // Data from store forwarding
    reg                     dcache_sent [0:NUM_ENTRIES-1];
    
    //=========================================================
    // Queue Pointers
    //=========================================================
    reg [LQ_IDX_BITS-1:0] head;  // Commit pointer
    reg [LQ_IDX_BITS-1:0] tail;  // Allocation pointer
    reg [LQ_IDX_BITS:0]   count;
    
    wire [LQ_IDX_BITS-1:0] tail_plus_1 = (tail == NUM_ENTRIES - 1) ? 0 : tail + 1;
    wire [LQ_IDX_BITS-1:0] head_plus_1 = (head == NUM_ENTRIES - 1) ? 0 : head + 1;
    
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
    // Issue Logic - Find oldest ready load
    //=========================================================
    wire [NUM_ENTRIES-1:0] ready_mask;
    genvar g;
    generate
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_ready
            assign ready_mask[g] = (state[g] == STATE_ADDR_VALID) && !dcache_sent[g] && !forwarded[g];
        end
    endgenerate
    
    // Age-based priority (oldest first)
    reg [LQ_IDX_BITS-1:0] issue_idx;
    reg issue_valid;
    
    always @(*) begin
        issue_valid = 0;
        issue_idx = 0;
        
        // Search from head (oldest) to tail (newest)
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (ready_mask[(head + i) % NUM_ENTRIES] && !issue_valid) begin
                issue_idx = (head + i) % NUM_ENTRIES;
                issue_valid = 1;
            end
        end
    end
    
    assign dcache_req_valid_o = issue_valid;
    assign dcache_req_addr_o = addr[issue_idx];
    assign dcache_req_lq_idx_o = issue_idx;
    assign dcache_req_size_o = size[issue_idx];
    
    //=========================================================
    // Completion Logic
    //=========================================================
    reg [NUM_ENTRIES-1:0] complete_mask;
    
    always @(*) begin
        complete_mask = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            complete_mask[i] = (state[i] == STATE_COMPLETE);
        end
    end
    
    // Priority encoder for completion (oldest first)
    reg [LQ_IDX_BITS-1:0] complete_idx;
    reg complete_valid_reg;
    
    always @(*) begin
        complete_valid_reg = 0;
        complete_idx = 0;
        
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (complete_mask[(head + i) % NUM_ENTRIES] && !complete_valid_reg) begin
                complete_idx = (head + i) % NUM_ENTRIES;
                complete_valid_reg = 1;
            end
        end
    end
    
    assign complete_valid_o = complete_valid_reg;
    assign complete_rob_idx_o = rob_idx[complete_idx];
    assign complete_dst_preg_o = dst_preg[complete_idx];
    assign complete_data_o = data[complete_idx];
    assign complete_lq_idx_o = complete_idx;
    
    //=========================================================
    // Memory Ordering Violation Detection
    //=========================================================
    reg violation_found;
    reg [ROB_IDX_BITS-1:0] violation_rob;
    
    always @(*) begin
        violation_found = 0;
        violation_rob = 0;
        
        if (store_commit_valid_i) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                // Check if there's a younger load that has already completed
                // but accessed the same address as the committing store
                if (state[i] >= STATE_COMPLETE &&
                    addr[i][ADDR_WIDTH-1:2] == store_commit_addr_i[ADDR_WIDTH-1:2] &&
                    rob_idx[i] > store_commit_rob_idx_i &&
                    !violation_found) begin
                    violation_found = 1;
                    violation_rob = rob_idx[i];
                end
            end
        end
    end
    
    assign violation_detected_o = violation_found;
    assign violation_rob_idx_o = violation_rob;
    
    //=========================================================
    // Load Data Processing
    //=========================================================
    function [31:0] process_load_data;
        input [31:0] raw_data;
        input [1:0]  load_size;
        input        is_signed;
        input [1:0]  byte_offset;
        begin
            case (load_size)
                2'b00: begin  // Byte
                    case (byte_offset)
                        2'b00: process_load_data = is_signed ? 
                               {{24{raw_data[7]}}, raw_data[7:0]} : 
                               {24'b0, raw_data[7:0]};
                        2'b01: process_load_data = is_signed ? 
                               {{24{raw_data[15]}}, raw_data[15:8]} : 
                               {24'b0, raw_data[15:8]};
                        2'b10: process_load_data = is_signed ? 
                               {{24{raw_data[23]}}, raw_data[23:16]} : 
                               {24'b0, raw_data[23:16]};
                        2'b11: process_load_data = is_signed ? 
                               {{24{raw_data[31]}}, raw_data[31:24]} : 
                               {24'b0, raw_data[31:24]};
                    endcase
                end
                2'b01: begin  // Halfword
                    case (byte_offset[1])
                        1'b0: process_load_data = is_signed ? 
                              {{16{raw_data[15]}}, raw_data[15:0]} : 
                              {16'b0, raw_data[15:0]};
                        1'b1: process_load_data = is_signed ? 
                              {{16{raw_data[31]}}, raw_data[31:16]} : 
                              {16'b0, raw_data[31:16]};
                    endcase
                end
                default: begin  // Word
                    process_load_data = raw_data;
                end
            endcase
        end
    endfunction
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                state[i] <= STATE_INVALID;
                addr[i] <= 0;
                size[i] <= 0;
                signed_ext[i] <= 0;
                data[i] <= 0;
                rob_idx[i] <= 0;
                dst_preg[i] <= 0;
                forwarded[i] <= 0;
                dcache_sent[i] <= 0;
            end
        end else if (flush_i) begin
            // Selective flush: invalidate entries younger than flush point
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (state[i] != STATE_INVALID && rob_idx[i] >= flush_rob_idx_i) begin
                    state[i] <= STATE_INVALID;
                    dcache_sent[i] <= 0;
                    forwarded[i] <= 0;
                end
            end
            // Reset tail to head on full flush
            if (flush_rob_idx_i == 0) begin
                tail <= head;
                count <= 0;
            end
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_req_i && alloc_ready_o) begin
                state[tail] <= STATE_ALLOCATED;
                rob_idx[tail] <= alloc_rob_idx_i;
                dst_preg[tail] <= alloc_dst_preg_i;
                forwarded[tail] <= 0;
                dcache_sent[tail] <= 0;
                
                tail <= tail_plus_1;
                count <= count + 1;
            end
            
            //=================================================
            // Address Generation
            //=================================================
            if (agen_valid_i && state[agen_lq_idx_i] == STATE_ALLOCATED) begin
                state[agen_lq_idx_i] <= STATE_ADDR_VALID;
                addr[agen_lq_idx_i] <= agen_addr_i;
                size[agen_lq_idx_i] <= agen_size_i;
                signed_ext[agen_lq_idx_i] <= agen_signed_i;
            end
            
            //=================================================
            // Store-to-Load Forwarding
            //=================================================
            if (stq_fwd_valid_i && state[stq_fwd_lq_idx_i] == STATE_ADDR_VALID) begin
                if (!stq_fwd_partial_i) begin
                    // Full forwarding
                    data[stq_fwd_lq_idx_i] <= process_load_data(
                        stq_fwd_data_i,
                        size[stq_fwd_lq_idx_i],
                        signed_ext[stq_fwd_lq_idx_i],
                        addr[stq_fwd_lq_idx_i][1:0]
                    );
                    state[stq_fwd_lq_idx_i] <= STATE_COMPLETE;
                    forwarded[stq_fwd_lq_idx_i] <= 1;
                end
                // Partial forwarding would need more complex handling
            end
            
            //=================================================
            // D-Cache Request Sent
            //=================================================
            if (dcache_req_valid_o && dcache_req_ready_i) begin
                state[issue_idx] <= STATE_EXECUTING;
                dcache_sent[issue_idx] <= 1;
            end
            
            //=================================================
            // D-Cache Response
            //=================================================
            if (dcache_resp_valid_i && state[dcache_resp_lq_idx_i] == STATE_EXECUTING) begin
                data[dcache_resp_lq_idx_i] <= process_load_data(
                    dcache_resp_data_i,
                    size[dcache_resp_lq_idx_i],
                    signed_ext[dcache_resp_lq_idx_i],
                    addr[dcache_resp_lq_idx_i][1:0]
                );
                state[dcache_resp_lq_idx_i] <= STATE_COMPLETE;
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_i && state[commit_lq_idx_i] == STATE_COMPLETE) begin
                state[commit_lq_idx_i] <= STATE_INVALID;
                head <= head_plus_1;
                count <= count - 1;
            end
        end
    end

endmodule
