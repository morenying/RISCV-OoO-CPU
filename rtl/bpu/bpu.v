//=================================================================
// Module: bpu
// Description: Branch Prediction Unit Top Level
//              Integrates TAGE + BTB + RAS + Loop Predictor
//              GHR management and checkpoint support
// Requirements: 7.9, 7.10
//=================================================================

`timescale 1ns/1ps

module bpu #(
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire                    pred_req_i,
    input  wire [31:0]             pred_pc_i,
    output wire                    pred_valid_o,
    output wire                    pred_taken_o,
    output wire [31:0]             pred_target_o,
    output wire [1:0]              pred_type_o,     // Branch type
    
    // Checkpoint interface
    input  wire                    checkpoint_i,
    input  wire [2:0]              checkpoint_id_i,
    
    // Recovery interface
    input  wire                    recover_i,
    input  wire [2:0]              recover_id_i,
    input  wire [GHR_WIDTH-1:0]    recover_ghr_i,
    
    // Update interface (from commit)
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire                    update_taken_i,
    input  wire [31:0]             update_target_i,
    input  wire [1:0]              update_type_i,
    input  wire                    update_mispredict_i,
    
    // GHR output for checkpoint
    output wire [GHR_WIDTH-1:0]    ghr_o
);

    //=========================================================
    // Global History Register
    //=========================================================
    reg [GHR_WIDTH-1:0] ghr;
    reg [GHR_WIDTH-1:0] ghr_checkpoint [0:7];
    
    assign ghr_o = ghr;
    
    //=========================================================
    // TAGE Predictor
    //=========================================================
    wire        tage_pred;
    wire [2:0]  tage_provider;
    wire        tage_alt_pred;
    
    tage_predictor #(
        .GHR_WIDTH(GHR_WIDTH)
    ) u_tage (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pred_pc_i),
        .ghr_i              (ghr),
        .pred_taken_o       (tage_pred),
        .provider_o         (tage_provider),
        .alt_pred_o         (tage_alt_pred),
        .update_valid_i     (update_valid_i && (update_type_i == 2'b00)),
        .update_pc_i        (update_pc_i),
        .update_ghr_i       (ghr),
        .update_taken_i     (update_taken_i),
        .update_provider_i  (tage_provider),
        .update_alt_pred_i  (tage_alt_pred),
        .update_pred_correct_i(!update_mispredict_i)
    );
    
    //=========================================================
    // Branch Target Buffer
    //=========================================================
    wire        btb_hit;
    wire [31:0] btb_target;
    wire [1:0]  btb_type;
    
    btb u_btb (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_i             (pred_pc_i),
        .hit_o            (btb_hit),
        .target_o         (btb_target),
        .br_type_o        (btb_type),
        .update_valid_i   (update_valid_i),
        .update_pc_i      (update_pc_i),
        .update_target_i  (update_target_i),
        .update_br_type_i (update_type_i)
    );
    
    //=========================================================
    // Return Address Stack
    //=========================================================
    wire        ras_push;
    wire        ras_pop;
    wire [31:0] ras_addr;
    wire        ras_valid;
    wire [3:0]  ras_checkpoint_ptr;
    
    // Push on CALL (type = 10), Pop on RET (type = 11)
    assign ras_push = pred_req_i && btb_hit && (btb_type == 2'b10);
    assign ras_pop = pred_req_i && btb_hit && (btb_type == 2'b11);
    
    ras u_ras (
        .clk              (clk),
        .rst_n            (rst_n),
        .push_i           (ras_push),
        .push_addr_i      (pred_pc_i + 4),  // Return address
        .pop_i            (ras_pop),
        .pop_addr_o       (ras_addr),
        .valid_o          (ras_valid),
        .checkpoint_i     (checkpoint_i),
        .checkpoint_ptr_o (ras_checkpoint_ptr),
        .recover_i        (recover_i),
        .recover_ptr_i    (4'd0)  // Simplified recovery
    );
    
    //=========================================================
    // Loop Predictor
    //=========================================================
    wire        loop_hit;
    wire        loop_pred_exit;
    wire        loop_confident;
    
    loop_predictor u_loop (
        .clk                (clk),
        .rst_n              (rst_n),
        .pc_i               (pred_pc_i),
        .hit_o              (loop_hit),
        .pred_exit_o        (loop_pred_exit),
        .confident_o        (loop_confident),
        .update_valid_i     (update_valid_i && (update_type_i == 2'b00)),
        .update_pc_i        (update_pc_i),
        .update_taken_i     (update_taken_i),
        .update_mispredict_i(update_mispredict_i)
    );

    //=========================================================
    // Final Prediction Logic
    //=========================================================
    reg        final_taken;
    reg [31:0] final_target;
    
    always @(*) begin
        final_taken = 1'b0;
        final_target = pred_pc_i + 4;  // Default: next sequential
        
        if (btb_hit) begin
            case (btb_type)
                2'b00: begin
                    // Conditional branch: use TAGE or loop predictor
                    if (loop_hit && loop_confident) begin
                        final_taken = !loop_pred_exit;
                    end else begin
                        final_taken = tage_pred;
                    end
                    final_target = final_taken ? btb_target : (pred_pc_i + 4);
                end
                2'b01: begin
                    // Unconditional jump (JAL)
                    final_taken = 1'b1;
                    final_target = btb_target;
                end
                2'b10: begin
                    // Call
                    final_taken = 1'b1;
                    final_target = btb_target;
                end
                2'b11: begin
                    // Return: use RAS
                    final_taken = 1'b1;
                    final_target = ras_valid ? ras_addr : btb_target;
                end
            endcase
        end
    end
    
    assign pred_valid_o = pred_req_i;
    assign pred_taken_o = final_taken;
    assign pred_target_o = final_target;
    assign pred_type_o = btb_hit ? btb_type : 2'b00;
    
    //=========================================================
    // GHR Management
    //=========================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= {GHR_WIDTH{1'b0}};
            for (i = 0; i < 8; i = i + 1) begin
                ghr_checkpoint[i] <= {GHR_WIDTH{1'b0}};
            end
        end else if (recover_i) begin
            // Recovery: restore GHR from checkpoint
            ghr <= recover_ghr_i;
        end else begin
            // Checkpoint creation
            if (checkpoint_i) begin
                ghr_checkpoint[checkpoint_id_i] <= ghr;
            end
            
            // Speculative GHR update on prediction
            if (pred_req_i && btb_hit && (btb_type == 2'b00)) begin
                ghr <= {ghr[GHR_WIDTH-2:0], final_taken};
            end
            
            // Committed GHR update
            if (update_valid_i && (update_type_i == 2'b00)) begin
                // Note: In a real implementation, we'd need to handle
                // the difference between speculative and committed GHR
            end
        end
    end

endmodule
