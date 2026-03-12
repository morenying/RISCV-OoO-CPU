//=================================================================
// Module: mshr
// Description: Miss Status Holding Register (MSHR)
//              Enables non-blocking cache operation
//              4 entries for outstanding cache misses
//              Supports load/store coalescing
// Requirements: 3.2
//=================================================================

`timescale 1ns/1ps

module mshr #(
    parameter NUM_ENTRIES   = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter LINE_SIZE     = 32,    // Cache line size in bytes
    parameter LINE_WIDTH    = 256,   // Cache line width in bits
    parameter TAG_WIDTH     = 20,
    parameter INDEX_WIDTH   = 6,
    parameter ROB_IDX_BITS  = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Allocation Interface (from D-Cache on miss)
    //=========================================================
    input  wire                     alloc_req_i,
    input  wire [ADDR_WIDTH-1:0]    alloc_addr_i,
    input  wire [TAG_WIDTH-1:0]     alloc_tag_i,
    input  wire [INDEX_WIDTH-1:0]   alloc_index_i,
    input  wire                     alloc_is_store_i,
    input  wire [DATA_WIDTH-1:0]    alloc_store_data_i,
    input  wire [3:0]               alloc_byte_en_i,
    input  wire [ROB_IDX_BITS-1:0]  alloc_rob_idx_i,
    output wire                     alloc_ready_o,
    output wire [1:0]               alloc_mshr_idx_o,
    
    //=========================================================
    // Secondary Miss Interface (coalescing)
    //=========================================================
    input  wire                     secondary_req_i,
    input  wire [1:0]               secondary_mshr_idx_i,
    input  wire                     secondary_is_store_i,
    input  wire [DATA_WIDTH-1:0]    secondary_store_data_i,
    input  wire [3:0]               secondary_byte_en_i,
    input  wire [4:0]               secondary_word_offset_i,  // Word offset within line
    input  wire [ROB_IDX_BITS-1:0]  secondary_rob_idx_i,
    
    //=========================================================
    // Address Match Interface (for checking incoming requests)
    //=========================================================
    input  wire [TAG_WIDTH-1:0]     match_tag_i,
    input  wire [INDEX_WIDTH-1:0]   match_index_i,
    output wire                     match_hit_o,
    output wire [1:0]               match_mshr_idx_o,
    
    //=========================================================
    // Memory Response Interface
    //=========================================================
    input  wire                     mem_resp_valid_i,
    input  wire [1:0]               mem_resp_mshr_idx_i,
    input  wire [LINE_WIDTH-1:0]    mem_resp_data_i,
    
    //=========================================================
    // Completion Interface (to D-Cache)
    //=========================================================
    output wire                     complete_valid_o,
    output wire [1:0]               complete_mshr_idx_o,
    output wire [TAG_WIDTH-1:0]     complete_tag_o,
    output wire [INDEX_WIDTH-1:0]   complete_index_o,
    output wire [LINE_WIDTH-1:0]    complete_data_o,
    output wire                     complete_dirty_o,
    input  wire                     complete_ack_i,
    
    //=========================================================
    // Wakeup Interface (to Load Queue)
    //=========================================================
    output wire                     wakeup_valid_o,
    output wire [ROB_IDX_BITS-1:0]  wakeup_rob_idx_o,
    output wire [DATA_WIDTH-1:0]    wakeup_data_o,
    
    //=========================================================
    // Memory Request Interface
    //=========================================================
    output wire                     mem_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    mem_req_addr_o,
    output wire [1:0]               mem_req_mshr_idx_o,
    input  wire                     mem_req_ready_i,
    
    //=========================================================
    // Status
    //=========================================================
    output wire                     full_o,
    output wire [NUM_ENTRIES-1:0]   entry_valid_o
);

    //=========================================================
    // MSHR Entry State
    //=========================================================
    localparam STATE_IDLE      = 2'b00;
    localparam STATE_PENDING   = 2'b01;  // Waiting for memory response
    localparam STATE_COMPLETE  = 2'b10;  // Response received, waiting for cache update
    
    //=========================================================
    // MSHR Entry Storage
    //=========================================================
    reg [1:0]               state       [0:NUM_ENTRIES-1];
    reg [TAG_WIDTH-1:0]     tag         [0:NUM_ENTRIES-1];
    reg [INDEX_WIDTH-1:0]   index       [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    addr        [0:NUM_ENTRIES-1];
    reg [LINE_WIDTH-1:0]    line_data   [0:NUM_ENTRIES-1];
    reg                     dirty       [0:NUM_ENTRIES-1];
    
    // Subentry table (for coalescing multiple requests to same line)
    localparam MAX_SUBENTRIES = 4;
    reg                     subentry_valid  [0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    reg                     subentry_is_store[0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    reg [DATA_WIDTH-1:0]    subentry_data   [0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    reg [3:0]               subentry_byte_en[0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    reg [4:0]               subentry_offset [0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    reg [ROB_IDX_BITS-1:0]  subentry_rob_idx[0:NUM_ENTRIES-1][0:MAX_SUBENTRIES-1];
    
    // Memory request sent flag
    reg                     mem_req_sent [0:NUM_ENTRIES-1];
    
    // Wakeup state machine
    reg [1:0]               wakeup_entry;
    reg [1:0]               wakeup_subentry;
    reg                     wakeup_pending;
    
    integer i, j;
    
    //=========================================================
    // Entry Valid Signals
    //=========================================================
    wire [NUM_ENTRIES-1:0] entry_idle;
    wire [NUM_ENTRIES-1:0] entry_pending;
    wire [NUM_ENTRIES-1:0] entry_complete;
    
    genvar g;
    generate
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_status
            assign entry_idle[g] = (state[g] == STATE_IDLE);
            assign entry_pending[g] = (state[g] == STATE_PENDING);
            assign entry_complete[g] = (state[g] == STATE_COMPLETE);
        end
    endgenerate
    
    assign entry_valid_o = ~entry_idle;
    assign full_o = &(~entry_idle);
    
    //=========================================================
    // Allocation Logic - Find first free entry
    //=========================================================
    wire [1:0] free_entry;
    wire       has_free_entry;
    
    assign free_entry = entry_idle[0] ? 2'd0 :
                        entry_idle[1] ? 2'd1 :
                        entry_idle[2] ? 2'd2 :
                        entry_idle[3] ? 2'd3 : 2'd0;
    
    assign has_free_entry = |entry_idle;
    assign alloc_ready_o = has_free_entry;
    assign alloc_mshr_idx_o = free_entry;
    
    //=========================================================
    // Address Matching Logic
    //=========================================================
    wire [NUM_ENTRIES-1:0] tag_match;
    wire [NUM_ENTRIES-1:0] index_match;
    wire [NUM_ENTRIES-1:0] addr_match;
    
    generate
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_match
            assign tag_match[g] = (tag[g] == match_tag_i);
            assign index_match[g] = (index[g] == match_index_i);
            assign addr_match[g] = tag_match[g] && index_match[g] && !entry_idle[g];
        end
    endgenerate
    
    assign match_hit_o = |addr_match;
    assign match_mshr_idx_o = addr_match[0] ? 2'd0 :
                              addr_match[1] ? 2'd1 :
                              addr_match[2] ? 2'd2 :
                              addr_match[3] ? 2'd3 : 2'd0;
    
    //=========================================================
    // Memory Request Output - Round-robin priority
    //=========================================================
    reg [1:0] mem_req_rr;
    wire [NUM_ENTRIES-1:0] need_mem_req;
    
    generate
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_mem_req
            assign need_mem_req[g] = entry_pending[g] && !mem_req_sent[g];
        end
    endgenerate
    
    wire [1:0] mem_req_entry;
    wire       has_mem_req;
    
    // Simple priority encoder with round-robin hint
    assign mem_req_entry = (need_mem_req[(mem_req_rr+0) & 2'b11]) ? ((mem_req_rr+0) & 2'b11) :
                           (need_mem_req[(mem_req_rr+1) & 2'b11]) ? ((mem_req_rr+1) & 2'b11) :
                           (need_mem_req[(mem_req_rr+2) & 2'b11]) ? ((mem_req_rr+2) & 2'b11) :
                           (need_mem_req[(mem_req_rr+3) & 2'b11]) ? ((mem_req_rr+3) & 2'b11) : 2'd0;
    
    assign has_mem_req = |need_mem_req;
    
    assign mem_req_valid_o = has_mem_req;
    assign mem_req_addr_o = addr[mem_req_entry];
    assign mem_req_mshr_idx_o = mem_req_entry;
    
    //=========================================================
    // Completion Output
    //=========================================================
    wire [1:0] complete_entry;
    wire       has_complete;
    
    assign complete_entry = entry_complete[0] ? 2'd0 :
                            entry_complete[1] ? 2'd1 :
                            entry_complete[2] ? 2'd2 :
                            entry_complete[3] ? 2'd3 : 2'd0;
    
    assign has_complete = |entry_complete;
    
    assign complete_valid_o = has_complete && !wakeup_pending;
    assign complete_mshr_idx_o = complete_entry;
    assign complete_tag_o = tag[complete_entry];
    assign complete_index_o = index[complete_entry];
    assign complete_data_o = line_data[complete_entry];
    assign complete_dirty_o = dirty[complete_entry];
    
    //=========================================================
    // Wakeup Output
    //=========================================================
    assign wakeup_valid_o = wakeup_pending;
    assign wakeup_rob_idx_o = subentry_rob_idx[wakeup_entry][wakeup_subentry];
    
    // Extract correct word from line based on offset
    wire [4:0] wakeup_offset = subentry_offset[wakeup_entry][wakeup_subentry];
    wire [LINE_WIDTH-1:0] wakeup_line = line_data[wakeup_entry];
    assign wakeup_data_o = wakeup_line[wakeup_offset*32 +: 32];
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                state[i] <= STATE_IDLE;
                tag[i] <= 0;
                index[i] <= 0;
                addr[i] <= 0;
                line_data[i] <= 0;
                dirty[i] <= 0;
                mem_req_sent[i] <= 0;
                
                for (j = 0; j < MAX_SUBENTRIES; j = j + 1) begin
                    subentry_valid[i][j] <= 0;
                    subentry_is_store[i][j] <= 0;
                    subentry_data[i][j] <= 0;
                    subentry_byte_en[i][j] <= 0;
                    subentry_offset[i][j] <= 0;
                    subentry_rob_idx[i][j] <= 0;
                end
            end
            mem_req_rr <= 0;
            wakeup_entry <= 0;
            wakeup_subentry <= 0;
            wakeup_pending <= 0;
        end else begin
            //=================================================
            // Allocation
            //=================================================
            if (alloc_req_i && alloc_ready_o) begin
                state[free_entry] <= STATE_PENDING;
                tag[free_entry] <= alloc_tag_i;
                index[free_entry] <= alloc_index_i;
                addr[free_entry] <= {alloc_addr_i[ADDR_WIDTH-1:5], 5'b0};  // Align to line
                dirty[free_entry] <= alloc_is_store_i;
                mem_req_sent[free_entry] <= 0;
                
                // First subentry
                subentry_valid[free_entry][0] <= 1'b1;
                subentry_is_store[free_entry][0] <= alloc_is_store_i;
                subentry_data[free_entry][0] <= alloc_store_data_i;
                subentry_byte_en[free_entry][0] <= alloc_byte_en_i;
                subentry_offset[free_entry][0] <= alloc_addr_i[4:2];  // Word offset
                subentry_rob_idx[free_entry][0] <= alloc_rob_idx_i;
                
                // Clear other subentries
                for (j = 1; j < MAX_SUBENTRIES; j = j + 1) begin
                    subentry_valid[free_entry][j] <= 0;
                end
            end
            
            //=================================================
            // Secondary Miss (Coalescing)
            //=================================================
            if (secondary_req_i) begin
                // Find free subentry slot
                for (j = 0; j < MAX_SUBENTRIES; j = j + 1) begin
                    if (!subentry_valid[secondary_mshr_idx_i][j]) begin
                        subentry_valid[secondary_mshr_idx_i][j] <= 1'b1;
                        subentry_is_store[secondary_mshr_idx_i][j] <= secondary_is_store_i;
                        subentry_data[secondary_mshr_idx_i][j] <= secondary_store_data_i;
                        subentry_byte_en[secondary_mshr_idx_i][j] <= secondary_byte_en_i;
                        subentry_offset[secondary_mshr_idx_i][j] <= secondary_word_offset_i;
                        subentry_rob_idx[secondary_mshr_idx_i][j] <= secondary_rob_idx_i;
                        
                        if (secondary_is_store_i) begin
                            dirty[secondary_mshr_idx_i] <= 1'b1;
                        end
                        
                        // Only process first available slot
                        j = MAX_SUBENTRIES;
                    end
                end
            end
            
            //=================================================
            // Memory Request Handshake
            //=================================================
            if (mem_req_valid_o && mem_req_ready_i) begin
                mem_req_sent[mem_req_entry] <= 1'b1;
                mem_req_rr <= mem_req_entry + 1;
            end
            
            //=================================================
            // Memory Response
            //=================================================
            if (mem_resp_valid_i) begin
                line_data[mem_resp_mshr_idx_i] <= mem_resp_data_i;
                state[mem_resp_mshr_idx_i] <= STATE_COMPLETE;
                
                // Apply pending stores to the line
                for (j = 0; j < MAX_SUBENTRIES; j = j + 1) begin
                    if (subentry_valid[mem_resp_mshr_idx_i][j] && 
                        subentry_is_store[mem_resp_mshr_idx_i][j]) begin
                        // Merge store data into line
                        // This is simplified - full implementation would use byte enables
                        line_data[mem_resp_mshr_idx_i][subentry_offset[mem_resp_mshr_idx_i][j]*32 +: 32] <= 
                            subentry_data[mem_resp_mshr_idx_i][j];
                    end
                end
                
                // Start wakeup sequence
                wakeup_entry <= mem_resp_mshr_idx_i;
                wakeup_subentry <= 0;
                wakeup_pending <= subentry_valid[mem_resp_mshr_idx_i][0] && 
                                  !subentry_is_store[mem_resp_mshr_idx_i][0];
            end
            
            //=================================================
            // Wakeup Sequence
            //=================================================
            if (wakeup_pending) begin
                // Move to next subentry
                if (wakeup_subentry < MAX_SUBENTRIES - 1) begin
                    wakeup_subentry <= wakeup_subentry + 1;
                    wakeup_pending <= subentry_valid[wakeup_entry][wakeup_subentry + 1] &&
                                      !subentry_is_store[wakeup_entry][wakeup_subentry + 1];
                end else begin
                    wakeup_pending <= 0;
                end
            end
            
            //=================================================
            // Completion Acknowledgment
            //=================================================
            if (complete_valid_o && complete_ack_i) begin
                state[complete_entry] <= STATE_IDLE;
                
                // Clear all subentries
                for (j = 0; j < MAX_SUBENTRIES; j = j + 1) begin
                    subentry_valid[complete_entry][j] <= 0;
                end
            end
        end
    end

endmodule
