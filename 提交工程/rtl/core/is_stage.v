//=================================================================
// Module: is_stage
// Description: Issue Stage
//              Reservation station allocation
//              Operand read from PRF
//              Instruction issue to execution units
// Requirements: 2.1, 2.5, 2.6
//=================================================================

`timescale 1ns/1ps

module is_stage #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ROB_IDX_BITS = 5,
    parameter ALU_RS_ENTRIES = 4,
    parameter MUL_RS_ENTRIES = 2,
    parameter LSU_RS_ENTRIES = 4,
    parameter BR_RS_ENTRIES = 2
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    stall_i,
    input  wire                    flush_i,
    
    // From RN stage
    input  wire                    rn_valid_i,
    input  wire [XLEN-1:0]         rn_pc_i,
    input  wire [PHYS_REG_BITS-1:0] rn_rs1_phys_i,
    input  wire [PHYS_REG_BITS-1:0] rn_rs2_phys_i,
    input  wire                    rn_rs1_ready_i,
    input  wire                    rn_rs2_ready_i,
    input  wire [PHYS_REG_BITS-1:0] rn_rd_phys_i,
    input  wire [XLEN-1:0]         rn_imm_i,
    input  wire [3:0]              rn_alu_op_i,
    input  wire [1:0]              rn_alu_src1_i,
    input  wire [1:0]              rn_alu_src2_i,
    input  wire                    rn_reg_write_i,
    input  wire                    rn_mem_read_i,
    input  wire                    rn_mem_write_i,
    input  wire                    rn_branch_i,
    input  wire                    rn_jump_i,
    input  wire [2:0]              rn_fu_type_i,
    input  wire [1:0]              rn_mem_size_i,
    input  wire                    rn_mem_sign_ext_i,
    input  wire [ROB_IDX_BITS-1:0] rn_rob_idx_i,
    input  wire                    rn_pred_taken_i,
    input  wire [XLEN-1:0]         rn_pred_target_i,
    
    // PRF read interface
    output wire [PHYS_REG_BITS-1:0] prf_rs1_addr_o,
    output wire [PHYS_REG_BITS-1:0] prf_rs2_addr_o,
    input  wire [XLEN-1:0]         prf_rs1_data_i,
    input  wire [XLEN-1:0]         prf_rs2_data_i,
    
    // CDB interface (for operand capture)
    input  wire                    cdb_valid_i,
    input  wire [PHYS_REG_BITS-1:0] cdb_preg_i,
    input  wire [XLEN-1:0]         cdb_data_i,
    
    // ALU RS interface
    output wire                    alu_rs_dispatch_valid_o,
    input  wire                    alu_rs_dispatch_ready_i,
    output wire [3:0]              alu_rs_op_o,
    output wire [PHYS_REG_BITS-1:0] alu_rs_src1_preg_o,
    output wire [XLEN-1:0]         alu_rs_src1_data_o,
    output wire                    alu_rs_src1_ready_o,
    output wire [PHYS_REG_BITS-1:0] alu_rs_src2_preg_o,
    output wire [XLEN-1:0]         alu_rs_src2_data_o,
    output wire                    alu_rs_src2_ready_o,
    output wire [PHYS_REG_BITS-1:0] alu_rs_dst_preg_o,
    output wire [ROB_IDX_BITS-1:0] alu_rs_rob_idx_o,
    output wire [XLEN-1:0]         alu_rs_imm_o,
    output wire                    alu_rs_use_imm_o,
    output wire [XLEN-1:0]         alu_rs_pc_o,
    
    // MUL RS interface
    output wire                    mul_rs_dispatch_valid_o,
    input  wire                    mul_rs_dispatch_ready_i,
    output wire [1:0]              mul_rs_op_o,
    output wire [PHYS_REG_BITS-1:0] mul_rs_src1_preg_o,
    output wire [XLEN-1:0]         mul_rs_src1_data_o,
    output wire                    mul_rs_src1_ready_o,
    output wire [PHYS_REG_BITS-1:0] mul_rs_src2_preg_o,
    output wire [XLEN-1:0]         mul_rs_src2_data_o,
    output wire                    mul_rs_src2_ready_o,
    output wire [PHYS_REG_BITS-1:0] mul_rs_dst_preg_o,
    output wire [ROB_IDX_BITS-1:0] mul_rs_rob_idx_o,
    
    // DIV RS interface
    output wire                    div_rs_dispatch_valid_o,
    input  wire                    div_rs_dispatch_ready_i,
    output wire [1:0]              div_rs_op_o,
    output wire [PHYS_REG_BITS-1:0] div_rs_src1_preg_o,
    output wire [XLEN-1:0]         div_rs_src1_data_o,
    output wire                    div_rs_src1_ready_o,
    output wire [PHYS_REG_BITS-1:0] div_rs_src2_preg_o,
    output wire [XLEN-1:0]         div_rs_src2_data_o,
    output wire                    div_rs_src2_ready_o,
    output wire [PHYS_REG_BITS-1:0] div_rs_dst_preg_o,
    output wire [ROB_IDX_BITS-1:0] div_rs_rob_idx_o,
    
    // LSU RS interface
    output wire                    lsu_rs_dispatch_valid_o,
    input  wire                    lsu_rs_dispatch_ready_i,
    output wire                    lsu_rs_is_load_o,
    output wire [1:0]              lsu_rs_mem_size_o,
    output wire                    lsu_rs_mem_sign_ext_o,
    output wire [PHYS_REG_BITS-1:0] lsu_rs_src1_preg_o,
    output wire [XLEN-1:0]         lsu_rs_src1_data_o,
    output wire                    lsu_rs_src1_ready_o,
    output wire [PHYS_REG_BITS-1:0] lsu_rs_src2_preg_o,
    output wire [XLEN-1:0]         lsu_rs_src2_data_o,
    output wire                    lsu_rs_src2_ready_o,
    output wire [PHYS_REG_BITS-1:0] lsu_rs_dst_preg_o,
    output wire [ROB_IDX_BITS-1:0] lsu_rs_rob_idx_o,
    output wire [XLEN-1:0]         lsu_rs_imm_o,
    
    // Branch RS interface
    output wire                    br_rs_dispatch_valid_o,
    input  wire                    br_rs_dispatch_ready_i,
    output wire [2:0]              br_rs_op_o,
    output wire [PHYS_REG_BITS-1:0] br_rs_src1_preg_o,
    output wire [XLEN-1:0]         br_rs_src1_data_o,
    output wire                    br_rs_src1_ready_o,
    output wire [PHYS_REG_BITS-1:0] br_rs_src2_preg_o,
    output wire [XLEN-1:0]         br_rs_src2_data_o,
    output wire                    br_rs_src2_ready_o,
    output wire [PHYS_REG_BITS-1:0] br_rs_dst_preg_o,
    output wire [ROB_IDX_BITS-1:0] br_rs_rob_idx_o,
    output wire [XLEN-1:0]         br_rs_pc_o,
    output wire [XLEN-1:0]         br_rs_imm_o,
    output wire                    br_rs_pred_taken_o,
    output wire [XLEN-1:0]         br_rs_pred_target_o,
    output wire                    br_rs_is_jump_o,
    
    // Stall output
    output wire                    stall_o
);

    // FU Type definitions
    localparam FU_TYPE_ALU    = 3'b000;
    localparam FU_TYPE_MUL    = 3'b001;
    localparam FU_TYPE_DIV    = 3'b010;
    localparam FU_TYPE_BRANCH = 3'b011;
    localparam FU_TYPE_LOAD   = 3'b100;
    localparam FU_TYPE_STORE  = 3'b101;

    //=========================================================
    // FU Type Decode
    //=========================================================
    wire is_alu = (rn_fu_type_i == FU_TYPE_ALU);
    wire is_mul = (rn_fu_type_i == FU_TYPE_MUL);
    wire is_div = (rn_fu_type_i == FU_TYPE_DIV);
    wire is_load = (rn_fu_type_i == FU_TYPE_LOAD);
    wire is_store = (rn_fu_type_i == FU_TYPE_STORE);
    wire is_branch = (rn_fu_type_i == FU_TYPE_BRANCH);
    wire is_lsu = is_load || is_store;

    //=========================================================
    // PRF Read
    //=========================================================
    assign prf_rs1_addr_o = rn_rs1_phys_i;
    assign prf_rs2_addr_o = rn_rs2_phys_i;
    
    //=========================================================
    // Operand Data with CDB Bypass
    //=========================================================
    wire rs1_cdb_match = cdb_valid_i && (cdb_preg_i == rn_rs1_phys_i);
    wire rs2_cdb_match = cdb_valid_i && (cdb_preg_i == rn_rs2_phys_i);
    
    wire [XLEN-1:0] rs1_data = rs1_cdb_match ? cdb_data_i : prf_rs1_data_i;
    wire [XLEN-1:0] rs2_data = rs2_cdb_match ? cdb_data_i : prf_rs2_data_i;
    wire rs1_ready = rn_rs1_ready_i || rs1_cdb_match;
    wire rs2_ready = rn_rs2_ready_i || rs2_cdb_match;

    //=========================================================
    // RS Ready Check
    //=========================================================
    wire alu_rs_ready = is_alu && alu_rs_dispatch_ready_i;
    wire mul_rs_ready = is_mul && mul_rs_dispatch_ready_i;
    wire div_rs_ready = is_div && div_rs_dispatch_ready_i;
    wire lsu_rs_ready = is_lsu && lsu_rs_dispatch_ready_i;
    wire br_rs_ready = is_branch && br_rs_dispatch_ready_i;
    
    wire can_dispatch = rn_valid_i && !flush_i && !stall_i &&
                        (alu_rs_ready || mul_rs_ready || div_rs_ready || 
                         lsu_rs_ready || br_rs_ready);
    
    // Stall if valid instruction but no RS available
    assign stall_o = rn_valid_i && !flush_i &&
                     ((is_alu && !alu_rs_dispatch_ready_i) ||
                      (is_mul && !mul_rs_dispatch_ready_i) ||
                      (is_div && !div_rs_dispatch_ready_i) ||
                      (is_lsu && !lsu_rs_dispatch_ready_i) ||
                      (is_branch && !br_rs_dispatch_ready_i));

    //=========================================================
    // ALU RS Dispatch
    //=========================================================
    assign alu_rs_dispatch_valid_o = rn_valid_i && is_alu && !flush_i && !stall_i;
    assign alu_rs_op_o = rn_alu_op_i;
    assign alu_rs_src1_preg_o = rn_rs1_phys_i;
    assign alu_rs_src1_data_o = rs1_data;
    assign alu_rs_src1_ready_o = rs1_ready;
    assign alu_rs_src2_preg_o = rn_rs2_phys_i;
    assign alu_rs_src2_data_o = rs2_data;
    assign alu_rs_src2_ready_o = rs2_ready;
    assign alu_rs_dst_preg_o = rn_rd_phys_i;
    assign alu_rs_rob_idx_o = rn_rob_idx_i;
    assign alu_rs_imm_o = rn_imm_i;
    assign alu_rs_use_imm_o = (rn_alu_src2_i != 2'b00);  // Use imm if not reg
    assign alu_rs_pc_o = rn_pc_i;

    //=========================================================
    // MUL RS Dispatch
    //=========================================================
    assign mul_rs_dispatch_valid_o = rn_valid_i && is_mul && !flush_i && !stall_i;
    assign mul_rs_op_o = rn_alu_op_i[1:0];
    assign mul_rs_src1_preg_o = rn_rs1_phys_i;
    assign mul_rs_src1_data_o = rs1_data;
    assign mul_rs_src1_ready_o = rs1_ready;
    assign mul_rs_src2_preg_o = rn_rs2_phys_i;
    assign mul_rs_src2_data_o = rs2_data;
    assign mul_rs_src2_ready_o = rs2_ready;
    assign mul_rs_dst_preg_o = rn_rd_phys_i;
    assign mul_rs_rob_idx_o = rn_rob_idx_i;

    //=========================================================
    // DIV RS Dispatch
    //=========================================================
    assign div_rs_dispatch_valid_o = rn_valid_i && is_div && !flush_i && !stall_i;
    assign div_rs_op_o = rn_alu_op_i[1:0];
    assign div_rs_src1_preg_o = rn_rs1_phys_i;
    assign div_rs_src1_data_o = rs1_data;
    assign div_rs_src1_ready_o = rs1_ready;
    assign div_rs_src2_preg_o = rn_rs2_phys_i;
    assign div_rs_src2_data_o = rs2_data;
    assign div_rs_src2_ready_o = rs2_ready;
    assign div_rs_dst_preg_o = rn_rd_phys_i;
    assign div_rs_rob_idx_o = rn_rob_idx_i;

    //=========================================================
    // LSU RS Dispatch
    //=========================================================
    assign lsu_rs_dispatch_valid_o = rn_valid_i && is_lsu && !flush_i && !stall_i;
    assign lsu_rs_is_load_o = is_load;
    assign lsu_rs_mem_size_o = rn_mem_size_i;
    assign lsu_rs_mem_sign_ext_o = rn_mem_sign_ext_i;
    assign lsu_rs_src1_preg_o = rn_rs1_phys_i;
    assign lsu_rs_src1_data_o = rs1_data;
    assign lsu_rs_src1_ready_o = rs1_ready;
    assign lsu_rs_src2_preg_o = rn_rs2_phys_i;  // Store data
    assign lsu_rs_src2_data_o = rs2_data;
    assign lsu_rs_src2_ready_o = is_load ? 1'b1 : rs2_ready;  // Load doesn't need rs2
    assign lsu_rs_dst_preg_o = rn_rd_phys_i;
    assign lsu_rs_rob_idx_o = rn_rob_idx_i;
    assign lsu_rs_imm_o = rn_imm_i;

    //=========================================================
    // Branch RS Dispatch
    //=========================================================
    assign br_rs_dispatch_valid_o = rn_valid_i && is_branch && !flush_i && !stall_i;
    assign br_rs_op_o = rn_alu_op_i[2:0];
    assign br_rs_src1_preg_o = rn_rs1_phys_i;
    assign br_rs_src1_data_o = rs1_data;
    assign br_rs_src1_ready_o = rs1_ready;
    assign br_rs_src2_preg_o = rn_rs2_phys_i;
    assign br_rs_src2_data_o = rs2_data;
    assign br_rs_src2_ready_o = rs2_ready;
    assign br_rs_dst_preg_o = rn_rd_phys_i;
    assign br_rs_rob_idx_o = rn_rob_idx_i;
    assign br_rs_pc_o = rn_pc_i;
    assign br_rs_imm_o = rn_imm_i;
    assign br_rs_pred_taken_o = rn_pred_taken_i;
    assign br_rs_pred_target_o = rn_pred_target_i;
    assign br_rs_is_jump_o = rn_jump_i;

endmodule
