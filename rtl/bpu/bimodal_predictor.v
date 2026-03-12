//=================================================================
// Module: bimodal_predictor
// Description: Bimodal Branch Predictor (Base predictor for TAGE)
//              2048 entries with 2-bit saturating counters
//              PC-indexed
// Requirements: 7.1
//=================================================================

`timescale 1ns/1ps

module bimodal_predictor #(
    parameter NUM_ENTRIES = 2048,
    parameter INDEX_BITS  = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    output wire                    pred_taken_o,
    output wire [1:0]              pred_counter_o,
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire                    update_taken_i
);

    //=========================================================
    // Counter Table
    //=========================================================
    reg [1:0] counters [0:NUM_ENTRIES-1];
    
    integer i;
    
    //=========================================================
    // Index Generation
    //=========================================================
    wire [INDEX_BITS-1:0] pred_idx;
    wire [INDEX_BITS-1:0] update_idx;
    
    assign pred_idx = pc_i[INDEX_BITS+1:2];  // Skip 2 LSBs (word aligned)
    assign update_idx = update_pc_i[INDEX_BITS+1:2];
    
    //=========================================================
    // Prediction Logic
    //=========================================================
    assign pred_counter_o = counters[pred_idx];
    assign pred_taken_o = counters[pred_idx][1];  // MSB determines prediction
    
    //=========================================================
    // Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all counters to weakly not-taken (2'b01)
            // This prevents false branch predictions for non-branch instructions
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                counters[i] <= 2'b01;
            end
        end else if (update_valid_i) begin
            // Saturating counter update
            if (update_taken_i) begin
                // Increment (saturate at 3)
                if (counters[update_idx] != 2'b11) begin
                    counters[update_idx] <= counters[update_idx] + 1;
                end
            end else begin
                // Decrement (saturate at 0)
                if (counters[update_idx] != 2'b00) begin
                    counters[update_idx] <= counters[update_idx] - 1;
                end
            end
        end
    end

endmodule
