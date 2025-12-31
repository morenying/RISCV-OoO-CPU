//=================================================================
// Module: rn_stage
// Description: Register Rename Stage
// Requirements: 2.1, 2.4
//=================================================================

`timescale 1ns/1ps

module rn_stage #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ROB_IDX_BITS = 5,
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    stall_i,
    input  wire                    flush_i,
    input  wire                    recover_i,
    input  wire [2:0]              recover_checkpoint_i,
    
    // From ID stage
    input  wire                    id_valid_i,
    input  wire [XLEN-1:0]         id_pc_i,
    input  wire [4:0]              id_rd_i,
    input  wire [4:0]              id_rs1_i,
    input  wire [4:0]              id_rs2_i,
    input  wire [XLEN-1:0]         id_imm_i,
    input  wire [3:0]              id_alu_op_i,
    input  wire [1:0]              id_alu_src1_i,
    input  wire [1:0]              id_alu_src2_i,
    input  wire                    id_reg_write_i,
    input  wire                    id_mem_read_i,
    input  wire                    id_mem_write_i,
    input  wire                    id_branch_i,
    input  wire                    id_jump_i,
    input  wire [2:0]              id_fu_type_i,
    input  wire [1:0]              id_mem_size_i,
    input  wire                    id_mem_sign_ext_i,
    input  wire                    id_pred_taken_i,
    input  wire [XLEN-1:0]         id_pred_target_i,
    input  wire [GHR_WIDTH-1:0]    id_ghr_i,
    
    // ROB interface
    input  wire                    rob_alloc_ready_i,
    input  wire [ROB_IDX_BITS-1:0] rob_alloc_idx_i,
    output wire                    rob_alloc_req_o,
    output wire [4:0]              rob_alloc_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] rob_alloc_rd_phys_o,
    output wire [PHYS_REG_BITS-1:0] rob_alloc_rd_phys_old_o,
    output wire [XLEN-1:0]         rob_alloc_pc_o,
    output wire                    rob_alloc_is_branch_o,
    output wire                    rob_alloc_is_store_o,
    
    // Free list interface
    input  wire                    fl_alloc_valid_i,
    input  wire [PHYS_REG_BITS-1:0] fl_alloc_preg_i,
    output wire                    fl_alloc_req_o,
    
    // RAT interface
    input  wire [PHYS_REG_BITS-1:0] rat_rs1_phys_i,
    input  wire [PHYS_REG_BITS-1:0] rat_rs2_phys_i,
    input  wire                    rat_rs1_ready_i,
    input  wire                    rat_rs2_ready_i,
    input  wire [PHYS_REG_BITS-1:0] rat_rd_phys_old_i,
    output wire [4:0]              rat_rs1_arch_o,
    output wire [4:0]              rat_rs2_arch_o,
    output wire                    rat_rename_valid_o,
    output wire [4:0]              rat_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] rat_rd_phys_new_o,
    
    // To IS stage
    output reg                     is_valid_o,
    output reg  [XLEN-1:0]         is_pc_o,
    output reg  [PHYS_REG_BITS-1:0] is_rs1_phys_o,
    output reg  [PHYS_REG_BITS-1:0] is_rs2_phys_o,
    output reg                     is_rs1_ready_o,
    output reg                     is_rs2_ready_o,
    output reg  [PHYS_REG_BITS-1:0] is_rd_phys_o,
    output reg  [XLEN-1:0]         is_imm_o,
    output reg  [3:0]              is_alu_op_o,
    output reg  [1:0]              is_alu_src1_o,
    output reg  [1:0]              is_alu_src2_o,
    output reg                     is_reg_write_o,
    output reg                     is_mem_read_o,
    output reg                     is_mem_write_o,
    output reg                     is_branch_o,
    output reg                     is_jump_o,
    output reg  [2:0]              is_fu_type_o,
    output reg  [1:0]              is_mem_size_o,
    output reg                     is_mem_sign_ext_o,
    output reg  [ROB_IDX_BITS-1:0] is_rob_idx_o,
    output reg                     is_pred_taken_o,
    output reg  [XLEN-1:0]         is_pred_target_o
);

    wire need_rd = id_reg_write_i && (id_rd_i != 5'd0);
    wire can_rename = id_valid_i && rob_alloc_ready_i && (!need_rd || fl_alloc_valid_i);
    
    assign rat_rs1_arch_o = id_rs1_i;
    assign rat_rs2_arch_o = id_rs2_i;
    assign rat_rename_valid_o = can_rename && need_rd && !stall_i && !flush_i;
    assign rat_rd_arch_o = id_rd_i;
    assign rat_rd_phys_new_o = fl_alloc_preg_i;
    
    assign fl_alloc_req_o = can_rename && need_rd && !stall_i && !flush_i;
    
    assign rob_alloc_req_o = can_rename && !stall_i && !flush_i;
    assign rob_alloc_rd_arch_o = id_rd_i;
    assign rob_alloc_rd_phys_o = need_rd ? fl_alloc_preg_i : 6'd0;
    assign rob_alloc_rd_phys_old_o = rat_rd_phys_old_i;
    assign rob_alloc_pc_o = id_pc_i;
    assign rob_alloc_is_branch_o = id_branch_i || id_jump_i;
    assign rob_alloc_is_store_o = id_mem_write_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            is_valid_o <= 0;
            is_pc_o <= 0; is_rs1_phys_o <= 0; is_rs2_phys_o <= 0;
            is_rs1_ready_o <= 0; is_rs2_ready_o <= 0; is_rd_phys_o <= 0;
            is_imm_o <= 0; is_alu_op_o <= 0; is_alu_src1_o <= 0; is_alu_src2_o <= 0;
            is_reg_write_o <= 0; is_mem_read_o <= 0; is_mem_write_o <= 0;
            is_branch_o <= 0; is_jump_o <= 0; is_fu_type_o <= 0;
            is_mem_size_o <= 0; is_mem_sign_ext_o <= 0; is_rob_idx_o <= 0;
            is_pred_taken_o <= 0; is_pred_target_o <= 0;
        end else if (flush_i) begin
            is_valid_o <= 0;
        end else if (!stall_i && can_rename) begin
            is_valid_o <= 1;
            is_pc_o <= id_pc_i;
            is_rs1_phys_o <= rat_rs1_phys_i;
            is_rs2_phys_o <= rat_rs2_phys_i;
            is_rs1_ready_o <= rat_rs1_ready_i;
            is_rs2_ready_o <= rat_rs2_ready_i;
            is_rd_phys_o <= need_rd ? fl_alloc_preg_i : 6'd0;
            is_imm_o <= id_imm_i; is_alu_op_o <= id_alu_op_i;
            is_alu_src1_o <= id_alu_src1_i; is_alu_src2_o <= id_alu_src2_i;
            is_reg_write_o <= id_reg_write_i;
            is_mem_read_o <= id_mem_read_i; is_mem_write_o <= id_mem_write_i;
            is_branch_o <= id_branch_i; is_jump_o <= id_jump_i;
            is_fu_type_o <= id_fu_type_i;
            is_mem_size_o <= id_mem_size_i; is_mem_sign_ext_o <= id_mem_sign_ext_i;
            is_rob_idx_o <= rob_alloc_idx_i;
            is_pred_taken_o <= id_pred_taken_i; is_pred_target_o <= id_pred_target_i;
        end else if (!stall_i) begin
            is_valid_o <= 0;
        end
    end
endmodule
