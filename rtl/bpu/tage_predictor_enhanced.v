//=================================================================
// Module: tage_predictor_enhanced
// Description: Enhanced TAGE Branch Predictor
//              Bimodal base + 8 tagged tables with geometric history
//              History lengths: 5, 8, 13, 21, 34, 55, 89, 144
//              256-bit GHR, improved allocation policy
//              Supports speculative history and recovery
// Requirements: 7.1, 7.2, 7.3, 7.4
//=================================================================

`timescale 1ns/1ps

module tage_predictor_enhanced #(
    parameter GHR_WIDTH = 256
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    input  wire [GHR_WIDTH-1:0]    ghr_i,
    output wire                    pred_taken_o,
    output wire [3:0]              provider_o,      // Which table provided prediction (0-8)
    output wire                    alt_pred_o,      // Alternate prediction
    output wire                    high_conf_o,     // High confidence indicator
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [GHR_WIDTH-1:0]    update_ghr_i,
    input  wire                    update_taken_i,
    input  wire [3:0]              update_provider_i,
    input  wire                    update_alt_pred_i,
    input  wire                    update_pred_correct_i,
    input  wire                    update_alt_differs_i   // Alt prediction differs from provider
);

    //=========================================================
    // Parameters for 8 Tagged Tables (Geometric history lengths)
    // Following Fibonacci-like sequence for optimal coverage
    //=========================================================
    localparam T0_HIST = 5;
    localparam T1_HIST = 8;
    localparam T2_HIST = 13;
    localparam T3_HIST = 21;
    localparam T4_HIST = 34;
    localparam T5_HIST = 55;
    localparam T6_HIST = 89;
    localparam T7_HIST = 144;
    
    // Table sizes (larger tables for longer histories)
    localparam T0_ENTRIES = 512;   localparam T0_INDEX = 9;
    localparam T1_ENTRIES = 512;   localparam T1_INDEX = 9;
    localparam T2_ENTRIES = 512;   localparam T2_INDEX = 9;
    localparam T3_ENTRIES = 512;   localparam T3_INDEX = 9;
    localparam T4_ENTRIES = 256;   localparam T4_INDEX = 8;
    localparam T5_ENTRIES = 256;   localparam T5_INDEX = 8;
    localparam T6_ENTRIES = 256;   localparam T6_INDEX = 8;
    localparam T7_ENTRIES = 256;   localparam T7_INDEX = 8;
    
    // Tag widths (increasing for longer history tables)
    localparam T0_TAG = 9;
    localparam T1_TAG = 9;
    localparam T2_TAG = 10;
    localparam T3_TAG = 10;
    localparam T4_TAG = 11;
    localparam T5_TAG = 11;
    localparam T6_TAG = 12;
    localparam T7_TAG = 12;

    //=========================================================
    // Bimodal Base Predictor (4K entries)
    //=========================================================
    wire        bimodal_pred;
    wire [1:0]  bimodal_counter;
    
    bimodal_predictor #(
        .NUM_ENTRIES(4096),
        .INDEX_BITS(12)
    ) u_bimodal (
        .clk            (clk),
        .rst_n          (rst_n),
        .pc_i           (pc_i),
        .pred_taken_o   (bimodal_pred),
        .pred_counter_o (bimodal_counter),
        .update_valid_i (update_valid_i && update_provider_i == 4'd0),
        .update_pc_i    (update_pc_i),
        .update_taken_i (update_taken_i)
    );

    //=========================================================
    // Tagged Tables Instantiation (8 tables)
    //=========================================================
    // Table outputs
    wire [7:0] t_hit;
    wire [7:0] t_pred;
    wire [2:0] t_counter [0:7];
    wire [1:0] t_useful  [0:7];
    
    // Update signals
    wire [7:0] t_update_valid;
    wire [7:0] t_alloc;
    wire useful_inc, useful_dec;
    wire global_useful_reset;
    
    // Table 0: history length 5
    tage_table_enhanced #(
        .NUM_ENTRIES(T0_ENTRIES), .INDEX_BITS(T0_INDEX),
        .TAG_BITS(T0_TAG), .HIST_LENGTH(T0_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table0 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[0]), .pred_taken_o(t_pred[0]),
        .pred_counter_o(t_counter[0]), .useful_o(t_useful[0]),
        .update_valid_i(t_update_valid[0]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[0]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd1),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd1),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 1: history length 8
    tage_table_enhanced #(
        .NUM_ENTRIES(T1_ENTRIES), .INDEX_BITS(T1_INDEX),
        .TAG_BITS(T1_TAG), .HIST_LENGTH(T1_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table1 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[1]), .pred_taken_o(t_pred[1]),
        .pred_counter_o(t_counter[1]), .useful_o(t_useful[1]),
        .update_valid_i(t_update_valid[1]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[1]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd2),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd2),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 2: history length 13
    tage_table_enhanced #(
        .NUM_ENTRIES(T2_ENTRIES), .INDEX_BITS(T2_INDEX),
        .TAG_BITS(T2_TAG), .HIST_LENGTH(T2_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table2 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[2]), .pred_taken_o(t_pred[2]),
        .pred_counter_o(t_counter[2]), .useful_o(t_useful[2]),
        .update_valid_i(t_update_valid[2]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[2]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd3),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd3),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 3: history length 21
    tage_table_enhanced #(
        .NUM_ENTRIES(T3_ENTRIES), .INDEX_BITS(T3_INDEX),
        .TAG_BITS(T3_TAG), .HIST_LENGTH(T3_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table3 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[3]), .pred_taken_o(t_pred[3]),
        .pred_counter_o(t_counter[3]), .useful_o(t_useful[3]),
        .update_valid_i(t_update_valid[3]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[3]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd4),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd4),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 4: history length 34
    tage_table_enhanced #(
        .NUM_ENTRIES(T4_ENTRIES), .INDEX_BITS(T4_INDEX),
        .TAG_BITS(T4_TAG), .HIST_LENGTH(T4_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table4 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[4]), .pred_taken_o(t_pred[4]),
        .pred_counter_o(t_counter[4]), .useful_o(t_useful[4]),
        .update_valid_i(t_update_valid[4]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[4]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd5),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd5),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 5: history length 55
    tage_table_enhanced #(
        .NUM_ENTRIES(T5_ENTRIES), .INDEX_BITS(T5_INDEX),
        .TAG_BITS(T5_TAG), .HIST_LENGTH(T5_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table5 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[5]), .pred_taken_o(t_pred[5]),
        .pred_counter_o(t_counter[5]), .useful_o(t_useful[5]),
        .update_valid_i(t_update_valid[5]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[5]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd6),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd6),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 6: history length 89
    tage_table_enhanced #(
        .NUM_ENTRIES(T6_ENTRIES), .INDEX_BITS(T6_INDEX),
        .TAG_BITS(T6_TAG), .HIST_LENGTH(T6_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table6 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[6]), .pred_taken_o(t_pred[6]),
        .pred_counter_o(t_counter[6]), .useful_o(t_useful[6]),
        .update_valid_i(t_update_valid[6]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[6]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd7),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd7),
        .update_useful_reset_i(global_useful_reset)
    );
    
    // Table 7: history length 144
    tage_table_enhanced #(
        .NUM_ENTRIES(T7_ENTRIES), .INDEX_BITS(T7_INDEX),
        .TAG_BITS(T7_TAG), .HIST_LENGTH(T7_HIST), .GHR_WIDTH(GHR_WIDTH)
    ) u_table7 (
        .clk(clk), .rst_n(rst_n),
        .pc_i(pc_i), .ghr_i(ghr_i),
        .hit_o(t_hit[7]), .pred_taken_o(t_pred[7]),
        .pred_counter_o(t_counter[7]), .useful_o(t_useful[7]),
        .update_valid_i(t_update_valid[7]),
        .update_pc_i(update_pc_i), .update_ghr_i(update_ghr_i),
        .update_taken_i(update_taken_i),
        .update_alloc_i(t_alloc[7]),
        .update_useful_inc_i(useful_inc && update_provider_i == 4'd8),
        .update_useful_dec_i(useful_dec && update_provider_i == 4'd8),
        .update_useful_reset_i(global_useful_reset)
    );

    //=========================================================
    // Provider Selection (longest matching history wins)
    // With USE_ALT_ON_NA logic for weak predictions
    //=========================================================
    reg [3:0]  provider;
    reg        final_pred;
    reg        alt_prediction;
    reg        provider_weak;  // Provider's counter is weak
    
    // USE_ALT_ON_NA: 4-bit counter to decide when to use alt prediction
    // on newly allocated entries
    reg [3:0] use_alt_on_na_ctr;
    wire use_alt_on_na;
    assign use_alt_on_na = use_alt_on_na_ctr[3];  // Use alt when MSB is set
    
    always @(*) begin
        // Default: use bimodal
        provider = 4'd0;
        final_pred = bimodal_pred;
        alt_prediction = bimodal_pred;
        provider_weak = 1'b0;
        
        // Check tables from longest to shortest history (7 down to 0)
        // Provider is the longest matching table
        if (t_hit[7]) begin
            provider = 4'd8;
            final_pred = t_pred[7];
            provider_weak = (t_counter[7] == 3'b011) || (t_counter[7] == 3'b100);
            // Find alternate (next shorter matching)
            if (t_hit[6])      alt_prediction = t_pred[6];
            else if (t_hit[5]) alt_prediction = t_pred[5];
            else if (t_hit[4]) alt_prediction = t_pred[4];
            else if (t_hit[3]) alt_prediction = t_pred[3];
            else if (t_hit[2]) alt_prediction = t_pred[2];
            else if (t_hit[1]) alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[6]) begin
            provider = 4'd7;
            final_pred = t_pred[6];
            provider_weak = (t_counter[6] == 3'b011) || (t_counter[6] == 3'b100);
            if (t_hit[5])      alt_prediction = t_pred[5];
            else if (t_hit[4]) alt_prediction = t_pred[4];
            else if (t_hit[3]) alt_prediction = t_pred[3];
            else if (t_hit[2]) alt_prediction = t_pred[2];
            else if (t_hit[1]) alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[5]) begin
            provider = 4'd6;
            final_pred = t_pred[5];
            provider_weak = (t_counter[5] == 3'b011) || (t_counter[5] == 3'b100);
            if (t_hit[4])      alt_prediction = t_pred[4];
            else if (t_hit[3]) alt_prediction = t_pred[3];
            else if (t_hit[2]) alt_prediction = t_pred[2];
            else if (t_hit[1]) alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[4]) begin
            provider = 4'd5;
            final_pred = t_pred[4];
            provider_weak = (t_counter[4] == 3'b011) || (t_counter[4] == 3'b100);
            if (t_hit[3])      alt_prediction = t_pred[3];
            else if (t_hit[2]) alt_prediction = t_pred[2];
            else if (t_hit[1]) alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[3]) begin
            provider = 4'd4;
            final_pred = t_pred[3];
            provider_weak = (t_counter[3] == 3'b011) || (t_counter[3] == 3'b100);
            if (t_hit[2])      alt_prediction = t_pred[2];
            else if (t_hit[1]) alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[2]) begin
            provider = 4'd3;
            final_pred = t_pred[2];
            provider_weak = (t_counter[2] == 3'b011) || (t_counter[2] == 3'b100);
            if (t_hit[1])      alt_prediction = t_pred[1];
            else if (t_hit[0]) alt_prediction = t_pred[0];
            else               alt_prediction = bimodal_pred;
        end else if (t_hit[1]) begin
            provider = 4'd2;
            final_pred = t_pred[1];
            provider_weak = (t_counter[1] == 3'b011) || (t_counter[1] == 3'b100);
            if (t_hit[0]) alt_prediction = t_pred[0];
            else          alt_prediction = bimodal_pred;
        end else if (t_hit[0]) begin
            provider = 4'd1;
            final_pred = t_pred[0];
            provider_weak = (t_counter[0] == 3'b011) || (t_counter[0] == 3'b100);
            alt_prediction = bimodal_pred;
        end
        
        // USE_ALT_ON_NA: use alternate when provider is newly allocated and weak
        if (provider_weak && use_alt_on_na) begin
            final_pred = alt_prediction;
        end
    end
    
    assign pred_taken_o = final_pred;
    assign provider_o = provider;
    assign alt_pred_o = alt_prediction;
    assign high_conf_o = !provider_weak;

    //=========================================================
    // Update Table Selection
    //=========================================================
    assign t_update_valid[0] = update_valid_i && (update_provider_i == 4'd1);
    assign t_update_valid[1] = update_valid_i && (update_provider_i == 4'd2);
    assign t_update_valid[2] = update_valid_i && (update_provider_i == 4'd3);
    assign t_update_valid[3] = update_valid_i && (update_provider_i == 4'd4);
    assign t_update_valid[4] = update_valid_i && (update_provider_i == 4'd5);
    assign t_update_valid[5] = update_valid_i && (update_provider_i == 4'd6);
    assign t_update_valid[6] = update_valid_i && (update_provider_i == 4'd7);
    assign t_update_valid[7] = update_valid_i && (update_provider_i == 4'd8);
    
    //=========================================================
    // Useful Counter Management
    //=========================================================
    // Increment if provider was correct and alt was wrong
    assign useful_inc = update_valid_i && update_pred_correct_i && update_alt_differs_i;
    // Decrement if provider was wrong
    assign useful_dec = update_valid_i && !update_pred_correct_i;

    //=========================================================
    // Allocation Logic (improved)
    // On misprediction, allocate in longer history tables
    // Probabilistic allocation to avoid thrashing
    //=========================================================
    wire need_alloc;
    assign need_alloc = update_valid_i && !update_pred_correct_i;
    
    // LFSR for pseudo-random allocation decisions
    reg [7:0] lfsr;
    wire lfsr_bit;
    assign lfsr_bit = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 8'hA5;  // Non-zero seed
        else
            lfsr <= {lfsr[6:0], lfsr_bit};
    end
    
    // Allocate in tables with longer history than provider
    // Use probabilistic allocation to avoid excessive allocation
    wire [7:0] can_alloc;  // Which tables are candidates for allocation
    
    assign can_alloc[0] = (update_provider_i < 4'd1);
    assign can_alloc[1] = (update_provider_i < 4'd2);
    assign can_alloc[2] = (update_provider_i < 4'd3);
    assign can_alloc[3] = (update_provider_i < 4'd4);
    assign can_alloc[4] = (update_provider_i < 4'd5);
    assign can_alloc[5] = (update_provider_i < 4'd6);
    assign can_alloc[6] = (update_provider_i < 4'd7);
    assign can_alloc[7] = (update_provider_i < 4'd8);
    
    // Probabilistic: allocate only one or two entries
    // Prefer shorter history difference for stability
    assign t_alloc[0] = need_alloc && can_alloc[0] && (lfsr[0] || update_provider_i == 4'd0);
    assign t_alloc[1] = need_alloc && can_alloc[1] && (lfsr[1] || update_provider_i == 4'd1);
    assign t_alloc[2] = need_alloc && can_alloc[2] && lfsr[2];
    assign t_alloc[3] = need_alloc && can_alloc[3] && lfsr[3];
    assign t_alloc[4] = need_alloc && can_alloc[4] && lfsr[4] && lfsr[0];
    assign t_alloc[5] = need_alloc && can_alloc[5] && lfsr[5] && lfsr[1];
    assign t_alloc[6] = need_alloc && can_alloc[6] && lfsr[6] && lfsr[2];
    assign t_alloc[7] = need_alloc && can_alloc[7] && lfsr[7] && lfsr[3];

    //=========================================================
    // Global Useful Reset Counter
    // Periodically reset useful bits to prevent stale entries
    //=========================================================
    reg [17:0] reset_counter;  // Reset every ~256K branches
    
    assign global_useful_reset = (reset_counter == 0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            reset_counter <= 18'd0;
        else if (update_valid_i)
            reset_counter <= reset_counter + 1;
    end

    //=========================================================
    // USE_ALT_ON_NA Counter Update
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            use_alt_on_na_ctr <= 4'd8;  // Start in middle
        end else if (update_valid_i && provider_weak) begin
            // Update only when provider was weak (newly allocated)
            if (update_alt_differs_i) begin
                // Alt and provider predictions differ
                if (update_pred_correct_i) begin
                    // Provider was correct despite being weak: decrease use_alt
                    if (use_alt_on_na_ctr > 0)
                        use_alt_on_na_ctr <= use_alt_on_na_ctr - 1;
                end else begin
                    // Provider was wrong: increase use_alt
                    if (use_alt_on_na_ctr < 15)
                        use_alt_on_na_ctr <= use_alt_on_na_ctr + 1;
                end
            end
        end
    end

endmodule
