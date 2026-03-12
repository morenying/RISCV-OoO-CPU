//=================================================================
// Module: ex_stage
// Description: Execute Stage
//              Functional unit scheduling
//              Result collection
//              CDB broadcast
// Requirements: 2.1, 2.7
//=================================================================

`timescale 1ns/1ps

module ex_stage #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ROB_IDX_BITS = 5
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    flush_i,
    
    //=========================================================
    // ALU Issue Interface (from RS)
    //=========================================================
    input  wire                    alu_issue_valid_i,
    output wire                    alu_issue_ready_o,
    input  wire [3:0]              alu_issue_op_i,
    input  wire [XLEN-1:0]         alu_issue_src1_i,
    input  wire [XLEN-1:0]         alu_issue_src2_i,
    input  wire [PHYS_REG_BITS-1:0] alu_issue_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0] alu_issue_rob_idx_i,
    input  wire [XLEN-1:0]         alu_issue_pc_i,
    
    //=========================================================
    // MUL Issue Interface (from RS)
    //=========================================================
    input  wire                    mul_issue_valid_i,
    output wire                    mul_issue_ready_o,
    input  wire [1:0]              mul_issue_op_i,
    input  wire [XLEN-1:0]         mul_issue_src1_i,
    input  wire [XLEN-1:0]         mul_issue_src2_i,
    input  wire [PHYS_REG_BITS-1:0] mul_issue_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0] mul_issue_rob_idx_i,
    
    //=========================================================
    // DIV Issue Interface (from RS)
    //=========================================================
    input  wire                    div_issue_valid_i,
    output wire                    div_issue_ready_o,
    input  wire [1:0]              div_issue_op_i,
    input  wire [XLEN-1:0]         div_issue_src1_i,
    input  wire [XLEN-1:0]         div_issue_src2_i,
    input  wire [PHYS_REG_BITS-1:0] div_issue_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0] div_issue_rob_idx_i,
    
    //=========================================================
    // Branch Issue Interface (from RS)
    //=========================================================
    input  wire                    br_issue_valid_i,
    output wire                    br_issue_ready_o,
    input  wire [2:0]              br_issue_op_i,
    input  wire [XLEN-1:0]         br_issue_src1_i,
    input  wire [XLEN-1:0]         br_issue_src2_i,
    input  wire [PHYS_REG_BITS-1:0] br_issue_dst_preg_i,
    input  wire [ROB_IDX_BITS-1:0] br_issue_rob_idx_i,
    input  wire [XLEN-1:0]         br_issue_pc_i,
    input  wire [XLEN-1:0]         br_issue_imm_i,
    input  wire                    br_issue_pred_taken_i,
    input  wire [XLEN-1:0]         br_issue_pred_target_i,
    input  wire                    br_issue_is_jump_i,
    
    //=========================================================
    // CDB Output Interface
    //=========================================================
    // ALU result to CDB
    output wire                    alu_cdb_valid_o,
    input  wire                    alu_cdb_ready_i,
    output wire [PHYS_REG_BITS-1:0] alu_cdb_preg_o,
    output wire [XLEN-1:0]         alu_cdb_data_o,
    output wire [ROB_IDX_BITS-1:0] alu_cdb_rob_idx_o,
    output wire                    alu_cdb_exception_o,
    output wire [3:0]              alu_cdb_exc_code_o,
    
    // MUL result to CDB
    output wire                    mul_cdb_valid_o,
    input  wire                    mul_cdb_ready_i,
    output wire [PHYS_REG_BITS-1:0] mul_cdb_preg_o,
    output wire [XLEN-1:0]         mul_cdb_data_o,
    output wire [ROB_IDX_BITS-1:0] mul_cdb_rob_idx_o,
    output wire                    mul_cdb_exception_o,
    output wire [3:0]              mul_cdb_exc_code_o,
    
    // DIV result to CDB
    output wire                    div_cdb_valid_o,
    input  wire                    div_cdb_ready_i,
    output wire [PHYS_REG_BITS-1:0] div_cdb_preg_o,
    output wire [XLEN-1:0]         div_cdb_data_o,
    output wire [ROB_IDX_BITS-1:0] div_cdb_rob_idx_o,
    output wire                    div_cdb_exception_o,
    output wire [3:0]              div_cdb_exc_code_o,
    
    // Branch result to CDB
    output wire                    br_cdb_valid_o,
    input  wire                    br_cdb_ready_i,
    output wire [PHYS_REG_BITS-1:0] br_cdb_preg_o,
    output wire [XLEN-1:0]         br_cdb_data_o,
    output wire [ROB_IDX_BITS-1:0] br_cdb_rob_idx_o,
    output wire                    br_cdb_exception_o,
    output wire [3:0]              br_cdb_exc_code_o,
    output wire                    br_cdb_taken_o,
    output wire [XLEN-1:0]         br_cdb_target_o,
    
    // Branch misprediction
    output wire                    br_mispredict_o,
    output wire [XLEN-1:0]         br_redirect_pc_o
);

    //=========================================================
    // ALU Unit
    //=========================================================
    wire [XLEN-1:0] alu_result;
    wire [PHYS_REG_BITS-1:0] alu_prd_out;
    wire [ROB_IDX_BITS-1:0] alu_rob_idx_out;
    wire alu_valid_out;
    
    alu_unit u_alu (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_i    (alu_issue_valid_i),
        .op_i       (alu_issue_op_i),
        .src1_i     (alu_issue_src1_i),
        .src2_i     (alu_issue_src2_i),
        .prd_i      (alu_issue_dst_preg_i),
        .rob_idx_i  (alu_issue_rob_idx_i),
        .pc_i       (alu_issue_pc_i),
        .valid_o    (alu_valid_out),
        .result_o   (alu_result),
        .prd_o      (alu_prd_out),
        .rob_idx_o  (alu_rob_idx_out)
    );
    
    // ALU is single-cycle, always ready
    assign alu_issue_ready_o = 1'b1;
    
    // ALU result pipeline register
    reg                    alu_result_valid;
    reg [PHYS_REG_BITS-1:0] alu_result_preg;
    reg [XLEN-1:0]         alu_result_data;
    reg [ROB_IDX_BITS-1:0] alu_result_rob_idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            alu_result_valid <= 1'b0;
            alu_result_preg <= 0;
            alu_result_data <= 0;
            alu_result_rob_idx <= 0;
        end else begin
            alu_result_valid <= alu_valid_out;
            alu_result_preg <= alu_prd_out;
            alu_result_data <= alu_result;
            alu_result_rob_idx <= alu_rob_idx_out;
        end
    end
    
    assign alu_cdb_valid_o = alu_result_valid;
    assign alu_cdb_preg_o = alu_result_preg;
    assign alu_cdb_data_o = alu_result_data;
    assign alu_cdb_rob_idx_o = alu_result_rob_idx;
    assign alu_cdb_exception_o = 1'b0;
    assign alu_cdb_exc_code_o = 4'd0;

    //=========================================================
    // MUL Unit (3-cycle pipeline)
    //=========================================================
    wire mul_busy;
    wire [XLEN-1:0] mul_result;
    wire [PHYS_REG_BITS-1:0] mul_prd_out;
    wire [ROB_IDX_BITS-1:0] mul_rob_idx_out;
    wire mul_valid_out;
    
    mul_unit u_mul (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_i    (mul_issue_valid_i && !mul_busy),
        .op_i       (mul_issue_op_i),
        .src1_i     (mul_issue_src1_i),
        .src2_i     (mul_issue_src2_i),
        .prd_i      (mul_issue_dst_preg_i),
        .rob_idx_i  (mul_issue_rob_idx_i),
        .valid_o    (mul_valid_out),
        .result_o   (mul_result),
        .prd_o      (mul_prd_out),
        .rob_idx_o  (mul_rob_idx_out),
        .busy_o     (mul_busy),
        .flush_i    (flush_i)
    );
    
    assign mul_issue_ready_o = !mul_busy;
    
    assign mul_cdb_valid_o = mul_valid_out;
    assign mul_cdb_preg_o = mul_prd_out;
    assign mul_cdb_data_o = mul_result;
    assign mul_cdb_rob_idx_o = mul_rob_idx_out;
    assign mul_cdb_exception_o = 1'b0;
    assign mul_cdb_exc_code_o = 4'd0;

    //=========================================================
    // DIV Unit (up to 32 cycles)
    //=========================================================
    wire div_busy;
    wire div_done;
    wire [XLEN-1:0] div_result;
    wire [PHYS_REG_BITS-1:0] div_prd_out;
    wire [ROB_IDX_BITS-1:0] div_rob_idx_out;
    
    div_unit u_div (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_i            (div_issue_valid_i && !div_busy),
        .op_i               (div_issue_op_i),
        .src1_i             (div_issue_src1_i),
        .src2_i             (div_issue_src2_i),
        .prd_i              (div_issue_dst_preg_i),
        .rob_idx_i          (div_issue_rob_idx_i),
        .done_o             (div_done),
        .result_o           (div_result),
        .result_prd_o       (div_prd_out),
        .result_rob_idx_o   (div_rob_idx_out),
        .busy_o             (div_busy)
    );
    
    assign div_issue_ready_o = !div_busy;
    
    assign div_cdb_valid_o = div_done;
    assign div_cdb_preg_o = div_prd_out;
    assign div_cdb_data_o = div_result;
    assign div_cdb_rob_idx_o = div_rob_idx_out;
    assign div_cdb_exception_o = 1'b0;
    assign div_cdb_exc_code_o = 4'd0;

    //=========================================================
    // Branch Unit
    //=========================================================
    wire br_done;
    wire br_taken;
    wire [XLEN-1:0] br_target;
    wire [XLEN-1:0] br_link_addr;
    wire br_mispredict_out;
    wire [PHYS_REG_BITS-1:0] br_prd_out;
    wire [ROB_IDX_BITS-1:0] br_rob_idx_out;
    
    branch_unit u_branch (
        .clk                (clk),
        .rst_n              (rst_n),
        .valid_i            (br_issue_valid_i),
        .op_i               ({1'b0, br_issue_op_i}),
        .src1_i             (br_issue_src1_i),
        .src2_i             (br_issue_src2_i),
        .pc_i               (br_issue_pc_i),
        .imm_i              (br_issue_imm_i),
        .pred_taken_i       (br_issue_pred_taken_i),
        .pred_target_i      (br_issue_pred_target_i),
        .prd_i              (br_issue_dst_preg_i),
        .rob_idx_i          (br_issue_rob_idx_i),
        .done_o             (br_done),
        .taken_o            (br_taken),
        .target_o           (br_target),
        .mispredict_o       (br_mispredict_out),
        .link_addr_o        (br_link_addr),
        .result_prd_o       (br_prd_out),
        .result_rob_idx_o   (br_rob_idx_out)
    );
    
    assign br_issue_ready_o = 1'b1;
    
    assign br_cdb_valid_o = br_done;
    assign br_cdb_preg_o = br_prd_out;
    assign br_cdb_data_o = br_link_addr;
    assign br_cdb_rob_idx_o = br_rob_idx_out;
    assign br_cdb_exception_o = 1'b0;
    assign br_cdb_exc_code_o = 4'd0;
    assign br_cdb_taken_o = br_taken;
    assign br_cdb_target_o = br_target;
    
    assign br_mispredict_o = br_mispredict_out;
    assign br_redirect_pc_o = br_taken ? br_target : (br_issue_pc_i + 4);

endmodule
