//=================================================================
// Module: id_stage
// Description: Instruction Decode Stage
// Requirements: 2.1, 2.3
//=================================================================

`timescale 1ns/1ps

module id_stage #(
    parameter XLEN = 32,
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    stall_i,
    input  wire                    flush_i,
    
    // From IF stage
    input  wire                    if_valid_i,
    input  wire [XLEN-1:0]         if_pc_i,
    input  wire [XLEN-1:0]         if_instr_i,
    input  wire                    if_pred_taken_i,
    input  wire [XLEN-1:0]         if_pred_target_i,
    input  wire [1:0]              if_pred_type_i,
    input  wire [GHR_WIDTH-1:0]    if_ghr_i,
    
    // To RN stage
    output reg                     rn_valid_o,
    output reg  [XLEN-1:0]         rn_pc_o,
    output reg  [XLEN-1:0]         rn_instr_o,
    output reg  [4:0]              rn_rd_o,
    output reg  [4:0]              rn_rs1_o,
    output reg  [4:0]              rn_rs2_o,
    output reg  [XLEN-1:0]         rn_imm_o,
    output reg  [3:0]              rn_alu_op_o,
    output reg  [1:0]              rn_alu_src1_o,
    output reg  [1:0]              rn_alu_src2_o,
    output reg                     rn_reg_write_o,
    output reg                     rn_mem_read_o,
    output reg                     rn_mem_write_o,
    output reg                     rn_branch_o,
    output reg                     rn_jump_o,
    output reg  [2:0]              rn_fu_type_o,
    output reg  [1:0]              rn_mem_size_o,
    output reg                     rn_mem_sign_ext_o,
    output reg                     rn_csr_op_o,
    output reg  [2:0]              rn_csr_type_o,
    output reg                     rn_pred_taken_o,
    output reg  [XLEN-1:0]         rn_pred_target_o,
    output reg  [GHR_WIDTH-1:0]    rn_ghr_o,
    output reg                     rn_illegal_o
);

    // Decoder wires
    wire [4:0]  dec_rd, dec_rs1, dec_rs2;
    wire [XLEN-1:0] dec_imm;
    wire [6:0]  dec_opcode;
    wire [2:0]  dec_funct3;
    wire [6:0]  dec_funct7;
    wire        dec_reg_write, dec_mem_read, dec_mem_write;
    wire        dec_branch, dec_jump, dec_csr_op;
    wire [3:0]  dec_alu_op;
    wire [1:0]  dec_alu_src1, dec_alu_src2;
    wire [2:0]  dec_csr_type, dec_imm_type, dec_fu_type;
    wire [1:0]  dec_mem_size;
    wire        dec_mem_sign_ext, dec_illegal;

    decoder u_decoder (
        .instr_i        (if_instr_i),
        .pc_i           (if_pc_i),
        .rd_o           (dec_rd),
        .rs1_o          (dec_rs1),
        .rs2_o          (dec_rs2),
        .imm_o          (dec_imm),
        .opcode_o       (dec_opcode),
        .funct3_o       (dec_funct3),
        .funct7_o       (dec_funct7),
        .reg_write_o    (dec_reg_write),
        .mem_read_o     (dec_mem_read),
        .mem_write_o    (dec_mem_write),
        .branch_o       (dec_branch),
        .jump_o         (dec_jump),
        .alu_op_o       (dec_alu_op),
        .alu_src1_o     (dec_alu_src1),
        .alu_src2_o     (dec_alu_src2),
        .csr_op_o       (dec_csr_op),
        .csr_type_o     (dec_csr_type),
        .imm_type_o     (dec_imm_type),
        .fu_type_o      (dec_fu_type),
        .mem_size_o     (dec_mem_size),
        .mem_sign_ext_o (dec_mem_sign_ext),
        .illegal_instr_o(dec_illegal)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rn_valid_o <= 0;
            rn_pc_o <= 0;
            rn_instr_o <= 32'h13;
            rn_rd_o <= 0; rn_rs1_o <= 0; rn_rs2_o <= 0;
            rn_imm_o <= 0; rn_alu_op_o <= 0;
            rn_alu_src1_o <= 0; rn_alu_src2_o <= 0;
            rn_reg_write_o <= 0; rn_mem_read_o <= 0; rn_mem_write_o <= 0;
            rn_branch_o <= 0; rn_jump_o <= 0; rn_fu_type_o <= 0;
            rn_mem_size_o <= 0; rn_mem_sign_ext_o <= 0;
            rn_csr_op_o <= 0; rn_csr_type_o <= 0;
            rn_pred_taken_o <= 0; rn_pred_target_o <= 0; rn_ghr_o <= 0;
            rn_illegal_o <= 0;
        end else if (flush_i) begin
            rn_valid_o <= 0;
        end else if (!stall_i) begin
            rn_valid_o <= if_valid_i;
            rn_pc_o <= if_pc_i;
            rn_instr_o <= if_instr_i;
            rn_rd_o <= dec_rd; rn_rs1_o <= dec_rs1; rn_rs2_o <= dec_rs2;
            rn_imm_o <= dec_imm; rn_alu_op_o <= dec_alu_op;
            rn_alu_src1_o <= dec_alu_src1; rn_alu_src2_o <= dec_alu_src2;
            rn_reg_write_o <= dec_reg_write;
            rn_mem_read_o <= dec_mem_read; rn_mem_write_o <= dec_mem_write;
            rn_branch_o <= dec_branch; rn_jump_o <= dec_jump;
            rn_fu_type_o <= dec_fu_type;
            rn_mem_size_o <= dec_mem_size; rn_mem_sign_ext_o <= dec_mem_sign_ext;
            rn_csr_op_o <= dec_csr_op; rn_csr_type_o <= dec_csr_type;
            rn_pred_taken_o <= if_pred_taken_i; rn_pred_target_o <= if_pred_target_i;
            rn_ghr_o <= if_ghr_i; rn_illegal_o <= dec_illegal;
        end
    end
endmodule
