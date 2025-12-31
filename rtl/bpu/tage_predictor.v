//=================================================================
// Module: tage_predictor
// Description: TAGE Branch Predictor Top Level
//              Bimodal base + 4 tagged tables
//              Geometric history lengths: 8, 16, 32, 64
//              Parallel query and provider selection
// Requirements: 7.1, 7.2, 7.3, 7.4
//=================================================================

`timescale 1ns/1ps

module tage_predictor #(
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    input  wire [GHR_WIDTH-1:0]    ghr_i,
    output wire                    pred_taken_o,
    output wire [2:0]              provider_o,      // Which table provided prediction
    output wire                    alt_pred_o,      // Alternate prediction
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [GHR_WIDTH-1:0]    update_ghr_i,
    input  wire                    update_taken_i,
    input  wire [2:0]              update_provider_i,
    input  wire                    update_alt_pred_i,
    input  wire                    update_pred_correct_i
);

    //=========================================================
    // Bimodal Base Predictor
    //=========================================================
    wire        bimodal_pred;
    wire [1:0]  bimodal_counter;
    
    bimodal_predictor #(
        .NUM_ENTRIES(2048),
        .INDEX_BITS(11)
    ) u_bimodal (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc_i           (pc_i),
        .pred_taken_o   (bimodal_pred),
        .pred_counter_o (bimodal_counter),
        .update_valid_i (update_valid_i && update_provider_i == 3'd0),
        .update_pc_i    (update_pc_i),
        .update_taken_i (update_taken_i)
    );
    
    //=========================================================
    // Tagged Tables (geometric history lengths)
    //=========================================================
    // Table 0: history length 8
    wire        t0_hit, t0_pred;
    wire [2:0]  t0_counter;
    wire [1:0]  t0_useful;
    
    // Table 1: history length 16
    wire        t1_hit, t1_pred;
    wire [2:0]  t1_counter;
    wire [1:0]  t1_useful;
    
    // Table 2: history length 32
    wire        t2_hit, t2_pred;
    wire [2:0]  t2_counter;
    wire [1:0]  t2_useful;
    
    // Table 3: history length 64
    wire        t3_hit, t3_pred;
    wire [2:0]  t3_counter;
    wire [1:0]  t3_useful;
    
    // Update signals for each table
    wire t0_update_valid, t1_update_valid, t2_update_valid, t3_update_valid;
    wire t0_alloc, t1_alloc, t2_alloc, t3_alloc;
    wire useful_inc, useful_dec;
    
    tage_table #(
        .NUM_ENTRIES(256),
        .INDEX_BITS(8),
        .TAG_BITS(9),
        .HIST_LENGTH(8)
    ) u_table0 (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pc_i),
        .ghr_i              (ghr_i),
        .hit_o              (t0_hit),
        .pred_taken_o       (t0_pred),
        .pred_counter_o     (t0_counter),
        .useful_o           (t0_useful),
        .update_valid_i     (t0_update_valid),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_alloc_i     (t0_alloc),
        .update_useful_inc_i(useful_inc && update_provider_i == 3'd1),
        .update_useful_dec_i(useful_dec && update_provider_i == 3'd1),
        .update_useful_reset_i(1'b0)
    );
    
    tage_table #(
        .NUM_ENTRIES(256),
        .INDEX_BITS(8),
        .TAG_BITS(9),
        .HIST_LENGTH(16)
    ) u_table1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pc_i),
        .ghr_i              (ghr_i),
        .hit_o              (t1_hit),
        .pred_taken_o       (t1_pred),
        .pred_counter_o     (t1_counter),
        .useful_o           (t1_useful),
        .update_valid_i     (t1_update_valid),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_alloc_i     (t1_alloc),
        .update_useful_inc_i(useful_inc && update_provider_i == 3'd2),
        .update_useful_dec_i(useful_dec && update_provider_i == 3'd2),
        .update_useful_reset_i(1'b0)
    );
    
    tage_table #(
        .NUM_ENTRIES(256),
        .INDEX_BITS(8),
        .TAG_BITS(9),
        .HIST_LENGTH(32)
    ) u_table2 (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pc_i),
        .ghr_i              (ghr_i),
        .hit_o              (t2_hit),
        .pred_taken_o       (t2_pred),
        .pred_counter_o     (t2_counter),
        .useful_o           (t2_useful),
        .update_valid_i     (t2_update_valid),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_alloc_i     (t2_alloc),
        .update_useful_inc_i(useful_inc && update_provider_i == 3'd3),
        .update_useful_dec_i(useful_dec && update_provider_i == 3'd3),
        .update_useful_reset_i(1'b0)
    );
    
    tage_table #(
        .NUM_ENTRIES(256),
        .INDEX_BITS(8),
        .TAG_BITS(9),
        .HIST_LENGTH(64)
    ) u_table3 (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pc_i),
        .ghr_i              (ghr_i),
        .hit_o              (t3_hit),
        .pred_taken_o       (t3_pred),
        .pred_counter_o     (t3_counter),
        .useful_o           (t3_useful),
        .update_valid_i     (t3_update_valid),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_alloc_i     (t3_alloc),
        .update_useful_inc_i(useful_inc && update_provider_i == 3'd4),
        .update_useful_dec_i(useful_dec && update_provider_i == 3'd4),
        .update_useful_reset_i(1'b0)
    );

    //=========================================================
    // Provider Selection (longest matching history)
    //=========================================================
    reg [2:0]  provider;
    reg        final_pred;
    reg        alt_prediction;
    
    always @(*) begin
        // Default: use bimodal
        provider = 3'd0;
        final_pred = bimodal_pred;
        alt_prediction = bimodal_pred;
        
        // Check tables from longest to shortest history
        if (t3_hit) begin
            provider = 3'd4;
            final_pred = t3_pred;
            // Alt pred is from next shorter matching table
            if (t2_hit) alt_prediction = t2_pred;
            else if (t1_hit) alt_prediction = t1_pred;
            else if (t0_hit) alt_prediction = t0_pred;
            else alt_prediction = bimodal_pred;
        end else if (t2_hit) begin
            provider = 3'd3;
            final_pred = t2_pred;
            if (t1_hit) alt_prediction = t1_pred;
            else if (t0_hit) alt_prediction = t0_pred;
            else alt_prediction = bimodal_pred;
        end else if (t1_hit) begin
            provider = 3'd2;
            final_pred = t1_pred;
            if (t0_hit) alt_prediction = t0_pred;
            else alt_prediction = bimodal_pred;
        end else if (t0_hit) begin
            provider = 3'd1;
            final_pred = t0_pred;
            alt_prediction = bimodal_pred;
        end
    end
    
    assign pred_taken_o = final_pred;
    assign provider_o = provider;
    assign alt_pred_o = alt_prediction;
    
    //=========================================================
    // Update Logic
    //=========================================================
    // Update the provider table
    assign t0_update_valid = update_valid_i && (update_provider_i == 3'd1);
    assign t1_update_valid = update_valid_i && (update_provider_i == 3'd2);
    assign t2_update_valid = update_valid_i && (update_provider_i == 3'd3);
    assign t3_update_valid = update_valid_i && (update_provider_i == 3'd4);
    
    // Useful counter management
    // Increment if provider was correct and alt was wrong
    assign useful_inc = update_valid_i && update_pred_correct_i && 
                        (update_alt_pred_i != update_taken_i);
    // Decrement if provider was wrong
    assign useful_dec = update_valid_i && !update_pred_correct_i;
    
    // Allocation logic (simplified)
    // On misprediction, try to allocate in a longer history table
    wire need_alloc;
    assign need_alloc = update_valid_i && !update_pred_correct_i;
    
    // Simple allocation: try to allocate in the next longer table
    assign t0_alloc = need_alloc && (update_provider_i == 3'd0);
    assign t1_alloc = need_alloc && (update_provider_i == 3'd1);
    assign t2_alloc = need_alloc && (update_provider_i == 3'd2);
    assign t3_alloc = need_alloc && (update_provider_i == 3'd3);

endmodule
