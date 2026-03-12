//=================================================================
// Module: dcache_enhanced
// Description: Enhanced Data Cache
//              8KB, 4-way set associative
//              32-byte cache line (256 bits)
//              Write-back, write-allocate
//              Non-blocking with MSHR integration
//              Pseudo-LRU replacement
// Requirements: 3.2
//=================================================================

`timescale 1ns/1ps

module dcache_enhanced #(
    parameter CACHE_SIZE    = 8192,         // 8KB
    parameter LINE_SIZE     = 32,           // 32 bytes per line
    parameter NUM_WAYS      = 4,            // 4-way associative
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter LINE_WIDTH    = 256,          // 32 * 8 bits
    parameter ROB_IDX_BITS  = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // CPU Interface
    //=========================================================
    input  wire                     req_valid_i,
    input  wire [ADDR_WIDTH-1:0]    req_addr_i,
    input  wire                     req_we_i,       // 1=write, 0=read
    input  wire [DATA_WIDTH-1:0]    req_wdata_i,
    input  wire [3:0]               req_byte_en_i,
    input  wire [ROB_IDX_BITS-1:0]  req_rob_idx_i,
    output wire                     req_ready_o,
    
    output wire                     resp_valid_o,
    output wire [DATA_WIDTH-1:0]    resp_rdata_o,
    output wire                     resp_hit_o,
    output wire [ROB_IDX_BITS-1:0]  resp_rob_idx_o,
    
    //=========================================================
    // Memory Interface
    //=========================================================
    output wire                     mem_req_valid_o,
    output wire [ADDR_WIDTH-1:0]    mem_req_addr_o,
    output wire                     mem_req_we_o,
    output wire [LINE_WIDTH-1:0]    mem_req_wdata_o,
    input  wire                     mem_req_ready_i,
    
    input  wire                     mem_resp_valid_i,
    input  wire [LINE_WIDTH-1:0]    mem_resp_rdata_i,
    
    //=========================================================
    // Flush/Invalidate Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire                     invalidate_i,
    output wire                     flush_done_o
);

    //=========================================================
    // Derived Parameters
    //=========================================================
    localparam NUM_SETS     = CACHE_SIZE / (LINE_SIZE * NUM_WAYS);  // 64 sets
    localparam OFFSET_BITS  = $clog2(LINE_SIZE);     // 5 bits (for 32-byte line)
    localparam INDEX_BITS   = $clog2(NUM_SETS);      // 6 bits (for 64 sets)
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;  // 21 bits
    localparam WORD_OFFSET_BITS = $clog2(LINE_SIZE/4);  // 3 bits
    
    //=========================================================
    // Cache State
    //=========================================================
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_LOOKUP     = 3'd1;
    localparam STATE_MISS       = 3'd2;
    localparam STATE_WRITEBACK  = 3'd3;
    localparam STATE_REFILL     = 3'd4;
    localparam STATE_FLUSH      = 3'd5;
    
    reg [2:0] state;
    reg [2:0] next_state;
    
    //=========================================================
    // Address Decomposition
    //=========================================================
    wire [OFFSET_BITS-1:0]   req_offset = req_addr_i[OFFSET_BITS-1:0];
    wire [INDEX_BITS-1:0]    req_index  = req_addr_i[OFFSET_BITS +: INDEX_BITS];
    wire [TAG_BITS-1:0]      req_tag    = req_addr_i[ADDR_WIDTH-1 -: TAG_BITS];
    wire [WORD_OFFSET_BITS-1:0] req_word_offset = req_addr_i[OFFSET_BITS-1:2];
    
    //=========================================================
    // Cache Storage (using block RAMs)
    //=========================================================
    // Tag arrays (one per way)
    reg [TAG_BITS-1:0]     tag_array   [0:NUM_WAYS-1][0:NUM_SETS-1];
    reg                    valid_array [0:NUM_WAYS-1][0:NUM_SETS-1];
    reg                    dirty_array [0:NUM_WAYS-1][0:NUM_SETS-1];
    
    // Data arrays (one per way)
    reg [LINE_WIDTH-1:0]   data_array  [0:NUM_WAYS-1][0:NUM_SETS-1];
    
    // Pseudo-LRU (tree-based, 3 bits per set for 4-way)
    reg [2:0] plru_bits [0:NUM_SETS-1];
    
    //=========================================================
    // MSHR Integration
    //=========================================================
    wire        mshr_alloc_req;
    wire        mshr_alloc_ready;
    wire [1:0]  mshr_alloc_idx;
    
    wire        mshr_match_hit;
    wire [1:0]  mshr_match_idx;
    
    wire        mshr_complete_valid;
    wire [1:0]  mshr_complete_idx;
    wire [TAG_BITS-1:0]   mshr_complete_tag;
    wire [INDEX_BITS-1:0] mshr_complete_index;
    wire [LINE_WIDTH-1:0] mshr_complete_data;
    wire        mshr_complete_dirty;
    reg         mshr_complete_ack;
    
    wire        mshr_mem_req_valid;
    wire [ADDR_WIDTH-1:0] mshr_mem_req_addr;
    wire [1:0]  mshr_mem_req_idx;
    
    wire        mshr_wakeup_valid;
    wire [ROB_IDX_BITS-1:0] mshr_wakeup_rob_idx;
    wire [DATA_WIDTH-1:0] mshr_wakeup_data;
    
    wire        mshr_full;
    
    //=========================================================
    // Pipeline Registers
    //=========================================================
    reg                     req_valid_r;
    reg [ADDR_WIDTH-1:0]    req_addr_r;
    reg                     req_we_r;
    reg [DATA_WIDTH-1:0]    req_wdata_r;
    reg [3:0]               req_byte_en_r;
    reg [ROB_IDX_BITS-1:0]  req_rob_idx_r;
    reg [TAG_BITS-1:0]      req_tag_r;
    reg [INDEX_BITS-1:0]    req_index_r;
    reg [WORD_OFFSET_BITS-1:0] req_word_offset_r;
    
    //=========================================================
    // Tag Comparison
    //=========================================================
    wire [NUM_WAYS-1:0] way_hit;
    wire [NUM_WAYS-1:0] way_valid;
    wire [NUM_WAYS-1:0] way_dirty;
    wire [TAG_BITS-1:0] way_tag [0:NUM_WAYS-1];
    wire [LINE_WIDTH-1:0] way_data [0:NUM_WAYS-1];
    
    genvar w;
    generate
        for (w = 0; w < NUM_WAYS; w = w + 1) begin : gen_way
            assign way_tag[w] = tag_array[w][req_index_r];
            assign way_valid[w] = valid_array[w][req_index_r];
            assign way_dirty[w] = dirty_array[w][req_index_r];
            assign way_data[w] = data_array[w][req_index_r];
            assign way_hit[w] = way_valid[w] && (way_tag[w] == req_tag_r);
        end
    endgenerate
    
    wire cache_hit = |way_hit;
    wire [1:0] hit_way;
    assign hit_way = way_hit[0] ? 2'd0 :
                     way_hit[1] ? 2'd1 :
                     way_hit[2] ? 2'd2 :
                     way_hit[3] ? 2'd3 : 2'd0;
    
    //=========================================================
    // Pseudo-LRU Victim Selection
    //=========================================================
    wire [1:0] victim_way;
    wire [2:0] plru = plru_bits[req_index_r];
    
    // Tree-PLRU decoding (3-bit tree for 4-way)
    // Bit 0: Left (0,1) vs Right (2,3)
    // Bit 1: Way 0 vs Way 1
    // Bit 2: Way 2 vs Way 3
    assign victim_way = plru[0] ? (plru[2] ? 2'd2 : 2'd3) :
                                  (plru[1] ? 2'd0 : 2'd1);
    
    wire victim_valid = valid_array[victim_way][req_index_r];
    wire victim_dirty = dirty_array[victim_way][req_index_r];
    wire [TAG_BITS-1:0] victim_tag = tag_array[victim_way][req_index_r];
    wire [LINE_WIDTH-1:0] victim_data = data_array[victim_way][req_index_r];
    
    //=========================================================
    // Read Data Selection
    //=========================================================
    wire [LINE_WIDTH-1:0] hit_line_data = way_data[hit_way];
    wire [DATA_WIDTH-1:0] hit_word_data;
    
    // Extract word from line
    assign hit_word_data = hit_line_data[req_word_offset_r * 32 +: 32];
    
    //=========================================================
    // State Machine
    //=========================================================
    reg [INDEX_BITS-1:0] flush_index;
    reg [1:0] flush_way;
    reg flush_in_progress;
    
    // Writeback state
    reg wb_pending;
    reg [ADDR_WIDTH-1:0] wb_addr;
    reg [LINE_WIDTH-1:0] wb_data;
    
    // Refill state
    reg [1:0] refill_way;
    
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (flush_i || invalidate_i) begin
                    next_state = STATE_FLUSH;
                end else if (req_valid_r) begin
                    next_state = STATE_LOOKUP;
                end
            end
            
            STATE_LOOKUP: begin
                if (cache_hit) begin
                    // Hit: return to idle, or process next request
                    next_state = STATE_IDLE;
                end else if (!mshr_full) begin
                    // Miss: check if writeback needed
                    if (victim_valid && victim_dirty) begin
                        next_state = STATE_WRITEBACK;
                    end else begin
                        next_state = STATE_MISS;
                    end
                end else begin
                    // MSHR full, stall
                    next_state = STATE_LOOKUP;
                end
            end
            
            STATE_WRITEBACK: begin
                if (mem_req_ready_i) begin
                    next_state = STATE_MISS;
                end
            end
            
            STATE_MISS: begin
                // Allocate MSHR entry, go back to idle (non-blocking)
                if (mshr_alloc_ready) begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_REFILL: begin
                // Process MSHR completion
                if (mshr_complete_valid) begin
                    next_state = STATE_IDLE;
                end
            end
            
            STATE_FLUSH: begin
                if (flush_done_o) begin
                    next_state = STATE_IDLE;
                end
            end
        endcase
        
        // Handle MSHR completion asynchronously
        if (mshr_complete_valid && state == STATE_IDLE) begin
            next_state = STATE_REFILL;
        end
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            req_valid_r <= 0;
            req_addr_r <= 0;
            req_we_r <= 0;
            req_wdata_r <= 0;
            req_byte_en_r <= 0;
            req_rob_idx_r <= 0;
            req_tag_r <= 0;
            req_index_r <= 0;
            req_word_offset_r <= 0;
            
            flush_index <= 0;
            flush_way <= 0;
            flush_in_progress <= 0;
            
            wb_pending <= 0;
            wb_addr <= 0;
            wb_data <= 0;
            refill_way <= 0;
            
            mshr_complete_ack <= 0;
            
            // Initialize cache arrays
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                for (j = 0; j < NUM_SETS; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    dirty_array[i][j] <= 0;
                    tag_array[i][j] <= 0;
                    data_array[i][j] <= 0;
                end
            end
            
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                plru_bits[j] <= 0;
            end
        end else begin
            state <= next_state;
            mshr_complete_ack <= 0;
            
            case (state)
                STATE_IDLE: begin
                    if (req_valid_i && !flush_i && !invalidate_i) begin
                        // Latch request
                        req_valid_r <= 1;
                        req_addr_r <= req_addr_i;
                        req_we_r <= req_we_i;
                        req_wdata_r <= req_wdata_i;
                        req_byte_en_r <= req_byte_en_i;
                        req_rob_idx_r <= req_rob_idx_i;
                        req_tag_r <= req_tag;
                        req_index_r <= req_index;
                        req_word_offset_r <= req_word_offset;
                    end else begin
                        req_valid_r <= 0;
                    end
                    
                    if (flush_i || invalidate_i) begin
                        flush_index <= 0;
                        flush_way <= 0;
                        flush_in_progress <= 1;
                    end
                end
                
                STATE_LOOKUP: begin
                    if (cache_hit) begin
                        // Update PLRU on hit
                        case (hit_way)
                            2'd0: plru_bits[req_index_r] <= {plru[2], 1'b1, 1'b1};
                            2'd1: plru_bits[req_index_r] <= {plru[2], 1'b0, 1'b1};
                            2'd2: plru_bits[req_index_r] <= {1'b1, plru[1], 1'b0};
                            2'd3: plru_bits[req_index_r] <= {1'b0, plru[1], 1'b0};
                        endcase
                        
                        // Write hit: update data and set dirty
                        if (req_we_r) begin
                            // Merge write data with byte enables
                            // Using word-level write for simplicity
                            data_array[hit_way][req_index_r][req_word_offset_r * 32 +: 32] <= 
                                merge_word(way_data[hit_way][req_word_offset_r * 32 +: 32],
                                          req_wdata_r, req_byte_en_r);
                            dirty_array[hit_way][req_index_r] <= 1'b1;
                        end
                        
                        req_valid_r <= 0;
                    end else if (!mshr_full) begin
                        // Cache miss - prepare writeback if needed
                        if (victim_valid && victim_dirty) begin
                            wb_pending <= 1;
                            wb_addr <= {victim_tag, req_index_r, {OFFSET_BITS{1'b0}}};
                            wb_data <= victim_data;
                        end
                        refill_way <= victim_way;
                    end
                end
                
                STATE_WRITEBACK: begin
                    if (mem_req_ready_i) begin
                        wb_pending <= 0;
                        // Invalidate victim after writeback
                        valid_array[refill_way][req_index_r] <= 0;
                        dirty_array[refill_way][req_index_r] <= 0;
                    end
                end
                
                STATE_MISS: begin
                    if (mshr_alloc_ready) begin
                        req_valid_r <= 0;
                    end
                end
                
                STATE_REFILL: begin
                    if (mshr_complete_valid) begin
                        // Write refill data to cache
                        tag_array[victim_way][mshr_complete_index] <= mshr_complete_tag;
                        data_array[victim_way][mshr_complete_index] <= mshr_complete_data;
                        valid_array[victim_way][mshr_complete_index] <= 1'b1;
                        dirty_array[victim_way][mshr_complete_index] <= mshr_complete_dirty;
                        
                        // Update PLRU
                        case (victim_way)
                            2'd0: plru_bits[mshr_complete_index] <= {plru_bits[mshr_complete_index][2], 1'b1, 1'b1};
                            2'd1: plru_bits[mshr_complete_index] <= {plru_bits[mshr_complete_index][2], 1'b0, 1'b1};
                            2'd2: plru_bits[mshr_complete_index] <= {1'b1, plru_bits[mshr_complete_index][1], 1'b0};
                            2'd3: plru_bits[mshr_complete_index] <= {1'b0, plru_bits[mshr_complete_index][1], 1'b0};
                        endcase
                        
                        mshr_complete_ack <= 1;
                    end
                end
                
                STATE_FLUSH: begin
                    // Flush/invalidate all cache lines
                    if (flush_in_progress) begin
                        // Check if current line needs writeback
                        if (valid_array[flush_way][flush_index] && 
                            dirty_array[flush_way][flush_index] && 
                            !invalidate_i) begin
                            // Writeback needed (skip for invalidate)
                            wb_pending <= 1;
                            wb_addr <= {tag_array[flush_way][flush_index], flush_index, {OFFSET_BITS{1'b0}}};
                            wb_data <= data_array[flush_way][flush_index];
                        end
                        
                        // Invalidate line
                        valid_array[flush_way][flush_index] <= 0;
                        dirty_array[flush_way][flush_index] <= 0;
                        
                        // Move to next line
                        if (flush_way == NUM_WAYS - 1) begin
                            flush_way <= 0;
                            if (flush_index == NUM_SETS - 1) begin
                                flush_in_progress <= 0;
                            end else begin
                                flush_index <= flush_index + 1;
                            end
                        end else begin
                            flush_way <= flush_way + 1;
                        end
                    end
                end
            endcase
        end
    end
    
    //=========================================================
    // Byte Merge Function
    //=========================================================
    function [31:0] merge_word;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0]  byte_en;
        begin
            merge_word[7:0]   = byte_en[0] ? new_data[7:0]   : old_data[7:0];
            merge_word[15:8]  = byte_en[1] ? new_data[15:8]  : old_data[15:8];
            merge_word[23:16] = byte_en[2] ? new_data[23:16] : old_data[23:16];
            merge_word[31:24] = byte_en[3] ? new_data[31:24] : old_data[31:24];
        end
    endfunction
    
    //=========================================================
    // Output Assignments
    //=========================================================
    assign req_ready_o = (state == STATE_IDLE) && !flush_i && !invalidate_i && !mshr_full;
    
    // Response on hit or from MSHR wakeup
    assign resp_valid_o = (state == STATE_LOOKUP && cache_hit && !req_we_r) || mshr_wakeup_valid;
    assign resp_rdata_o = mshr_wakeup_valid ? mshr_wakeup_data : hit_word_data;
    assign resp_hit_o = (state == STATE_LOOKUP && cache_hit);
    assign resp_rob_idx_o = mshr_wakeup_valid ? mshr_wakeup_rob_idx : req_rob_idx_r;
    
    // Memory interface - prioritize writeback over MSHR
    assign mem_req_valid_o = wb_pending || mshr_mem_req_valid;
    assign mem_req_addr_o = wb_pending ? wb_addr : mshr_mem_req_addr;
    assign mem_req_we_o = wb_pending;
    assign mem_req_wdata_o = wb_data;
    
    assign flush_done_o = (state == STATE_FLUSH) && !flush_in_progress;
    
    //=========================================================
    // MSHR Instance
    //=========================================================
    assign mshr_alloc_req = (state == STATE_MISS);
    
    mshr #(
        .NUM_ENTRIES    (4),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .LINE_SIZE      (LINE_SIZE),
        .LINE_WIDTH     (LINE_WIDTH),
        .TAG_WIDTH      (TAG_BITS),
        .INDEX_WIDTH    (INDEX_BITS),
        .ROB_IDX_BITS   (ROB_IDX_BITS)
    ) u_mshr (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Allocation
        .alloc_req_i            (mshr_alloc_req),
        .alloc_addr_i           (req_addr_r),
        .alloc_tag_i            (req_tag_r),
        .alloc_index_i          (req_index_r),
        .alloc_is_store_i       (req_we_r),
        .alloc_store_data_i     (req_wdata_r),
        .alloc_byte_en_i        (req_byte_en_r),
        .alloc_rob_idx_i        (req_rob_idx_r),
        .alloc_ready_o          (mshr_alloc_ready),
        .alloc_mshr_idx_o       (mshr_alloc_idx),
        
        // Secondary miss
        .secondary_req_i        (1'b0),  // Simplified
        .secondary_mshr_idx_i   (2'b0),
        .secondary_is_store_i   (1'b0),
        .secondary_store_data_i (32'b0),
        .secondary_byte_en_i    (4'b0),
        .secondary_word_offset_i(5'b0),
        .secondary_rob_idx_i    (6'b0),
        
        // Address match
        .match_tag_i            (req_tag),
        .match_index_i          (req_index),
        .match_hit_o            (mshr_match_hit),
        .match_mshr_idx_o       (mshr_match_idx),
        
        // Memory response
        .mem_resp_valid_i       (mem_resp_valid_i && !wb_pending),
        .mem_resp_mshr_idx_i    (mshr_mem_req_idx),
        .mem_resp_data_i        (mem_resp_rdata_i),
        
        // Completion
        .complete_valid_o       (mshr_complete_valid),
        .complete_mshr_idx_o    (mshr_complete_idx),
        .complete_tag_o         (mshr_complete_tag),
        .complete_index_o       (mshr_complete_index),
        .complete_data_o        (mshr_complete_data),
        .complete_dirty_o       (mshr_complete_dirty),
        .complete_ack_i         (mshr_complete_ack),
        
        // Wakeup
        .wakeup_valid_o         (mshr_wakeup_valid),
        .wakeup_rob_idx_o       (mshr_wakeup_rob_idx),
        .wakeup_data_o          (mshr_wakeup_data),
        
        // Memory request
        .mem_req_valid_o        (mshr_mem_req_valid),
        .mem_req_addr_o         (mshr_mem_req_addr),
        .mem_req_mshr_idx_o     (mshr_mem_req_idx),
        .mem_req_ready_i        (mem_req_ready_i && !wb_pending),
        
        // Status
        .full_o                 (mshr_full),
        .entry_valid_o          ()
    );

endmodule
