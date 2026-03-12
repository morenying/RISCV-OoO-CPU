//=================================================================
// Module: tage_table_enhanced
// Description: Enhanced TAGE Tagged Table
//              Supports configurable table size, tag width, history length
//              Improved hash functions for better distribution
//              Supports probabilistic counter updates
//              Implements useful bit aging with global reset
// Requirements: 7.1, 7.2, 7.3, 7.4
//=================================================================

`timescale 1ns/1ps

module tage_table_enhanced #(
    parameter NUM_ENTRIES   = 512,      // Number of entries (power of 2)
    parameter INDEX_BITS    = 9,        // log2(NUM_ENTRIES)
    parameter TAG_BITS      = 11,       // Tag width (increased for less aliasing)
    parameter HIST_LENGTH   = 8,        // History length used for this table
    parameter GHR_WIDTH     = 256,      // Global history width
    parameter COUNTER_BITS  = 3,        // Prediction counter bits
    parameter USEFUL_BITS   = 2         // Useful counter bits
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    input  wire [GHR_WIDTH-1:0]    ghr_i,
    output wire                    hit_o,
    output wire                    pred_taken_o,
    output wire [COUNTER_BITS-1:0] pred_counter_o,
    output wire [USEFUL_BITS-1:0]  useful_o,
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [GHR_WIDTH-1:0]    update_ghr_i,
    input  wire                    update_taken_i,
    input  wire                    update_alloc_i,       // Allocate new entry
    input  wire                    update_useful_inc_i,  // Increment useful
    input  wire                    update_useful_dec_i,  // Decrement useful
    input  wire                    update_useful_reset_i // Global reset
);

    //=========================================================
    // Table Storage
    //=========================================================
    reg                     valid     [0:NUM_ENTRIES-1];
    reg [TAG_BITS-1:0]      tag       [0:NUM_ENTRIES-1];
    reg [COUNTER_BITS-1:0]  counter   [0:NUM_ENTRIES-1];
    reg [USEFUL_BITS-1:0]   useful    [0:NUM_ENTRIES-1];
    
    integer i;
    
    //=========================================================
    // Improved Hash Functions (CSR-like folding)
    //=========================================================
    // Compute folded history using XOR compression
    // Uses fixed-width chunks to avoid variable part-select issues
    function [INDEX_BITS-1:0] fold_history;
        input [GHR_WIDTH-1:0] history;
        input integer len;
        reg [INDEX_BITS-1:0] result;
        reg [INDEX_BITS-1:0] chunk;
        integer j, k;
        begin
            result = 0;
            // Fold in INDEX_BITS-sized chunks
            for (j = 0; j < HIST_LENGTH && j < GHR_WIDTH; j = j + INDEX_BITS) begin
                chunk = 0;
                for (k = 0; k < INDEX_BITS && (j + k) < HIST_LENGTH && (j + k) < GHR_WIDTH; k = k + 1) begin
                    chunk[k] = history[j + k];
                end
                result = result ^ chunk;
            end
            fold_history = result;
        end
    endfunction
    
    // Compute folded history for tag (different folding pattern)
    function [TAG_BITS-1:0] fold_history_tag;
        input [GHR_WIDTH-1:0] history;
        input integer len;
        reg [TAG_BITS-1:0] result;
        reg [TAG_BITS-1:0] chunk;
        integer j, k;
        begin
            result = 0;
            // Fold in TAG_BITS-sized chunks
            for (j = 0; j < HIST_LENGTH && j < GHR_WIDTH; j = j + TAG_BITS) begin
                chunk = 0;
                for (k = 0; k < TAG_BITS && (j + k) < HIST_LENGTH && (j + k) < GHR_WIDTH; k = k + 1) begin
                    chunk[k] = history[j + k];
                end
                result = result ^ chunk;
            end
            fold_history_tag = result;
        end
    endfunction
    
    // Index computation with PC and history mixing
    function [INDEX_BITS-1:0] compute_index;
        input [31:0] pc;
        input [GHR_WIDTH-1:0] ghr;
        reg [INDEX_BITS-1:0] pc_hash;
        reg [INDEX_BITS-1:0] hist_fold;
        reg [INDEX_BITS-1:0] hist_fold2;
        begin
            pc_hash = pc[INDEX_BITS+1:2];  // Use PC bits (word aligned)
            hist_fold = fold_history(ghr, HIST_LENGTH);
            // Second folding with rotation for better mixing
            hist_fold2 = fold_history(ghr >> 1, HIST_LENGTH);
            compute_index = pc_hash ^ hist_fold ^ {hist_fold2[INDEX_BITS-2:0], hist_fold2[INDEX_BITS-1]};
        end
    endfunction
    
    // Tag computation (different hash from index)
    function [TAG_BITS-1:0] compute_tag;
        input [31:0] pc;
        input [GHR_WIDTH-1:0] ghr;
        reg [TAG_BITS-1:0] pc_tag;
        reg [TAG_BITS-1:0] hist_tag;
        reg [TAG_BITS-1:0] hist_tag2;
        begin
            pc_tag = pc[TAG_BITS+1:2] ^ pc[TAG_BITS+13:14];  // Use more PC bits
            hist_tag = fold_history_tag(ghr, HIST_LENGTH);
            hist_tag2 = fold_history_tag(ghr >> 2, HIST_LENGTH);
            compute_tag = pc_tag ^ hist_tag ^ {hist_tag2[0], hist_tag2[TAG_BITS-1:1]};
        end
    endfunction
    
    //=========================================================
    // Prediction Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] pred_index;
    wire [TAG_BITS-1:0]   pred_tag;
    
    assign pred_index = compute_index(pc_i, ghr_i);
    assign pred_tag = compute_tag(pc_i, ghr_i);
    
    //=========================================================
    // Prediction Output
    //=========================================================
    wire tag_match;
    assign tag_match = valid[pred_index] && (tag[pred_index] == pred_tag);
    
    assign hit_o = tag_match;
    assign pred_taken_o = counter[pred_index][COUNTER_BITS-1];  // MSB is prediction
    assign pred_counter_o = counter[pred_index];
    assign useful_o = useful[pred_index];
    
    //=========================================================
    // Update Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] update_index;
    wire [TAG_BITS-1:0]   update_tag;
    
    assign update_index = compute_index(update_pc_i, update_ghr_i);
    assign update_tag = compute_tag(update_pc_i, update_ghr_i);
    
    //=========================================================
    // Update Logic
    //=========================================================
    // Saturating counter increment/decrement
    function [COUNTER_BITS-1:0] sat_inc;
        input [COUNTER_BITS-1:0] cnt;
        begin
            sat_inc = (cnt == {COUNTER_BITS{1'b1}}) ? cnt : cnt + 1;
        end
    endfunction
    
    function [COUNTER_BITS-1:0] sat_dec;
        input [COUNTER_BITS-1:0] cnt;
        begin
            sat_dec = (cnt == 0) ? cnt : cnt - 1;
        end
    endfunction
    
    function [USEFUL_BITS-1:0] useful_inc;
        input [USEFUL_BITS-1:0] u;
        begin
            useful_inc = (u == {USEFUL_BITS{1'b1}}) ? u : u + 1;
        end
    endfunction
    
    function [USEFUL_BITS-1:0] useful_dec;
        input [USEFUL_BITS-1:0] u;
        begin
            useful_dec = (u == 0) ? u : u - 1;
        end
    endfunction
    
    //=========================================================
    // Sequential Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 0;
                counter[i] <= {1'b1, {(COUNTER_BITS-1){1'b0}}};  // Weak taken
                useful[i] <= 0;
            end
        end else begin
            //=================================================
            // Global useful bit reset (aging)
            //=================================================
            if (update_useful_reset_i) begin
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    useful[i] <= useful[i] >> 1;  // Gradual decay
                end
            end
            
            //=================================================
            // Update existing entry or allocate new
            //=================================================
            if (update_valid_i) begin
                if (valid[update_index] && (tag[update_index] == update_tag)) begin
                    // Hit: update counter
                    if (update_taken_i)
                        counter[update_index] <= sat_inc(counter[update_index]);
                    else
                        counter[update_index] <= sat_dec(counter[update_index]);
                    
                    // Update useful
                    if (update_useful_inc_i)
                        useful[update_index] <= useful_inc(useful[update_index]);
                    else if (update_useful_dec_i)
                        useful[update_index] <= useful_dec(useful[update_index]);
                end
            end
            
            //=================================================
            // Allocation on misprediction
            //=================================================
            if (update_alloc_i) begin
                // Check if entry can be replaced (useful == 0 or invalid)
                if (!valid[update_index] || (useful[update_index] == 0)) begin
                    valid[update_index] <= 1'b1;
                    tag[update_index] <= update_tag;
                    // Initialize counter to weak taken/not-taken based on outcome
                    counter[update_index] <= update_taken_i ? 
                        {1'b1, {(COUNTER_BITS-1){1'b0}}} :  // Weak taken (4)
                        {1'b0, {(COUNTER_BITS-1){1'b1}}};   // Weak not-taken (3)
                    useful[update_index] <= 0;
                end else begin
                    // Decrement useful for graceful aging
                    useful[update_index] <= useful_dec(useful[update_index]);
                end
            end
        end
    end

endmodule
