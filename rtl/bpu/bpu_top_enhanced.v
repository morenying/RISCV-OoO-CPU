//=================================================================
// Module: bpu_top_enhanced
// Description: Enhanced Branch Prediction Unit Top-Level
//              Integrates: TAGE-SC-L, Loop Predictor, BTB, RAS
//              256-bit GHR, Speculative History Management
//              Target: 97%+ branch prediction accuracy
// Requirements: 2.1-2.6
//=================================================================

`timescale 1ns/1ps

module bpu_top_enhanced #(
    parameter ADDR_WIDTH      = 32,
    parameter GHR_WIDTH       = 256,
    parameter BTB_SIZE        = 2048,
    parameter RAS_DEPTH       = 32,
    parameter ROB_IDX_BITS    = 6,
    parameter NUM_CHECKPOINTS = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Fetch Interface
    //=========================================================
    input  wire [ADDR_WIDTH-1:0]    fetch_pc_i,
    input  wire                     fetch_valid_i,
    
    output wire                     pred_valid_o,
    output wire                     pred_taken_o,
    output wire [ADDR_WIDTH-1:0]    pred_target_o,
    output wire                     pred_is_branch_o,
    output wire                     pred_is_call_o,
    output wire                     pred_is_return_o,
    output wire [2:0]               pred_confidence_o,  // 0=low, 7=high
    
    //=========================================================
    // Checkpoint Interface (from Rename)
    //=========================================================
    input  wire                     checkpoint_create_i,
    input  wire [ROB_IDX_BITS-1:0]  checkpoint_rob_idx_i,
    output wire [2:0]               checkpoint_id_o,
    output wire                     checkpoint_valid_o,
    
    //=========================================================
    // Update Interface (from Execute - branch resolution)
    //=========================================================
    input  wire                     update_valid_i,
    input  wire [ADDR_WIDTH-1:0]    update_pc_i,
    input  wire                     update_taken_i,
    input  wire [ADDR_WIDTH-1:0]    update_target_i,
    input  wire                     update_is_branch_i,
    input  wire                     update_is_call_i,
    input  wire                     update_is_return_i,
    input  wire                     update_mispred_i,
    input  wire [2:0]               update_checkpoint_id_i,
    input  wire [GHR_WIDTH-1:0]     update_ghr_i,       // GHR at prediction time
    
    //=========================================================
    // Commit Interface (from ROB)
    //=========================================================
    input  wire                     commit_valid_i,
    input  wire [ROB_IDX_BITS-1:0]  commit_rob_idx_i,
    input  wire                     commit_is_branch_i,
    input  wire                     commit_taken_i,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    
    //=========================================================
    // GHR Output (for checkpoint save)
    //=========================================================
    output wire [GHR_WIDTH-1:0]     current_ghr_o
);

    //=========================================================
    // Internal Wires
    //=========================================================
    // Speculative History Manager
    wire [GHR_WIDTH-1:0] spec_ghr;
    wire [GHR_WIDTH-1:0] committed_ghr;
    wire [31:0] path_history;
    
    // TAGE Predictor
    wire tage_pred_valid;
    wire tage_pred_taken;
    wire [2:0] tage_provider_idx;
    wire tage_use_alt;
    
    // Statistical Corrector
    wire sc_pred_valid;
    wire sc_pred_taken;
    wire sc_override;
    
    // Loop Predictor
    wire loop_pred_valid;
    wire loop_pred_taken;
    wire loop_confident;
    
    // BTB
    wire btb_hit;
    wire [ADDR_WIDTH-1:0] btb_target;
    wire btb_is_branch;
    wire btb_is_call;
    wire btb_is_return;
    wire [1:0] btb_type;
    
    // RAS
    wire [ADDR_WIDTH-1:0] ras_top;
    wire ras_valid;
    
    //=========================================================
    // Speculative History Manager
    //=========================================================
    speculative_history_manager #(
        .GHR_WIDTH       (GHR_WIDTH),
        .NUM_CHECKPOINTS (NUM_CHECKPOINTS),
        .ROB_IDX_BITS    (ROB_IDX_BITS)
    ) u_spec_hist_mgr (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        .update_valid_i         (pred_valid_o && fetch_valid_i),
        .update_taken_i         (pred_taken_o),
        .update_is_branch_i     (pred_is_branch_o),
        .update_pc_i            (fetch_pc_i),
        
        .checkpoint_create_i    (checkpoint_create_i),
        .checkpoint_rob_idx_i   (checkpoint_rob_idx_i),
        .checkpoint_id_o        (checkpoint_id_o),
        .checkpoint_valid_o     (checkpoint_valid_o),
        
        .recover_valid_i        (update_valid_i && update_mispred_i),
        .recover_id_i           (update_checkpoint_id_i),
        .recover_direction_i    (update_taken_i),
        
        .commit_valid_i         (commit_valid_i),
        .commit_rob_idx_i       (commit_rob_idx_i),
        .commit_is_branch_i     (commit_is_branch_i),
        .commit_taken_i         (commit_taken_i),
        
        .flush_i                (flush_i),
        
        .speculative_ghr_o      (spec_ghr),
        .committed_ghr_o        (committed_ghr),
        .path_history_o         (path_history)
    );
    
    assign current_ghr_o = spec_ghr;
    
    //=========================================================
    // Enhanced TAGE Predictor
    //=========================================================
    // Additional TAGE signals
    wire [3:0] tage_provider_raw;
    wire       tage_alt_pred;
    wire       tage_high_conf;
    
    tage_predictor_enhanced #(
        .GHR_WIDTH      (GHR_WIDTH)
    ) u_tage (
        .clk                (clk),
        .rst_n              (rst_n),
        // Prediction interface
        .pc_i               (fetch_pc_i),
        .ghr_i              (spec_ghr),
        .pred_taken_o       (tage_pred_taken),
        .provider_o         (tage_provider_raw),
        .alt_pred_o         (tage_alt_pred),
        .high_conf_o        (tage_high_conf),
        // Update interface
        .update_valid_i     (update_valid_i && update_is_branch_i),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_provider_i  (4'd0),
        .update_alt_pred_i  (1'b0),
        .update_pred_correct_i(~update_mispred_i),
        .update_alt_differs_i(1'b0)
    );
    
    assign tage_pred_valid = fetch_valid_i;
    assign tage_provider_idx = tage_provider_raw[2:0];
    assign tage_use_alt = ~tage_high_conf;
    
    //=========================================================
    // Statistical Corrector
    //=========================================================
    wire [6:0] sc_sum_out;
    
    tage_sc #(
        .GHR_WIDTH      (GHR_WIDTH)
    ) u_sc (
        .clk                (clk),
        .rst_n              (rst_n),
        // Prediction interface
        .pc_i               (fetch_pc_i),
        .ghr_i              (spec_ghr),
        .tage_pred_i        (tage_pred_taken),
        .tage_high_conf_i   (tage_high_conf),
        .sc_pred_o          (sc_pred_taken),
        .sc_correct_o       (sc_override),
        .sc_sum_o           (sc_sum_out),
        // Update interface
        .update_valid_i     (update_valid_i && update_is_branch_i),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (update_ghr_i),
        .update_taken_i     (update_taken_i),
        .update_tage_pred_i (tage_pred_taken),
        .update_tage_high_conf_i(tage_high_conf),
        .update_sc_correct_i(sc_override)
    );
    
    //=========================================================
    // Loop Predictor
    //=========================================================
    wire [13:0] loop_count_out, loop_trip_out;
    
    loop_predictor_enhanced #(
        .NUM_ENTRIES(64),
        .INDEX_BITS(6),
        .TAG_BITS(14),
        .COUNT_BITS(14)
    ) u_loop (
        .clk                (clk),
        .rst_n              (rst_n),
        // Prediction interface
        .pc_i               (fetch_pc_i),
        .loop_valid_o       (loop_pred_valid),
        .loop_pred_o        (loop_pred_taken),
        .loop_confident_o   (loop_confident),
        .loop_count_o       (loop_count_out),
        .loop_trip_o        (loop_trip_out),
        // Update interface
        .update_valid_i     (update_valid_i && update_is_branch_i),
        .update_pc_i        (update_pc_i),
        .update_taken_i     (update_taken_i),
        .update_mispredict_i(update_mispred_i),
        // Speculative interface
        .spec_update_i      (fetch_valid_i),
        .spec_pc_i          (fetch_pc_i),
        .spec_taken_i       (tage_pred_taken),
        // Recovery interface
        .recover_i          (update_mispred_i),
        .recover_idx_i      (6'd0),
        .recover_count_i    (14'd0)
    );
    
    //=========================================================
    // Branch Target Buffer (BTB)
    //=========================================================
    btb #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .NUM_ENTRIES    (BTB_SIZE)
    ) u_btb (
        .clk                (clk),
        .rst_n              (rst_n),
        
        .lookup_pc_i        (fetch_pc_i),
        .lookup_valid_i     (fetch_valid_i),
        
        .hit_o              (btb_hit),
        .target_o           (btb_target),
        .is_branch_o        (btb_is_branch),
        .is_call_o          (btb_is_call),
        .is_return_o        (btb_is_return),
        .branch_type_o      (btb_type),
        
        .update_valid_i     (update_valid_i),
        .update_pc_i        (update_pc_i),
        .update_target_i    (update_target_i),
        .update_is_branch_i (update_is_branch_i),
        .update_is_call_i   (update_is_call_i),
        .update_is_return_i (update_is_return_i)
    );
    
    //=========================================================
    // Return Address Stack (RAS)
    //=========================================================
    ras #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DEPTH          (RAS_DEPTH)
    ) u_ras (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .push_i         (pred_valid_o && pred_is_call_o && fetch_valid_i),
        .push_addr_i    (fetch_pc_i + 4),  // Return address is PC+4
        
        .pop_i          (pred_valid_o && pred_is_return_o && fetch_valid_i),
        
        .top_o          (ras_top),
        .valid_o        (ras_valid),
        
        .flush_i        (flush_i),
        .recover_i      (update_valid_i && update_mispred_i && (update_is_call_i || update_is_return_i))
    );
    
    //=========================================================
    // Final Prediction Logic
    //=========================================================
    // Combine all predictors
    wire final_taken;
    wire [2:0] final_confidence;
    
    // Priority: Loop (if confident) > SC Override > TAGE
    assign final_taken = (loop_pred_valid && loop_confident) ? loop_pred_taken :
                         (sc_override) ? sc_pred_taken :
                         tage_pred_taken;
    
    // Confidence calculation
    assign final_confidence = (loop_pred_valid && loop_confident) ? 3'd7 :  // Highest for loop
                              (tage_provider_idx >= 5) ? 3'd6 :              // Long history match
                              (tage_provider_idx >= 3) ? 3'd5 :              // Medium history
                              (sc_override) ? 3'd4 :                          // SC correction
                              (tage_provider_idx >= 1) ? 3'd3 :              // Short history
                              3'd2;                                           // Bimodal only
    
    // Target selection
    wire [ADDR_WIDTH-1:0] final_target;
    assign final_target = btb_is_return ? ras_top :
                          btb_hit ? btb_target :
                          fetch_pc_i + 4;  // Fallback: next sequential
    
    //=========================================================
    // Output Assignments
    //=========================================================
    assign pred_valid_o = btb_hit || btb_is_branch;
    assign pred_taken_o = final_taken;
    assign pred_target_o = final_target;
    assign pred_is_branch_o = btb_is_branch;
    assign pred_is_call_o = btb_is_call;
    assign pred_is_return_o = btb_is_return;
    assign pred_confidence_o = final_confidence;

endmodule

//=================================================================
// Simple BTB Module
//=================================================================
module btb #(
    parameter ADDR_WIDTH   = 32,
    parameter NUM_ENTRIES  = 2048
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    input  wire [ADDR_WIDTH-1:0]    lookup_pc_i,
    input  wire                     lookup_valid_i,
    
    output wire                     hit_o,
    output wire [ADDR_WIDTH-1:0]    target_o,
    output wire                     is_branch_o,
    output wire                     is_call_o,
    output wire                     is_return_o,
    output wire [1:0]               branch_type_o,
    
    input  wire                     update_valid_i,
    input  wire [ADDR_WIDTH-1:0]    update_pc_i,
    input  wire [ADDR_WIDTH-1:0]    update_target_i,
    input  wire                     update_is_branch_i,
    input  wire                     update_is_call_i,
    input  wire                     update_is_return_i
);
    localparam INDEX_BITS = $clog2(NUM_ENTRIES);
    localparam TAG_BITS = ADDR_WIDTH - INDEX_BITS - 2;
    
    reg [TAG_BITS-1:0]      tag_array    [0:NUM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    target_array [0:NUM_ENTRIES-1];
    reg [1:0]               type_array   [0:NUM_ENTRIES-1];  // 00=branch, 01=call, 10=return
    reg [NUM_ENTRIES-1:0]   valid_array;
    
    wire [INDEX_BITS-1:0] lookup_index = lookup_pc_i[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   lookup_tag = lookup_pc_i[ADDR_WIDTH-1:INDEX_BITS+2];
    
    wire [INDEX_BITS-1:0] update_index = update_pc_i[INDEX_BITS+1:2];
    wire [TAG_BITS-1:0]   update_tag = update_pc_i[ADDR_WIDTH-1:INDEX_BITS+2];
    
    assign hit_o = valid_array[lookup_index] && (tag_array[lookup_index] == lookup_tag);
    assign target_o = target_array[lookup_index];
    assign branch_type_o = type_array[lookup_index];
    assign is_branch_o = hit_o;
    assign is_call_o = hit_o && (type_array[lookup_index] == 2'b01);
    assign is_return_o = hit_o && (type_array[lookup_index] == 2'b10);
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_array <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                tag_array[i] <= 0;
                target_array[i] <= 0;
                type_array[i] <= 0;
            end
        end else if (update_valid_i && update_is_branch_i) begin
            tag_array[update_index] <= update_tag;
            target_array[update_index] <= update_target_i;
            type_array[update_index] <= update_is_call_i ? 2'b01 :
                                        update_is_return_i ? 2'b10 : 2'b00;
            valid_array[update_index] <= 1'b1;
        end
    end
endmodule

//=================================================================
// Return Address Stack Module
//=================================================================
module ras #(
    parameter ADDR_WIDTH = 32,
    parameter DEPTH      = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    input  wire                     push_i,
    input  wire [ADDR_WIDTH-1:0]    push_addr_i,
    
    input  wire                     pop_i,
    
    output wire [ADDR_WIDTH-1:0]    top_o,
    output wire                     valid_o,
    
    input  wire                     flush_i,
    input  wire                     recover_i
);
    localparam PTR_BITS = $clog2(DEPTH);
    
    reg [ADDR_WIDTH-1:0] stack [0:DEPTH-1];
    reg [PTR_BITS:0] sp;  // Stack pointer (extra bit for empty detection)
    reg [PTR_BITS:0] committed_sp;
    
    assign top_o = stack[sp[PTR_BITS-1:0] - 1];
    assign valid_o = (sp > 0);
    
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp <= 0;
            committed_sp <= 0;
            for (i = 0; i < DEPTH; i = i + 1) begin
                stack[i] <= 0;
            end
        end else if (flush_i) begin
            sp <= committed_sp;
        end else if (recover_i) begin
            // Recovery on misprediction - simplified
            sp <= committed_sp;
        end else begin
            if (push_i && !pop_i) begin
                stack[sp[PTR_BITS-1:0]] <= push_addr_i;
                sp <= sp + 1;
            end else if (pop_i && !push_i && sp > 0) begin
                sp <= sp - 1;
            end
        end
    end
endmodule
