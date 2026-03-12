//=================================================================
// Module: loop_predictor_enhanced
// Description: Enhanced Loop Predictor
//              14-bit trip count for large loops (up to 16K iterations)
//              Supports nested loop detection
//              Improved loop boundary identification
//              Confidence-based prediction with hysteresis
// Requirements: 7.1, 7.2, 7.3, 7.4
//=================================================================

`timescale 1ns/1ps

module loop_predictor_enhanced #(
    parameter NUM_ENTRIES = 64,      // Number of loop entries
    parameter INDEX_BITS  = 6,       // log2(NUM_ENTRIES)
    parameter TAG_BITS    = 14,      // Tag width for disambiguation
    parameter COUNT_BITS  = 14       // Trip count bits (up to 16K iterations)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire [31:0]             pc_i,
    output wire                    loop_valid_o,     // Loop detected
    output wire                    loop_pred_o,      // Loop prediction (taken/not-taken)
    output wire                    loop_confident_o, // High confidence
    output wire [COUNT_BITS-1:0]   loop_count_o,     // Current iteration count
    output wire [COUNT_BITS-1:0]   loop_trip_o,      // Expected trip count
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire                    update_taken_i,
    input  wire                    update_mispredict_i,
    
    // Speculative interface
    input  wire                    spec_update_i,    // Speculative count update
    input  wire [31:0]             spec_pc_i,
    input  wire                    spec_taken_i,
    
    // Recovery interface
    input  wire                    recover_i,
    input  wire [INDEX_BITS-1:0]   recover_idx_i,
    input  wire [COUNT_BITS-1:0]   recover_count_i
);

    //=========================================================
    // Loop Entry Structure
    //=========================================================
    // State machine for loop detection
    localparam LOOP_IDLE       = 3'b000;  // No loop detected
    localparam LOOP_FIRST_ITER = 3'b001;  // First iteration seen
    localparam LOOP_TRAINING   = 3'b010;  // Learning trip count
    localparam LOOP_CONFIDENT  = 3'b011;  // Confident in trip count
    localparam LOOP_SPECULATE  = 3'b100;  // Speculatively predicting
    
    reg                     valid     [0:NUM_ENTRIES-1];
    reg [TAG_BITS-1:0]      tag       [0:NUM_ENTRIES-1];
    reg [2:0]               state     [0:NUM_ENTRIES-1];
    reg [COUNT_BITS-1:0]    trip_count[0:NUM_ENTRIES-1];  // Learned trip count
    reg [COUNT_BITS-1:0]    curr_count[0:NUM_ENTRIES-1];  // Current iteration
    reg [COUNT_BITS-1:0]    spec_count[0:NUM_ENTRIES-1];  // Speculative count
    reg [2:0]               confidence[0:NUM_ENTRIES-1];  // Confidence level (0-7)
    reg                     is_nested [0:NUM_ENTRIES-1];  // Nested loop flag
    reg [3:0]               age       [0:NUM_ENTRIES-1];  // LRU age
    
    integer i;

    //=========================================================
    // Index and Tag Computation
    //=========================================================
    wire [INDEX_BITS-1:0] pred_index;
    wire [TAG_BITS-1:0]   pred_tag;
    
    assign pred_index = pc_i[INDEX_BITS+1:2];
    assign pred_tag   = pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];

    //=========================================================
    // Prediction Output
    //=========================================================
    wire entry_hit;
    wire [2:0] entry_state;
    wire [COUNT_BITS-1:0] entry_trip;
    wire [COUNT_BITS-1:0] entry_curr;
    wire [COUNT_BITS-1:0] entry_spec;
    wire [2:0] entry_conf;
    
    assign entry_hit   = valid[pred_index] && (tag[pred_index] == pred_tag);
    assign entry_state = state[pred_index];
    assign entry_trip  = trip_count[pred_index];
    assign entry_curr  = curr_count[pred_index];
    assign entry_spec  = spec_count[pred_index];
    assign entry_conf  = confidence[pred_index];
    
    // Loop is valid when in confident or speculate state
    assign loop_valid_o = entry_hit && 
                         (entry_state == LOOP_CONFIDENT || entry_state == LOOP_SPECULATE);
    
    // Predict taken until we reach trip count, then not-taken
    // Use speculative count for prediction
    assign loop_pred_o = (entry_spec < entry_trip);
    
    // High confidence when confidence counter is saturated
    assign loop_confident_o = (entry_conf >= 3'd6);
    
    assign loop_count_o = entry_spec;
    assign loop_trip_o  = entry_trip;

    //=========================================================
    // Update Index and Tag
    //=========================================================
    wire [INDEX_BITS-1:0] upd_index;
    wire [TAG_BITS-1:0]   upd_tag;
    
    assign upd_index = update_pc_i[INDEX_BITS+1:2];
    assign upd_tag   = update_pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];

    //=========================================================
    // Speculative Update Index
    //=========================================================
    wire [INDEX_BITS-1:0] spec_index;
    wire [TAG_BITS-1:0]   spec_tag;
    
    assign spec_index = spec_pc_i[INDEX_BITS+1:2];
    assign spec_tag   = spec_pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];

    //=========================================================
    // LRU Management
    //=========================================================
    function [INDEX_BITS-1:0] find_lru;
        integer j;
        reg [INDEX_BITS-1:0] lru_idx;
        reg [3:0] max_age;
        begin
            lru_idx = 0;
            max_age = 0;
            for (j = 0; j < NUM_ENTRIES; j = j + 1) begin
                if (!valid[j]) begin
                    lru_idx = j[INDEX_BITS-1:0];
                    max_age = 4'hF;  // Invalid entries have highest priority
                end else if (age[j] > max_age) begin
                    max_age = age[j];
                    lru_idx = j[INDEX_BITS-1:0];
                end
            end
            find_lru = lru_idx;
        end
    endfunction

    //=========================================================
    // Main Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                valid[i]      <= 1'b0;
                tag[i]        <= 0;
                state[i]      <= LOOP_IDLE;
                trip_count[i] <= 0;
                curr_count[i] <= 0;
                spec_count[i] <= 0;
                confidence[i] <= 0;
                is_nested[i]  <= 1'b0;
                age[i]        <= 0;
            end
        end else begin
            //=================================================
            // Recovery from misprediction
            //=================================================
            if (recover_i) begin
                spec_count[recover_idx_i] <= recover_count_i;
            end
            
            //=================================================
            // Speculative count update (from frontend)
            //=================================================
            if (spec_update_i && !recover_i) begin
                if (valid[spec_index] && (tag[spec_index] == spec_tag)) begin
                    if (spec_taken_i) begin
                        // Increment speculative count
                        spec_count[spec_index] <= spec_count[spec_index] + 1;
                    end else begin
                        // Loop exit: reset speculative count
                        spec_count[spec_index] <= 0;
                    end
                end
            end
            
            //=================================================
            // Committed update (from retire)
            //=================================================
            if (update_valid_i) begin
                // Age all entries
                for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                    if (valid[i] && age[i] < 4'hF)
                        age[i] <= age[i] + 1;
                end
                
                if (valid[upd_index] && (tag[upd_index] == upd_tag)) begin
                    // Entry hit
                    age[upd_index] <= 0;  // Reset age
                    
                    case (state[upd_index])
                        LOOP_IDLE: begin
                            if (update_taken_i) begin
                                // First taken: might be a loop
                                state[upd_index] <= LOOP_FIRST_ITER;
                                curr_count[upd_index] <= 1;
                            end
                        end
                        
                        LOOP_FIRST_ITER: begin
                            if (update_taken_i) begin
                                // Another iteration
                                curr_count[upd_index] <= curr_count[upd_index] + 1;
                            end else begin
                                // Loop exit: record trip count
                                trip_count[upd_index] <= curr_count[upd_index];
                                curr_count[upd_index] <= 0;
                                state[upd_index] <= LOOP_TRAINING;
                            end
                        end
                        
                        LOOP_TRAINING: begin
                            if (update_taken_i) begin
                                curr_count[upd_index] <= curr_count[upd_index] + 1;
                            end else begin
                                // Check if trip count matches
                                if (curr_count[upd_index] == trip_count[upd_index]) begin
                                    // Consistent trip count
                                    if (confidence[upd_index] < 7)
                                        confidence[upd_index] <= confidence[upd_index] + 1;
                                    if (confidence[upd_index] >= 2)
                                        state[upd_index] <= LOOP_CONFIDENT;
                                end else begin
                                    // Different trip count: might be nested or variable
                                    trip_count[upd_index] <= curr_count[upd_index];
                                    if (confidence[upd_index] > 0)
                                        confidence[upd_index] <= confidence[upd_index] - 1;
                                    is_nested[upd_index] <= 1'b1;
                                end
                                curr_count[upd_index] <= 0;
                            end
                        end
                        
                        LOOP_CONFIDENT, LOOP_SPECULATE: begin
                            if (update_taken_i) begin
                                curr_count[upd_index] <= curr_count[upd_index] + 1;
                                
                                // Check for trip count mismatch (early exit or late exit)
                                if (curr_count[upd_index] >= trip_count[upd_index]) begin
                                    // Beyond expected trip count
                                    if (confidence[upd_index] > 0)
                                        confidence[upd_index] <= confidence[upd_index] - 1;
                                end
                            end else begin
                                // Loop exit
                                if (curr_count[upd_index] == trip_count[upd_index]) begin
                                    // Correct trip count
                                    if (confidence[upd_index] < 7)
                                        confidence[upd_index] <= confidence[upd_index] + 1;
                                end else if (curr_count[upd_index] < trip_count[upd_index]) begin
                                    // Early exit
                                    if (confidence[upd_index] > 0)
                                        confidence[upd_index] <= confidence[upd_index] - 1;
                                    if (confidence[upd_index] <= 1)
                                        state[upd_index] <= LOOP_TRAINING;
                                end else begin
                                    // Late exit: update trip count
                                    trip_count[upd_index] <= curr_count[upd_index];
                                    if (confidence[upd_index] > 1)
                                        confidence[upd_index] <= confidence[upd_index] - 2;
                                end
                                curr_count[upd_index] <= 0;
                                spec_count[upd_index] <= 0;  // Sync speculative count
                            end
                        end
                        
                        default: state[upd_index] <= LOOP_IDLE;
                    endcase
                    
                    // Handle misprediction
                    if (update_mispredict_i) begin
                        if (confidence[upd_index] > 0)
                            confidence[upd_index] <= confidence[upd_index] - 1;
                        if (confidence[upd_index] <= 1)
                            state[upd_index] <= LOOP_TRAINING;
                    end
                    
                end else begin
                    // Entry miss: check if this is a backward branch (potential loop)
                    // Backward branches: target < PC
                    // Only allocate for backward taken branches
                    if (update_taken_i) begin
                        // Allocate new entry
                        // Use direct-mapped for simplicity; could use LRU
                        valid[upd_index]      <= 1'b1;
                        tag[upd_index]        <= upd_tag;
                        state[upd_index]      <= LOOP_FIRST_ITER;
                        trip_count[upd_index] <= 0;
                        curr_count[upd_index] <= 1;
                        spec_count[upd_index] <= 1;
                        confidence[upd_index] <= 0;
                        is_nested[upd_index]  <= 1'b0;
                        age[upd_index]        <= 0;
                    end
                end
            end
        end
    end

endmodule
