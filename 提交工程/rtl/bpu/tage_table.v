//=================================================================
// Module: tage_table
// Description: TAGE Tagged Table Component
//              256 entries with partial tag
//              3-bit prediction counter + 2-bit useful counter
//              Parameterized history length
// Requirements: 7.1, 7.2
//=================================================================

`timescale 1ns/1ps

module tage_table #(
    parameter NUM_ENTRIES  = 256,
    parameter INDEX_BITS   = 8,
    parameter TAG_BITS     = 9,
    parameter HIST_LENGTH  = 8    // Geometric history length
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    input  wire [63:0]             ghr_i,           // Global history register
    output wire                    hit_o,           // Tag match
    output wire                    pred_taken_o,    // Prediction
    output wire [2:0]              pred_counter_o,  // 3-bit counter
    output wire [1:0]              useful_o,        // Useful counter
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [63:0]             update_ghr_i,
    input  wire                    update_taken_i,
    input  wire                    update_alloc_i,  // Allocate new entry
    input  wire                    update_useful_inc_i,
    input  wire                    update_useful_dec_i,
    input  wire                    update_useful_reset_i
);

    //=========================================================
    // Entry Structure
    //=========================================================
    reg                valid   [0:NUM_ENTRIES-1];
    reg [TAG_BITS-1:0] tag     [0:NUM_ENTRIES-1];
    reg [2:0]          counter [0:NUM_ENTRIES-1];  // 3-bit prediction
    reg [1:0]          useful  [0:NUM_ENTRIES-1];  // 2-bit useful
    
    integer i;
    
    //=========================================================
    // Hash Functions for Index and Tag
    //=========================================================
    function [INDEX_BITS-1:0] compute_index;
        input [31:0] pc;
        input [63:0] ghr;
        reg [INDEX_BITS-1:0] pc_hash;
        reg [INDEX_BITS-1:0] ghr_hash;
        begin
            pc_hash = pc[INDEX_BITS+1:2];
            // Fold history to index width
            ghr_hash = ghr[INDEX_BITS-1:0] ^ ghr[2*INDEX_BITS-1:INDEX_BITS];
            compute_index = pc_hash ^ ghr_hash;
        end
    endfunction
    
    function [TAG_BITS-1:0] compute_tag;
        input [31:0] pc;
        input [63:0] ghr;
        reg [TAG_BITS-1:0] pc_hash;
        reg [TAG_BITS-1:0] ghr_hash;
        begin
            pc_hash = pc[TAG_BITS+1:2] ^ pc[TAG_BITS+TAG_BITS+1:TAG_BITS+2];
            ghr_hash = ghr[TAG_BITS-1:0];
            compute_tag = pc_hash ^ ghr_hash;
        end
    endfunction
    
    //=========================================================
    // Prediction Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] pred_idx;
    wire [TAG_BITS-1:0]   pred_tag;
    
    assign pred_idx = compute_index(pc_i, ghr_i);
    assign pred_tag = compute_tag(pc_i, ghr_i);
    
    //=========================================================
    // Prediction Output
    //=========================================================
    assign hit_o = valid[pred_idx] && (tag[pred_idx] == pred_tag);
    assign pred_taken_o = counter[pred_idx][2];  // MSB determines prediction
    assign pred_counter_o = counter[pred_idx];
    assign useful_o = useful[pred_idx];
    
    //=========================================================
    // Update Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] update_idx;
    wire [TAG_BITS-1:0]   update_tag;
    
    assign update_idx = compute_index(update_pc_i, update_ghr_i);
    assign update_tag = compute_tag(update_pc_i, update_ghr_i);
    
    //=========================================================
    // Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 0;
                counter[i] <= 3'b100;  // Weakly taken
                useful[i] <= 2'b00;
            end
        end else if (update_valid_i) begin
            if (update_alloc_i) begin
                // Allocate new entry
                valid[update_idx] <= 1'b1;
                tag[update_idx] <= update_tag;
                counter[update_idx] <= update_taken_i ? 3'b100 : 3'b011;
                useful[update_idx] <= 2'b00;
            end else if (valid[update_idx] && tag[update_idx] == update_tag) begin
                // Update existing entry
                // Update prediction counter
                if (update_taken_i) begin
                    if (counter[update_idx] != 3'b111) begin
                        counter[update_idx] <= counter[update_idx] + 1;
                    end
                end else begin
                    if (counter[update_idx] != 3'b000) begin
                        counter[update_idx] <= counter[update_idx] - 1;
                    end
                end
                
                // Update useful counter
                if (update_useful_reset_i) begin
                    useful[update_idx] <= 2'b00;
                end else if (update_useful_inc_i) begin
                    if (useful[update_idx] != 2'b11) begin
                        useful[update_idx] <= useful[update_idx] + 1;
                    end
                end else if (update_useful_dec_i) begin
                    if (useful[update_idx] != 2'b00) begin
                        useful[update_idx] <= useful[update_idx] - 1;
                    end
                end
            end
        end
    end

endmodule
