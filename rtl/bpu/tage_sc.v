//=================================================================
// Module: tage_sc
// Description: Statistical Corrector for TAGE
//              Uses 4 GEHL tables to correct TAGE predictions
//              Targets hard-to-predict branches with biased behavior
//              Implements IMLI (Inner Most Loop Iteration) tracking
// Requirements: 7.1, 7.2, 7.3, 7.4
//=================================================================

`timescale 1ns/1ps

module tage_sc #(
    parameter GHR_WIDTH = 256
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    input  wire [GHR_WIDTH-1:0]    ghr_i,
    input  wire                    tage_pred_i,      // TAGE prediction
    input  wire                    tage_high_conf_i, // TAGE confidence
    output wire                    sc_pred_o,        // SC corrected prediction
    output wire                    sc_correct_o,     // SC wants to correct TAGE
    output wire [6:0]              sc_sum_o,         // SC confidence sum (signed)
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [GHR_WIDTH-1:0]    update_ghr_i,
    input  wire                    update_taken_i,
    input  wire                    update_tage_pred_i,
    input  wire                    update_tage_high_conf_i,
    input  wire                    update_sc_correct_i
);

    //=========================================================
    // GEHL Table Parameters
    // 4 tables with different history lengths
    //=========================================================
    localparam GEHL0_ENTRIES = 512;   localparam GEHL0_INDEX = 9;   localparam GEHL0_HIST = 4;
    localparam GEHL1_ENTRIES = 512;   localparam GEHL1_INDEX = 9;   localparam GEHL1_HIST = 8;
    localparam GEHL2_ENTRIES = 256;   localparam GEHL2_INDEX = 8;   localparam GEHL2_HIST = 16;
    localparam GEHL3_ENTRIES = 256;   localparam GEHL3_INDEX = 8;   localparam GEHL3_HIST = 32;
    
    localparam COUNTER_BITS = 6;  // 6-bit signed counters (-32 to +31)

    //=========================================================
    // GEHL Tables Storage
    //=========================================================
    reg signed [COUNTER_BITS-1:0] gehl0 [0:GEHL0_ENTRIES-1];
    reg signed [COUNTER_BITS-1:0] gehl1 [0:GEHL1_ENTRIES-1];
    reg signed [COUNTER_BITS-1:0] gehl2 [0:GEHL2_ENTRIES-1];
    reg signed [COUNTER_BITS-1:0] gehl3 [0:GEHL3_ENTRIES-1];
    
    // Bias table (indexed by PC only)
    reg signed [COUNTER_BITS-1:0] bias_table [0:511];  // 512 entries
    
    // IMLI counters (Inner Most Loop Iteration)
    reg [9:0] imli_counter;  // Current loop iteration
    reg signed [COUNTER_BITS-1:0] imli_table [0:255];  // 256 entries
    
    integer i;

    //=========================================================
    // Hash Functions for GEHL Index
    //=========================================================
    function [8:0] gehl_hash_9;
        input [31:0] pc;
        input [GHR_WIDTH-1:0] ghr;
        input integer hist_len;
        reg [8:0] pc_part;
        reg [8:0] hist_part;
        integer j;
        begin
            pc_part = pc[10:2];
            hist_part = 9'd0;
            for (j = 0; j < hist_len && j < 9; j = j + 1) begin
                hist_part[j] = ghr[j];
            end
            // XOR with rotated portions
            gehl_hash_9 = pc_part ^ hist_part ^ {hist_part[0], hist_part[8:1]};
        end
    endfunction
    
    function [7:0] gehl_hash_8;
        input [31:0] pc;
        input [GHR_WIDTH-1:0] ghr;
        input integer hist_len;
        reg [7:0] pc_part;
        reg [7:0] hist_fold;
        integer j, k;
        begin
            pc_part = pc[9:2];
            hist_fold = 8'd0;
            // Fold history - XOR each bit into corresponding position
            for (j = 0; j < hist_len && j < GHR_WIDTH; j = j + 1) begin
                k = j % 8;  // Target bit position
                hist_fold[k] = hist_fold[k] ^ ghr[j];
            end
            gehl_hash_8 = pc_part ^ hist_fold ^ {hist_fold[1:0], hist_fold[7:2]};
        end
    endfunction

    //=========================================================
    // Prediction Indices
    //=========================================================
    wire [GEHL0_INDEX-1:0] pred_idx0;
    wire [GEHL1_INDEX-1:0] pred_idx1;
    wire [GEHL2_INDEX-1:0] pred_idx2;
    wire [GEHL3_INDEX-1:0] pred_idx3;
    wire [8:0] pred_bias_idx;
    wire [7:0] pred_imli_idx;
    
    assign pred_idx0 = gehl_hash_9(pc_i, ghr_i, GEHL0_HIST);
    assign pred_idx1 = gehl_hash_9(pc_i, ghr_i, GEHL1_HIST);
    assign pred_idx2 = gehl_hash_8(pc_i, ghr_i, GEHL2_HIST);
    assign pred_idx3 = gehl_hash_8(pc_i, ghr_i, GEHL3_HIST);
    assign pred_bias_idx = pc_i[10:2];
    assign pred_imli_idx = pc_i[9:2] ^ imli_counter[7:0];

    //=========================================================
    // Prediction Computation
    //=========================================================
    wire signed [COUNTER_BITS-1:0] gehl0_val, gehl1_val, gehl2_val, gehl3_val;
    wire signed [COUNTER_BITS-1:0] bias_val, imli_val;
    
    assign gehl0_val = gehl0[pred_idx0];
    assign gehl1_val = gehl1[pred_idx1];
    assign gehl2_val = gehl2[pred_idx2];
    assign gehl3_val = gehl3[pred_idx3];
    assign bias_val = bias_table[pred_bias_idx];
    assign imli_val = imli_table[pred_imli_idx];
    
    // Sum all contributions (weighted)
    // Using 10-bit accumulator to avoid overflow
    wire signed [9:0] sc_sum_wide;
    assign sc_sum_wide = $signed({gehl0_val[COUNTER_BITS-1], gehl0_val}) +
                         $signed({gehl1_val[COUNTER_BITS-1], gehl1_val}) +
                         $signed({gehl2_val[COUNTER_BITS-1], gehl2_val}) +
                         $signed({gehl3_val[COUNTER_BITS-1], gehl3_val}) +
                         $signed({bias_val[COUNTER_BITS-1], bias_val}) +
                         $signed({imli_val[COUNTER_BITS-1], imli_val});
    
    // Saturate to 7-bit signed
    wire signed [6:0] sc_sum;
    assign sc_sum = (sc_sum_wide > 63) ? 7'sd63 :
                    (sc_sum_wide < -64) ? -7'sd64 :
                    sc_sum_wide[6:0];
    
    assign sc_sum_o = sc_sum;
    
    //=========================================================
    // SC Correction Decision
    //=========================================================
    // SC suggests correction if:
    // 1. TAGE confidence is low (weak prediction)
    // 2. SC sum disagrees with TAGE and has sufficient magnitude
    
    wire sc_suggests_taken;
    wire sc_disagrees;
    wire sc_strong_enough;
    
    assign sc_suggests_taken = (sc_sum >= 0);
    assign sc_disagrees = (sc_suggests_taken != tage_pred_i);
    
    // Threshold depends on TAGE confidence
    // For low confidence TAGE, use lower threshold
    wire [5:0] threshold;
    assign threshold = tage_high_conf_i ? 6'd24 : 6'd8;
    
    // SC magnitude check
    wire [5:0] sc_magnitude;
    assign sc_magnitude = (sc_sum >= 0) ? sc_sum[5:0] : (~sc_sum[5:0] + 1);
    
    assign sc_strong_enough = (sc_magnitude >= threshold);
    assign sc_correct_o = sc_disagrees && sc_strong_enough && !tage_high_conf_i;
    
    // Final prediction
    assign sc_pred_o = sc_correct_o ? sc_suggests_taken : tage_pred_i;

    //=========================================================
    // Update Indices
    //=========================================================
    wire [GEHL0_INDEX-1:0] upd_idx0;
    wire [GEHL1_INDEX-1:0] upd_idx1;
    wire [GEHL2_INDEX-1:0] upd_idx2;
    wire [GEHL3_INDEX-1:0] upd_idx3;
    wire [8:0] upd_bias_idx;
    wire [7:0] upd_imli_idx;
    
    assign upd_idx0 = gehl_hash_9(update_pc_i, update_ghr_i, GEHL0_HIST);
    assign upd_idx1 = gehl_hash_9(update_pc_i, update_ghr_i, GEHL1_HIST);
    assign upd_idx2 = gehl_hash_8(update_pc_i, update_ghr_i, GEHL2_HIST);
    assign upd_idx3 = gehl_hash_8(update_pc_i, update_ghr_i, GEHL3_HIST);
    assign upd_bias_idx = update_pc_i[10:2];
    assign upd_imli_idx = update_pc_i[9:2] ^ imli_counter[7:0];

    //=========================================================
    // Saturating Counter Functions
    //=========================================================
    function signed [COUNTER_BITS-1:0] sat_inc_signed;
        input signed [COUNTER_BITS-1:0] cnt;
        begin
            if (cnt == {1'b0, {(COUNTER_BITS-1){1'b1}}})  // Max positive
                sat_inc_signed = cnt;
            else
                sat_inc_signed = cnt + 1;
        end
    endfunction
    
    function signed [COUNTER_BITS-1:0] sat_dec_signed;
        input signed [COUNTER_BITS-1:0] cnt;
        begin
            if (cnt == {1'b1, {(COUNTER_BITS-1){1'b0}}})  // Min negative
                sat_dec_signed = cnt;
            else
                sat_dec_signed = cnt - 1;
        end
    endfunction

    //=========================================================
    // Update Logic
    //=========================================================
    // Update GEHL tables when SC correction was used or TAGE had low confidence
    wire should_update;
    assign should_update = update_sc_correct_i || !update_tage_high_conf_i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < GEHL0_ENTRIES; i = i + 1) gehl0[i] <= 0;
            for (i = 0; i < GEHL1_ENTRIES; i = i + 1) gehl1[i] <= 0;
            for (i = 0; i < GEHL2_ENTRIES; i = i + 1) gehl2[i] <= 0;
            for (i = 0; i < GEHL3_ENTRIES; i = i + 1) gehl3[i] <= 0;
            for (i = 0; i < 512; i = i + 1) bias_table[i] <= 0;
            for (i = 0; i < 256; i = i + 1) imli_table[i] <= 0;
            imli_counter <= 10'd0;
        end else if (update_valid_i) begin
            if (should_update) begin
                // Update all GEHL tables
                if (update_taken_i) begin
                    gehl0[upd_idx0] <= sat_inc_signed(gehl0[upd_idx0]);
                    gehl1[upd_idx1] <= sat_inc_signed(gehl1[upd_idx1]);
                    gehl2[upd_idx2] <= sat_inc_signed(gehl2[upd_idx2]);
                    gehl3[upd_idx3] <= sat_inc_signed(gehl3[upd_idx3]);
                    bias_table[upd_bias_idx] <= sat_inc_signed(bias_table[upd_bias_idx]);
                    imli_table[upd_imli_idx] <= sat_inc_signed(imli_table[upd_imli_idx]);
                end else begin
                    gehl0[upd_idx0] <= sat_dec_signed(gehl0[upd_idx0]);
                    gehl1[upd_idx1] <= sat_dec_signed(gehl1[upd_idx1]);
                    gehl2[upd_idx2] <= sat_dec_signed(gehl2[upd_idx2]);
                    gehl3[upd_idx3] <= sat_dec_signed(gehl3[upd_idx3]);
                    bias_table[upd_bias_idx] <= sat_dec_signed(bias_table[upd_bias_idx]);
                    imli_table[upd_imli_idx] <= sat_dec_signed(imli_table[upd_imli_idx]);
                end
            end
            
            // Update IMLI counter
            // Detect backward branches (potential loop back-edges)
            if (update_taken_i && ($signed(update_pc_i) > $signed(update_pc_i + 32'd4))) begin
                // Backward taken branch - potential loop iteration
                imli_counter <= imli_counter + 1;
            end else if (!update_taken_i && ($signed(update_pc_i) > $signed(update_pc_i + 32'd4))) begin
                // Backward not-taken - loop exit
                imli_counter <= 10'd0;
            end
        end
    end

endmodule
