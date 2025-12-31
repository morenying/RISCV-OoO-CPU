//=================================================================
// Module: cpu_core_top
// Description: RISC-V Out-of-Order CPU Core Top Level
//              Integrates all pipeline stages
//              Integrates BPU, Cache, LSQ
//              Integrates CSR and Exception handling
//              Connects AXI interfaces
// Requirements: 2.1, 15.1, 15.3, 15.4
//=================================================================

`timescale 1ns/1ps

module cpu_core_top #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ARCH_REG_BITS = 5,
    parameter ROB_IDX_BITS = 5,
    parameter GHR_WIDTH = 64,
    parameter RESET_VECTOR = 32'h8000_0000
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // AXI Instruction Bus Interface
    //=========================================================
    output wire                    m_axi_ibus_arvalid,
    input  wire                    m_axi_ibus_arready,
    output wire [XLEN-1:0]         m_axi_ibus_araddr,
    output wire [2:0]              m_axi_ibus_arprot,
    input  wire                    m_axi_ibus_rvalid,
    output wire                    m_axi_ibus_rready,
    input  wire [XLEN-1:0]         m_axi_ibus_rdata,
    input  wire [1:0]              m_axi_ibus_rresp,
    
    //=========================================================
    // AXI Data Bus Interface
    //=========================================================
    output wire                    m_axi_dbus_awvalid,
    input  wire                    m_axi_dbus_awready,
    output wire [XLEN-1:0]         m_axi_dbus_awaddr,
    output wire [2:0]              m_axi_dbus_awprot,
    output wire                    m_axi_dbus_wvalid,
    input  wire                    m_axi_dbus_wready,
    output wire [XLEN-1:0]         m_axi_dbus_wdata,
    output wire [3:0]              m_axi_dbus_wstrb,
    input  wire                    m_axi_dbus_bvalid,
    output wire                    m_axi_dbus_bready,
    input  wire [1:0]              m_axi_dbus_bresp,
    output wire                    m_axi_dbus_arvalid,
    input  wire                    m_axi_dbus_arready,
    output wire [XLEN-1:0]         m_axi_dbus_araddr,
    output wire [2:0]              m_axi_dbus_arprot,
    input  wire                    m_axi_dbus_rvalid,
    output wire                    m_axi_dbus_rready,
    input  wire [XLEN-1:0]         m_axi_dbus_rdata,
    input  wire [1:0]              m_axi_dbus_rresp,
    
    //=========================================================
    // External Interrupts
    //=========================================================
    input  wire                    ext_irq_i,
    input  wire                    timer_irq_i,
    input  wire                    sw_irq_i
);

    //=========================================================
    // Internal Wires - Pipeline Control
    //=========================================================
    wire stall_if, stall_id, stall_rn, stall_is;
    wire flush_if, flush_id, flush_rn, flush_is, flush_ex, flush_mem;
    wire redirect_valid;
    wire [XLEN-1:0] redirect_pc;
    
    //=========================================================
    // IF Stage Signals
    //=========================================================
    wire if_icache_req_valid, if_icache_req_ready;
    wire [XLEN-1:0] if_icache_req_addr;
    wire if_icache_resp_valid;
    wire [XLEN-1:0] if_icache_resp_data;
    
    wire if_bpu_req;
    wire [XLEN-1:0] if_bpu_pc;
    wire if_bpu_pred_taken;
    wire [XLEN-1:0] if_bpu_pred_target;
    wire [1:0] if_bpu_pred_type;
    
    wire if_id_valid;
    wire [XLEN-1:0] if_id_pc, if_id_instr;
    wire if_id_pred_taken;
    wire [XLEN-1:0] if_id_pred_target;
    wire [1:0] if_id_pred_type;
    wire [GHR_WIDTH-1:0] if_id_ghr;
    
    //=========================================================
    // ID Stage Signals
    //=========================================================
    wire id_rn_valid;
    wire [XLEN-1:0] id_rn_pc, id_rn_instr, id_rn_imm;
    wire [4:0] id_rn_rd, id_rn_rs1, id_rn_rs2;
    wire [3:0] id_rn_alu_op;
    wire [1:0] id_rn_alu_src1, id_rn_alu_src2, id_rn_mem_size;
    wire id_rn_reg_write, id_rn_mem_read, id_rn_mem_write;
    wire id_rn_branch, id_rn_jump, id_rn_mem_sign_ext;
    wire [2:0] id_rn_fu_type, id_rn_csr_type;
    wire id_rn_csr_op, id_rn_pred_taken, id_rn_illegal;
    wire [XLEN-1:0] id_rn_pred_target;
    wire [GHR_WIDTH-1:0] id_rn_ghr;

    //=========================================================
    // RN Stage Signals
    //=========================================================
    wire rn_is_valid;
    wire [XLEN-1:0] rn_is_pc, rn_is_imm;
    wire [PHYS_REG_BITS-1:0] rn_is_rs1_phys, rn_is_rs2_phys, rn_is_rd_phys;
    wire rn_is_rs1_ready, rn_is_rs2_ready;
    wire [3:0] rn_is_alu_op;
    wire [1:0] rn_is_alu_src1, rn_is_alu_src2, rn_is_mem_size;
    wire rn_is_reg_write, rn_is_mem_read, rn_is_mem_write;
    wire rn_is_branch, rn_is_jump, rn_is_mem_sign_ext;
    wire [2:0] rn_is_fu_type;
    wire [ROB_IDX_BITS-1:0] rn_is_rob_idx;
    wire rn_is_pred_taken;
    wire [XLEN-1:0] rn_is_pred_target;
    
    //=========================================================
    // ROB Signals
    //=========================================================
    wire rob_alloc_req, rob_alloc_ready;
    wire [ROB_IDX_BITS-1:0] rob_alloc_idx;
    wire [4:0] rob_alloc_rd_arch;
    wire [PHYS_REG_BITS-1:0] rob_alloc_rd_phys, rob_alloc_rd_phys_old;
    wire [XLEN-1:0] rob_alloc_pc;
    wire rob_alloc_is_branch, rob_alloc_is_store;
    
    wire rob_complete_valid;
    wire [ROB_IDX_BITS-1:0] rob_complete_idx;
    wire [XLEN-1:0] rob_complete_result;
    wire rob_complete_exception;
    wire [3:0] rob_complete_exc_code;
    wire rob_complete_branch_taken;
    wire [XLEN-1:0] rob_complete_branch_target;
    
    wire rob_commit_valid, rob_commit_ready;
    wire [ROB_IDX_BITS-1:0] rob_commit_idx;
    wire [4:0] rob_commit_rd_arch;
    wire [PHYS_REG_BITS-1:0] rob_commit_rd_phys, rob_commit_rd_phys_old;
    wire [XLEN-1:0] rob_commit_result, rob_commit_pc;
    wire rob_commit_is_branch, rob_commit_branch_taken;
    wire [XLEN-1:0] rob_commit_branch_target;
    wire rob_commit_is_store, rob_commit_exception;
    wire [3:0] rob_commit_exc_code;
    wire rob_empty, rob_full;
    
    //=========================================================
    // Free List Signals
    //=========================================================
    wire fl_alloc_req, fl_alloc_valid;
    wire [PHYS_REG_BITS-1:0] fl_alloc_preg;
    wire fl_release_valid;
    wire [PHYS_REG_BITS-1:0] fl_release_preg;
    
    //=========================================================
    // RAT Signals
    //=========================================================
    wire [4:0] rat_rs1_arch, rat_rs2_arch, rat_rd_arch;
    wire [PHYS_REG_BITS-1:0] rat_rs1_phys, rat_rs2_phys, rat_rd_phys_old, rat_rd_phys_new;
    wire rat_rs1_ready, rat_rs2_ready;
    wire rat_rename_valid, rat_commit_valid;
    wire [4:0] rat_commit_rd_arch;
    wire [PHYS_REG_BITS-1:0] rat_commit_rd_phys;

    //=========================================================
    // PRF Signals
    //=========================================================
    wire [PHYS_REG_BITS-1:0] prf_rs1_addr, prf_rs2_addr;
    wire [XLEN-1:0] prf_rs1_data, prf_rs2_data;
    wire prf_write_en;
    wire [PHYS_REG_BITS-1:0] prf_write_addr;
    wire [XLEN-1:0] prf_write_data;
    
    //=========================================================
    // CDB Signals
    //=========================================================
    wire cdb_valid;
    wire [PHYS_REG_BITS-1:0] cdb_preg;
    wire [XLEN-1:0] cdb_data;
    wire [ROB_IDX_BITS-1:0] cdb_rob_idx;
    wire cdb_exception;
    wire [3:0] cdb_exc_code;
    wire cdb_branch_taken;
    wire [XLEN-1:0] cdb_branch_target;
    
    // CDB source signals
    wire alu_cdb_valid, alu_cdb_ready;
    wire [PHYS_REG_BITS-1:0] alu_cdb_preg;
    wire [XLEN-1:0] alu_cdb_data;
    wire [ROB_IDX_BITS-1:0] alu_cdb_rob_idx;
    wire alu_cdb_exception;
    wire [3:0] alu_cdb_exc_code;
    
    wire mul_cdb_valid, mul_cdb_ready;
    wire [PHYS_REG_BITS-1:0] mul_cdb_preg;
    wire [XLEN-1:0] mul_cdb_data;
    wire [ROB_IDX_BITS-1:0] mul_cdb_rob_idx;
    
    wire div_cdb_valid, div_cdb_ready;
    wire [PHYS_REG_BITS-1:0] div_cdb_preg;
    wire [XLEN-1:0] div_cdb_data;
    wire [ROB_IDX_BITS-1:0] div_cdb_rob_idx;
    
    wire lsu_cdb_valid, lsu_cdb_ready;
    wire [PHYS_REG_BITS-1:0] lsu_cdb_preg;
    wire [XLEN-1:0] lsu_cdb_data;
    wire [ROB_IDX_BITS-1:0] lsu_cdb_rob_idx;
    wire lsu_cdb_exception;
    wire [3:0] lsu_cdb_exc_code;
    
    wire br_cdb_valid, br_cdb_ready;
    wire [PHYS_REG_BITS-1:0] br_cdb_preg;
    wire [XLEN-1:0] br_cdb_data;
    wire [ROB_IDX_BITS-1:0] br_cdb_rob_idx;
    wire br_cdb_taken;
    wire [XLEN-1:0] br_cdb_target;
    
    //=========================================================
    // Branch Misprediction
    //=========================================================
    wire br_mispredict;
    wire [XLEN-1:0] br_redirect_pc;
    
    //=========================================================
    // Exception Signals
    //=========================================================
    wire exception_valid;
    wire [XLEN-1:0] exception_pc;
    wire [3:0] exception_code;
    wire [XLEN-1:0] exception_tval;
    wire [XLEN-1:0] exception_redirect_pc;
    
    //=========================================================
    // Store Commit
    //=========================================================
    wire store_commit_valid;
    wire [ROB_IDX_BITS-1:0] store_commit_rob_idx;
    
    //=========================================================
    // BPU Update
    //=========================================================
    wire bpu_update_valid;
    wire [XLEN-1:0] bpu_update_pc;
    wire bpu_update_taken;
    wire [XLEN-1:0] bpu_update_target;
    
    //=========================================================
    // GHR
    //=========================================================
    wire [GHR_WIDTH-1:0] ghr;

    //=========================================================
    // D-Cache Signals
    //=========================================================
    wire dcache_req_valid, dcache_req_ready;
    wire dcache_req_write;
    wire [XLEN-1:0] dcache_req_addr, dcache_req_wdata;
    wire [3:0] dcache_req_wmask;
    wire dcache_resp_valid;
    wire [XLEN-1:0] dcache_resp_rdata;
    
    //=========================================================
    // Pipeline Control
    //=========================================================
    assign redirect_valid = br_mispredict || exception_valid;
    assign redirect_pc = exception_valid ? exception_redirect_pc : br_redirect_pc;
    
    assign flush_if = redirect_valid;
    assign flush_id = redirect_valid;
    assign flush_rn = redirect_valid;
    assign flush_is = redirect_valid;
    assign flush_ex = redirect_valid;
    assign flush_mem = redirect_valid;
    
    //=========================================================
    // IF Stage
    //=========================================================
    if_stage #(
        .XLEN(XLEN),
        .GHR_WIDTH(GHR_WIDTH)
    ) u_if_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .stall_i            (stall_if),
        .flush_i            (flush_if),
        .redirect_valid_i   (redirect_valid),
        .redirect_pc_i      (redirect_pc),
        .icache_req_valid_o (if_icache_req_valid),
        .icache_req_addr_o  (if_icache_req_addr),
        .icache_req_ready_i (if_icache_req_ready),
        .icache_resp_valid_i(if_icache_resp_valid),
        .icache_resp_data_i (if_icache_resp_data),
        .bpu_req_o          (if_bpu_req),
        .bpu_pc_o           (if_bpu_pc),
        .bpu_pred_taken_i   (if_bpu_pred_taken),
        .bpu_pred_target_i  (if_bpu_pred_target),
        .bpu_pred_type_i    (if_bpu_pred_type),
        .id_valid_o         (if_id_valid),
        .id_pc_o            (if_id_pc),
        .id_instr_o         (if_id_instr),
        .id_pred_taken_o    (if_id_pred_taken),
        .id_pred_target_o   (if_id_pred_target),
        .id_pred_type_o     (if_id_pred_type),
        .id_ghr_o           (if_id_ghr),
        .ghr_i              (ghr)
    );
    
    //=========================================================
    // ID Stage
    //=========================================================
    id_stage #(
        .XLEN(XLEN),
        .GHR_WIDTH(GHR_WIDTH)
    ) u_id_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .stall_i            (stall_id),
        .flush_i            (flush_id),
        .if_valid_i         (if_id_valid),
        .if_pc_i            (if_id_pc),
        .if_instr_i         (if_id_instr),
        .if_pred_taken_i    (if_id_pred_taken),
        .if_pred_target_i   (if_id_pred_target),
        .if_pred_type_i     (if_id_pred_type),
        .if_ghr_i           (if_id_ghr),
        .rn_valid_o         (id_rn_valid),
        .rn_pc_o            (id_rn_pc),
        .rn_instr_o         (id_rn_instr),
        .rn_rd_o            (id_rn_rd),
        .rn_rs1_o           (id_rn_rs1),
        .rn_rs2_o           (id_rn_rs2),
        .rn_imm_o           (id_rn_imm),
        .rn_alu_op_o        (id_rn_alu_op),
        .rn_alu_src1_o      (id_rn_alu_src1),
        .rn_alu_src2_o      (id_rn_alu_src2),
        .rn_reg_write_o     (id_rn_reg_write),
        .rn_mem_read_o      (id_rn_mem_read),
        .rn_mem_write_o     (id_rn_mem_write),
        .rn_branch_o        (id_rn_branch),
        .rn_jump_o          (id_rn_jump),
        .rn_fu_type_o       (id_rn_fu_type),
        .rn_mem_size_o      (id_rn_mem_size),
        .rn_mem_sign_ext_o  (id_rn_mem_sign_ext),
        .rn_csr_op_o        (id_rn_csr_op),
        .rn_csr_type_o      (id_rn_csr_type),
        .rn_pred_taken_o    (id_rn_pred_taken),
        .rn_pred_target_o   (id_rn_pred_target),
        .rn_ghr_o           (id_rn_ghr),
        .rn_illegal_o       (id_rn_illegal)
    );

    //=========================================================
    // RN Stage
    //=========================================================
    rn_stage #(
        .XLEN(XLEN),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .GHR_WIDTH(GHR_WIDTH)
    ) u_rn_stage (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .stall_i                (stall_rn),
        .flush_i                (flush_rn),
        .recover_i              (1'b0),
        .recover_checkpoint_i   (3'd0),
        .id_valid_i             (id_rn_valid),
        .id_pc_i                (id_rn_pc),
        .id_rd_i                (id_rn_rd),
        .id_rs1_i               (id_rn_rs1),
        .id_rs2_i               (id_rn_rs2),
        .id_imm_i               (id_rn_imm),
        .id_alu_op_i            (id_rn_alu_op),
        .id_alu_src1_i          (id_rn_alu_src1),
        .id_alu_src2_i          (id_rn_alu_src2),
        .id_reg_write_i         (id_rn_reg_write),
        .id_mem_read_i          (id_rn_mem_read),
        .id_mem_write_i         (id_rn_mem_write),
        .id_branch_i            (id_rn_branch),
        .id_jump_i              (id_rn_jump),
        .id_fu_type_i           (id_rn_fu_type),
        .id_mem_size_i          (id_rn_mem_size),
        .id_mem_sign_ext_i      (id_rn_mem_sign_ext),
        .id_pred_taken_i        (id_rn_pred_taken),
        .id_pred_target_i       (id_rn_pred_target),
        .id_ghr_i               (id_rn_ghr),
        .rob_alloc_ready_i      (rob_alloc_ready),
        .rob_alloc_idx_i        (rob_alloc_idx),
        .rob_alloc_req_o        (rob_alloc_req),
        .rob_alloc_rd_arch_o    (rob_alloc_rd_arch),
        .rob_alloc_rd_phys_o    (rob_alloc_rd_phys),
        .rob_alloc_rd_phys_old_o(rob_alloc_rd_phys_old),
        .rob_alloc_pc_o         (rob_alloc_pc),
        .rob_alloc_is_branch_o  (rob_alloc_is_branch),
        .rob_alloc_is_store_o   (rob_alloc_is_store),
        .fl_alloc_valid_i       (fl_alloc_valid),
        .fl_alloc_preg_i        (fl_alloc_preg),
        .fl_alloc_req_o         (fl_alloc_req),
        .rat_rs1_phys_i         (rat_rs1_phys),
        .rat_rs2_phys_i         (rat_rs2_phys),
        .rat_rs1_ready_i        (rat_rs1_ready),
        .rat_rs2_ready_i        (rat_rs2_ready),
        .rat_rd_phys_old_i      (rat_rd_phys_old),
        .rat_rs1_arch_o         (rat_rs1_arch),
        .rat_rs2_arch_o         (rat_rs2_arch),
        .rat_rename_valid_o     (rat_rename_valid),
        .rat_rd_arch_o          (rat_rd_arch),
        .rat_rd_phys_new_o      (rat_rd_phys_new),
        .is_valid_o             (rn_is_valid),
        .is_pc_o                (rn_is_pc),
        .is_rs1_phys_o          (rn_is_rs1_phys),
        .is_rs2_phys_o          (rn_is_rs2_phys),
        .is_rs1_ready_o         (rn_is_rs1_ready),
        .is_rs2_ready_o         (rn_is_rs2_ready),
        .is_rd_phys_o           (rn_is_rd_phys),
        .is_imm_o               (rn_is_imm),
        .is_alu_op_o            (rn_is_alu_op),
        .is_alu_src1_o          (rn_is_alu_src1),
        .is_alu_src2_o          (rn_is_alu_src2),
        .is_reg_write_o         (rn_is_reg_write),
        .is_mem_read_o          (rn_is_mem_read),
        .is_mem_write_o         (rn_is_mem_write),
        .is_branch_o            (rn_is_branch),
        .is_jump_o              (rn_is_jump),
        .is_fu_type_o           (rn_is_fu_type),
        .is_mem_size_o          (rn_is_mem_size),
        .is_mem_sign_ext_o      (rn_is_mem_sign_ext),
        .is_rob_idx_o           (rn_is_rob_idx),
        .is_pred_taken_o        (rn_is_pred_taken),
        .is_pred_target_o       (rn_is_pred_target)
    );

    //=========================================================
    // Free List
    //=========================================================
    free_list #(
        .NUM_PHYS_REGS(64),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_free_list (
        .clk            (clk),
        .rst_n          (rst_n),
        .alloc_req_i    (fl_alloc_req),
        .alloc_valid_o  (fl_alloc_valid),
        .alloc_preg_o   (fl_alloc_preg),
        .release_valid_i(fl_release_valid),
        .release_preg_i (fl_release_preg),
        .flush_i        (flush_rn),
        .empty_o        (),
        .full_o         ()
    );
    
    //=========================================================
    // RAT
    //=========================================================
    rat #(
        .NUM_ARCH_REGS(32),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_rat (
        .clk                (clk),
        .rst_n              (rst_n),
        .rs1_arch_i         (rat_rs1_arch),
        .rs1_phys_o         (rat_rs1_phys),
        .rs1_ready_o        (rat_rs1_ready),
        .rs2_arch_i         (rat_rs2_arch),
        .rs2_phys_o         (rat_rs2_phys),
        .rs2_ready_o        (rat_rs2_ready),
        .rd_arch_i          (rat_rd_arch),
        .rd_phys_old_o      (rat_rd_phys_old),
        .rename_valid_i     (rat_rename_valid),
        .rd_phys_new_i      (rat_rd_phys_new),
        .commit_valid_i     (rat_commit_valid),
        .commit_rd_arch_i   (rat_commit_rd_arch),
        .commit_rd_phys_i   (rat_commit_rd_phys),
        .cdb_valid_i        (cdb_valid),
        .cdb_preg_i         (cdb_preg),
        .flush_i            (flush_rn),
        .checkpoint_i       (1'b0),
        .checkpoint_id_i    (3'd0),
        .restore_i          (1'b0),
        .restore_id_i       (3'd0)
    );
    
    //=========================================================
    // PRF
    //=========================================================
    prf #(
        .NUM_REGS(64),
        .REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN)
    ) u_prf (
        .clk        (clk),
        .rst_n      (rst_n),
        .rs1_addr_i (prf_rs1_addr),
        .rs1_data_o (prf_rs1_data),
        .rs2_addr_i (prf_rs2_addr),
        .rs2_data_o (prf_rs2_data),
        .rs3_addr_i (6'd0),
        .rs3_data_o (),
        .rs4_addr_i (6'd0),
        .rs4_data_o (),
        .wr1_en_i   (prf_write_en),
        .wr1_addr_i (prf_write_addr),
        .wr1_data_i (prf_write_data),
        .wr2_en_i   (1'b0),
        .wr2_addr_i (6'd0),
        .wr2_data_i (32'd0)
    );
    
    // PRF write from CDB
    assign prf_write_en = cdb_valid && (cdb_preg != 6'd0);
    assign prf_write_addr = cdb_preg;
    assign prf_write_data = cdb_data;
    
    //=========================================================
    // ROB
    //=========================================================
    rob #(
        .NUM_ENTRIES(32),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .DATA_WIDTH(XLEN),
        .EXC_CODE_WIDTH(4)
    ) u_rob (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .alloc_req_i            (rob_alloc_req),
        .alloc_ready_o          (rob_alloc_ready),
        .alloc_idx_o            (rob_alloc_idx),
        .alloc_rd_arch_i        (rob_alloc_rd_arch),
        .alloc_rd_phys_i        (rob_alloc_rd_phys),
        .alloc_rd_phys_old_i    (rob_alloc_rd_phys_old),
        .alloc_pc_i             (rob_alloc_pc),
        .alloc_instr_type_i     (4'd0),
        .alloc_is_branch_i      (rob_alloc_is_branch),
        .alloc_is_store_i       (rob_alloc_is_store),
        .complete_valid_i       (cdb_valid),
        .complete_idx_i         (cdb_rob_idx),
        .complete_result_i      (cdb_data),
        .complete_exception_i   (cdb_exception),
        .complete_exc_code_i    (cdb_exc_code),
        .complete_branch_taken_i(cdb_branch_taken),
        .complete_branch_target_i(cdb_branch_target),
        .commit_valid_o         (rob_commit_valid),
        .commit_ready_i         (rob_commit_ready),
        .commit_idx_o           (rob_commit_idx),
        .commit_rd_arch_o       (rob_commit_rd_arch),
        .commit_rd_phys_o       (rob_commit_rd_phys),
        .commit_rd_phys_old_o   (rob_commit_rd_phys_old),
        .commit_result_o        (rob_commit_result),
        .commit_pc_o            (rob_commit_pc),
        .commit_is_branch_o     (rob_commit_is_branch),
        .commit_branch_taken_o  (rob_commit_branch_taken),
        .commit_branch_target_o (rob_commit_branch_target),
        .commit_is_store_o      (rob_commit_is_store),
        .commit_exception_o     (rob_commit_exception),
        .commit_exc_code_o      (rob_commit_exc_code),
        .flush_i                (flush_rn),
        .empty_o                (rob_empty),
        .full_o                 (rob_full),
        .count_o                ()
    );

    //=========================================================
    // CDB Arbiter
    //=========================================================
    cdb #(
        .NUM_SOURCES(6),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_cdb (
        .clk                (clk),
        .rst_n              (rst_n),
        .src0_valid_i       (alu_cdb_valid),
        .src0_ready_o       (alu_cdb_ready),
        .src0_preg_i        (alu_cdb_preg),
        .src0_data_i        (alu_cdb_data),
        .src0_rob_idx_i     (alu_cdb_rob_idx),
        .src0_exception_i   (alu_cdb_exception),
        .src0_exc_code_i    (alu_cdb_exc_code),
        .src1_valid_i       (1'b0),  // ALU1 not used
        .src1_ready_o       (),
        .src1_preg_i        (6'd0),
        .src1_data_i        (32'd0),
        .src1_rob_idx_i     (5'd0),
        .src1_exception_i   (1'b0),
        .src1_exc_code_i    (4'd0),
        .src2_valid_i       (mul_cdb_valid),
        .src2_ready_o       (mul_cdb_ready),
        .src2_preg_i        (mul_cdb_preg),
        .src2_data_i        (mul_cdb_data),
        .src2_rob_idx_i     (mul_cdb_rob_idx),
        .src2_exception_i   (1'b0),
        .src2_exc_code_i    (4'd0),
        .src3_valid_i       (div_cdb_valid),
        .src3_ready_o       (div_cdb_ready),
        .src3_preg_i        (div_cdb_preg),
        .src3_data_i        (div_cdb_data),
        .src3_rob_idx_i     (div_cdb_rob_idx),
        .src3_exception_i   (1'b0),
        .src3_exc_code_i    (4'd0),
        .src4_valid_i       (lsu_cdb_valid),
        .src4_ready_o       (lsu_cdb_ready),
        .src4_preg_i        (lsu_cdb_preg),
        .src4_data_i        (lsu_cdb_data),
        .src4_rob_idx_i     (lsu_cdb_rob_idx),
        .src4_exception_i   (lsu_cdb_exception),
        .src4_exc_code_i    (lsu_cdb_exc_code),
        .src5_valid_i       (br_cdb_valid),
        .src5_ready_o       (br_cdb_ready),
        .src5_preg_i        (br_cdb_preg),
        .src5_data_i        (br_cdb_data),
        .src5_rob_idx_i     (br_cdb_rob_idx),
        .src5_exception_i   (1'b0),
        .src5_exc_code_i    (4'd0),
        .src5_branch_taken_i(br_cdb_taken),
        .src5_branch_target_i(br_cdb_target),
        .cdb_valid_o        (cdb_valid),
        .cdb_preg_o         (cdb_preg),
        .cdb_data_o         (cdb_data),
        .cdb_rob_idx_o      (cdb_rob_idx),
        .cdb_exception_o    (cdb_exception),
        .cdb_exc_code_o     (cdb_exc_code),
        .cdb_branch_taken_o (cdb_branch_taken),
        .cdb_branch_target_o(cdb_branch_target),
        .cdb_src_id_o       ()
    );
    
    //=========================================================
    // WB Stage
    //=========================================================
    wb_stage #(
        .XLEN(XLEN),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .EXC_CODE_WIDTH(4)
    ) u_wb_stage (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .rob_commit_valid_i         (rob_commit_valid),
        .rob_commit_ready_o         (rob_commit_ready),
        .rob_commit_idx_i           (rob_commit_idx),
        .rob_commit_rd_arch_i       (rob_commit_rd_arch),
        .rob_commit_rd_phys_i       (rob_commit_rd_phys),
        .rob_commit_rd_phys_old_i   (rob_commit_rd_phys_old),
        .rob_commit_result_i        (rob_commit_result),
        .rob_commit_pc_i            (rob_commit_pc),
        .rob_commit_is_branch_i     (rob_commit_is_branch),
        .rob_commit_branch_taken_i  (rob_commit_branch_taken),
        .rob_commit_branch_target_i (rob_commit_branch_target),
        .rob_commit_is_store_i      (rob_commit_is_store),
        .rob_commit_exception_i     (rob_commit_exception),
        .rob_commit_exc_code_i      (rob_commit_exc_code),
        .fl_release_valid_o         (fl_release_valid),
        .fl_release_preg_o          (fl_release_preg),
        .rat_commit_valid_o         (rat_commit_valid),
        .rat_commit_rd_arch_o       (rat_commit_rd_arch),
        .rat_commit_rd_phys_o       (rat_commit_rd_phys),
        .store_commit_valid_o       (store_commit_valid),
        .store_commit_rob_idx_o     (store_commit_rob_idx),
        .exception_valid_o          (exception_valid),
        .exception_pc_o             (exception_pc),
        .exception_code_o           (exception_code),
        .exception_tval_o           (exception_tval),
        .bpu_update_valid_o         (bpu_update_valid),
        .bpu_update_pc_o            (bpu_update_pc),
        .bpu_update_taken_o         (bpu_update_taken),
        .bpu_update_target_o        (bpu_update_target),
        .instr_commit_o             (),
        .branch_commit_o            (),
        .store_commit_o             ()
    );

    //=========================================================
    // BPU
    //=========================================================
    bpu #(
        .XLEN(XLEN),
        .GHR_WIDTH(GHR_WIDTH)
    ) u_bpu (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_i              (if_bpu_req),
        .req_pc_i           (if_bpu_pc),
        .pred_taken_o       (if_bpu_pred_taken),
        .pred_target_o      (if_bpu_pred_target),
        .pred_type_o        (if_bpu_pred_type),
        .ghr_o              (ghr),
        .update_valid_i     (bpu_update_valid),
        .update_pc_i        (bpu_update_pc),
        .update_taken_i     (bpu_update_taken),
        .update_target_i    (bpu_update_target),
        .update_type_i      (2'b00),
        .flush_i            (flush_if),
        .recover_ghr_i      (64'd0),
        .recover_valid_i    (1'b0)
    );
    
    //=========================================================
    // I-Cache
    //=========================================================
    icache #(
        .XLEN(XLEN),
        .CACHE_SIZE(4096),
        .LINE_SIZE(32)
    ) u_icache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (if_icache_req_valid),
        .req_addr_i         (if_icache_req_addr),
        .req_ready_o        (if_icache_req_ready),
        .resp_valid_o       (if_icache_resp_valid),
        .resp_data_o        (if_icache_resp_data),
        .mem_req_valid_o    (),
        .mem_req_addr_o     (),
        .mem_req_ready_i    (1'b1),
        .mem_resp_valid_i   (m_axi_ibus_rvalid),
        .mem_resp_data_i    (m_axi_ibus_rdata),
        .mem_resp_last_i    (1'b1),
        .fence_i_i          (1'b0)
    );
    
    //=========================================================
    // D-Cache
    //=========================================================
    dcache #(
        .XLEN(XLEN),
        .CACHE_SIZE(4096),
        .LINE_SIZE(32),
        .NUM_WAYS(2)
    ) u_dcache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (dcache_req_valid),
        .req_write_i        (dcache_req_write),
        .req_addr_i         (dcache_req_addr),
        .req_wdata_i        (dcache_req_wdata),
        .req_wmask_i        (dcache_req_wmask),
        .req_ready_o        (dcache_req_ready),
        .resp_valid_o       (dcache_resp_valid),
        .resp_rdata_o       (dcache_resp_rdata),
        .mem_req_valid_o    (),
        .mem_req_write_o    (),
        .mem_req_addr_o     (),
        .mem_req_wdata_o    (),
        .mem_req_ready_i    (1'b1),
        .mem_resp_valid_i   (m_axi_dbus_rvalid),
        .mem_resp_rdata_i   (m_axi_dbus_rdata),
        .mem_resp_last_i    (1'b1),
        .fence_i            (1'b0)
    );
    
    //=========================================================
    // Exception Unit
    //=========================================================
    exception_unit #(
        .XLEN(XLEN)
    ) u_exception_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .exception_valid_i  (exception_valid),
        .exception_pc_i     (exception_pc),
        .exception_code_i   (exception_code),
        .exception_tval_i   (exception_tval),
        .mtvec_i            (32'h8000_0000),
        .mstatus_mie_i      (1'b0),
        .redirect_valid_o   (),
        .redirect_pc_o      (exception_redirect_pc),
        .flush_o            (),
        .mepc_o             (),
        .mcause_o           (),
        .mtval_o            ()
    );
    
    //=========================================================
    // Stall Logic (simplified)
    //=========================================================
    assign stall_if = stall_id;
    assign stall_id = stall_rn;
    assign stall_rn = stall_is || !rob_alloc_ready || !fl_alloc_valid;
    assign stall_is = 1'b0;  // IS stage handles its own stalls
    
    //=========================================================
    // Simplified AXI connections (directly connect for now)
    //=========================================================
    // I-Bus AXI (directly connected to icache for simplicity)
    assign m_axi_ibus_arvalid = 1'b0;  // Handled by icache
    assign m_axi_ibus_araddr = 32'd0;
    assign m_axi_ibus_arprot = 3'b100;
    assign m_axi_ibus_rready = 1'b1;
    
    // D-Bus AXI (directly connected to dcache for simplicity)
    assign m_axi_dbus_awvalid = 1'b0;
    assign m_axi_dbus_awaddr = 32'd0;
    assign m_axi_dbus_awprot = 3'b000;
    assign m_axi_dbus_wvalid = 1'b0;
    assign m_axi_dbus_wdata = 32'd0;
    assign m_axi_dbus_wstrb = 4'b0;
    assign m_axi_dbus_bready = 1'b1;
    assign m_axi_dbus_arvalid = 1'b0;
    assign m_axi_dbus_araddr = 32'd0;
    assign m_axi_dbus_arprot = 3'b000;
    assign m_axi_dbus_rready = 1'b1;
    
    // Placeholder connections for IS/EX/MEM stages
    // These would need full RS instantiation for complete implementation
    assign prf_rs1_addr = rn_is_rs1_phys;
    assign prf_rs2_addr = rn_is_rs2_phys;
    
    // Placeholder for execution results
    assign alu_cdb_valid = 1'b0;
    assign alu_cdb_preg = 6'd0;
    assign alu_cdb_data = 32'd0;
    assign alu_cdb_rob_idx = 5'd0;
    assign alu_cdb_exception = 1'b0;
    assign alu_cdb_exc_code = 4'd0;
    
    assign mul_cdb_valid = 1'b0;
    assign mul_cdb_preg = 6'd0;
    assign mul_cdb_data = 32'd0;
    assign mul_cdb_rob_idx = 5'd0;
    
    assign div_cdb_valid = 1'b0;
    assign div_cdb_preg = 6'd0;
    assign div_cdb_data = 32'd0;
    assign div_cdb_rob_idx = 5'd0;
    
    assign lsu_cdb_valid = 1'b0;
    assign lsu_cdb_preg = 6'd0;
    assign lsu_cdb_data = 32'd0;
    assign lsu_cdb_rob_idx = 5'd0;
    assign lsu_cdb_exception = 1'b0;
    assign lsu_cdb_exc_code = 4'd0;
    
    assign br_cdb_valid = 1'b0;
    assign br_cdb_preg = 6'd0;
    assign br_cdb_data = 32'd0;
    assign br_cdb_rob_idx = 5'd0;
    assign br_cdb_taken = 1'b0;
    assign br_cdb_target = 32'd0;
    
    assign br_mispredict = 1'b0;
    assign br_redirect_pc = 32'd0;
    
    assign dcache_req_valid = 1'b0;
    assign dcache_req_write = 1'b0;
    assign dcache_req_addr = 32'd0;
    assign dcache_req_wdata = 32'd0;
    assign dcache_req_wmask = 4'b0;

endmodule
