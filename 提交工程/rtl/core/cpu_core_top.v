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
    wire fl_empty;  // Free list empty signal for stall logic
    
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
    wire mul_cdb_exception;
    wire [3:0] mul_cdb_exc_code;
    
    wire div_cdb_valid, div_cdb_ready;
    wire [PHYS_REG_BITS-1:0] div_cdb_preg;
    wire [XLEN-1:0] div_cdb_data;
    wire [ROB_IDX_BITS-1:0] div_cdb_rob_idx;
    wire div_cdb_exception;
    wire [3:0] div_cdb_exc_code;
    
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
    wire br_cdb_exception;
    wire [3:0] br_cdb_exc_code;
    
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
    // IS Stage to RS Signals
    //=========================================================
    // ALU RS dispatch
    wire                    alu_rs_dispatch_valid;
    wire                    alu_rs_dispatch_ready;
    wire [3:0]              alu_rs_op;
    wire [PHYS_REG_BITS-1:0] alu_rs_src1_preg;
    wire [XLEN-1:0]         alu_rs_src1_data;
    wire                    alu_rs_src1_ready;
    wire [PHYS_REG_BITS-1:0] alu_rs_src2_preg;
    wire [XLEN-1:0]         alu_rs_src2_data;
    wire                    alu_rs_src2_ready;
    wire [PHYS_REG_BITS-1:0] alu_rs_dst_preg;
    wire [ROB_IDX_BITS-1:0] alu_rs_rob_idx;
    wire [XLEN-1:0]         alu_rs_imm;
    wire                    alu_rs_use_imm;
    wire [XLEN-1:0]         alu_rs_pc;
    
    // MUL RS dispatch
    wire                    mul_rs_dispatch_valid;
    wire                    mul_rs_dispatch_ready;
    wire [1:0]              mul_rs_op;
    wire [PHYS_REG_BITS-1:0] mul_rs_src1_preg;
    wire [XLEN-1:0]         mul_rs_src1_data;
    wire                    mul_rs_src1_ready;
    wire [PHYS_REG_BITS-1:0] mul_rs_src2_preg;
    wire [XLEN-1:0]         mul_rs_src2_data;
    wire                    mul_rs_src2_ready;
    wire [PHYS_REG_BITS-1:0] mul_rs_dst_preg;
    wire [ROB_IDX_BITS-1:0] mul_rs_rob_idx;
    
    // DIV RS dispatch
    wire                    div_rs_dispatch_valid;
    wire                    div_rs_dispatch_ready;
    wire [1:0]              div_rs_op;
    wire [PHYS_REG_BITS-1:0] div_rs_src1_preg;
    wire [XLEN-1:0]         div_rs_src1_data;
    wire                    div_rs_src1_ready;
    wire [PHYS_REG_BITS-1:0] div_rs_src2_preg;
    wire [XLEN-1:0]         div_rs_src2_data;
    wire                    div_rs_src2_ready;
    wire [PHYS_REG_BITS-1:0] div_rs_dst_preg;
    wire [ROB_IDX_BITS-1:0] div_rs_rob_idx;
    
    // LSU RS dispatch
    wire                    lsu_rs_dispatch_valid;
    wire                    lsu_rs_dispatch_ready;
    wire                    lsu_rs_is_load;
    wire [1:0]              lsu_rs_mem_size;
    wire                    lsu_rs_mem_sign_ext;
    wire [PHYS_REG_BITS-1:0] lsu_rs_src1_preg;
    wire [XLEN-1:0]         lsu_rs_src1_data;
    wire                    lsu_rs_src1_ready;
    wire [PHYS_REG_BITS-1:0] lsu_rs_src2_preg;
    wire [XLEN-1:0]         lsu_rs_src2_data;
    wire                    lsu_rs_src2_ready;
    wire [PHYS_REG_BITS-1:0] lsu_rs_dst_preg;
    wire [ROB_IDX_BITS-1:0] lsu_rs_rob_idx;
    wire [XLEN-1:0]         lsu_rs_imm;
    
    // Branch RS dispatch
    wire                    br_rs_dispatch_valid;
    wire                    br_rs_dispatch_ready;
    wire [2:0]              br_rs_op;
    wire [PHYS_REG_BITS-1:0] br_rs_src1_preg;
    wire [XLEN-1:0]         br_rs_src1_data;
    wire                    br_rs_src1_ready;
    wire [PHYS_REG_BITS-1:0] br_rs_src2_preg;
    wire [XLEN-1:0]         br_rs_src2_data;
    wire                    br_rs_src2_ready;
    wire [PHYS_REG_BITS-1:0] br_rs_dst_preg;
    wire [ROB_IDX_BITS-1:0] br_rs_rob_idx;
    wire [XLEN-1:0]         br_rs_pc;
    wire [XLEN-1:0]         br_rs_imm;
    wire                    br_rs_pred_taken;
    wire [XLEN-1:0]         br_rs_pred_target;
    wire                    br_rs_is_jump;
    
    //=========================================================
    // RS to EX Stage Signals
    //=========================================================
    // ALU issue
    wire                    alu_issue_valid;
    wire                    alu_issue_ready;
    wire [3:0]              alu_issue_op;
    wire [XLEN-1:0]         alu_issue_src1;
    wire [XLEN-1:0]         alu_issue_src2;
    wire [PHYS_REG_BITS-1:0] alu_issue_dst_preg;
    wire [ROB_IDX_BITS-1:0] alu_issue_rob_idx;
    wire [XLEN-1:0]         alu_issue_pc;
    
    // MUL issue
    wire                    mul_issue_valid;
    wire                    mul_issue_ready;
    wire [1:0]              mul_issue_op;
    wire [XLEN-1:0]         mul_issue_src1;
    wire [XLEN-1:0]         mul_issue_src2;
    wire [PHYS_REG_BITS-1:0] mul_issue_dst_preg;
    wire [ROB_IDX_BITS-1:0] mul_issue_rob_idx;
    
    // DIV issue
    wire                    div_issue_valid;
    wire                    div_issue_ready;
    wire [1:0]              div_issue_op;
    wire [XLEN-1:0]         div_issue_src1;
    wire [XLEN-1:0]         div_issue_src2;
    wire [PHYS_REG_BITS-1:0] div_issue_dst_preg;
    wire [ROB_IDX_BITS-1:0] div_issue_rob_idx;
    
    // Branch issue
    wire                    br_issue_valid;
    wire                    br_issue_ready;
    wire [2:0]              br_issue_op;
    wire [XLEN-1:0]         br_issue_src1;
    wire [XLEN-1:0]         br_issue_src2;
    wire [PHYS_REG_BITS-1:0] br_issue_dst_preg;
    wire [ROB_IDX_BITS-1:0] br_issue_rob_idx;
    wire [XLEN-1:0]         br_issue_pc;
    wire [XLEN-1:0]         br_issue_imm;
    wire                    br_issue_pred_taken;
    wire [XLEN-1:0]         br_issue_pred_target;
    wire                    br_issue_is_jump;
    
    // IS stage stall output
    wire                    is_stall_out;
    
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
    // IS Stage
    //=========================================================
    is_stage #(
        .XLEN(XLEN),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_is_stage (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .stall_i                (stall_is),
        .flush_i                (flush_is),
        // From RN stage
        .rn_valid_i             (rn_is_valid),
        .rn_pc_i                (rn_is_pc),
        .rn_rs1_phys_i          (rn_is_rs1_phys),
        .rn_rs2_phys_i          (rn_is_rs2_phys),
        .rn_rs1_ready_i         (rn_is_rs1_ready),
        .rn_rs2_ready_i         (rn_is_rs2_ready),
        .rn_rd_phys_i           (rn_is_rd_phys),
        .rn_imm_i               (rn_is_imm),
        .rn_alu_op_i            (rn_is_alu_op),
        .rn_alu_src1_i          (rn_is_alu_src1),
        .rn_alu_src2_i          (rn_is_alu_src2),
        .rn_reg_write_i         (rn_is_reg_write),
        .rn_mem_read_i          (rn_is_mem_read),
        .rn_mem_write_i         (rn_is_mem_write),
        .rn_branch_i            (rn_is_branch),
        .rn_jump_i              (rn_is_jump),
        .rn_fu_type_i           (rn_is_fu_type),
        .rn_mem_size_i          (rn_is_mem_size),
        .rn_mem_sign_ext_i      (rn_is_mem_sign_ext),
        .rn_rob_idx_i           (rn_is_rob_idx),
        .rn_pred_taken_i        (rn_is_pred_taken),
        .rn_pred_target_i       (rn_is_pred_target),
        // PRF read interface
        .prf_rs1_addr_o         (prf_rs1_addr),
        .prf_rs2_addr_o         (prf_rs2_addr),
        .prf_rs1_data_i         (prf_rs1_data),
        .prf_rs2_data_i         (prf_rs2_data),
        // CDB interface
        .cdb_valid_i            (cdb_valid),
        .cdb_preg_i             (cdb_preg),
        .cdb_data_i             (cdb_data),
        // ALU RS interface
        .alu_rs_dispatch_valid_o(alu_rs_dispatch_valid),
        .alu_rs_dispatch_ready_i(alu_rs_dispatch_ready),
        .alu_rs_op_o            (alu_rs_op),
        .alu_rs_src1_preg_o     (alu_rs_src1_preg),
        .alu_rs_src1_data_o     (alu_rs_src1_data),
        .alu_rs_src1_ready_o    (alu_rs_src1_ready),
        .alu_rs_src2_preg_o     (alu_rs_src2_preg),
        .alu_rs_src2_data_o     (alu_rs_src2_data),
        .alu_rs_src2_ready_o    (alu_rs_src2_ready),
        .alu_rs_dst_preg_o      (alu_rs_dst_preg),
        .alu_rs_rob_idx_o       (alu_rs_rob_idx),
        .alu_rs_imm_o           (alu_rs_imm),
        .alu_rs_use_imm_o       (alu_rs_use_imm),
        .alu_rs_pc_o            (alu_rs_pc),
        // MUL RS interface
        .mul_rs_dispatch_valid_o(mul_rs_dispatch_valid),
        .mul_rs_dispatch_ready_i(mul_rs_dispatch_ready),
        .mul_rs_op_o            (mul_rs_op),
        .mul_rs_src1_preg_o     (mul_rs_src1_preg),
        .mul_rs_src1_data_o     (mul_rs_src1_data),
        .mul_rs_src1_ready_o    (mul_rs_src1_ready),
        .mul_rs_src2_preg_o     (mul_rs_src2_preg),
        .mul_rs_src2_data_o     (mul_rs_src2_data),
        .mul_rs_src2_ready_o    (mul_rs_src2_ready),
        .mul_rs_dst_preg_o      (mul_rs_dst_preg),
        .mul_rs_rob_idx_o       (mul_rs_rob_idx),
        // DIV RS interface
        .div_rs_dispatch_valid_o(div_rs_dispatch_valid),
        .div_rs_dispatch_ready_i(div_rs_dispatch_ready),
        .div_rs_op_o            (div_rs_op),
        .div_rs_src1_preg_o     (div_rs_src1_preg),
        .div_rs_src1_data_o     (div_rs_src1_data),
        .div_rs_src1_ready_o    (div_rs_src1_ready),
        .div_rs_src2_preg_o     (div_rs_src2_preg),
        .div_rs_src2_data_o     (div_rs_src2_data),
        .div_rs_src2_ready_o    (div_rs_src2_ready),
        .div_rs_dst_preg_o      (div_rs_dst_preg),
        .div_rs_rob_idx_o       (div_rs_rob_idx),
        // LSU RS interface
        .lsu_rs_dispatch_valid_o(lsu_rs_dispatch_valid),
        .lsu_rs_dispatch_ready_i(lsu_rs_dispatch_ready),
        .lsu_rs_is_load_o       (lsu_rs_is_load),
        .lsu_rs_mem_size_o      (lsu_rs_mem_size),
        .lsu_rs_mem_sign_ext_o  (lsu_rs_mem_sign_ext),
        .lsu_rs_src1_preg_o     (lsu_rs_src1_preg),
        .lsu_rs_src1_data_o     (lsu_rs_src1_data),
        .lsu_rs_src1_ready_o    (lsu_rs_src1_ready),
        .lsu_rs_src2_preg_o     (lsu_rs_src2_preg),
        .lsu_rs_src2_data_o     (lsu_rs_src2_data),
        .lsu_rs_src2_ready_o    (lsu_rs_src2_ready),
        .lsu_rs_dst_preg_o      (lsu_rs_dst_preg),
        .lsu_rs_rob_idx_o       (lsu_rs_rob_idx),
        .lsu_rs_imm_o           (lsu_rs_imm),
        // Branch RS interface
        .br_rs_dispatch_valid_o (br_rs_dispatch_valid),
        .br_rs_dispatch_ready_i (br_rs_dispatch_ready),
        .br_rs_op_o             (br_rs_op),
        .br_rs_src1_preg_o      (br_rs_src1_preg),
        .br_rs_src1_data_o      (br_rs_src1_data),
        .br_rs_src1_ready_o     (br_rs_src1_ready),
        .br_rs_src2_preg_o      (br_rs_src2_preg),
        .br_rs_src2_data_o      (br_rs_src2_data),
        .br_rs_src2_ready_o     (br_rs_src2_ready),
        .br_rs_dst_preg_o       (br_rs_dst_preg),
        .br_rs_rob_idx_o        (br_rs_rob_idx),
        .br_rs_pc_o             (br_rs_pc),
        .br_rs_imm_o            (br_rs_imm),
        .br_rs_pred_taken_o     (br_rs_pred_taken),
        .br_rs_pred_target_o    (br_rs_pred_target),
        .br_rs_is_jump_o        (br_rs_is_jump),
        // Stall output
        .stall_o                (is_stall_out)
    );

    //=========================================================
    // ALU Reservation Station
    //=========================================================
    reservation_station #(
        .NUM_ENTRIES(4),
        .ENTRY_IDX_BITS(2),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .ALU_OP_WIDTH(4)
    ) u_alu_rs (
        .clk                (clk),
        .rst_n              (rst_n),
        .dispatch_valid_i   (alu_rs_dispatch_valid),
        .dispatch_ready_o   (alu_rs_dispatch_ready),
        .dispatch_op_i      (alu_rs_op),
        .dispatch_src1_preg_i(alu_rs_src1_preg),
        .dispatch_src1_data_i(alu_rs_src1_data),
        .dispatch_src1_ready_i(alu_rs_src1_ready),
        .dispatch_src2_preg_i(alu_rs_src2_preg),
        .dispatch_src2_data_i(alu_rs_src2_data),
        .dispatch_src2_ready_i(alu_rs_src2_ready),
        .dispatch_dst_preg_i(alu_rs_dst_preg),
        .dispatch_rob_idx_i (alu_rs_rob_idx),
        .dispatch_imm_i     (alu_rs_imm),
        .dispatch_use_imm_i (alu_rs_use_imm),
        .dispatch_pc_i      (alu_rs_pc),
        .issue_valid_o      (alu_issue_valid),
        .issue_ready_i      (alu_issue_ready),
        .issue_op_o         (alu_issue_op),
        .issue_src1_data_o  (alu_issue_src1),
        .issue_src2_data_o  (alu_issue_src2),
        .issue_dst_preg_o   (alu_issue_dst_preg),
        .issue_rob_idx_o    (alu_issue_rob_idx),
        .issue_pc_o         (alu_issue_pc),
        .cdb_valid_i        (cdb_valid),
        .cdb_preg_i         (cdb_preg),
        .cdb_data_i         (cdb_data),
        .flush_i            (flush_is),
        .empty_o            (),
        .full_o             ()
    );
    
    //=========================================================
    // MUL Reservation Station
    //=========================================================
    reservation_station #(
        .NUM_ENTRIES(2),
        .ENTRY_IDX_BITS(1),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .ALU_OP_WIDTH(2)
    ) u_mul_rs (
        .clk                (clk),
        .rst_n              (rst_n),
        .dispatch_valid_i   (mul_rs_dispatch_valid),
        .dispatch_ready_o   (mul_rs_dispatch_ready),
        .dispatch_op_i      (mul_rs_op),
        .dispatch_src1_preg_i(mul_rs_src1_preg),
        .dispatch_src1_data_i(mul_rs_src1_data),
        .dispatch_src1_ready_i(mul_rs_src1_ready),
        .dispatch_src2_preg_i(mul_rs_src2_preg),
        .dispatch_src2_data_i(mul_rs_src2_data),
        .dispatch_src2_ready_i(mul_rs_src2_ready),
        .dispatch_dst_preg_i(mul_rs_dst_preg),
        .dispatch_rob_idx_i (mul_rs_rob_idx),
        .dispatch_imm_i     (32'd0),
        .dispatch_use_imm_i (1'b0),
        .dispatch_pc_i      (32'd0),
        .issue_valid_o      (mul_issue_valid),
        .issue_ready_i      (mul_issue_ready),
        .issue_op_o         (mul_issue_op),
        .issue_src1_data_o  (mul_issue_src1),
        .issue_src2_data_o  (mul_issue_src2),
        .issue_dst_preg_o   (mul_issue_dst_preg),
        .issue_rob_idx_o    (mul_issue_rob_idx),
        .issue_pc_o         (),
        .cdb_valid_i        (cdb_valid),
        .cdb_preg_i         (cdb_preg),
        .cdb_data_i         (cdb_data),
        .flush_i            (flush_is),
        .empty_o            (),
        .full_o             ()
    );
    
    //=========================================================
    // DIV Reservation Station
    //=========================================================
    reservation_station #(
        .NUM_ENTRIES(2),
        .ENTRY_IDX_BITS(1),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .ALU_OP_WIDTH(2)
    ) u_div_rs (
        .clk                (clk),
        .rst_n              (rst_n),
        .dispatch_valid_i   (div_rs_dispatch_valid),
        .dispatch_ready_o   (div_rs_dispatch_ready),
        .dispatch_op_i      (div_rs_op),
        .dispatch_src1_preg_i(div_rs_src1_preg),
        .dispatch_src1_data_i(div_rs_src1_data),
        .dispatch_src1_ready_i(div_rs_src1_ready),
        .dispatch_src2_preg_i(div_rs_src2_preg),
        .dispatch_src2_data_i(div_rs_src2_data),
        .dispatch_src2_ready_i(div_rs_src2_ready),
        .dispatch_dst_preg_i(div_rs_dst_preg),
        .dispatch_rob_idx_i (div_rs_rob_idx),
        .dispatch_imm_i     (32'd0),
        .dispatch_use_imm_i (1'b0),
        .dispatch_pc_i      (32'd0),
        .issue_valid_o      (div_issue_valid),
        .issue_ready_i      (div_issue_ready),
        .issue_op_o         (div_issue_op),
        .issue_src1_data_o  (div_issue_src1),
        .issue_src2_data_o  (div_issue_src2),
        .issue_dst_preg_o   (div_issue_dst_preg),
        .issue_rob_idx_o    (div_issue_rob_idx),
        .issue_pc_o         (),
        .cdb_valid_i        (cdb_valid),
        .cdb_preg_i         (cdb_preg),
        .cdb_data_i         (cdb_data),
        .flush_i            (flush_is),
        .empty_o            (),
        .full_o             ()
    );

    //=========================================================
    // Branch Reservation Station
    //=========================================================
    // Branch RS needs extra fields, use a simplified direct connection
    // since branch unit is single-cycle
    assign br_rs_dispatch_ready = br_issue_ready;
    assign br_issue_valid = br_rs_dispatch_valid && br_rs_src1_ready && br_rs_src2_ready;
    assign br_issue_op = br_rs_op;
    assign br_issue_src1 = br_rs_src1_data;
    assign br_issue_src2 = br_rs_src2_data;
    assign br_issue_dst_preg = br_rs_dst_preg;
    assign br_issue_rob_idx = br_rs_rob_idx;
    assign br_issue_pc = br_rs_pc;
    assign br_issue_imm = br_rs_imm;
    assign br_issue_pred_taken = br_rs_pred_taken;
    assign br_issue_pred_target = br_rs_pred_target;
    assign br_issue_is_jump = br_rs_is_jump;
    
    //=========================================================
    // LSU Reservation Station (simplified - direct to MEM stage)
    //=========================================================
    assign lsu_rs_dispatch_ready = lsq_ld_alloc_ready && lsq_st_alloc_ready;
    
    //=========================================================
    // LSQ Signals
    //=========================================================
    wire lsq_ld_alloc_ready, lsq_st_alloc_ready;
    wire [2:0] lsq_ld_alloc_idx, lsq_st_alloc_idx;
    
    // LSQ address calculation signals
    wire lsq_ld_addr_valid, lsq_st_addr_valid;
    wire [2:0] lsq_ld_addr_idx, lsq_st_addr_idx;
    wire [XLEN-1:0] lsq_ld_addr, lsq_st_addr;
    
    // LSQ store data signals
    wire lsq_st_data_valid;
    wire [2:0] lsq_st_data_idx;
    wire [XLEN-1:0] lsq_st_data;
    
    // LSQ D-Cache interface
    wire lsq_dcache_rd_valid, lsq_dcache_wr_valid;
    wire [XLEN-1:0] lsq_dcache_rd_addr, lsq_dcache_wr_addr;
    wire [XLEN-1:0] lsq_dcache_wr_data;
    wire [1:0] lsq_dcache_wr_size;
    wire lsq_dcache_rd_ready, lsq_dcache_wr_ready;
    wire lsq_dcache_rd_resp_valid, lsq_dcache_wr_resp_valid;
    wire [XLEN-1:0] lsq_dcache_rd_resp_data;
    
    // LSQ commit interface
    wire lsq_ld_commit_valid, lsq_st_commit_valid;
    wire [2:0] lsq_ld_commit_idx, lsq_st_commit_idx;
    
    // LSQ violation detection
    wire lsq_violation;
    wire [ROB_IDX_BITS-1:0] lsq_violation_rob_idx;
    
    // AGU for address calculation
    wire agu_valid;
    wire [XLEN-1:0] agu_base, agu_offset, agu_result;
    reg lsu_pending;
    reg lsu_is_load;
    reg [2:0] lsu_lq_idx, lsu_sq_idx;
    reg [XLEN-1:0] lsu_store_data;
    reg [PHYS_REG_BITS-1:0] lsu_dst_preg;
    reg [ROB_IDX_BITS-1:0] lsu_rob_idx;
    
    // AGU signals
    wire agu_done;
    wire [31:0] agu_addr;
    wire agu_misaligned;
    
    // AGU instance for LSU address calculation
    agu_unit u_agu (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (agu_valid),
        .is_store_i     (~lsu_rs_is_load),
        .base_i         (agu_base),
        .offset_i       (agu_offset),
        .store_data_i   (lsu_rs_src2_data),
        .size_i         (2'b10),  // Word size for now
        .sign_ext_i     (1'b0),
        .prd_i          (lsu_rs_dst_preg),
        .rob_idx_i      (lsu_rs_rob_idx),
        .done_o         (agu_done),
        .addr_o         (agu_addr),
        .data_o         (),
        .misaligned_o   (agu_misaligned),
        .size_o         (),
        .sign_ext_o     (),
        .is_store_o     (),
        .result_prd_o   (),
        .result_rob_idx_o()
    );
    
    assign agu_result = agu_addr;
    
    // LSU dispatch handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsu_pending <= 1'b0;
            lsu_is_load <= 1'b0;
            lsu_lq_idx <= 3'd0;
            lsu_sq_idx <= 3'd0;
            lsu_store_data <= 32'd0;
            lsu_dst_preg <= 6'd0;
            lsu_rob_idx <= 5'd0;
        end else if (flush_is) begin
            lsu_pending <= 1'b0;
        end else if (lsu_rs_dispatch_valid && lsu_rs_dispatch_ready && lsu_rs_src1_ready) begin
            lsu_pending <= 1'b1;
            lsu_is_load <= lsu_rs_is_load;
            lsu_lq_idx <= lsq_ld_alloc_idx;
            lsu_sq_idx <= lsq_st_alloc_idx;
            lsu_store_data <= lsu_rs_src2_data;
            lsu_dst_preg <= lsu_rs_dst_preg;
            lsu_rob_idx <= lsu_rs_rob_idx;
        end else if (lsu_pending) begin
            lsu_pending <= 1'b0;
        end
    end
    
    assign agu_valid = lsu_rs_dispatch_valid && lsu_rs_dispatch_ready && lsu_rs_src1_ready;
    assign agu_base = lsu_rs_src1_data;
    assign agu_offset = lsu_rs_imm;
    
    // LSQ allocation signals
    wire lsq_ld_alloc_valid = lsu_rs_dispatch_valid && lsu_rs_dispatch_ready && lsu_rs_is_load;
    wire lsq_st_alloc_valid = lsu_rs_dispatch_valid && lsu_rs_dispatch_ready && !lsu_rs_is_load;
    
    // LSQ address signals (one cycle after dispatch)
    assign lsq_ld_addr_valid = lsu_pending && lsu_is_load;
    assign lsq_ld_addr_idx = lsu_lq_idx;
    assign lsq_ld_addr = agu_result;
    
    assign lsq_st_addr_valid = lsu_pending && !lsu_is_load;
    assign lsq_st_addr_idx = lsu_sq_idx;
    assign lsq_st_addr = agu_result;
    
    // Store data (available same cycle as address)
    assign lsq_st_data_valid = lsu_pending && !lsu_is_load;
    assign lsq_st_data_idx = lsu_sq_idx;
    assign lsq_st_data = lsu_store_data;
    
    //=========================================================
    // LSQ Instance
    //=========================================================
    lsq #(
        .LQ_ENTRIES(8),
        .SQ_ENTRIES(8),
        .ADDR_WIDTH(XLEN),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_lsq (
        .clk                    (clk),
        .rst_n                  (rst_n),
        // Load allocation
        .ld_alloc_valid_i       (lsq_ld_alloc_valid),
        .ld_alloc_ready_o       (lsq_ld_alloc_ready),
        .ld_alloc_idx_o         (lsq_ld_alloc_idx),
        .ld_alloc_rob_idx_i     (lsu_rs_rob_idx),
        .ld_alloc_dst_preg_i    (lsu_rs_dst_preg),
        .ld_alloc_size_i        (lsu_rs_mem_size),
        .ld_alloc_sign_ext_i    (lsu_rs_mem_sign_ext),
        // Store allocation
        .st_alloc_valid_i       (lsq_st_alloc_valid),
        .st_alloc_ready_o       (lsq_st_alloc_ready),
        .st_alloc_idx_o         (lsq_st_alloc_idx),
        .st_alloc_rob_idx_i     (lsu_rs_rob_idx),
        .st_alloc_size_i        (lsu_rs_mem_size),
        // Load address
        .ld_addr_valid_i        (lsq_ld_addr_valid),
        .ld_addr_idx_i          (lsq_ld_addr_idx),
        .ld_addr_i              (lsq_ld_addr),
        // Store address
        .st_addr_valid_i        (lsq_st_addr_valid),
        .st_addr_idx_i          (lsq_st_addr_idx),
        .st_addr_i              (lsq_st_addr),
        // Store data
        .st_data_valid_i        (lsq_st_data_valid),
        .st_data_idx_i          (lsq_st_data_idx),
        .st_data_i              (lsq_st_data),
        // D-Cache read interface
        .dcache_rd_valid_o      (lsq_dcache_rd_valid),
        .dcache_rd_addr_o       (lsq_dcache_rd_addr),
        .dcache_rd_ready_i      (lsq_dcache_rd_ready),
        .dcache_rd_resp_valid_i (lsq_dcache_rd_resp_valid),
        .dcache_rd_resp_data_i  (lsq_dcache_rd_resp_data),
        // D-Cache write interface
        .dcache_wr_valid_o      (lsq_dcache_wr_valid),
        .dcache_wr_addr_o       (lsq_dcache_wr_addr),
        .dcache_wr_data_o       (lsq_dcache_wr_data),
        .dcache_wr_size_o       (lsq_dcache_wr_size),
        .dcache_wr_ready_i      (lsq_dcache_wr_ready),
        .dcache_wr_resp_valid_i (lsq_dcache_wr_resp_valid),
        // Load completion (to CDB)
        .ld_complete_valid_o    (lsu_cdb_valid),
        .ld_complete_preg_o     (lsu_cdb_preg),
        .ld_complete_data_o     (lsu_cdb_data),
        .ld_complete_rob_idx_o  (lsu_cdb_rob_idx),
        .ld_complete_ready_i    (lsu_cdb_ready),
        // Commit interface
        .ld_commit_valid_i      (lsq_ld_commit_valid),
        .ld_commit_idx_i        (lsq_ld_commit_idx),
        .st_commit_valid_i      (lsq_st_commit_valid),
        .st_commit_idx_i        (lsq_st_commit_idx),
        // Flush
        .flush_i                (flush_is),
        // Violation detection
        .violation_o            (lsq_violation),
        .violation_rob_idx_o    (lsq_violation_rob_idx)
    );
    
    // LSU CDB exception signals (no exceptions from LSU for now)
    assign lsu_cdb_exception = 1'b0;
    assign lsu_cdb_exc_code = 4'd0;
    
    //=========================================================
    // EX Stage
    //=========================================================
    ex_stage #(
        .XLEN(XLEN),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_ex_stage (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .flush_i                (flush_ex),
        // ALU Issue Interface
        .alu_issue_valid_i      (alu_issue_valid),
        .alu_issue_ready_o      (alu_issue_ready),
        .alu_issue_op_i         (alu_issue_op),
        .alu_issue_src1_i       (alu_issue_src1),
        .alu_issue_src2_i       (alu_issue_src2),
        .alu_issue_dst_preg_i   (alu_issue_dst_preg),
        .alu_issue_rob_idx_i    (alu_issue_rob_idx),
        .alu_issue_pc_i         (alu_issue_pc),
        // MUL Issue Interface
        .mul_issue_valid_i      (mul_issue_valid),
        .mul_issue_ready_o      (mul_issue_ready),
        .mul_issue_op_i         (mul_issue_op),
        .mul_issue_src1_i       (mul_issue_src1),
        .mul_issue_src2_i       (mul_issue_src2),
        .mul_issue_dst_preg_i   (mul_issue_dst_preg),
        .mul_issue_rob_idx_i    (mul_issue_rob_idx),
        // DIV Issue Interface
        .div_issue_valid_i      (div_issue_valid),
        .div_issue_ready_o      (div_issue_ready),
        .div_issue_op_i         (div_issue_op),
        .div_issue_src1_i       (div_issue_src1),
        .div_issue_src2_i       (div_issue_src2),
        .div_issue_dst_preg_i   (div_issue_dst_preg),
        .div_issue_rob_idx_i    (div_issue_rob_idx),
        // Branch Issue Interface
        .br_issue_valid_i       (br_issue_valid),
        .br_issue_ready_o       (br_issue_ready),
        .br_issue_op_i          (br_issue_op),
        .br_issue_src1_i        (br_issue_src1),
        .br_issue_src2_i        (br_issue_src2),
        .br_issue_dst_preg_i    (br_issue_dst_preg),
        .br_issue_rob_idx_i     (br_issue_rob_idx),
        .br_issue_pc_i          (br_issue_pc),
        .br_issue_imm_i         (br_issue_imm),
        .br_issue_pred_taken_i  (br_issue_pred_taken),
        .br_issue_pred_target_i (br_issue_pred_target),
        .br_issue_is_jump_i     (br_issue_is_jump),
        // ALU CDB Output
        .alu_cdb_valid_o        (alu_cdb_valid),
        .alu_cdb_ready_i        (alu_cdb_ready),
        .alu_cdb_preg_o         (alu_cdb_preg),
        .alu_cdb_data_o         (alu_cdb_data),
        .alu_cdb_rob_idx_o      (alu_cdb_rob_idx),
        .alu_cdb_exception_o    (alu_cdb_exception),
        .alu_cdb_exc_code_o     (alu_cdb_exc_code),
        // MUL CDB Output
        .mul_cdb_valid_o        (mul_cdb_valid),
        .mul_cdb_ready_i        (mul_cdb_ready),
        .mul_cdb_preg_o         (mul_cdb_preg),
        .mul_cdb_data_o         (mul_cdb_data),
        .mul_cdb_rob_idx_o      (mul_cdb_rob_idx),
        .mul_cdb_exception_o    (mul_cdb_exception),
        .mul_cdb_exc_code_o     (mul_cdb_exc_code),
        // DIV CDB Output
        .div_cdb_valid_o        (div_cdb_valid),
        .div_cdb_ready_i        (div_cdb_ready),
        .div_cdb_preg_o         (div_cdb_preg),
        .div_cdb_data_o         (div_cdb_data),
        .div_cdb_rob_idx_o      (div_cdb_rob_idx),
        .div_cdb_exception_o    (div_cdb_exception),
        .div_cdb_exc_code_o     (div_cdb_exc_code),
        // Branch CDB Output
        .br_cdb_valid_o         (br_cdb_valid),
        .br_cdb_ready_i         (br_cdb_ready),
        .br_cdb_preg_o          (br_cdb_preg),
        .br_cdb_data_o          (br_cdb_data),
        .br_cdb_rob_idx_o       (br_cdb_rob_idx),
        .br_cdb_exception_o     (br_cdb_exception),
        .br_cdb_exc_code_o      (br_cdb_exc_code),
        .br_cdb_taken_o         (br_cdb_taken),
        .br_cdb_target_o        (br_cdb_target),
        // Branch misprediction
        .br_mispredict_o        (br_mispredict),
        .br_redirect_pc_o       (br_redirect_pc)
    );

    //=========================================================
    // Free List
    //=========================================================
    free_list #(
        .NUM_PHYS_REGS(64),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_free_list (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_req_i        (fl_alloc_req),
        .alloc_preg_o       (fl_alloc_preg),
        .alloc_valid_o      (fl_alloc_valid),
        .release_req_i      (fl_release_valid),
        .release_preg_i     (fl_release_preg),
        .recover_i          (1'b0),
        .recover_head_i     (6'd0),
        .recover_tail_i     (6'd0),
        .recover_count_i    (6'd0),
        .checkpoint_head_o  (),
        .checkpoint_tail_o  (),
        .checkpoint_count_o (),
        .empty_o            (fl_empty),
        .full_o             (),
        .free_count_o       ()
    );
    
    //=========================================================
    // RAT
    //=========================================================
    rat #(
        .NUM_ARCH_REGS(32),
        .NUM_PHYS_REGS(64),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_rat (
        .clk                (clk),
        .rst_n              (rst_n),
        .rs1_arch_i         (rat_rs1_arch),
        .rs2_arch_i         (rat_rs2_arch),
        .rs1_phys_o         (rat_rs1_phys),
        .rs2_phys_o         (rat_rs2_phys),
        .rs1_ready_o        (rat_rs1_ready),
        .rs2_ready_o        (rat_rs2_ready),
        .rename_valid_i     (rat_rename_valid),
        .rd_arch_i          (rat_rd_arch),
        .rd_phys_new_i      (rat_rd_phys_new),
        .rd_phys_old_o      (rat_rd_phys_old),
        .cdb_valid_i        (cdb_valid),
        .cdb_preg_i         (cdb_preg),
        .checkpoint_create_i(1'b0),
        .checkpoint_id_i    (3'd0),
        .recover_i          (1'b0),
        .recover_id_i       (3'd0),
        .commit_valid_i     (rat_commit_valid),
        .commit_rd_arch_i   (rat_commit_rd_arch),
        .commit_rd_phys_i   (rat_commit_rd_phys)
    );
    
    //=========================================================
    // PRF
    //=========================================================
    prf #(
        .NUM_PHYS_REGS(64),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN)
    ) u_prf (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_addr0_i (prf_rs1_addr),
        .rd_data0_o (prf_rs1_data),
        .rd_addr1_i (prf_rs2_addr),
        .rd_data1_o (prf_rs2_data),
        .rd_addr2_i (6'd0),
        .rd_data2_o (),
        .rd_addr3_i (6'd0),
        .rd_data3_o (),
        .wr_en0_i   (prf_write_en),
        .wr_addr0_i (prf_write_addr),
        .wr_data0_i (prf_write_data),
        .wr_en1_i   (1'b0),
        .wr_addr1_i (6'd0),
        .wr_data1_i (32'd0)
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
        .src2_exception_i   (mul_cdb_exception),
        .src2_exc_code_i    (mul_cdb_exc_code),
        .src3_valid_i       (div_cdb_valid),
        .src3_ready_o       (div_cdb_ready),
        .src3_preg_i        (div_cdb_preg),
        .src3_data_i        (div_cdb_data),
        .src3_rob_idx_i     (div_cdb_rob_idx),
        .src3_exception_i   (div_cdb_exception),
        .src3_exc_code_i    (div_cdb_exc_code),
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
        .src5_exception_i   (br_cdb_exception),
        .src5_exc_code_i    (br_cdb_exc_code),
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
        .GHR_WIDTH(GHR_WIDTH)
    ) u_bpu (
        .clk                (clk),
        .rst_n              (rst_n),
        .pred_req_i         (if_bpu_req),
        .pred_pc_i          (if_bpu_pc),
        .pred_valid_o       (),
        .pred_taken_o       (if_bpu_pred_taken),
        .pred_target_o      (if_bpu_pred_target),
        .pred_type_o        (if_bpu_pred_type),
        .checkpoint_i       (1'b0),
        .checkpoint_id_i    (3'd0),
        .recover_i          (1'b0),
        .recover_id_i       (3'd0),
        .recover_ghr_i      (64'd0),
        .update_valid_i     (bpu_update_valid),
        .update_pc_i        (bpu_update_pc),
        .update_taken_i     (bpu_update_taken),
        .update_target_i    (bpu_update_target),
        .update_type_i      (2'b00),
        .update_mispredict_i(br_mispredict),
        .ghr_o              (ghr)
    );
    
    //=========================================================
    // I-Cache
    //=========================================================
    icache #(
        .CACHE_SIZE(4096),
        .LINE_SIZE(32),
        .ADDR_WIDTH(XLEN),
        .DATA_WIDTH(XLEN)
    ) u_icache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (if_icache_req_valid),
        .req_addr_i         (if_icache_req_addr),
        .req_ready_o        (if_icache_req_ready),
        .resp_valid_o       (if_icache_resp_valid),
        .resp_data_o        (if_icache_resp_data),
        .mem_req_valid_o    (icache_mem_req_valid),
        .mem_req_addr_o     (icache_mem_req_addr),
        .mem_req_ready_i    (icache_mem_req_ready),
        .mem_resp_valid_i   (icache_mem_resp_valid),
        .mem_resp_data_i    (icache_mem_resp_data),
        .invalidate_i       (1'b0)
    );
    
    //=========================================================
    // D-Cache
    //=========================================================
    dcache #(
        .CACHE_SIZE(4096),
        .LINE_SIZE(32),
        .NUM_WAYS(2),
        .ADDR_WIDTH(XLEN),
        .DATA_WIDTH(XLEN)
    ) u_dcache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (dcache_req_valid),
        .req_write_i        (dcache_req_write),
        .req_addr_i         (dcache_req_addr),
        .req_wdata_i        (dcache_req_wdata),
        .req_size_i         (2'b10),
        .req_ready_o        (dcache_req_ready),
        .resp_valid_o       (dcache_resp_valid),
        .resp_data_o        (dcache_resp_rdata),
        .mem_req_valid_o    (dcache_mem_req_valid),
        .mem_req_write_o    (dcache_mem_req_write),
        .mem_req_addr_o     (dcache_mem_req_addr),
        .mem_req_wdata_o    (dcache_mem_req_wdata),
        .mem_req_ready_i    (dcache_mem_req_ready),
        .mem_resp_valid_i   (dcache_mem_resp_valid),
        .mem_resp_data_i    (dcache_mem_resp_data),
        .flush_i            (1'b0)
    );
    
    //=========================================================
    // Exception Unit
    //=========================================================
    exception_unit #(
        .XLEN(XLEN)
    ) u_exception_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .illegal_instr_i    (1'b0),
        .instr_misalign_i   (1'b0),
        .load_misalign_i    (1'b0),
        .store_misalign_i   (1'b0),
        .ecall_i            (1'b0),
        .ebreak_i           (1'b0),
        .mret_i             (1'b0),
        .exc_pc_i           (exception_pc),
        .exc_tval_i         (exception_tval),
        .branch_mispredict_i(1'b0),
        .branch_target_i    (32'd0),
        .mtvec_i            (32'h8000_0000),
        .mepc_i             (32'd0),
        .mie_i              (1'b0),
        .irq_pending_i      (1'b0),
        .exception_o        (),
        .exc_code_o         (),
        .exc_pc_o           (),
        .exc_tval_o         (),
        .mret_o             (),
        .flush_o            (),
        .redirect_pc_o      (exception_redirect_pc),
        .redirect_valid_o   ()
    );

    //=========================================================
    // Stall Logic
    //=========================================================
    assign stall_if = stall_id;
    assign stall_id = stall_rn;
    // Use fl_empty instead of fl_alloc_valid to avoid deadlock
    assign stall_rn = is_stall_out || !rob_alloc_ready || fl_empty;
    assign stall_is = 1'b0;  // IS stage handles its own stalls via RS ready signals
    
    //=========================================================
    // I-Cache Memory Interface Signals
    //=========================================================
    wire        icache_mem_req_valid;
    wire [31:0] icache_mem_req_addr;
    wire        icache_mem_req_ready;
    wire        icache_mem_resp_valid;
    wire [255:0] icache_mem_resp_data;
    
    //=========================================================
    // AXI I-Bus Burst Accumulator
    // Accumulates 8 x 32-bit AXI transfers into 256-bit cache line
    //=========================================================
    reg [2:0] ibus_beat_count;
    reg [255:0] ibus_line_data;
    reg ibus_burst_active;
    reg [31:0] ibus_req_addr;
    
    // State machine for burst accumulation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibus_beat_count <= 3'd0;
            ibus_line_data <= 256'd0;
            ibus_burst_active <= 1'b0;
            ibus_req_addr <= 32'd0;
        end else begin
            if (icache_mem_req_valid && !ibus_burst_active && m_axi_ibus_arready) begin
                // Start new burst
                ibus_burst_active <= 1'b1;
                ibus_beat_count <= 3'd0;
                ibus_req_addr <= icache_mem_req_addr;
            end else if (ibus_burst_active && m_axi_ibus_rvalid) begin
                // Accumulate data
                case (ibus_beat_count)
                    3'd0: ibus_line_data[31:0]    <= m_axi_ibus_rdata;
                    3'd1: ibus_line_data[63:32]   <= m_axi_ibus_rdata;
                    3'd2: ibus_line_data[95:64]   <= m_axi_ibus_rdata;
                    3'd3: ibus_line_data[127:96]  <= m_axi_ibus_rdata;
                    3'd4: ibus_line_data[159:128] <= m_axi_ibus_rdata;
                    3'd5: ibus_line_data[191:160] <= m_axi_ibus_rdata;
                    3'd6: ibus_line_data[223:192] <= m_axi_ibus_rdata;
                    3'd7: ibus_line_data[255:224] <= m_axi_ibus_rdata;
                endcase
                ibus_beat_count <= ibus_beat_count + 1;
                if (ibus_beat_count == 3'd7) begin
                    ibus_burst_active <= 1'b0;
                end
            end
        end
    end
    
    //=========================================================
    // AXI Interface Connections
    //=========================================================
    // I-Bus AXI - Connect to I-Cache memory interface with burst support
    assign m_axi_ibus_arvalid = icache_mem_req_valid && !ibus_burst_active;
    assign m_axi_ibus_araddr = icache_mem_req_addr;
    assign m_axi_ibus_arprot = 3'b100;
    assign m_axi_ibus_rready = ibus_burst_active;
    assign icache_mem_req_ready = m_axi_ibus_arready && !ibus_burst_active;
    // Response valid when all 8 beats received
    assign icache_mem_resp_valid = ibus_burst_active && (ibus_beat_count == 3'd7) && m_axi_ibus_rvalid;
    // Provide accumulated cache line data (with current beat in correct position)
    assign icache_mem_resp_data = {m_axi_ibus_rdata, ibus_line_data[223:0]};
    
    // D-Bus AXI - Connect to D-Cache memory interface
    wire        dcache_mem_req_valid;
    wire        dcache_mem_req_write;
    wire [31:0] dcache_mem_req_addr;
    wire [255:0] dcache_mem_req_wdata;
    wire        dcache_mem_req_ready;
    wire        dcache_mem_resp_valid;
    wire [255:0] dcache_mem_resp_data;
    
    // D-Bus Read Channel
    assign m_axi_dbus_arvalid = dcache_mem_req_valid && !dcache_mem_req_write;
    assign m_axi_dbus_araddr = dcache_mem_req_addr;
    assign m_axi_dbus_arprot = 3'b000;
    assign m_axi_dbus_rready = 1'b1;
    
    // D-Bus Write Channel
    assign m_axi_dbus_awvalid = dcache_mem_req_valid && dcache_mem_req_write;
    assign m_axi_dbus_awaddr = dcache_mem_req_addr;
    assign m_axi_dbus_awprot = 3'b000;
    assign m_axi_dbus_wvalid = dcache_mem_req_valid && dcache_mem_req_write;
    assign m_axi_dbus_wdata = dcache_mem_req_wdata[31:0];
    assign m_axi_dbus_wstrb = 4'b1111;
    assign m_axi_dbus_bready = 1'b1;
    
    // D-Cache memory interface signals
    assign dcache_mem_req_ready = dcache_mem_req_write ? 
                                  (m_axi_dbus_awready && m_axi_dbus_wready) : 
                                  m_axi_dbus_arready;
    assign dcache_mem_resp_valid = dcache_mem_req_write ? m_axi_dbus_bvalid : m_axi_dbus_rvalid;
    assign dcache_mem_resp_data = {8{m_axi_dbus_rdata}};
    
    //=========================================================
    // D-Cache Request (connected to LSQ)
    //=========================================================
    // Mux between LSQ read and write requests
    // Priority: write (store commit) > read (load)
    assign dcache_req_valid = lsq_dcache_rd_valid || lsq_dcache_wr_valid;
    assign dcache_req_write = lsq_dcache_wr_valid;
    assign dcache_req_addr = lsq_dcache_wr_valid ? lsq_dcache_wr_addr : lsq_dcache_rd_addr;
    assign dcache_req_wdata = lsq_dcache_wr_data;
    
    // Generate write mask based on store size
    reg [3:0] dcache_wmask_reg;
    always @(*) begin
        case (lsq_dcache_wr_size)
            2'b00: dcache_wmask_reg = 4'b0001 << lsq_dcache_wr_addr[1:0];  // Byte
            2'b01: dcache_wmask_reg = 4'b0011 << {lsq_dcache_wr_addr[1], 1'b0};  // Half
            default: dcache_wmask_reg = 4'b1111;  // Word
        endcase
    end
    assign dcache_req_wmask = dcache_wmask_reg;
    
    // D-Cache ready signals back to LSQ
    assign lsq_dcache_rd_ready = dcache_req_ready && !lsq_dcache_wr_valid;
    assign lsq_dcache_wr_ready = dcache_req_ready;
    
    // D-Cache response signals
    assign lsq_dcache_rd_resp_valid = dcache_resp_valid && !dcache_req_write;
    assign lsq_dcache_rd_resp_data = dcache_resp_rdata;
    assign lsq_dcache_wr_resp_valid = dcache_resp_valid && dcache_req_write;
    
    //=========================================================
    // Store Commit Logic
    //=========================================================
    // Track store index for commit
    // This is simplified - a full implementation would track per-store
    reg [2:0] store_commit_sq_idx;
    reg store_commit_pending;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            store_commit_sq_idx <= 3'd0;
            store_commit_pending <= 1'b0;
        end else if (flush_is) begin
            store_commit_pending <= 1'b0;
        end else if (store_commit_valid && !store_commit_pending) begin
            store_commit_pending <= 1'b1;
        end else if (store_commit_pending && lsq_dcache_wr_resp_valid) begin
            store_commit_pending <= 1'b0;
            store_commit_sq_idx <= store_commit_sq_idx + 1;
        end
    end
    
    assign lsq_st_commit_valid = store_commit_valid;
    assign lsq_st_commit_idx = store_commit_sq_idx;
    
    // Load commit (loads are committed when they complete)
    // For simplicity, we track load index similarly
    reg [2:0] load_commit_lq_idx;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_commit_lq_idx <= 3'd0;
        end else if (flush_is) begin
            load_commit_lq_idx <= 3'd0;
        end else if (lsq_ld_commit_valid) begin
            load_commit_lq_idx <= load_commit_lq_idx + 1;
        end
    end
    
    // Loads are committed when ROB commits a load instruction
    // For now, commit loads when they complete (simplified)
    assign lsq_ld_commit_valid = lsu_cdb_valid && lsu_cdb_ready;
    assign lsq_ld_commit_idx = load_commit_lq_idx;

endmodule
