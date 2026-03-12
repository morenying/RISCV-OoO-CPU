//=================================================================
// Module: store_queue
// Description: Store Queue for Memory Ordering
//              8-entry queue
//              In-order commit to memory
//              Address forwarding to Load Queue
// Requirements: 10.1, 10.4
//=================================================================

`timescale 1ns/1ps

module store_queue #(
    parameter NUM_ENTRIES   = 8,
    parameter ENTRY_BITS    = 3,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 5
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Allocation interface
    input  wire                     alloc_valid_i,
    output wire                     alloc_ready_o,
    output wire [ENTRY_BITS-1:0]    alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  alloc_rob_idx_i,
    input  wire [1:0]               alloc_size_i,
    
    // Address calculation complete
    input  wire                     addr_valid_i,
    input  wire [ENTRY_BITS-1:0]    addr_idx_i,
    input  wire [ADDR_WIDTH-1:0]    addr_i,
    
    // Data ready
    input  wire                     data_valid_i,
    input  wire [ENTRY_BITS-1:0]    data_idx_i,
    input  wire [DATA_WIDTH-1:0]    data_i,
    
    // Load Queue forwarding check
    input  wire                     lq_check_valid_i,
    input  wire [ADDR_WIDTH-1:0]    lq_check_addr_i,
    input  wire [1:0]               lq_check_size_i,
    input  wire [ROB_IDX_BITS-1:0]  lq_check_rob_idx_i,
    output wire                     lq_fwd_valid_o,
    output wire [DATA_WIDTH-1:0]    lq_fwd_data_o,
    output wire                     lq_conflict_o,
    
    // Cache interface (for committed stores)
    output wire                     cache_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    cache_req_addr_o,
    output wire [DATA_WIDTH-1:0]    cache_req_data_o,
    output wire [1:0]               cache_req_size_o,
    input  wire                     cache_req_ready_i,
    input  wire                     cache_resp_valid_i,
    
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
    reg                     data_valid  [0:NUM_ENTRIES-1];
    reg                     committed   [0:NUM_ENTRIES-1];
    reg                     sent        [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    addr        [0:NUM_ENTRIES-1];
    reg [DATA_WIDTH-1:0]    data        [0:NUM_ENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  rob_idx     [0:NUM_ENTRIES-1];
    reg [1:0]               size        [0:NUM_ENTRIES-1];
    
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
    // Load Queue Forwarding Logic
    //=========================================================
    // Check all older stores for address match
    reg fwd_found;
    reg conflict_found;
    reg [DATA_WIDTH-1:0] fwd_data;
    reg [ENTRY_BITS-1:0] fwd_idx;
    
    // Address comparison (word-aligned for simplicity)
    wire [ADDR_WIDTH-3:0] lq_word_addr;
    assign lq_word_addr = lq_check_addr_i[ADDR_WIDTH-1:2];
    
    always @(*) begin
        fwd_found = 0;
        conflict_found = 0;
        fwd_data = 0;
        fwd_idx = 0;
        
        // Search from newest to oldest for forwarding
        for (i = NUM_ENTRIES - 1; i >= 0; i = i - 1) begin
            if (valid[i] && addr_valid[i]) begin
                // Check if this store is older than the load
                // (simplified: compare ROB indices)
                if (rob_idx[i] < lq_check_rob_idx_i) begin
                    // Check address match (word-aligned)
                    if (addr[i][ADDR_WIDTH-1:2] == lq_word_addr) begin
                        if (data_valid[i]) begin
                            // Can forward
                            fwd_found = 1;
                            fwd_data = data[i];
                            fwd_idx = i[ENTRY_BITS-1:0];
                        end else begin
                            // Address match but data not ready - conflict
                            conflict_found = 1;
                        end
                    end
                end
            end
        end
    end
    
    assign lq_fwd_valid_o = lq_check_valid_i && fwd_found && !conflict_found;
    assign lq_fwd_data_o = fwd_data;
    assign lq_conflict_o = lq_check_valid_i && conflict_found;
    
    //=========================================================
    // Cache Request (committed stores)
    //=========================================================
    wire head_ready;
    assign head_ready = valid[head] && committed[head] && addr_valid[head] && 
                        data_valid[head] && !sent[head];
    
    assign cache_req_valid_o = head_ready;
    assign cache_req_addr_o = addr[head];
    assign cache_req_data_o = data[head];
    assign cache_req_size_o = size[head];

    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= 0;
            tail <= 0;
            count <= 0;
            
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 0;
                addr_valid[i] <= 0;
                data_valid[i] <= 0;
                committed[i] <= 0;
                sent[i] <= 0;
                addr[i] <= 0;
                data[i] <= 0;
                rob_idx[i] <= 0;
                size[i] <= 0;
            end
        end else if (flush_i) begin
            // On flush, keep committed stores, remove speculative ones
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                if (!committed[i]) begin
                    valid[i] <= 0;
                    addr_valid[i] <= 0;
                    data_valid[i] <= 0;
                end
            end
            // Reset tail to after last committed store
            // (simplified: just reset pointers)
            tail <= head;
            count <= 0;
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_valid_i && !full) begin
                valid[tail] <= 1'b1;
                addr_valid[tail] <= 1'b0;
                data_valid[tail] <= 1'b0;
                committed[tail] <= 1'b0;
                sent[tail] <= 1'b0;
                rob_idx[tail] <= alloc_rob_idx_i;
                size[tail] <= alloc_size_i;
                
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
            // Data Ready
            //=================================================
            if (data_valid_i && valid[data_idx_i]) begin
                data[data_idx_i] <= data_i;
                data_valid[data_idx_i] <= 1'b1;
            end
            
            //=================================================
            // Commit
            //=================================================
            if (commit_valid_i && valid[commit_idx_i]) begin
                committed[commit_idx_i] <= 1'b1;
            end
            
            //=================================================
            // Cache Request Sent
            //=================================================
            if (cache_req_valid_o && cache_req_ready_i) begin
                sent[head] <= 1'b1;
            end
            
            //=================================================
            // Cache Response (store complete)
            //=================================================
            if (cache_resp_valid_i && sent[head]) begin
                valid[head] <= 1'b0;
                committed[head] <= 1'b0;
                sent[head] <= 1'b0;
                head <= (head == NUM_ENTRIES - 1) ? 0 : head + 1;
                count <= count - 1;
            end
        end
    end

endmodule
