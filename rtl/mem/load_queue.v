//=================================================================
// Module: load_queue
// Description: Load Queue for Memory Ordering
//              8-entry queue
//              Store Queue address checking
//              Store-to-Load forwarding support
// Requirements: 10.1, 10.2, 10.3, 10.5
//=================================================================

`timescale 1ns/1ps

module load_queue #(
    parameter NUM_ENTRIES   = 8,
    parameter ENTRY_BITS    = 3,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 5,
    parameter PHYS_REG_BITS = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Allocation interface
    input  wire                     alloc_valid_i,
    output wire                     alloc_ready_o,
    output wire [ENTRY_BITS-1:0]    alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  alloc_rob_idx_i,
    input  wire [PHYS_REG_BITS-1:0] alloc_dst_preg_i,
    input  wire [1:0]               alloc_size_i,
    input  wire                     alloc_sign_ext_i,
    
    // Address calculation complete
    input  wire                     addr_valid_i,
    input  wire [ENTRY_BITS-1:0]    addr_idx_i,
    input  wire [ADDR_WIDTH-1:0]    addr_i,
    
    // Store Queue forwarding interface
    output wire                     sq_check_valid_o,
    output wire [ADDR_WIDTH-1:0]    sq_check_addr_o,
    output wire [1:0]               sq_check_size_o,
    output wire [ROB_IDX_BITS-1:0]  sq_check_rob_idx_o,
    input  wire                     sq_fwd_valid_i,
    input  wire [DATA_WIDTH-1:0]    sq_fwd_data_i,
    input  wire                     sq_conflict_i,    // Older store to same address
    
    // Cache interface
    output wire                     cache_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    cache_req_addr_o,
    input  wire                     cache_req_ready_i,
    input  wire                     cache_resp_valid_i,
    input  wire [DATA_WIDTH-1:0]    cache_resp_data_i,
    
    // Completion interface (to CDB)
    output wire                     complete_valid_o,
    output wire [PHYS_REG_BITS-1:0] complete_preg_o,
    output wire [DATA_WIDTH-1:0]    complete_data_o,
    output wire [ROB_IDX_BITS-1:0]  complete_rob_idx_o,
    input  wire                     complete_ready_i,
    
    // Commit interface
    input  wire                     commit_valid_i,
    input  wire [ENTRY_BITS-1:0]    commit_idx_i,
    
    // Flush interface
    input  wire                     flush_i
);

    //=========================================================
    // Entry Storage
    //=========================================================
    reg                     valid       [0:NUM_ENTRIES-1];
    reg                     addr_valid  [0:NUM_ENTRIES-1];
    reg                     executed    [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    addr        [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    data        [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  rob_idx     [0:NUM_ENTRIES-1];
    reg [PHYS_REG_BITS-1:0] dst_preg    [0:NUM_ENTRIES-1];
    reg [1:0]               size        [0:NUM_ENTRIES-1];
    reg                     sign_ext    [0:NUM_ENTRIES-1];
    reg                     waiting_sq  [0:NUM_ENTRIES-1];  // Waiting for SQ check
    reg                     forwarded   [0:NUM_ENTRIES-1];  // Data from SQ forward
    
    integer i;
    
    //=========================================================
    // Queue Pointers
    //=========================================================
    reg [ENTRY_BITS-1:0] head;
    reg [ENTRY_BITS-1:0] tail;
    reg [ENTRY_BITS:0]   count;
    
    //=========================================================
    // Status
    //=========================================================
    wire empty, full;
    assign empty = (count == 0);
    assign full = (count == NUM_ENTRIES);
    assign alloc_ready_o = !full;
    assign alloc_idx_o = tail;
    
    //=========================================================
    // Find Ready Load (oldest with address, not waiting)
    //=========================================================
    reg [ENTRY_BITS-1:0] ready_idx;
    reg                  ready_found;
    
    always @(*) begin
        ready_idx = head;
        ready_found = 0;
        
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (valid[i] && addr_valid[i] && !executed[i] && !waiting_sq[i] && !ready_found) begin
                ready_idx = i[ENTRY_BITS-1:0];
                ready_found = 1;
            end
        end
    end
    
    //=========================================================
    // Store Queue Check
    //=========================================================
    assign sq_check_valid_o = ready_found;
    assign sq_check_addr_o = addr[ready_idx];
    assign sq_check_size_o = size[ready_idx];
    assign sq_check_rob_idx_o = rob_idx[ready_idx];
    
    //=========================================================
    // Cache Request
    //=========================================================
    reg cache_pending;
    reg [ENTRY_BITS-1:0] cache_idx;
    
    assign cache_req_valid_o = ready_found && !sq_conflict_i && !sq_fwd_valid_i && !cache_pending;
    assign cache_req_addr_o = addr[ready_idx];
    
    //=========================================================
    // Completion Output
    //=========================================================
    reg complete_pending;
    reg [ENTRY_BITS-1:0] complete_idx;
    
    assign complete_valid_o = complete_pending;
    assign complete_preg_o = dst_preg[complete_idx];
    assign complete_data_o = data[complete_idx];
    assign complete_rob_idx_o = rob_idx[complete_idx];

    //=========================================================
    // Data Formatting
    //=========================================================
    function [DATA_WIDTH-1:0] format_load_data;
        input [DATA_WIDTH-1:0] raw_data;
        input [1:0] addr_offset;
        input [1:0] ld_size;
        input sign_extend;
        reg [7:0] byte_data;
        reg [15:0] half_data;
        begin
            case (ld_size)
                2'b00: begin  // Byte
                    case (addr_offset)
                        2'b00: byte_data = raw_data[7:0];
                        2'b01: byte_data = raw_data[15:8];
                        2'b10: byte_data = raw_data[23:16];
                        2'b11: byte_data = raw_data[31:24];
                    endcase
                    format_load_data = sign_extend ? {{24{byte_data[7]}}, byte_data} : {24'd0, byte_data};
                end
                2'b01: begin  // Half
                    case (addr_offset[1])
                        1'b0: half_data = raw_data[15:0];
                        1'b1: half_data = raw_data[31:16];
                    endcase
                    format_load_data = sign_extend ? {{16{half_data[15]}}, half_data} : {16'd0, half_data};
                end
                default: format_load_data = raw_data;  // Word
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
            cache_pending <= 0;
            cache_idx <= 0;
            complete_pending <= 0;
            complete_idx <= 0;
            
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                addr_valid[i] <= 0;
                executed[i] <= 0;
                addr[i] <= 0;
                data[i] <= 0;
                rob_idx[i] <= 0;
                dst_preg[i] <= 0;
                size[i] <= 0;
                sign_ext[i] <= 0;
                waiting_sq[i] <= 0;
                forwarded[i] <= 0;
            end
        end else if (flush_i) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            cache_pending <= 0;
            complete_pending <= 0;
            
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                addr_valid[i] <= 0;
                executed[i] <= 0;
                waiting_sq[i] <= 0;
            end
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_valid_i && !full) begin
                valid[tail] <= 1'b1;
                addr_valid[tail] <= 1'b0;
                executed[tail] <= 1'b0;
                rob_idx[tail] <= alloc_rob_idx_i;
                dst_preg[tail] <= alloc_dst_preg_i;
                size[tail] <= alloc_size_i;
                sign_ext[tail] <= alloc_sign_ext_i;
                waiting_sq[tail] <= 1'b0;
                forwarded[tail] <= 1'b0;
                
                tail <= (tail == NUM_ENTRIES - 1) ? 0 : tail + 1;
                count <= count + 1;
            end
            
            //=================================================
            // Address Calculation Complete
            //=================================================
            if (addr_valid_i && valid[addr_idx_i]) begin
                addr[addr_idx_i] <= addr_i;
                addr_valid[addr_idx_i] <= 1'b1;
            end
            
            //=================================================
            // Store Queue Forwarding
            //=================================================
            if (sq_fwd_valid_i && ready_found) begin
                data[ready_idx] <= format_load_data(sq_fwd_data_i, addr[ready_idx][1:0],
                                                    size[ready_idx], sign_ext[ready_idx]);
                executed[ready_idx] <= 1'b1;
                forwarded[ready_idx] <= 1'b1;
                complete_pending <= 1'b1;
                complete_idx <= ready_idx;
            end
            
            //=================================================
            // Store Queue Conflict
            //=================================================
            if (sq_conflict_i && ready_found) begin
                waiting_sq[ready_idx] <= 1'b1;
            end
            
            //=================================================
            // Cache Request
            //=================================================
            if (cache_req_valid_o && cache_req_ready_i) begin
                cache_pending <= 1'b1;
                cache_idx <= ready_idx;
            end
            
            //=================================================
            // Cache Response
            //=================================================
            if (cache_resp_valid_i && cache_pending) begin
                data[cache_idx] <= format_load_data(cache_resp_data_i, addr[cache_idx][1:0],
                                                    size[cache_idx], sign_ext[cache_idx]);
                executed[cache_idx] <= 1'b1;
                cache_pending <= 1'b0;
                complete_pending <= 1'b1;
                complete_idx <= cache_idx;
            end
            
            //=================================================
            // Completion Handshake
            //=================================================
            if (complete_valid_o && complete_ready_i) begin
                complete_pending <= 1'b0;
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_i && valid[commit_idx_i]) begin
                valid[commit_idx_i] <= 1'b0;
                head <= (head == NUM_ENTRIES - 1) ? 0 : head + 1;
                count <= count - 1;
            end
        end
    end

endmodule
