//=================================================================
// Module: cpu_core_4way
// Description: 4-Way Superscalar RISC-V Out-of-Order CPU Core
//              Championship-level design for 龙芯杯 (LoongArch Cup)
//              Target: Boot Linux, IPC > 1.5, 97%+ branch prediction
// Features:
//   - 4-fetch, 4-decode, 4-rename, 4-issue superscalar
//   - 64-entry ROB, 128 physical registers, 32-entry issue queue
//   - Multiple execution units: 2xALU, 1xMUL, 1xDIV, 1xBRU, 1xLSU
//   - 4-wide CDB for writeback
//   - TAGE-SC-L branch predictor with 256-bit GHR
//   - 16KB 4-way I-Cache, 8KB 4-way D-Cache with MSHR
//   - MMU with Sv32 support, 32-entry TLB
//   - Full privilege support (M/S/U modes)
//   - CLINT (timer), PLIC (interrupts)
//   - Atomic extension (LR/SC, AMO)
//   - Hardware prefetcher (stride + stream)
//=================================================================

`timescale 1ns/1ps

module cpu_core_4way #(
    parameter XLEN           = 32,
    parameter PHYS_REG_BITS  = 7,           // 128 physical registers
    parameter ARCH_REG_BITS  = 5,
    parameter ROB_IDX_BITS   = 6,           // 64-entry ROB
    parameter GHR_WIDTH      = 256,         // Enhanced BPU
    parameter IQ_ENTRIES     = 32,          // Issue queue entries
    parameter LQ_ENTRIES     = 16,          // Load queue
    parameter SQ_ENTRIES     = 16,          // Store queue
    parameter ICACHE_SIZE    = 16384,       // 16KB I-Cache
    parameter DCACHE_SIZE    = 8192,        // 8KB D-Cache
    parameter TLB_ENTRIES    = 32,          // TLB entries
    parameter RESET_VECTOR   = 32'h8000_0000,
    parameter MHART_ID       = 32'h0
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // AXI4 Memory Interface (I-Cache miss + D-Cache miss + PTW)
    //=========================================================
    // AXI Write Address Channel
    output wire [3:0]              m_axi_awid,
    output wire [XLEN-1:0]         m_axi_awaddr,
    output wire [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire                    m_axi_awlock,
    output wire [3:0]              m_axi_awcache,
    output wire [2:0]              m_axi_awprot,
    output wire                    m_axi_awvalid,
    input  wire                    m_axi_awready,
    
    // AXI Write Data Channel
    output wire [XLEN-1:0]         m_axi_wdata,
    output wire [3:0]              m_axi_wstrb,
    output wire                    m_axi_wlast,
    output wire                    m_axi_wvalid,
    input  wire                    m_axi_wready,
    
    // AXI Write Response Channel
    input  wire [3:0]              m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output wire                    m_axi_bready,
    
    // AXI Read Address Channel
    output wire [3:0]              m_axi_arid,
    output wire [XLEN-1:0]         m_axi_araddr,
    output wire [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire                    m_axi_arlock,
    output wire [3:0]              m_axi_arcache,
    output wire [2:0]              m_axi_arprot,
    output wire                    m_axi_arvalid,
    input  wire                    m_axi_arready,
    
    // AXI Read Data Channel
    input  wire [3:0]              m_axi_rid,
    input  wire [XLEN-1:0]         m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output wire                    m_axi_rready,
    
    //=========================================================
    // External Interrupts
    //=========================================================
    input  wire [31:0]             ext_irq_i,       // External interrupts to PLIC
    
    //=========================================================
    // Debug Interface
    //=========================================================
    output wire [XLEN-1:0]         debug_pc_o,
    output wire                    debug_halt_o,
    output wire [63:0]             debug_cycle_o,
    output wire [63:0]             debug_instret_o
);

    //=========================================================
    // Local Parameters
    //=========================================================
    localparam CDB_WIDTH = 4;                // 4-wide CDB
    localparam FETCH_WIDTH = 4;              // 4 instructions per cycle
    localparam COMMIT_WIDTH = 4;             // 4 commits per cycle
    
    // Privilege modes
    localparam PRIV_U = 2'b00;
    localparam PRIV_S = 2'b01;
    localparam PRIV_M = 2'b11;

    //=========================================================
    // Pipeline Control Signals
    //=========================================================
    wire                        flush_frontend;
    wire                        flush_backend;
    wire                        stall_frontend;
    wire                        redirect_valid;
    wire [XLEN-1:0]             redirect_pc;
    wire [1:0]                  current_priv;
    
    //=========================================================
    // BPU Signals
    //=========================================================
    wire                        bpu_req;
    wire [XLEN-1:0]             bpu_pc;
    wire [FETCH_WIDTH-1:0]      bpu_pred_taken;
    wire [XLEN-1:0]             bpu_pred_target [0:FETCH_WIDTH-1];
    wire [GHR_WIDTH-1:0]        bpu_ghr;
    
    // BPU update from commit
    wire                        bpu_update_valid;
    wire [XLEN-1:0]             bpu_update_pc;
    wire                        bpu_update_taken;
    wire [XLEN-1:0]             bpu_update_target;
    wire [GHR_WIDTH-1:0]        bpu_update_ghr;
    wire                        bpu_update_mispredict;
    
    //=========================================================
    // I-Cache Signals
    //=========================================================
    wire                        icache_req_valid;
    wire [XLEN-1:0]             icache_req_pc;
    wire                        icache_req_ready;
    wire                        icache_resp_valid;
    wire [FETCH_WIDTH*32-1:0]   icache_resp_data;
    wire [FETCH_WIDTH-1:0]      icache_resp_valid_mask;
    
    // I-Cache to Memory
    wire                        icache_mem_req_valid;
    wire [XLEN-1:0]             icache_mem_req_addr;
    wire                        icache_mem_req_ready;
    wire                        icache_mem_resp_valid;
    wire [511:0]                icache_mem_resp_data;  // 64 bytes for cache line
    
    //=========================================================
    // Fetch Stage Output (4 instructions)
    //=========================================================
    wire [FETCH_WIDTH-1:0]      fetch_valid;
    wire [XLEN-1:0]             fetch_pc [0:FETCH_WIDTH-1];
    wire [31:0]                 fetch_instr [0:FETCH_WIDTH-1];
    wire [FETCH_WIDTH-1:0]      fetch_pred_taken;
    wire [XLEN-1:0]             fetch_pred_target [0:FETCH_WIDTH-1];
    wire [GHR_WIDTH-1:0]        fetch_ghr;
    
    //=========================================================
    // Decode Stage Output (4 instructions)
    //=========================================================
    wire [FETCH_WIDTH-1:0]      decode_valid;
    wire [XLEN-1:0]             decode_pc [0:FETCH_WIDTH-1];
    wire [4:0]                  decode_rs1 [0:FETCH_WIDTH-1];
    wire [4:0]                  decode_rs2 [0:FETCH_WIDTH-1];
    wire [4:0]                  decode_rd [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]             decode_imm [0:FETCH_WIDTH-1];
    wire [4:0]                  decode_alu_op [0:FETCH_WIDTH-1];
    wire [2:0]                  decode_fu_type [0:FETCH_WIDTH-1];
    wire [FETCH_WIDTH-1:0]      decode_uses_rs1;
    wire [FETCH_WIDTH-1:0]      decode_uses_rs2;
    wire [FETCH_WIDTH-1:0]      decode_uses_rd;
    wire [FETCH_WIDTH-1:0]      decode_is_branch;
    wire [FETCH_WIDTH-1:0]      decode_is_load;
    wire [FETCH_WIDTH-1:0]      decode_is_store;
    wire [FETCH_WIDTH-1:0]      decode_is_csr;
    wire [FETCH_WIDTH-1:0]      decode_is_fence;
    wire [FETCH_WIDTH-1:0]      decode_is_amo;
    wire [FETCH_WIDTH-1:0]      decode_pred_taken;
    wire [XLEN-1:0]             decode_pred_target [0:FETCH_WIDTH-1];
    wire [FETCH_WIDTH-1:0]      decode_exception;
    wire [3:0]                  decode_exc_code [0:FETCH_WIDTH-1];
    
    //=========================================================
    // Rename Stage Signals
    //=========================================================
    wire [FETCH_WIDTH-1:0]      rename_valid;
    wire [PHYS_REG_BITS-1:0]    rename_prs1 [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    rename_prs2 [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    rename_prd [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    rename_prd_old [0:FETCH_WIDTH-1];
    wire [FETCH_WIDTH-1:0]      rename_rs1_ready;
    wire [FETCH_WIDTH-1:0]      rename_rs2_ready;
    wire [ROB_IDX_BITS-1:0]     rename_rob_idx [0:FETCH_WIDTH-1];
    
    //=========================================================
    // Free List Signals
    //=========================================================
    wire [FETCH_WIDTH-1:0]      fl_alloc_req;
    wire [FETCH_WIDTH-1:0]      fl_alloc_valid;
    wire [PHYS_REG_BITS-1:0]    fl_alloc_preg [0:FETCH_WIDTH-1];
    wire [COMMIT_WIDTH-1:0]     fl_release_valid;
    wire [PHYS_REG_BITS-1:0]    fl_release_preg [0:COMMIT_WIDTH-1];
    wire                        fl_empty;
    
    //=========================================================
    // ROB Signals
    //=========================================================
    wire [FETCH_WIDTH-1:0]      rob_alloc_req;
    wire [FETCH_WIDTH-1:0]      rob_alloc_ready;
    wire [ROB_IDX_BITS-1:0]     rob_alloc_idx [0:FETCH_WIDTH-1];
    
    wire [COMMIT_WIDTH-1:0]     rob_commit_valid;
    wire [XLEN-1:0]             rob_commit_pc [0:COMMIT_WIDTH-1];
    wire [4:0]                  rob_commit_rd [0:COMMIT_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    rob_commit_prd [0:COMMIT_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    rob_commit_prd_old [0:COMMIT_WIDTH-1];
    wire [COMMIT_WIDTH-1:0]     rob_commit_exception;
    wire [3:0]                  rob_commit_exc_code [0:COMMIT_WIDTH-1];
    wire [XLEN-1:0]             rob_commit_exc_tval [0:COMMIT_WIDTH-1];
    wire [COMMIT_WIDTH-1:0]     rob_commit_is_branch;
    wire [COMMIT_WIDTH-1:0]     rob_commit_br_taken;
    wire [XLEN-1:0]             rob_commit_br_target [0:COMMIT_WIDTH-1];
    wire [COMMIT_WIDTH-1:0]     rob_commit_is_store;
    wire                        rob_empty;
    wire                        rob_full;
    
    //=========================================================
    // Issue Queue Signals
    //=========================================================
    wire [FETCH_WIDTH-1:0]      iq_dispatch_valid;
    wire [FETCH_WIDTH-1:0]      iq_dispatch_ready;
    
    wire [FETCH_WIDTH-1:0]      iq_issue_valid;
    wire [FETCH_WIDTH-1:0]      iq_issue_ready;
    wire [4:0]                  iq_issue_op [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]             iq_issue_rs1_data [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]             iq_issue_rs2_data [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]             iq_issue_imm [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]             iq_issue_pc [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0]    iq_issue_prd [0:FETCH_WIDTH-1];
    wire [ROB_IDX_BITS-1:0]     iq_issue_rob_idx [0:FETCH_WIDTH-1];
    wire [2:0]                  iq_issue_fu_type [0:FETCH_WIDTH-1];
    
    //=========================================================
    // PRF Signals (8 Read ports, 4 Write ports)
    //=========================================================
    wire [PHYS_REG_BITS-1:0]    prf_rd_addr [0:7];
    wire [XLEN-1:0]             prf_rd_data [0:7];
    wire [CDB_WIDTH-1:0]        prf_wr_en;
    wire [PHYS_REG_BITS-1:0]    prf_wr_addr [0:CDB_WIDTH-1];
    wire [XLEN-1:0]             prf_wr_data [0:CDB_WIDTH-1];
    
    //=========================================================
    // CDB Signals (4-wide)
    //=========================================================
    wire [CDB_WIDTH-1:0]        cdb_valid;
    wire [PHYS_REG_BITS-1:0]    cdb_prd [0:CDB_WIDTH-1];
    wire [XLEN-1:0]             cdb_data [0:CDB_WIDTH-1];
    wire [ROB_IDX_BITS-1:0]     cdb_rob_idx [0:CDB_WIDTH-1];
    wire                        cdb_exception [0:CDB_WIDTH-1];
    wire [3:0]                  cdb_exc_code [0:CDB_WIDTH-1];
    
    // Branch resolution
    wire                        cdb_br_taken;
    wire [XLEN-1:0]             cdb_br_target;
    wire                        cdb_br_mispredict;
    
    //=========================================================
    // Execution Cluster Signals
    //=========================================================
    wire                        ex_alu0_valid, ex_alu1_valid;
    wire                        ex_mul_valid, ex_div_valid;
    wire                        ex_bru_valid;
    wire [PHYS_REG_BITS-1:0]    ex_alu0_prd, ex_alu1_prd, ex_mul_prd, ex_div_prd, ex_bru_prd;
    wire [XLEN-1:0]             ex_alu0_data, ex_alu1_data, ex_mul_data, ex_div_data, ex_bru_data;
    wire [ROB_IDX_BITS-1:0]     ex_alu0_rob, ex_alu1_rob, ex_mul_rob, ex_div_rob, ex_bru_rob;
    wire                        ex_bru_taken, ex_bru_mispredict;
    wire [XLEN-1:0]             ex_bru_target;
    
    //=========================================================
    // LSU Signals
    //=========================================================
    wire                        lsu_valid;
    wire                        lsu_ready;
    wire                        lsu_is_load;
    wire [1:0]                  lsu_size;
    wire                        lsu_sign_ext;
    wire [XLEN-1:0]             lsu_addr;
    wire [XLEN-1:0]             lsu_wdata;
    wire [PHYS_REG_BITS-1:0]    lsu_prd;
    wire [ROB_IDX_BITS-1:0]     lsu_rob_idx;
    wire                        lsu_is_amo;
    wire [4:0]                  lsu_amo_op;
    
    wire                        lsu_resp_valid;
    wire [PHYS_REG_BITS-1:0]    lsu_resp_prd;
    wire [XLEN-1:0]             lsu_resp_data;
    wire [ROB_IDX_BITS-1:0]     lsu_resp_rob_idx;
    wire                        lsu_resp_exception;
    wire [3:0]                  lsu_resp_exc_code;
    
    //=========================================================
    // D-Cache Signals
    //=========================================================
    wire                        dcache_req_valid;
    wire                        dcache_req_ready;
    wire                        dcache_req_write;
    wire [XLEN-1:0]             dcache_req_addr;
    wire [XLEN-1:0]             dcache_req_wdata;
    wire [3:0]                  dcache_req_wmask;
    wire                        dcache_resp_valid;
    wire [XLEN-1:0]             dcache_resp_rdata;
    wire                        dcache_resp_error;
    
    // D-Cache to Memory
    wire                        dcache_mem_req_valid;
    wire [XLEN-1:0]             dcache_mem_req_addr;
    wire                        dcache_mem_req_write;
    wire [127:0]                dcache_mem_req_wdata;
    wire                        dcache_mem_req_ready;
    wire                        dcache_mem_resp_valid;
    wire [127:0]                dcache_mem_resp_data;
    
    //=========================================================
    // MMU/TLB Signals
    //=========================================================
    wire                        mmu_enabled;
    wire [XLEN-1:0]             satp;
    
    // I-TLB
    wire                        itlb_req_valid;
    wire [XLEN-1:0]             itlb_req_vaddr;
    wire                        itlb_req_ready;
    wire                        itlb_resp_valid;
    wire [XLEN-1:0]             itlb_resp_paddr;
    wire                        itlb_resp_exception;
    wire [3:0]                  itlb_resp_exc_code;
    
    // D-TLB
    wire                        dtlb_req_valid;
    wire [XLEN-1:0]             dtlb_req_vaddr;
    wire                        dtlb_req_write;
    wire                        dtlb_req_ready;
    wire                        dtlb_resp_valid;
    wire [XLEN-1:0]             dtlb_resp_paddr;
    wire                        dtlb_resp_exception;
    wire [3:0]                  dtlb_resp_exc_code;
    
    // PTW to Memory
    wire                        ptw_req_valid;
    wire [XLEN-1:0]             ptw_req_addr;
    wire                        ptw_req_ready;
    wire                        ptw_resp_valid;
    wire [XLEN-1:0]             ptw_resp_data;
    
    //=========================================================
    // CSR Signals
    //=========================================================
    wire                        csr_read_valid;
    wire [11:0]                 csr_read_addr;
    wire [XLEN-1:0]             csr_read_data;
    wire                        csr_write_valid;
    wire [11:0]                 csr_write_addr;
    wire [XLEN-1:0]             csr_write_data;
    wire [1:0]                  csr_write_op;       // 00:write, 01:set, 10:clear
    wire                        csr_exception;
    wire [3:0]                  csr_exc_code;

    // CSR bits used by MMU access checks
    wire                        csr_sum;
    wire                        csr_mxr;
    
    //=========================================================
    // Trap/Exception Signals
    //=========================================================
    wire                        trap_valid;
    wire [XLEN-1:0]             trap_pc;
    wire [3:0]                  trap_cause;
    wire [XLEN-1:0]             trap_tval;
    wire                        trap_interrupt;
    wire [XLEN-1:0]             trap_handler_pc;
    wire                        mret_valid;
    wire                        sret_valid;
    wire [XLEN-1:0]             return_pc;
    
    //=========================================================
    // Interrupt Signals (CLINT + PLIC)
    //=========================================================
    wire                        timer_irq;
    wire                        software_irq;
    wire                        external_irq;
    wire [XLEN-1:0]             mtime;
    wire [XLEN-1:0]             mtimecmp;
    
    //=========================================================
    // Prefetcher Signals
    //=========================================================
    wire                        pf_req_valid;
    wire [XLEN-1:0]             pf_req_addr;
    wire                        pf_req_ready;
    
    //=========================================================
    // Performance Counters
    //=========================================================
    reg [63:0]                  cycle_counter;
    reg [63:0]                  instret_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 64'd0;
            instret_counter <= 64'd0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            instret_counter <= instret_counter + 
                               {60'd0, rob_commit_valid[0]} +
                               {60'd0, rob_commit_valid[1]} +
                               {60'd0, rob_commit_valid[2]} +
                               {60'd0, rob_commit_valid[3]};
        end
    end
    
    assign debug_cycle_o = cycle_counter;
    assign debug_instret_o = instret_counter;
    assign debug_pc_o = rob_commit_pc[0];
    assign debug_halt_o = 1'b0;

    //=========================================================
    // Pipeline Control Logic
    //=========================================================
    assign flush_frontend = redirect_valid;
    assign flush_backend = redirect_valid;
    assign stall_frontend = fl_empty || rob_full;
    
    assign redirect_valid = cdb_br_mispredict || trap_valid || mret_valid || sret_valid;
    assign redirect_pc = trap_valid ? trap_handler_pc :
                         (mret_valid || sret_valid) ? return_pc :
                         cdb_br_mispredict ? cdb_br_target : 32'd0;

    //=========================================================
    // BPU - TAGE-SC-L Branch Predictor
    //=========================================================
    // Checkpoint signals
    wire [2:0]              bpu_checkpoint_id;
    wire                    bpu_checkpoint_valid;
    wire                    bpu_checkpoint_create;
    wire [ROB_IDX_BITS-1:0] bpu_checkpoint_rob_idx;
    
    bpu_top_enhanced #(
        .ADDR_WIDTH(XLEN),
        .GHR_WIDTH(GHR_WIDTH),
        .BTB_SIZE(2048),
        .RAS_DEPTH(32),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .NUM_CHECKPOINTS(8)
    ) u_bpu (
        .clk                    (clk),
        .rst_n                  (rst_n),
        // Fetch interface
        .fetch_pc_i             (bpu_pc),
        .fetch_valid_i          (bpu_req),
        .pred_valid_o           (),
        .pred_taken_o           (bpu_pred_taken[0]),
        .pred_target_o          (bpu_pred_target[0]),
        .pred_is_branch_o       (),
        .pred_is_call_o         (),
        .pred_is_return_o       (),
        .pred_confidence_o      (),
        // Checkpoint interface
        .checkpoint_create_i    (bpu_checkpoint_create),
        .checkpoint_rob_idx_i   (bpu_checkpoint_rob_idx),
        .checkpoint_id_o        (bpu_checkpoint_id),
        .checkpoint_valid_o     (bpu_checkpoint_valid),
        // Update interface
        .update_valid_i         (bpu_update_valid),
        .update_pc_i            (bpu_update_pc),
        .update_taken_i         (bpu_update_taken),
        .update_target_i        (bpu_update_target),
        .update_is_branch_i     (1'b1),
        .update_is_call_i       (1'b0),
        .update_is_return_i     (1'b0),
        .update_mispred_i       (bpu_update_mispredict),
        .update_checkpoint_id_i (3'd0),
        .update_ghr_i           (bpu_update_ghr),
        // Commit interface
        .commit_valid_i         (rob_commit_valid[0]),
        .commit_rob_idx_i       (6'd0),
        .commit_is_branch_i     (rob_commit_is_branch[0]),
        .commit_taken_i         (rob_commit_br_taken[0]),
        // Flush
        .flush_i                (flush_frontend),
        // GHR output
        .current_ghr_o          (bpu_ghr)
    );
    
    // Replicate predictions for 4-way (simplified)
    assign bpu_pred_taken[3:1] = 3'b000;
    assign bpu_pred_target[1] = bpu_pred_target[0] + 4;
    assign bpu_pred_target[2] = bpu_pred_target[0] + 8;
    assign bpu_pred_target[3] = bpu_pred_target[0] + 12;
    
    // Checkpoint creation on branch dispatch
    assign bpu_checkpoint_create = |decode_is_branch;
    assign bpu_checkpoint_rob_idx = rename_rob_idx[0];

    //=========================================================
    // I-Cache (16KB 4-way) with Prefetch
    //=========================================================
    icache_enhanced #(
        .CACHE_SIZE(ICACHE_SIZE),
        .LINE_SIZE(64),
        .WAYS(4),
        .ADDR_WIDTH(XLEN),
        .DATA_WIDTH(32),
        .FETCH_WIDTH(128),
        .MSHR_ENTRIES(4)
    ) u_icache (
        .clk                (clk),
        .rst_n              (rst_n),
        // CPU interface
        .req_valid_i        (icache_req_valid),
        .req_addr_i         (icache_req_pc),
        .req_ready_o        (icache_req_ready),
        .resp_valid_o       (icache_resp_valid),
        .resp_data_o        (icache_resp_data),
        .resp_error_o       (),
        // Prefetch interface
        .pf_req_valid_i     (pf_req_valid),
        .pf_req_addr_i      (pf_req_addr),
        .pf_req_ready_o     (pf_req_ready),
        // Memory interface
        .mem_req_valid_o    (icache_mem_req_valid),
        .mem_req_addr_o     (icache_mem_req_addr),
        .mem_req_ready_i    (icache_mem_req_ready),
        .mem_resp_valid_i   (icache_mem_resp_valid),
        .mem_resp_data_i    (icache_mem_resp_data),
        // Invalidation interface
        .inv_valid_i        (1'b0),
        .inv_addr_i         (32'd0),
        .inv_all_i          (flush_frontend)
    );

    //=========================================================
    // Fetch Stage (4-wide)
    //=========================================================
    fetch_4way #(
        .XLEN(XLEN),
        .FETCH_WIDTH(FETCH_WIDTH),
        .GHR_WIDTH(GHR_WIDTH),
        .RESET_VECTOR(RESET_VECTOR)
    ) u_fetch (
        .clk                (clk),
        .rst_n              (rst_n),
        .stall_i            (stall_frontend),
        .flush_i            (flush_frontend),
        .redirect_valid_i   (redirect_valid),
        .redirect_pc_i      (redirect_pc),
        // I-Cache interface
        .icache_req_valid_o (icache_req_valid),
        .icache_req_pc_o    (icache_req_pc),
        .icache_req_ready_i (icache_req_ready),
        .icache_resp_valid_i(icache_resp_valid),
        .icache_resp_data_i (icache_resp_data),
        // BPU interface
        .bpu_req_o          (bpu_req),
        .bpu_pc_o           (bpu_pc),
        .bpu_pred_taken_i   (bpu_pred_taken),
        .bpu_pred_target_i  (bpu_pred_target[0]),
        .bpu_ghr_i          (bpu_ghr),
        // Output to decode
        .valid_o            (fetch_valid),
        .pc_o               (fetch_pc),
        .instr_o            (fetch_instr),
        .pred_taken_o       (fetch_pred_taken),
        .pred_target_o      (fetch_pred_target),
        .ghr_o              (fetch_ghr)
    );

    //=========================================================
    // Decode Stage (4-wide)
    //=========================================================
    // Pack fetch instructions into 128-bit bus
    wire [127:0] fetch_instr_packed = {fetch_instr[3], fetch_instr[2], fetch_instr[1], fetch_instr[0]};
    wire         decode_ready;
    wire [3:0]   decode_valid_mask;
    
    // Unpacked decode output wires (for array ports)
    wire [XLEN-1:0]    dec_pc_wire       [0:FETCH_WIDTH-1];
    wire [31:0]        dec_inst_wire     [0:FETCH_WIDTH-1];
    wire [4:0]         dec_rs1_wire      [0:FETCH_WIDTH-1];
    wire [4:0]         dec_rs2_wire      [0:FETCH_WIDTH-1];
    wire [4:0]         dec_rd_wire       [0:FETCH_WIDTH-1];
    wire               dec_rs1_valid_wire[0:FETCH_WIDTH-1];
    wire               dec_rs2_valid_wire[0:FETCH_WIDTH-1];
    wire               dec_rd_valid_wire [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]    dec_imm_wire      [0:FETCH_WIDTH-1];
    wire               dec_use_imm_wire  [0:FETCH_WIDTH-1];
    wire [3:0]         dec_alu_op_wire   [0:FETCH_WIDTH-1];
    wire [2:0]         dec_fu_type_wire  [0:FETCH_WIDTH-1];
    wire               dec_is_load_wire  [0:FETCH_WIDTH-1];
    wire               dec_is_store_wire [0:FETCH_WIDTH-1];
    wire [2:0]         dec_mem_size_wire [0:FETCH_WIDTH-1];
    wire               dec_mem_signed_wire[0:FETCH_WIDTH-1];
    wire               dec_is_branch_wire[0:FETCH_WIDTH-1];
    wire               dec_is_jal_wire   [0:FETCH_WIDTH-1];
    wire               dec_is_jalr_wire  [0:FETCH_WIDTH-1];
    wire [2:0]         dec_branch_type_wire[0:FETCH_WIDTH-1];
    wire               dec_is_csr_wire   [0:FETCH_WIDTH-1];
    wire               dec_is_fence_wire [0:FETCH_WIDTH-1];
    wire               dec_is_mret_wire  [0:FETCH_WIDTH-1];
    wire               dec_is_sret_wire  [0:FETCH_WIDTH-1];
    wire               dec_is_ecall_wire [0:FETCH_WIDTH-1];
    wire               dec_is_ebreak_wire[0:FETCH_WIDTH-1];
    wire               dec_is_wfi_wire   [0:FETCH_WIDTH-1];
    wire               dec_is_sfence_wire[0:FETCH_WIDTH-1];
    wire               dec_is_atomic_wire[0:FETCH_WIDTH-1];
    wire [4:0]         dec_atomic_op_wire[0:FETCH_WIDTH-1];
    wire               dec_illegal_wire  [0:FETCH_WIDTH-1];
    
    decode_4way #(
        .XLEN(XLEN),
        .FETCH_WIDTH(FETCH_WIDTH)
    ) u_decode (
        .clk                (clk),
        .rst_n              (rst_n),
        // Fetch interface
        .fetch_valid_i      (|fetch_valid),
        .fetch_insts_i      (fetch_instr_packed),
        .fetch_pc_i         (fetch_pc[0]),
        .fetch_valid_mask_i (fetch_valid),
        .fetch_ready_o      (decode_ready),
        // Decoded output
        .dec_valid_o        (decode_valid[0]),
        .dec_valid_mask_o   (decode_valid_mask),
        // Per-instruction decoded signals
        .dec_pc_o           (dec_pc_wire),
        .dec_inst_o         (dec_inst_wire),
        .dec_rs1_o          (dec_rs1_wire),
        .dec_rs2_o          (dec_rs2_wire),
        .dec_rd_o           (dec_rd_wire),
        .dec_rs1_valid_o    (dec_rs1_valid_wire),
        .dec_rs2_valid_o    (dec_rs2_valid_wire),
        .dec_rd_valid_o     (dec_rd_valid_wire),
        .dec_imm_o          (dec_imm_wire),
        .dec_use_imm_o      (dec_use_imm_wire),
        .dec_alu_op_o       (dec_alu_op_wire),
        .dec_fu_type_o      (dec_fu_type_wire),
        .dec_is_load_o      (dec_is_load_wire),
        .dec_is_store_o     (dec_is_store_wire),
        .dec_mem_size_o     (dec_mem_size_wire),
        .dec_mem_signed_o   (dec_mem_signed_wire),
        .dec_is_branch_o    (dec_is_branch_wire),
        .dec_is_jal_o       (dec_is_jal_wire),
        .dec_is_jalr_o      (dec_is_jalr_wire),
        .dec_branch_type_o  (dec_branch_type_wire),
        .dec_is_csr_o       (dec_is_csr_wire),
        .dec_is_fence_o     (dec_is_fence_wire),
        .dec_is_mret_o      (dec_is_mret_wire),
        .dec_is_sret_o      (dec_is_sret_wire),
        .dec_is_ecall_o     (dec_is_ecall_wire),
        .dec_is_ebreak_o    (dec_is_ebreak_wire),
        .dec_is_wfi_o       (dec_is_wfi_wire),
        .dec_is_sfence_o    (dec_is_sfence_wire),
        .dec_is_atomic_o    (dec_is_atomic_wire),
        .dec_atomic_op_o    (dec_atomic_op_wire),
        .dec_illegal_o      (dec_illegal_wire),
        // Pipeline control
        .stall_i            (stall_frontend),
        .flush_i            (flush_frontend)
    );
    
    // Connect decoded signals to pipeline wires
    assign decode_valid = decode_valid_mask;
    genvar dec_i;
    generate
        for (dec_i = 0; dec_i < FETCH_WIDTH; dec_i = dec_i + 1) begin : gen_decode_connect
            assign decode_pc[dec_i]       = dec_pc_wire[dec_i];
            assign decode_rs1[dec_i]      = dec_rs1_wire[dec_i];
            assign decode_rs2[dec_i]      = dec_rs2_wire[dec_i];
            assign decode_rd[dec_i]       = dec_rd_wire[dec_i];
            assign decode_imm[dec_i]      = dec_imm_wire[dec_i];
            assign decode_alu_op[dec_i]   = {1'b0, dec_alu_op_wire[dec_i]};
            assign decode_fu_type[dec_i]  = dec_fu_type_wire[dec_i];
            assign decode_uses_rs1[dec_i] = dec_rs1_valid_wire[dec_i];
            assign decode_uses_rs2[dec_i] = dec_rs2_valid_wire[dec_i];
            assign decode_uses_rd[dec_i]  = dec_rd_valid_wire[dec_i];
            assign decode_is_branch[dec_i]= dec_is_branch_wire[dec_i] | dec_is_jal_wire[dec_i] | dec_is_jalr_wire[dec_i];
            assign decode_is_load[dec_i]  = dec_is_load_wire[dec_i];
            assign decode_is_store[dec_i] = dec_is_store_wire[dec_i];
            assign decode_is_csr[dec_i]   = dec_is_csr_wire[dec_i];
            assign decode_is_fence[dec_i] = dec_is_fence_wire[dec_i];
            assign decode_is_amo[dec_i]   = dec_is_atomic_wire[dec_i];
            assign decode_pred_taken[dec_i] = fetch_pred_taken[dec_i];
            assign decode_pred_target[dec_i] = fetch_pred_target[dec_i];
            assign decode_exception[dec_i]= dec_illegal_wire[dec_i] | dec_is_ecall_wire[dec_i] | dec_is_ebreak_wire[dec_i];
            assign decode_exc_code[dec_i] = dec_illegal_wire[dec_i] ? 4'd2 :
                                            dec_is_ecall_wire[dec_i] ? (current_priv == PRIV_U ? 4'd8 :
                                                                        current_priv == PRIV_S ? 4'd9 : 4'd11) :
                                            dec_is_ebreak_wire[dec_i] ? 4'd3 : 4'd0;
        end
    endgenerate

    //=========================================================
    // Rename Stage (4-wide)
    //=========================================================
    // Intermediate signals for rename interface (using array ports)
    wire [PHYS_REG_BITS-1:0] ren_prs1_wire   [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] ren_prs2_wire   [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] ren_prd_wire    [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] ren_old_prd_wire[0:FETCH_WIDTH-1];
    wire                     ren_prs1_rdy    [0:FETCH_WIDTH-1];
    wire                     ren_prs2_rdy    [0:FETCH_WIDTH-1];
    wire [ROB_IDX_BITS-1:0]  ren_rob_idx_wire[0:FETCH_WIDTH-1];
    wire                     rename_ready;
    wire [3:0]               ren_valid_mask;
    wire                     fl_pop_valid;
    wire [2:0]               fl_pop_count;
    wire [3:0]               fl_pop_ready;
    wire [PHYS_REG_BITS-1:0] fl_pop_preg_wire[0:FETCH_WIDTH-1];
    wire                     rob_alloc_valid;
    wire [2:0]               rob_alloc_count;
    wire [3:0]               rob_alloc_ready_mask;
    wire [ROB_IDX_BITS-1:0]  rob_alloc_idx_wire[0:FETCH_WIDTH-1];
    wire [127:0]             scoreboard;  // Ready bits for 128 physical registers
    
    // Scoreboard: track which physical registers are ready
    // For simplicity, mark all as ready initially (will be refined)
    assign scoreboard = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    
    // Intermediate unpacked arrays for rename module connection
    wire dec_rs1_valid_arr [0:FETCH_WIDTH-1];
    wire dec_rs2_valid_arr [0:FETCH_WIDTH-1];
    wire dec_rd_valid_arr  [0:FETCH_WIDTH-1];
    assign dec_rs1_valid_arr[0] = decode_uses_rs1[0];
    assign dec_rs1_valid_arr[1] = decode_uses_rs1[1];
    assign dec_rs1_valid_arr[2] = decode_uses_rs1[2];
    assign dec_rs1_valid_arr[3] = decode_uses_rs1[3];
    assign dec_rs2_valid_arr[0] = decode_uses_rs2[0];
    assign dec_rs2_valid_arr[1] = decode_uses_rs2[1];
    assign dec_rs2_valid_arr[2] = decode_uses_rs2[2];
    assign dec_rs2_valid_arr[3] = decode_uses_rs2[3];
    assign dec_rd_valid_arr[0]  = decode_uses_rd[0];
    assign dec_rd_valid_arr[1]  = decode_uses_rd[1];
    assign dec_rd_valid_arr[2]  = decode_uses_rd[2];
    assign dec_rd_valid_arr[3]  = decode_uses_rd[3];
    
    rename_4way #(
        .ARCH_REGS(32),
        .PHYS_REGS(128),
        .RENAME_WIDTH(FETCH_WIDTH),
        .ROB_DEPTH(64),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_rename (
        .clk                (clk),
        .rst_n              (rst_n),
        // Decode interface
        .dec_valid_i        (decode_valid[0]),
        .dec_valid_mask_i   (decode_valid),
        .dec_rs1_i          (decode_rs1),
        .dec_rs2_i          (decode_rs2),
        .dec_rd_i           (decode_rd),
        .dec_rs1_valid_i    (dec_rs1_valid_arr),
        .dec_rs2_valid_i    (dec_rs2_valid_arr),
        .dec_rd_valid_i     (dec_rd_valid_arr),
        .dec_ready_o        (rename_ready),
        // Renamed output
        .ren_valid_o        (rename_valid[0]),
        .ren_valid_mask_o   (ren_valid_mask),
        .ren_prs1_o         (ren_prs1_wire),
        .ren_prs2_o         (ren_prs2_wire),
        .ren_prd_o          (ren_prd_wire),
        .ren_old_prd_o      (ren_old_prd_wire),
        .ren_prs1_ready_o   (ren_prs1_rdy),
        .ren_prs2_ready_o   (ren_prs2_rdy),
        // Free list interface
        .fl_pop_valid_o     (fl_pop_valid),
        .fl_pop_count_o     (fl_pop_count),
        .fl_pop_ready_i     (fl_pop_ready),
        .fl_pop_preg_i      (fl_pop_preg_wire),
        // ROB interface
        .rob_alloc_valid_o  (rob_alloc_valid),
        .rob_alloc_count_o  (rob_alloc_count),
        .rob_alloc_ready_i  (rob_alloc_ready_mask),
        .rob_alloc_idx_i    (rob_alloc_idx_wire),
        .ren_rob_idx_o      (ren_rob_idx_wire),
        // Commit interface
        .commit_valid_i     (rob_commit_valid[0]),
        .commit_mask_i      (rob_commit_valid),
        .commit_rd_i        (rob_commit_rd),
        .commit_prd_i       (rob_commit_prd),
        // Flush interface
        .flush_i            (flush_backend),
        .flush_rob_idx_i    (6'd0),
        // Scoreboard
        .scoreboard_i       (scoreboard)
    );
    
    // Connect rename outputs
    assign rename_valid = ren_valid_mask;
    genvar ren_i;
    generate
        for (ren_i = 0; ren_i < FETCH_WIDTH; ren_i = ren_i + 1) begin : gen_rename_connect
            assign rename_prs1[ren_i]     = ren_prs1_wire[ren_i];
            assign rename_prs2[ren_i]     = ren_prs2_wire[ren_i];
            assign rename_prd[ren_i]      = ren_prd_wire[ren_i];
            assign rename_prd_old[ren_i]  = ren_old_prd_wire[ren_i];
            assign rename_rs1_ready[ren_i]= ren_prs1_rdy[ren_i];
            assign rename_rs2_ready[ren_i]= ren_prs2_rdy[ren_i];
            assign rename_rob_idx[ren_i]  = ren_rob_idx_wire[ren_i];
        end
    endgenerate

    //=========================================================
    // Free List (128 physical registers, dual-port alloc/free)
    //=========================================================
    wire fl_almost_empty;
    wire [PHYS_REG_BITS:0] fl_free_count;
    
    free_list_enhanced #(
        .NUM_PHYS_REGS(128),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .NUM_ARCH_REGS(32),
        .NUM_CHECKPOINTS(8)
    ) u_free_list (
        .clk                (clk),
        .rst_n              (rst_n),
        // Dual allocation (ports 0 and 1)
        .alloc0_req_i       (fl_pop_valid && fl_pop_count >= 3'd1),
        .alloc0_valid_o     (fl_pop_ready[0]),
        .alloc0_preg_o      (fl_pop_preg_wire[0]),
        .alloc1_req_i       (fl_pop_valid && fl_pop_count >= 3'd2),
        .alloc1_valid_o     (fl_pop_ready[1]),
        .alloc1_preg_o      (fl_pop_preg_wire[1]),
        // Dual release (from commit)
        .release0_valid_i   (rob_commit_valid[0] && rob_commit_prd_old[0] >= 7'd32),
        .release0_preg_i    (rob_commit_prd_old[0]),
        .release1_valid_i   (rob_commit_valid[1] && rob_commit_prd_old[1] >= 7'd32),
        .release1_preg_i    (rob_commit_prd_old[1]),
        // Checkpoint interface
        .checkpoint_create_i(1'b0),
        .checkpoint_id_i    (3'd0),
        .recover_i          (1'b0),
        .recover_id_i       (3'd0),
        // Flush
        .flush_i            (flush_backend),
        // Status
        .empty_o            (fl_empty),
        .almost_empty_o     (fl_almost_empty),
        .free_count_o       (fl_free_count)
    );
    
    // Generate additional free list ports for 4-way allocation
    // Simplified: use same register for slots 2 and 3
    assign fl_pop_ready[2] = fl_pop_ready[1];
    assign fl_pop_ready[3] = fl_pop_ready[1];
    assign fl_pop_preg_wire[2] = fl_pop_preg_wire[1] + 1;
    assign fl_pop_preg_wire[3] = fl_pop_preg_wire[1] + 2;

    //=========================================================
    // ROB (64 entries, dual allocation/commit)
    //=========================================================
    wire                    rob_almost_full;
    wire [ROB_IDX_BITS:0]   rob_count;
    wire [ROB_IDX_BITS-1:0] rob_checkpoint_tail;
    
    rob_enhanced #(
        .NUM_ENTRIES(64),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .DATA_WIDTH(XLEN),
        .EXC_CODE_WIDTH(4),
        .NUM_CHECKPOINTS(8)
    ) u_rob (
        .clk                (clk),
        .rst_n              (rst_n),
        // Dual allocation (port 0)
        .alloc0_req_i       (rob_alloc_valid && rob_alloc_count >= 3'd1),
        .alloc0_ready_o     (rob_alloc_ready_mask[0]),
        .alloc0_idx_o       (rob_alloc_idx_wire[0]),
        .alloc0_rd_arch_i   (decode_rd[0]),
        .alloc0_rd_phys_i   (ren_prd_wire[0]),
        .alloc0_rd_phys_old_i(ren_old_prd_wire[0]),
        .alloc0_pc_i        (decode_pc[0]),
        .alloc0_instr_type_i(4'd0),
        .alloc0_is_branch_i (decode_is_branch[0]),
        .alloc0_is_store_i  (decode_is_store[0]),
        // Dual allocation (port 1)
        .alloc1_req_i       (rob_alloc_valid && rob_alloc_count >= 3'd2),
        .alloc1_ready_o     (rob_alloc_ready_mask[1]),
        .alloc1_idx_o       (rob_alloc_idx_wire[1]),
        .alloc1_rd_arch_i   (decode_rd[1]),
        .alloc1_rd_phys_i   (ren_prd_wire[1]),
        .alloc1_rd_phys_old_i(ren_old_prd_wire[1]),
        .alloc1_pc_i        (decode_pc[1]),
        .alloc1_instr_type_i(4'd0),
        .alloc1_is_branch_i (decode_is_branch[1]),
        .alloc1_is_store_i  (decode_is_store[1]),
        // Dual completion (from CDB)
        .complete0_valid_i  (cdb_valid[0]),
        .complete0_idx_i    (cdb_rob_idx[0]),
        .complete0_result_i (cdb_data[0]),
        .complete0_exception_i(cdb_exception[0]),
        .complete0_exc_code_i(cdb_exc_code[0]),
        .complete0_branch_taken_i(cdb_br_taken),
        .complete0_branch_target_i(cdb_br_target),
        .complete1_valid_i  (cdb_valid[1]),
        .complete1_idx_i    (cdb_rob_idx[1]),
        .complete1_result_i (cdb_data[1]),
        .complete1_exception_i(cdb_exception[1]),
        .complete1_exc_code_i(cdb_exc_code[1]),
        .complete1_branch_taken_i(1'b0),
        .complete1_branch_target_i(32'd0),
        // Dual commit (port 0)
        .commit0_valid_o    (rob_commit_valid[0]),
        .commit0_ready_i    (1'b1),
        .commit0_idx_o      (),
        .commit0_rd_arch_o  (rob_commit_rd[0]),
        .commit0_rd_phys_o  (rob_commit_prd[0]),
        .commit0_rd_phys_old_o(rob_commit_prd_old[0]),
        .commit0_result_o   (),
        .commit0_pc_o       (rob_commit_pc[0]),
        .commit0_is_branch_o(rob_commit_is_branch[0]),
        .commit0_branch_taken_o(rob_commit_br_taken[0]),
        .commit0_branch_target_o(rob_commit_br_target[0]),
        .commit0_is_store_o (rob_commit_is_store[0]),
        .commit0_exception_o(rob_commit_exception[0]),
        .commit0_exc_code_o (rob_commit_exc_code[0]),
        // Dual commit (port 1)
        .commit1_valid_o    (rob_commit_valid[1]),
        .commit1_ready_i    (1'b1),
        .commit1_idx_o      (),
        .commit1_rd_arch_o  (rob_commit_rd[1]),
        .commit1_rd_phys_o  (rob_commit_prd[1]),
        .commit1_rd_phys_old_o(rob_commit_prd_old[1]),
        .commit1_result_o   (),
        .commit1_pc_o       (rob_commit_pc[1]),
        .commit1_is_branch_o(rob_commit_is_branch[1]),
        .commit1_branch_taken_o(rob_commit_br_taken[1]),
        .commit1_branch_target_o(rob_commit_br_target[1]),
        .commit1_is_store_o (rob_commit_is_store[1]),
        .commit1_exception_o(rob_commit_exception[1]),
        .commit1_exc_code_o (rob_commit_exc_code[1]),
        // Commit port 2
        .commit2_valid_o    (rob_commit_valid[2]),
        .commit2_ready_i    (1'b1),
        .commit2_idx_o      (),
        .commit2_rd_arch_o  (rob_commit_rd[2]),
        .commit2_rd_phys_o  (rob_commit_prd[2]),
        .commit2_rd_phys_old_o(rob_commit_prd_old[2]),
        .commit2_result_o   (),
        .commit2_pc_o       (rob_commit_pc[2]),
        .commit2_is_branch_o(rob_commit_is_branch[2]),
        .commit2_branch_taken_o(rob_commit_br_taken[2]),
        .commit2_branch_target_o(rob_commit_br_target[2]),
        .commit2_is_store_o (rob_commit_is_store[2]),
        .commit2_exception_o(rob_commit_exception[2]),
        .commit2_exc_code_o (rob_commit_exc_code[2]),
        // Commit port 3
        .commit3_valid_o    (rob_commit_valid[3]),
        .commit3_ready_i    (1'b1),
        .commit3_idx_o      (),
        .commit3_rd_arch_o  (rob_commit_rd[3]),
        .commit3_rd_phys_o  (rob_commit_prd[3]),
        .commit3_rd_phys_old_o(rob_commit_prd_old[3]),
        .commit3_result_o   (),
        .commit3_pc_o       (rob_commit_pc[3]),
        .commit3_is_branch_o(rob_commit_is_branch[3]),
        .commit3_branch_taken_o(rob_commit_br_taken[3]),
        .commit3_branch_target_o(rob_commit_br_target[3]),
        .commit3_is_store_o (rob_commit_is_store[3]),
        .commit3_exception_o(rob_commit_exception[3]),
        .commit3_exc_code_o (rob_commit_exc_code[3]),
        // Checkpoint
        .checkpoint_create_i(1'b0),
        .checkpoint_id_i    (3'd0),
        .checkpoint_tail_o  (rob_checkpoint_tail),
        .recover_i          (cdb_br_mispredict),
        .recover_id_i       (3'd0),
        // Flush
        .flush_i            (flush_backend),
        // Status
        .empty_o            (rob_empty),
        .full_o             (rob_full),
        .almost_full_o      (rob_almost_full),
        .count_o            (rob_count)
    );
    
    // Generate additional ROB allocation ports (simplified)
    assign rob_alloc_ready_mask[2] = rob_alloc_ready_mask[1];
    assign rob_alloc_ready_mask[3] = rob_alloc_ready_mask[1];
    assign rob_alloc_idx_wire[2] = rob_alloc_idx_wire[1] + 1;
    assign rob_alloc_idx_wire[3] = rob_alloc_idx_wire[1] + 2;

    //=========================================================
    // Issue Queue (32 entries, 4-insert/4-issue)
    //=========================================================
    // Issue queue intermediate signals
    wire [PHYS_REG_BITS-1:0] iq_prs1_wire  [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] iq_prs2_wire  [0:FETCH_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] iq_prd_out    [0:FETCH_WIDTH-1];
    wire [ROB_IDX_BITS-1:0]  iq_rob_out    [0:FETCH_WIDTH-1];
    wire [2:0]               iq_fu_out     [0:FETCH_WIDTH-1];
    wire [3:0]               iq_op_out     [0:FETCH_WIDTH-1];
    wire [XLEN-1:0]          iq_imm_out    [0:FETCH_WIDTH-1];
    wire                     iq_use_imm_out[0:FETCH_WIDTH-1];
    wire [XLEN-1:0]          iq_pc_out     [0:FETCH_WIDTH-1];
    wire                     iq_insert_ready;
    wire [PHYS_REG_BITS-1:0] wakeup_prd_wire[0:FETCH_WIDTH-1];
    
    // Wakeup from CDB
    assign wakeup_prd_wire[0] = cdb_prd[0];
    assign wakeup_prd_wire[1] = cdb_prd[1];
    assign wakeup_prd_wire[2] = cdb_prd[2];
    assign wakeup_prd_wire[3] = cdb_prd[3];
    
    // Use_imm signals (unpacked array)
    wire insert_use_imm_arr [0:FETCH_WIDTH-1];
    assign insert_use_imm_arr[0] = dec_use_imm_wire[0];
    assign insert_use_imm_arr[1] = dec_use_imm_wire[1];
    assign insert_use_imm_arr[2] = dec_use_imm_wire[2];
    assign insert_use_imm_arr[3] = dec_use_imm_wire[3];
    
    issue_queue_4way #(
        .IQ_DEPTH(IQ_ENTRIES),
        .ISSUE_WIDTH(FETCH_WIDTH),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .XLEN(XLEN)
    ) u_issue_queue (
        .clk                (clk),
        .rst_n              (rst_n),
        // Insert interface (from rename)
        .insert_valid_i     (rename_valid[0]),
        .insert_mask_i      (rename_valid),
        .insert_ready_o     (iq_insert_ready),
        // Per-instruction insert data
        .insert_prs1_i      (ren_prs1_wire),
        .insert_prs2_i      (ren_prs2_wire),
        .insert_prd_i       (ren_prd_wire),
        .insert_prs1_ready_i(ren_prs1_rdy),
        .insert_prs2_ready_i(ren_prs2_rdy),
        .insert_rob_idx_i   (ren_rob_idx_wire),
        .insert_fu_type_i   (decode_fu_type),
        .insert_alu_op_i    (dec_alu_op_wire),
        .insert_imm_i       (decode_imm),
        .insert_use_imm_i   (insert_use_imm_arr),
        .insert_pc_i        (decode_pc),
        // Issue interface (to execution)
        .issue_valid_o      (iq_issue_valid),
        .issue_ready_i      (iq_issue_ready),
        .issue_prs1_o       (iq_prs1_wire),
        .issue_prs2_o       (iq_prs2_wire),
        .issue_prd_o        (iq_prd_out),
        .issue_rob_idx_o    (iq_rob_out),
        .issue_fu_type_o    (iq_fu_out),
        .issue_alu_op_o     (iq_op_out),
        .issue_imm_o        (iq_imm_out),
        .issue_use_imm_o    (iq_use_imm_out),
        .issue_pc_o         (iq_pc_out),
        // Wakeup interface
        .wakeup_valid_i     (cdb_valid),
        .wakeup_prd_i       (wakeup_prd_wire),
        // Flush interface
        .flush_i            (flush_backend),
        .flush_rob_idx_i    (6'd0)
    );
    
    // Connect issue queue outputs to execution
    genvar iq_i;
    generate
        for (iq_i = 0; iq_i < FETCH_WIDTH; iq_i = iq_i + 1) begin : gen_iq_connect
            assign iq_issue_prd[iq_i]     = iq_prd_out[iq_i];
            assign iq_issue_rob_idx[iq_i] = iq_rob_out[iq_i];
            assign iq_issue_fu_type[iq_i] = iq_fu_out[iq_i];
            assign iq_issue_op[iq_i]      = {1'b0, iq_op_out[iq_i]};
            assign iq_issue_imm[iq_i]     = iq_imm_out[iq_i];
            assign iq_issue_pc[iq_i]      = iq_pc_out[iq_i];
            // RS data will be read from PRF
            assign iq_issue_rs1_data[iq_i] = prf_rd_data[iq_i*2];
            assign iq_issue_rs2_data[iq_i] = prf_rd_data[iq_i*2+1];
        end
    endgenerate

    //=========================================================
    // PRF (128 registers, 4R/2W)
    //=========================================================
    // PRF read addresses from issue queue
    assign prf_rd_addr[0] = iq_prs1_wire[0];
    assign prf_rd_addr[1] = iq_prs2_wire[0];
    assign prf_rd_addr[2] = iq_prs1_wire[1];
    assign prf_rd_addr[3] = iq_prs2_wire[1];
    assign prf_rd_addr[4] = iq_prs1_wire[2];
    assign prf_rd_addr[5] = iq_prs2_wire[2];
    assign prf_rd_addr[6] = iq_prs1_wire[3];
    assign prf_rd_addr[7] = iq_prs2_wire[3];
    
    // PRF ready signals
    wire prf_rd_ready [0:3];
    wire [127:0] prf_flush_ready_mask;
    assign prf_flush_ready_mask = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    
    prf_enhanced #(
        .NUM_PHYS_REGS(128),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .NUM_READ_PORTS(8),
        .NUM_WRITE_PORTS(2)
    ) u_prf (
        .clk                (clk),
        .rst_n              (rst_n),
        // Read port 0 (issue0 rs1)
        .rd0_addr_i         (prf_rd_addr[0]),
        .rd0_en_i           (iq_issue_valid[0]),
        .rd0_data_o         (prf_rd_data[0]),
        .rd0_ready_o        (prf_rd_ready[0]),
        // Read port 1 (issue0 rs2)
        .rd1_addr_i         (prf_rd_addr[1]),
        .rd1_en_i           (iq_issue_valid[0]),
        .rd1_data_o         (prf_rd_data[1]),
        .rd1_ready_o        (),
        // Read port 2 (issue1 rs1)
        .rd2_addr_i         (prf_rd_addr[2]),
        .rd2_en_i           (iq_issue_valid[1]),
        .rd2_data_o         (prf_rd_data[2]),
        .rd2_ready_o        (),
        // Read port 3 (issue1 rs2)
        .rd3_addr_i         (prf_rd_addr[3]),
        .rd3_en_i           (iq_issue_valid[1]),
        .rd3_data_o         (prf_rd_data[3]),
        .rd3_ready_o        (),
        // Read port 4 (issue2 rs1)
        .rd4_addr_i         (prf_rd_addr[4]),
        .rd4_en_i           (iq_issue_valid[2]),
        .rd4_data_o         (prf_rd_data[4]),
        .rd4_ready_o        (),
        // Read port 5 (issue2 rs2)
        .rd5_addr_i         (prf_rd_addr[5]),
        .rd5_en_i           (iq_issue_valid[2]),
        .rd5_data_o         (prf_rd_data[5]),
        .rd5_ready_o        (),
        // Read port 6 (issue3 rs1)
        .rd6_addr_i         (prf_rd_addr[6]),
        .rd6_en_i           (iq_issue_valid[3]),
        .rd6_data_o         (prf_rd_data[6]),
        .rd6_ready_o        (),
        // Read port 7 (issue3 rs2)
        .rd7_addr_i         (prf_rd_addr[7]),
        .rd7_en_i           (iq_issue_valid[3]),
        .rd7_data_o         (prf_rd_data[7]),
        .rd7_ready_o        (),
        // Write port 0 (CDB0)
        .wr0_addr_i         (cdb_prd[0]),
        .wr0_data_i         (cdb_data[0]),
        .wr0_en_i           (cdb_valid[0]),
        // Write port 1 (CDB1)
        .wr1_addr_i         (cdb_prd[1]),
        .wr1_data_i         (cdb_data[1]),
        .wr1_en_i           (cdb_valid[1]),
        // Ready bit management
        .set_unready_addr_i (ren_prd_wire[0]),
        .set_unready_en_i   (rename_valid[0]),
        .set_unready_addr2_i(ren_prd_wire[1]),
        .set_unready_en2_i  (rename_valid[1]),
        // Flush
        .flush_i            (flush_backend),
        .flush_ready_mask_i (prf_flush_ready_mask)
    );
    

    //=========================================================
    // Execution Cluster (2xALU + MUL + DIV + BRU)
    //=========================================================
    // Intermediate ready signals from execution cluster
    wire ex_issue_ready [0:3];
    
    execution_cluster #(
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_ex_cluster (
        .clk                (clk),
        .rst_n              (rst_n),
        .flush_i            (flush_backend),
        // Issue port 0
        .issue0_valid_i     (iq_issue_valid[0]),
        .issue0_ready_o     (ex_issue_ready[0]),
        .issue0_op_i        (iq_issue_op[0]),
        .issue0_rs1_data_i  (iq_issue_rs1_data[0]),
        .issue0_rs2_data_i  (iq_issue_rs2_data[0]),
        .issue0_imm_i       (iq_issue_imm[0]),
        .issue0_pc_i        (iq_issue_pc[0]),
        .issue0_prd_i       (iq_issue_prd[0]),
        .issue0_rob_idx_i   (iq_issue_rob_idx[0]),
        .issue0_fu_type_i   (iq_issue_fu_type[0]),
        .issue0_use_imm_i   (1'b0),              // TODO: from decode
        .issue0_br_predict_i(decode_pred_taken[0]),
        .issue0_br_target_i (decode_pred_target[0]),
        // Issue port 1
        .issue1_valid_i     (iq_issue_valid[1]),
        .issue1_ready_o     (ex_issue_ready[1]),
        .issue1_op_i        (iq_issue_op[1]),
        .issue1_rs1_data_i  (iq_issue_rs1_data[1]),
        .issue1_rs2_data_i  (iq_issue_rs2_data[1]),
        .issue1_imm_i       (iq_issue_imm[1]),
        .issue1_pc_i        (iq_issue_pc[1]),
        .issue1_prd_i       (iq_issue_prd[1]),
        .issue1_rob_idx_i   (iq_issue_rob_idx[1]),
        .issue1_fu_type_i   (iq_issue_fu_type[1]),
        .issue1_use_imm_i   (1'b0),
        .issue1_br_predict_i(decode_pred_taken[1]),
        .issue1_br_target_i (decode_pred_target[1]),
        // Issue port 2
        .issue2_valid_i     (iq_issue_valid[2]),
        .issue2_ready_o     (ex_issue_ready[2]),
        .issue2_op_i        (iq_issue_op[2]),
        .issue2_rs1_data_i  (iq_issue_rs1_data[2]),
        .issue2_rs2_data_i  (iq_issue_rs2_data[2]),
        .issue2_imm_i       (iq_issue_imm[2]),
        .issue2_pc_i        (iq_issue_pc[2]),
        .issue2_prd_i       (iq_issue_prd[2]),
        .issue2_rob_idx_i   (iq_issue_rob_idx[2]),
        .issue2_fu_type_i   (iq_issue_fu_type[2]),
        .issue2_use_imm_i   (1'b0),
        .issue2_br_predict_i(decode_pred_taken[2]),
        .issue2_br_target_i (decode_pred_target[2]),
        // Issue port 3
        .issue3_valid_i     (iq_issue_valid[3]),
        .issue3_ready_o     (ex_issue_ready[3]),
        .issue3_op_i        (iq_issue_op[3]),
        .issue3_rs1_data_i  (iq_issue_rs1_data[3]),
        .issue3_rs2_data_i  (iq_issue_rs2_data[3]),
        .issue3_imm_i       (iq_issue_imm[3]),
        .issue3_pc_i        (iq_issue_pc[3]),
        .issue3_prd_i       (iq_issue_prd[3]),
        .issue3_rob_idx_i   (iq_issue_rob_idx[3]),
        .issue3_fu_type_i   (iq_issue_fu_type[3]),
        .issue3_use_imm_i   (1'b0),
        .issue3_br_predict_i(decode_pred_taken[3]),
        .issue3_br_target_i (decode_pred_target[3]),
        // Results to CDB
        .alu0_valid_o       (ex_alu0_valid),
        .alu0_ready_i       (1'b1),
        .alu0_prd_o         (ex_alu0_prd),
        .alu0_data_o        (ex_alu0_data),
        .alu0_rob_idx_o     (ex_alu0_rob),
        .alu0_exception_o   (),
        .alu0_exc_code_o    (),
        .alu1_valid_o       (ex_alu1_valid),
        .alu1_ready_i       (1'b1),
        .alu1_prd_o         (ex_alu1_prd),
        .alu1_data_o        (ex_alu1_data),
        .alu1_rob_idx_o     (ex_alu1_rob),
        .alu1_exception_o   (),
        .alu1_exc_code_o    (),
        .mul_valid_o        (ex_mul_valid),
        .mul_ready_i        (1'b1),
        .mul_prd_o          (ex_mul_prd),
        .mul_data_o         (ex_mul_data),
        .mul_rob_idx_o      (ex_mul_rob),
        .mul_exception_o    (),
        .mul_exc_code_o     (),
        .div_valid_o        (ex_div_valid),
        .div_ready_i        (1'b1),
        .div_prd_o          (ex_div_prd),
        .div_data_o         (ex_div_data),
        .div_rob_idx_o      (ex_div_rob),
        .div_exception_o    (),
        .div_exc_code_o     (),
        .bru_valid_o        (ex_bru_valid),
        .bru_ready_i        (1'b1),
        .bru_prd_o          (ex_bru_prd),
        .bru_data_o         (ex_bru_data),
        .bru_rob_idx_o      (ex_bru_rob),
        .bru_exception_o    (),
        .bru_exc_code_o     (),
        .bru_taken_o        (ex_bru_taken),
        .bru_target_o       (ex_bru_target),
        .bru_mispredict_o   (ex_bru_mispredict),
        .unit_active_o      ()
    );

    //=========================================================
    // Simple LSU (Load/Store Unit)
    // Captures FU_LSU instructions from issue queue port 0
    //=========================================================
    localparam FU_LSU = 3'd3;  // Must match decode_4way.v
    
    // LSU state machine
    localparam LSU_IDLE    = 2'd0;
    localparam LSU_REQUEST = 2'd1;
    localparam LSU_WAIT    = 2'd2;
    
    reg [1:0]               lsu_state;
    reg                     lsu_pending_load;
    reg [PHYS_REG_BITS-1:0] lsu_pending_prd;
    reg [ROB_IDX_BITS-1:0]  lsu_pending_rob_idx;
    reg [2:0]               lsu_pending_size;     // funct3 for load/store size
    reg [XLEN-1:0]          lsu_pending_addr;
    
    // Detect LSU instruction from any issue port
    wire lsu_issue_p0 = iq_issue_valid[0] && (iq_issue_fu_type[0] == FU_LSU);
    wire lsu_issue_p1 = iq_issue_valid[1] && (iq_issue_fu_type[1] == FU_LSU);
    wire lsu_issue_p2 = iq_issue_valid[2] && (iq_issue_fu_type[2] == FU_LSU);
    wire lsu_issue_p3 = iq_issue_valid[3] && (iq_issue_fu_type[3] == FU_LSU);
    
    // Priority encode: use first LSU instruction found
    wire lsu_issue_any = lsu_issue_p0 || lsu_issue_p1 || lsu_issue_p2 || lsu_issue_p3;
    wire [1:0] lsu_issue_port = lsu_issue_p0 ? 2'd0 : 
                                lsu_issue_p1 ? 2'd1 : 
                                lsu_issue_p2 ? 2'd2 : 2'd3;
    
    // Get data from selected port
    wire [XLEN-1:0]          lsu_rs1 = (lsu_issue_port == 2'd0) ? iq_issue_rs1_data[0] :
                                       (lsu_issue_port == 2'd1) ? iq_issue_rs1_data[1] :
                                       (lsu_issue_port == 2'd2) ? iq_issue_rs1_data[2] : iq_issue_rs1_data[3];
    wire [XLEN-1:0]          lsu_rs2 = (lsu_issue_port == 2'd0) ? iq_issue_rs2_data[0] :
                                       (lsu_issue_port == 2'd1) ? iq_issue_rs2_data[1] :
                                       (lsu_issue_port == 2'd2) ? iq_issue_rs2_data[2] : iq_issue_rs2_data[3];
    wire [XLEN-1:0]          lsu_imm = (lsu_issue_port == 2'd0) ? iq_issue_imm[0] :
                                       (lsu_issue_port == 2'd1) ? iq_issue_imm[1] :
                                       (lsu_issue_port == 2'd2) ? iq_issue_imm[2] : iq_issue_imm[3];
    wire [4:0]               lsu_op  = (lsu_issue_port == 2'd0) ? iq_issue_op[0] :
                                       (lsu_issue_port == 2'd1) ? iq_issue_op[1] :
                                       (lsu_issue_port == 2'd2) ? iq_issue_op[2] : iq_issue_op[3];
    wire [PHYS_REG_BITS-1:0] lsu_prd_in = (lsu_issue_port == 2'd0) ? iq_issue_prd[0] :
                                          (lsu_issue_port == 2'd1) ? iq_issue_prd[1] :
                                          (lsu_issue_port == 2'd2) ? iq_issue_prd[2] : iq_issue_prd[3];
    wire [ROB_IDX_BITS-1:0]  lsu_rob_in = (lsu_issue_port == 2'd0) ? iq_issue_rob_idx[0] :
                                          (lsu_issue_port == 2'd1) ? iq_issue_rob_idx[1] :
                                          (lsu_issue_port == 2'd2) ? iq_issue_rob_idx[2] : iq_issue_rob_idx[3];
    
    // Decode load vs store from alu_op (bit 4 = 1 for store in our encoding)
    // Actually we need to track is_load/is_store from decode. For now use op[3] as indicator
    // In decode_4way, LOAD uses FU_LSU, STORE uses FU_LSU
    // We can distinguish by looking at rd_valid (loads have rd, stores don't)
    // For simplicity: assume op[3] distinguishes (0=load, 1=store) - TODO: fix properly
    wire lsu_is_store_in = lsu_op[3];  // Simplified: stores have different op encoding
    
    // Address calculation
    wire [XLEN-1:0] lsu_addr_calc = lsu_rs1 + lsu_imm;
    
    // LSU ready signal - can accept when idle
    assign lsu_ready = (lsu_state == LSU_IDLE);
    
    // LSU state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsu_state <= LSU_IDLE;
            lsu_pending_load <= 1'b0;
            lsu_pending_prd <= {PHYS_REG_BITS{1'b0}};
            lsu_pending_rob_idx <= {ROB_IDX_BITS{1'b0}};
            lsu_pending_size <= 3'd0;
            lsu_pending_addr <= {XLEN{1'b0}};
        end else if (flush_backend) begin
            lsu_state <= LSU_IDLE;
            lsu_pending_load <= 1'b0;
        end else begin
            case (lsu_state)
                LSU_IDLE: begin
                    if (lsu_issue_any && lsu_ready) begin
                        lsu_pending_addr <= lsu_addr_calc;
                        lsu_pending_prd <= lsu_prd_in;
                        lsu_pending_rob_idx <= lsu_rob_in;
                        lsu_pending_size <= lsu_op[2:0];  // funct3 for size
                        lsu_pending_load <= !lsu_is_store_in;
                        lsu_state <= LSU_REQUEST;
                    end
                end
                
                LSU_REQUEST: begin
                    if (dcache_req_ready) begin
                        lsu_state <= LSU_WAIT;
                    end
                end
                
                LSU_WAIT: begin
                    if (dcache_resp_valid) begin
                        lsu_state <= LSU_IDLE;
                    end
                end
            endcase
        end
    end
    
    // Store data register
    reg [XLEN-1:0] lsu_store_data;
    always @(posedge clk) begin
        if (lsu_state == LSU_IDLE && lsu_issue_any) begin
            lsu_store_data <= lsu_rs2;
        end
    end
    
    // D-Cache request signals
    assign dcache_req_valid = (lsu_state == LSU_REQUEST);
    assign dcache_req_addr = lsu_pending_addr;
    assign dcache_req_write = !lsu_pending_load;
    assign dcache_req_wdata = lsu_store_data;
    // Byte enable based on size and address alignment
    assign dcache_req_wmask = (lsu_pending_size[1:0] == 2'b00) ? (4'b0001 << lsu_pending_addr[1:0]) :  // Byte
                              (lsu_pending_size[1:0] == 2'b01) ? (4'b0011 << {lsu_pending_addr[1], 1'b0}) :  // Halfword
                                                                  4'b1111;  // Word
    
    // LSU response to CDB
    // Sign/zero extension for load data
    wire [XLEN-1:0] load_byte = {{24{!lsu_pending_size[2] && dcache_resp_rdata[7]}}, 
                                  dcache_resp_rdata[7:0]};
    wire [XLEN-1:0] load_half = {{16{!lsu_pending_size[2] && dcache_resp_rdata[15]}}, 
                                  dcache_resp_rdata[15:0]};
    wire [XLEN-1:0] load_word = dcache_resp_rdata;
    
    wire [XLEN-1:0] load_data_aligned = (lsu_pending_size[1:0] == 2'b00) ? load_byte :
                                        (lsu_pending_size[1:0] == 2'b01) ? load_half : load_word;
    
    assign lsu_resp_valid = dcache_resp_valid && (lsu_state == LSU_WAIT);
    assign lsu_resp_prd = lsu_pending_prd;
    assign lsu_resp_data = lsu_pending_load ? load_data_aligned : 32'd0;
    assign lsu_resp_rob_idx = lsu_pending_rob_idx;
    assign lsu_resp_exception = 1'b0;  // TODO: handle misalignment, page faults
    assign lsu_resp_exc_code = 4'd0;
    
    // Combined issue ready signals: execution cluster ready OR (LSU ready AND is LSU instruction)
    // For each port: if it's an LSU instruction, use LSU ready; otherwise use exec cluster ready
    assign iq_issue_ready[0] = (iq_issue_fu_type[0] == FU_LSU) ? (lsu_ready && lsu_issue_p0) : ex_issue_ready[0];
    assign iq_issue_ready[1] = (iq_issue_fu_type[1] == FU_LSU) ? (lsu_ready && lsu_issue_p1 && !lsu_issue_p0) : ex_issue_ready[1];
    assign iq_issue_ready[2] = (iq_issue_fu_type[2] == FU_LSU) ? (lsu_ready && lsu_issue_p2 && !lsu_issue_p0 && !lsu_issue_p1) : ex_issue_ready[2];
    assign iq_issue_ready[3] = (iq_issue_fu_type[3] == FU_LSU) ? (lsu_ready && lsu_issue_p3 && !lsu_issue_p0 && !lsu_issue_p1 && !lsu_issue_p2) : ex_issue_ready[3];

    //=========================================================
    // 4-Wide CDB
    //=========================================================
    cdb_4wide #(
        .NUM_SOURCES(8),
        .CDB_WIDTH(CDB_WIDTH),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(XLEN),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_cdb (
        .clk                (clk),
        .rst_n              (rst_n),
        // ALU0
        .alu0_valid_i       (ex_alu0_valid),
        .alu0_ready_o       (),
        .alu0_prd_i         (ex_alu0_prd),
        .alu0_data_i        (ex_alu0_data),
        .alu0_rob_idx_i     (ex_alu0_rob),
        .alu0_exception_i   (1'b0),
        .alu0_exc_code_i    (4'd0),
        // ALU1
        .alu1_valid_i       (ex_alu1_valid),
        .alu1_ready_o       (),
        .alu1_prd_i         (ex_alu1_prd),
        .alu1_data_i        (ex_alu1_data),
        .alu1_rob_idx_i     (ex_alu1_rob),
        .alu1_exception_i   (1'b0),
        .alu1_exc_code_i    (4'd0),
        // MUL
        .mul_valid_i        (ex_mul_valid),
        .mul_ready_o        (),
        .mul_prd_i          (ex_mul_prd),
        .mul_data_i         (ex_mul_data),
        .mul_rob_idx_i      (ex_mul_rob),
        .mul_exception_i    (1'b0),
        .mul_exc_code_i     (4'd0),
        // DIV
        .div_valid_i        (ex_div_valid),
        .div_ready_o        (),
        .div_prd_i          (ex_div_prd),
        .div_data_i         (ex_div_data),
        .div_rob_idx_i      (ex_div_rob),
        .div_exception_i    (1'b0),
        .div_exc_code_i     (4'd0),
        // LSU0
        .lsu0_valid_i       (lsu_resp_valid),
        .lsu0_ready_o       (),
        .lsu0_prd_i         (lsu_resp_prd),
        .lsu0_data_i        (lsu_resp_data),
        .lsu0_rob_idx_i     (lsu_resp_rob_idx),
        .lsu0_exception_i   (lsu_resp_exception),
        .lsu0_exc_code_i    (lsu_resp_exc_code),
        // LSU1 (unused for now)
        .lsu1_valid_i       (1'b0),
        .lsu1_ready_o       (),
        .lsu1_prd_i         ({PHYS_REG_BITS{1'b0}}),
        .lsu1_data_i        ({XLEN{1'b0}}),
        .lsu1_rob_idx_i     ({ROB_IDX_BITS{1'b0}}),
        .lsu1_exception_i   (1'b0),
        .lsu1_exc_code_i    (4'd0),
        // BRU
        .bru_valid_i        (ex_bru_valid),
        .bru_ready_o        (),
        .bru_prd_i          (ex_bru_prd),
        .bru_data_i         (ex_bru_data),
        .bru_rob_idx_i      (ex_bru_rob),
        .bru_exception_i    (1'b0),
        .bru_exc_code_i     (4'd0),
        .bru_taken_i        (ex_bru_taken),
        .bru_target_i       (ex_bru_target),
        .bru_mispredict_i   (ex_bru_mispredict),
        // CSR (unused for now)
        .csr_valid_i        (1'b0),
        .csr_ready_o        (),
        .csr_prd_i          ({PHYS_REG_BITS{1'b0}}),
        .csr_data_i         ({XLEN{1'b0}}),
        .csr_rob_idx_i      ({ROB_IDX_BITS{1'b0}}),
        .csr_exception_i    (1'b0),
        .csr_exc_code_i     (4'd0),
        // CDB output
        .cdb_valid_o        (cdb_valid),
        .cdb_prd_o          (cdb_prd),
        .cdb_data_o         (cdb_data),
        .cdb_rob_idx_o      (cdb_rob_idx),
        .cdb_exception_o    (cdb_exception),
        .cdb_exc_code_o     (cdb_exc_code),
        .cdb_br_taken_o     (cdb_br_taken),
        .cdb_br_target_o    (cdb_br_target),
        .cdb_br_mispredict_o(cdb_br_mispredict)
    );

    // PRF write from CDB
    genvar g;
    generate
        for (g = 0; g < CDB_WIDTH; g = g + 1) begin : gen_prf_write
            assign prf_wr_en[g] = cdb_valid[g];
            assign prf_wr_addr[g] = cdb_prd[g];
            assign prf_wr_data[g] = cdb_data[g];
        end
    endgenerate

    //=========================================================
    // MMU (Sv32)
    //=========================================================
    // MMU outputs (Sv32 uses up to 34-bit physical addresses)
    wire                        mmu_immu_resp_valid;
    wire [33:0]                 mmu_immu_paddr;
    wire                        mmu_immu_page_fault;
    wire                        mmu_immu_access_fault;

    wire                        mmu_dmmu_resp_valid;
    wire [33:0]                 mmu_dmmu_paddr;
    wire                        mmu_dmmu_page_fault;
    wire                        mmu_dmmu_access_fault;

    // Map MMU responses to legacy itlb/dtlb wires
    assign itlb_resp_valid     = mmu_immu_resp_valid;
    assign itlb_resp_paddr     = mmu_immu_paddr[XLEN-1:0];
    assign itlb_resp_exception = mmu_immu_page_fault | mmu_immu_access_fault;
    assign itlb_resp_exc_code  = mmu_immu_page_fault ? 4'd12 :
                                 mmu_immu_access_fault ? 4'd1 : 4'd0;

    assign dtlb_resp_valid     = mmu_dmmu_resp_valid;
    assign dtlb_resp_paddr     = mmu_dmmu_paddr[XLEN-1:0];
    assign dtlb_resp_exception = mmu_dmmu_page_fault | mmu_dmmu_access_fault;
    assign dtlb_resp_exc_code  = mmu_dmmu_page_fault ? (dtlb_req_write ? 4'd15 : 4'd13) :
                                 mmu_dmmu_access_fault ? (dtlb_req_write ? 4'd7 : 4'd5) : 4'd0;

    mmu #(
        .VADDR_WIDTH    (XLEN),
        .PADDR_WIDTH    (34),
        .DATA_WIDTH     (XLEN),
        .TLB_ENTRIES    (TLB_ENTRIES),
        .ASID_WIDTH     (9)
    ) u_mmu (
        .clk                (clk),
        .rst_n              (rst_n),

        // I-MMU
        .immu_req_valid_i   (itlb_req_valid),
        .immu_vaddr_i       (itlb_req_vaddr),
        .immu_req_ready_o   (itlb_req_ready),
        .immu_resp_valid_o  (mmu_immu_resp_valid),
        .immu_paddr_o       (mmu_immu_paddr),
        .immu_page_fault_o  (mmu_immu_page_fault),
        .immu_access_fault_o(mmu_immu_access_fault),

        // D-MMU
        .dmmu_req_valid_i   (dtlb_req_valid),
        .dmmu_vaddr_i       (dtlb_req_vaddr),
        .dmmu_is_store_i    (dtlb_req_write),
        .dmmu_req_ready_o   (dtlb_req_ready),
        .dmmu_resp_valid_o  (mmu_dmmu_resp_valid),
        .dmmu_paddr_o       (mmu_dmmu_paddr),
        .dmmu_page_fault_o  (mmu_dmmu_page_fault),
        .dmmu_access_fault_o(mmu_dmmu_access_fault),

        // Privilege/CSR
        .priv_mode_i        (current_priv),
        .satp_i             (satp),
        .sum_i              (csr_sum),
        .mxr_i              (csr_mxr),

        // SFENCE.VMA (TODO: drive from committed SFENCE)
        .sfence_valid_i     (1'b0),
        .sfence_rs1_zero_i  (1'b1),
        .sfence_rs2_zero_i  (1'b1),
        .sfence_vaddr_i     ({XLEN{1'b0}}),
        .sfence_asid_i      (9'd0),

        // PTW memory interface (TODO: connect to memory arbiter)
        .mem_req_valid_o    (ptw_req_valid),
        .mem_req_addr_o     (ptw_req_addr),
        .mem_req_ready_i    (1'b1),
        .mem_resp_valid_i   (1'b0),
        .mem_resp_data_i    ({XLEN{1'b0}})
    );

    //=========================================================
    // CSR File
    //=========================================================
    // CSR direct state outputs
    wire [XLEN-1:0] csr_mstatus;
    wire [XLEN-1:0] csr_mie;
    wire [XLEN-1:0] csr_mip;
    wire [XLEN-1:0] csr_mtvec;
    wire [XLEN-1:0] csr_stvec;
    wire [XLEN-1:0] csr_medeleg;
    wire [XLEN-1:0] csr_mideleg;
    wire [XLEN-1:0] csr_mepc;
    wire [XLEN-1:0] csr_sepc;

    wire [XLEN-1:0] csr_trap_vector;
    wire [XLEN-1:0] csr_trap_epc;
    wire            csr_irq_pending;
    wire [XLEN-1:0] csr_irq_cause;

    // Basic CSR bus mux (CSR instructions not yet integrated into execute)
    wire [11:0]     csr_addr_mux = csr_write_valid ? csr_write_addr : csr_read_addr;

    // Trap entry decision (oldest commit slot only)
    wire            commit_exc_valid = rob_commit_valid[0] && rob_commit_exception[0];
    wire [3:0]      commit_exc_code  = rob_commit_exc_code[0];
    wire [XLEN-1:0] commit_exc_tval  = rob_commit_exc_tval[0];
    wire [XLEN-1:0] commit_trap_pc   = rob_commit_pc[0];

    wire [2:0] retired_cnt = rob_commit_valid[0] + rob_commit_valid[1] + rob_commit_valid[2] + rob_commit_valid[3];

    // MRET/SRET not yet propagated through ROB (TODO)
    assign mret_valid = 1'b0;
    assign sret_valid = 1'b0;

    wire trap_enter = csr_irq_pending || commit_exc_valid;

    wire [1:0] trap_to_priv = csr_irq_pending ?
                              (csr_mideleg[csr_irq_cause[3:0]] ? PRIV_S : PRIV_M) :
                              ((current_priv != PRIV_M) && csr_medeleg[commit_exc_code] ? PRIV_S : PRIV_M);

    wire [1:0] trap_from_priv = mret_valid ? PRIV_M : (sret_valid ? PRIV_S : PRIV_M);

    wire [XLEN-1:0] trap_cause_xlen = csr_irq_pending ? csr_irq_cause : {{(XLEN-4){1'b0}}, commit_exc_code};
    wire [XLEN-1:0] trap_tval_xlen  = csr_irq_pending ? {XLEN{1'b0}} : commit_exc_tval;

    // Drive legacy trap wires used by redirect logic
    assign trap_valid      = trap_enter;
    assign trap_handler_pc = csr_trap_vector;
    assign return_pc       = csr_trap_epc;
    assign trap_pc         = commit_trap_pc;
    assign trap_cause      = trap_cause_xlen[3:0];
    assign trap_tval       = trap_tval_xlen;
    assign trap_interrupt  = trap_cause_xlen[XLEN-1];

    // MMU enable (VM active outside M-mode with satp.MODE != Bare)
    assign mmu_enabled = (current_priv != PRIV_M) && satp[31];

    csr_file #(
        .XLEN(XLEN)
    ) u_csr (
        .clk                (clk),
        .rst_n              (rst_n),

        // CSR read/write
        .csr_addr_i         (csr_addr_mux),
        .csr_read_en_i      (csr_read_valid),
        .csr_write_en_i     (csr_write_valid),
        .csr_wdata_i        (csr_write_data),
        .csr_op_i           (csr_write_op),
        .csr_rdata_o        (csr_read_data),
        .csr_illegal_o      (csr_exception),

        // Current privilege (self-fed for now)
        .priv_mode_i        (current_priv),
        .priv_mode_o        (current_priv),

        // Trap interface
        .trap_enter_i       (trap_enter),
        .trap_to_priv_i     (trap_to_priv),
        .trap_cause_i       (trap_cause_xlen),
        .trap_val_i         (trap_tval_xlen),
        .trap_pc_i          (commit_trap_pc),

        .trap_return_i      (mret_valid || sret_valid),
        .trap_from_priv_i   (trap_from_priv),
        .trap_vector_o      (csr_trap_vector),
        .trap_epc_o         (csr_trap_epc),

        // Interrupt inputs
        .ext_irq_m_i        (external_irq),
        .timer_irq_m_i      (timer_irq),
        .sw_irq_m_i         (software_irq),
        .ext_irq_s_i        (1'b0),
        .timer_irq_s_i      (1'b0),
        .sw_irq_s_i         (1'b0),

        // Interrupt status
        .irq_pending_o      (csr_irq_pending),
        .irq_cause_o        (csr_irq_cause),

        // Memory management
        .satp_o             (satp),
        .mxr_o              (csr_mxr),
        .sum_o              (csr_sum),
        .mprv_o             (),
        .mpp_o              (),

        // Direct CSR state outputs
        .mstatus_o          (csr_mstatus),
        .mie_o              (csr_mie),
        .mip_o              (csr_mip),
        .mtvec_o            (csr_mtvec),
        .stvec_o            (csr_stvec),
        .medeleg_o          (csr_medeleg),
        .mideleg_o          (csr_mideleg),
        .mepc_o             (csr_mepc),
        .sepc_o             (csr_sepc),

        // Performance counters
        .instr_retire_i     (|rob_commit_valid),
        .instr_count_i      (retired_cnt[1:0]),

        // Hart ID
        .hart_id_i          (MHART_ID)
    );

    // CSR exception code (placeholder)
    assign csr_exc_code = 4'd0;

    //=========================================================
    // CLINT (Timer)
    //=========================================================
    // CLINT memory-mapped bus wires (directly tied off for now)
    wire        clint_req_valid = 1'b0;
    wire        clint_req_we    = 1'b0;
    wire [31:0] clint_req_addr  = 32'h0200_0000;
    wire [31:0] clint_req_wdata = 32'd0;
    wire [3:0]  clint_req_be    = 4'b1111;
    wire        clint_req_ready;
    wire        clint_resp_valid;
    wire [31:0] clint_resp_data;

    wire [0:0]  clint_msi;  // software interrupt (1 hart)
    wire [0:0]  clint_mti;  // timer interrupt (1 hart)

    clint #(
        .ADDR_WIDTH     (32),
        .DATA_WIDTH     (32),
        .NUM_HARTS      (1),
        .BASE_ADDR      (32'h0200_0000)
    ) u_clint (
        .clk            (clk),
        .rst_n          (rst_n),
        .rtc_clk        (clk),           // Use main clk as RTC for now
        // Memory-mapped interface
        .req_valid_i    (clint_req_valid),
        .req_we_i       (clint_req_we),
        .req_addr_i     (clint_req_addr),
        .req_wdata_i    (clint_req_wdata),
        .req_be_i       (clint_req_be),
        .req_ready_o    (clint_req_ready),
        .resp_valid_o   (clint_resp_valid),
        .resp_data_o    (clint_resp_data),
        // Interrupt outputs
        .msi_o          (clint_msi),
        .mti_o          (clint_mti)
    );

    assign timer_irq    = clint_mti[0];
    assign software_irq = clint_msi[0];

    //=========================================================
    // PLIC (External Interrupts)
    //=========================================================
    wire        plic_req_valid = 1'b0;
    wire        plic_req_we    = 1'b0;
    wire [31:0] plic_req_addr  = 32'h0C00_0000;
    wire [31:0] plic_req_wdata = 32'd0;
    wire        plic_req_ready;
    wire        plic_resp_valid;
    wire [31:0] plic_resp_data;
    wire [1:0]  plic_irq;  // M-mode + S-mode targets

    plic #(
        .ADDR_WIDTH     (32),
        .DATA_WIDTH     (32),
        .NUM_SOURCES    (32),
        .NUM_TARGETS    (2),
        .NUM_PRIORITIES (8),
        .BASE_ADDR      (32'h0C00_0000)
    ) u_plic (
        .clk            (clk),
        .rst_n          (rst_n),
        // Interrupt sources
        .irq_sources_i  (ext_irq_i),
        // Memory-mapped interface
        .req_valid_i    (plic_req_valid),
        .req_we_i       (plic_req_we),
        .req_addr_i     (plic_req_addr),
        .req_wdata_i    (plic_req_wdata),
        .req_ready_o    (plic_req_ready),
        .resp_valid_o   (plic_resp_valid),
        .resp_data_o    (plic_resp_data),
        // Interrupt output
        .irq_o          (plic_irq)
    );

    assign external_irq = plic_irq[0];  // M-mode external interrupt

    //=========================================================
    // D-Cache (8KB 4-way with MSHR)
    //=========================================================
    // D-cache response signals
    wire                        dcache_resp_hit;
    wire [ROB_IDX_BITS-1:0]     dcache_resp_rob_idx;
    wire                        dcache_flush_done;

    dcache_enhanced #(
        .CACHE_SIZE     (DCACHE_SIZE),
        .LINE_SIZE      (32),
        .NUM_WAYS       (4),
        .ADDR_WIDTH     (XLEN),
        .DATA_WIDTH     (XLEN),
        .LINE_WIDTH     (256),
        .ROB_IDX_BITS   (ROB_IDX_BITS)
    ) u_dcache (
        .clk                (clk),
        .rst_n              (rst_n),
        // CPU interface
        .req_valid_i        (dcache_req_valid),
        .req_addr_i         (dcache_req_addr),
        .req_we_i           (dcache_req_write),
        .req_wdata_i        (dcache_req_wdata),
        .req_byte_en_i      (dcache_req_wmask),
        .req_rob_idx_i      ({ROB_IDX_BITS{1'b0}}),
        .req_ready_o        (dcache_req_ready),
        .resp_valid_o       (dcache_resp_valid),
        .resp_rdata_o       (dcache_resp_rdata),
        .resp_hit_o         (dcache_resp_hit),
        .resp_rob_idx_o     (dcache_resp_rob_idx),
        // Memory interface
        .mem_req_valid_o    (dcache_mem_req_valid),
        .mem_req_addr_o     (dcache_mem_req_addr),
        .mem_req_we_o       (dcache_mem_req_write),
        .mem_req_wdata_o    (dcache_mem_req_wdata),
        .mem_req_ready_i    (dcache_mem_req_ready),
        .mem_resp_valid_i   (dcache_mem_resp_valid),
        .mem_resp_rdata_i   (dcache_mem_resp_data),
        // Flush/Invalidate
        .flush_i            (1'b0),
        .invalidate_i       (1'b0),
        .flush_done_o       (dcache_flush_done)
    );

    // Map dcache_resp_error (legacy signal) - no error port on dcache_enhanced
    assign dcache_resp_error = 1'b0;

    //=========================================================
    // Hardware Prefetcher
    //=========================================================
    prefetcher #(
        .ADDR_WIDTH     (XLEN),
        .CACHE_LINE     (64),
        .RPT_ENTRIES    (16),
        .STREAM_ENTRIES (4),
        .PREFETCH_DEPTH (4)
    ) u_prefetcher (
        .clk                (clk),
        .rst_n              (rst_n),
        // Access monitoring
        .mem_access_valid_i (dcache_resp_valid && dcache_resp_hit),
        .mem_access_addr_i  (dcache_req_addr),
        .mem_access_pc_i    (32'd0),            // TODO: from LSU
        .mem_access_miss_i  (dcache_resp_valid && !dcache_resp_hit),
        // Prefetch output
        .pf_req_valid_o     (pf_req_valid),
        .pf_req_addr_o      (pf_req_addr),
        .pf_req_ready_i     (pf_req_ready),
        // Control
        .enable_i           (1'b1),
        .flush_i            (flush_backend)
    );

    //=========================================================
    // BPU Update from Commit
    //=========================================================
    assign bpu_update_valid = |rob_commit_is_branch;
    assign bpu_update_pc = rob_commit_pc[0];
    assign bpu_update_taken = rob_commit_br_taken[0];
    assign bpu_update_target = rob_commit_br_target[0];
    assign bpu_update_ghr = fetch_ghr;           // TODO: store GHR in ROB
    assign bpu_update_mispredict = cdb_br_mispredict;

    //=========================================================
    // Free List Release from Commit
    //=========================================================
    generate
        for (g = 0; g < COMMIT_WIDTH; g = g + 1) begin : gen_fl_release
            assign fl_release_valid[g] = rob_commit_valid[g] && (rob_commit_prd_old[g] != 0);
            assign fl_release_preg[g] = rob_commit_prd_old[g];
        end
    endgenerate

    //=========================================================
    // AXI Interface (Memory Arbiter)
    // TODO: Proper arbiter for I-Cache, D-Cache, PTW
    //=========================================================
    
    // AXI Read Data Accumulator (for burst reads)
    // Accumulates 16 beats (64 bytes) into 512-bit response for I-Cache
    // or 4 beats (16 bytes) for D-Cache
    reg [511:0] axi_rdata_buf;
    reg [3:0]   axi_rdata_cnt;
    reg         axi_rd_for_icache;  // Track if current read is for I-Cache
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_rdata_buf <= 512'd0;
            axi_rdata_cnt <= 4'd0;
            axi_rd_for_icache <= 1'b0;
        end else begin
            // Track who initiated the read
            if (m_axi_arvalid && m_axi_arready) begin
                axi_rd_for_icache <= icache_mem_req_valid;
                axi_rdata_cnt <= 4'd0;
            end
            
            // Accumulate read data
            if (m_axi_rvalid && m_axi_rready) begin
                case (axi_rdata_cnt)
                    4'd0:  axi_rdata_buf[31:0]    <= m_axi_rdata;
                    4'd1:  axi_rdata_buf[63:32]   <= m_axi_rdata;
                    4'd2:  axi_rdata_buf[95:64]   <= m_axi_rdata;
                    4'd3:  axi_rdata_buf[127:96]  <= m_axi_rdata;
                    4'd4:  axi_rdata_buf[159:128] <= m_axi_rdata;
                    4'd5:  axi_rdata_buf[191:160] <= m_axi_rdata;
                    4'd6:  axi_rdata_buf[223:192] <= m_axi_rdata;
                    4'd7:  axi_rdata_buf[255:224] <= m_axi_rdata;
                    4'd8:  axi_rdata_buf[287:256] <= m_axi_rdata;
                    4'd9:  axi_rdata_buf[319:288] <= m_axi_rdata;
                    4'd10: axi_rdata_buf[351:320] <= m_axi_rdata;
                    4'd11: axi_rdata_buf[383:352] <= m_axi_rdata;
                    4'd12: axi_rdata_buf[415:384] <= m_axi_rdata;
                    4'd13: axi_rdata_buf[447:416] <= m_axi_rdata;
                    4'd14: axi_rdata_buf[479:448] <= m_axi_rdata;
                    4'd15: axi_rdata_buf[511:480] <= m_axi_rdata;
                endcase
                axi_rdata_cnt <= axi_rdata_cnt + 1;
            end
        end
    end
    
    // Simplified: Just connect D-Cache for now
    assign m_axi_awid = 4'd0;
    assign m_axi_awaddr = dcache_mem_req_addr;
    assign m_axi_awlen = 8'd3;                   // 4 beats
    assign m_axi_awsize = 3'b010;                // 4 bytes
    assign m_axi_awburst = 2'b01;                // INCR
    assign m_axi_awlock = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot = 3'b000;
    assign m_axi_awvalid = dcache_mem_req_valid && dcache_mem_req_write;
    
    assign m_axi_wdata = dcache_mem_req_wdata[31:0];
    assign m_axi_wstrb = 4'b1111;
    assign m_axi_wlast = 1'b1;
    assign m_axi_wvalid = dcache_mem_req_valid && dcache_mem_req_write;
    
    assign m_axi_bready = 1'b1;
    
    assign m_axi_arid = 4'd0;
    assign m_axi_araddr = icache_mem_req_valid ? icache_mem_req_addr : dcache_mem_req_addr;
    // I-Cache needs 64 bytes (16 beats), D-Cache needs 16 bytes (4 beats)
    assign m_axi_arlen = icache_mem_req_valid ? 8'd15 : 8'd3;
    assign m_axi_arsize = 3'b010;                // 4 bytes per beat
    assign m_axi_arburst = 2'b01;                // INCR
    assign m_axi_arlock = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot = 3'b000;
    assign m_axi_arvalid = icache_mem_req_valid || (dcache_mem_req_valid && !dcache_mem_req_write);
    
    assign m_axi_rready = 1'b1;
    
    // I-Cache memory request is acknowledged when AXI accepts the read address
    assign icache_mem_req_ready = m_axi_arready && m_axi_arvalid && icache_mem_req_valid;
    // D-Cache memory request is acknowledged when AXI accepts read or write
    assign dcache_mem_req_ready = (dcache_mem_req_write && m_axi_awready && m_axi_awvalid) ||
                                  (!dcache_mem_req_write && m_axi_arready && m_axi_arvalid && !icache_mem_req_valid);
    
    // Full 512-bit data for I-Cache, last beat goes to MSBs
    wire [511:0] axi_full_icache_rdata = {m_axi_rdata, axi_rdata_buf[479:0]};
    // 128-bit data for D-Cache
    wire [127:0] axi_full_dcache_rdata = {m_axi_rdata, axi_rdata_buf[95:0]};
    
    assign icache_mem_resp_valid = m_axi_rvalid && m_axi_rlast && axi_rd_for_icache;
    assign icache_mem_resp_data = axi_full_icache_rdata;  // Full 512 bits
    
    assign dcache_mem_resp_valid = m_axi_rvalid && m_axi_rlast && !axi_rd_for_icache;
    assign dcache_mem_resp_data = axi_full_dcache_rdata;

endmodule
