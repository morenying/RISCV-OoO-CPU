//=================================================================
// Module: loop_predictor
// Description: Loop Branch Predictor
//              32 entries for loop detection
//              Iteration counter for loop exit prediction
// Requirements: 7.8
//=================================================================

`timescale 1ns/1ps

module loop_predictor #(
    parameter NUM_ENTRIES = 32,
    parameter INDEX_BITS  = 5,
    parameter TAG_BITS    = 14,
    parameter COUNT_BITS  = 10
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    output wire                    hit_o,
    output wire                    pred_exit_o,     // Predict loop exit
    output wire                    confident_o,     // High confidence
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire                    update_taken_i,  // Branch taken (loop continues)
    input  wire                    update_mispredict_i
);

    //=========================================================
    // Loop Entry Structure
    //=========================================================
    reg                     valid       [0:NUM_ENTRIES-1];
    reg [TAG_BITS-1:0]      tag         [0:NUM_ENTRIES-1];
    reg [COUNT_BITS-1:0]    trip_count  [0:NUM_ENTRIES-1];  // Expected iterations
    reg [COUNT_BITS-1:0]    curr_count  [0:NUM_ENTRIES-1];  // Current iteration
    reg [1:0]               confidence  [0:NUM_ENTRIES-1];  // Confidence level
    reg                     speculative [0:NUM_ENTRIES-1];  // Learning mode
    
    integer i;
    
    //=========================================================
    // Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] lookup_idx;
    wire [TAG_BITS-1:0]   lookup_tag;
    wire [INDEX_BITS-1:0] update_idx;
    wire [TAG_BITS-1:0]   update_tag;
    
    assign lookup_idx = pc_i[INDEX_BITS+1:2];
    assign lookup_tag = pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];
    assign update_idx = update_pc_i[INDEX_BITS+1:2];
    assign update_tag = update_pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];
    
    //=========================================================
    // Lookup Logic
    //=========================================================
    wire tag_match;
    assign tag_match = valid[lookup_idx] && (tag[lookup_idx] == lookup_tag);
    assign hit_o = tag_match && !speculative[lookup_idx];
    
    // Predict exit when current count reaches trip count
    assign pred_exit_o = tag_match && (curr_count[lookup_idx] >= trip_count[lookup_idx]);
    assign confident_o = tag_match && (confidence[lookup_idx] == 2'b11);
    
    //=========================================================
    // Update Logic
    //=========================================================
    wire update_tag_match;
    assign update_tag_match = valid[update_idx] && (tag[update_idx] == update_tag);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 0;
                trip_count[i] <= 0;
                curr_count[i] <= 0;
                confidence[i] <= 0;
                speculative[i] <= 1'b1;
            end
        end else if (update_valid_i) begin
            if (update_tag_match) begin
                if (update_taken_i) begin
                    // Loop continues
                    curr_count[update_idx] <= curr_count[update_idx] + 1;
                end else begin
                    // Loop exit
                    if (speculative[update_idx]) begin
                        // Learning: record trip count
                        trip_count[update_idx] <= curr_count[update_idx];
                        speculative[update_idx] <= 1'b0;
                        confidence[update_idx] <= 2'b01;
                    end else if (curr_count[update_idx] == trip_count[update_idx]) begin
                        // Correct prediction: increase confidence
                        if (confidence[update_idx] != 2'b11) begin
                            confidence[update_idx] <= confidence[update_idx] + 1;
                        end
                    end else begin
                        // Wrong trip count: update and reduce confidence
                        trip_count[update_idx] <= curr_count[update_idx];
                        if (confidence[update_idx] != 2'b00) begin
                            confidence[update_idx] <= confidence[update_idx] - 1;
                        end
                    end
                    // Reset current count for next loop instance
                    curr_count[update_idx] <= 0;
                end
                
                // Handle misprediction
                if (update_mispredict_i) begin
                    if (confidence[update_idx] != 2'b00) begin
                        confidence[update_idx] <= confidence[update_idx] - 1;
                    end else begin
                        // Very low confidence: invalidate entry
                        valid[update_idx] <= 1'b0;
                    end
                end
            end else begin
                // Allocate new entry (potential loop)
                valid[update_idx] <= 1'b1;
                tag[update_idx] <= update_tag;
                trip_count[update_idx] <= 0;
                curr_count[update_idx] <= update_taken_i ? 1 : 0;
                confidence[update_idx] <= 2'b00;
                speculative[update_idx] <= 1'b1;
            end
        end
    end

endmodule
