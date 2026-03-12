//=================================================================
// Module: lsq
// Description: Load/Store Queue Top Level
//              Integrates Load Queue and Store Queue
//              Memory ordering violation detection
// Requirements: 10.6
//=================================================================

`timescale 1ns/1ps

module lsq #(
    parameter LQ_ENTRIES    = 8,
    parameter SQ_ENTRIES    = 8,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 5,
    parameter PHYS_REG_BITS = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Load allocation interface
    input  wire                     ld_alloc_valid_i,
    output wire                     ld_alloc_ready_o,
    output wire [2:0]               ld_alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  ld_alloc_rob_idx_i,
    input  wire [PHYS_REG_BITS-1:0] ld_alloc_dst_preg_i,
    input  wire [1:0]               ld_alloc_size_i,
    input  wire                     ld_alloc_sign_ext_i,
    
    // Store allocation interface
    input  wire                     st_alloc_valid_i,
    output wire                     st_alloc_ready_o,
    output wire [2:0]               st_alloc_idx_o,
    input  wire [ROB_IDX_BITS-1:0]  st_alloc_rob_idx_i,
    input  wire [1:0]               st_alloc_size_i,
    
    // Load address interface
    input  wire                     ld_addr_valid_i,
    input  wire [2:0]               ld_addr_idx_i,
    input  wire [ADDR_WIDTH-1:0]    ld_addr_i,
    
    // Store address interface
    input  wire                     st_addr_valid_i,
    input  wire [2:0]               st_addr_idx_i,
    input  wire [ADDR_WIDTH-1:0]    st_addr_i,
    
    // Store data interface
    input  wire                     st_data_valid_i,
    input  wire [2:0]               st_data_idx_i,
    input  wire [DATA_WIDTH-1:0]    st_data_i,
    
    // D-Cache interface
    output wire                     dcache_rd_valid_o,
    output wire [ADDR_WIDTH-1:0]    dcache_rd_addr_o,
    input  wire                     dcache_rd_ready_i,
    input  wire                     dcache_rd_resp_valid_i,
    input  wire [DATA_WIDTH-1:0]    dcache_rd_resp_data_i,
    
    output wire                     dcache_wr_valid_o,
    output wire [ADDR_WIDTH-1:0]    dcache_wr_addr_o,
    output wire [DATA_WIDTH-1:0]    dcache_wr_data_o,
    output wire [1:0]               dcache_wr_size_o,
    input  wire                     dcache_wr_ready_i,
    input  wire                     dcache_wr_resp_valid_i,
    
    // Load completion (to CDB)
    output wire                     ld_complete_valid_o,
    output wire [PHYS_REG_BITS-1:0] ld_complete_preg_o,
    output wire [DATA_WIDTH-1:0]    ld_complete_data_o,
    output wire [ROB_IDX_BITS-1:0]  ld_complete_rob_idx_o,
    input  wire                     ld_complete_ready_i,
    
    // Commit interface
    input  wire                     ld_commit_valid_i,
    input  wire [2:0]               ld_commit_idx_i,
    input  wire                     st_commit_valid_i,
    input  wire [2:0]               st_commit_idx_i,
    
    // Flush interface
    input  wire                     flush_i,
    
    // Memory ordering violation
    output wire                     violation_o,
    output wire [ROB_IDX_BITS-1:0]  violation_rob_idx_o
);

    //=========================================================
    // Internal Signals
    //=========================================================
    // LQ to SQ forwarding
    wire        lq_sq_check_valid;
    wire [ADDR_WIDTH-1:0] lq_sq_check_addr;
    wire [1:0]  lq_sq_check_size;
    wire [ROB_IDX_BITS-1:0] lq_sq_check_rob_idx;
    wire        sq_lq_fwd_valid;
    wire [DATA_WIDTH-1:0] sq_lq_fwd_data;
    wire        sq_lq_conflict;
    
    //=========================================================
    // Load Queue Instance
    //=========================================================
    load_queue #(
        .NUM_ENTRIES(LQ_ENTRIES),
        .ENTRY_BITS(3),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_load_queue (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_valid_i      (ld_alloc_valid_i),
        .alloc_ready_o      (ld_alloc_ready_o),
        .alloc_idx_o        (ld_alloc_idx_o),
        .alloc_rob_idx_i    (ld_alloc_rob_idx_i),
        .alloc_dst_preg_i   (ld_alloc_dst_preg_i),
        .alloc_size_i       (ld_alloc_size_i),
        .alloc_sign_ext_i   (ld_alloc_sign_ext_i),
        .addr_valid_i       (ld_addr_valid_i),
        .addr_idx_i         (ld_addr_idx_i),
        .addr_i             (ld_addr_i),
        .sq_check_valid_o   (lq_sq_check_valid),
        .sq_check_addr_o    (lq_sq_check_addr),
        .sq_check_size_o    (lq_sq_check_size),
        .sq_check_rob_idx_o (lq_sq_check_rob_idx),
        .sq_fwd_valid_i     (sq_lq_fwd_valid),
        .sq_fwd_data_i      (sq_lq_fwd_data),
        .sq_conflict_i      (sq_lq_conflict),
        .cache_req_valid_o  (dcache_rd_valid_o),
        .cache_req_addr_o   (dcache_rd_addr_o),
        .cache_req_ready_i  (dcache_rd_ready_i),
        .cache_resp_valid_i (dcache_rd_resp_valid_i),
        .cache_resp_data_i  (dcache_rd_resp_data_i),
        .complete_valid_o   (ld_complete_valid_o),
        .complete_preg_o    (ld_complete_preg_o),
        .complete_data_o    (ld_complete_data_o),
        .complete_rob_idx_o (ld_complete_rob_idx_o),
        .complete_ready_i   (ld_complete_ready_i),
        .commit_valid_i     (ld_commit_valid_i),
        .commit_idx_i       (ld_commit_idx_i),
        .flush_i            (flush_i)
    );
    
    //=========================================================
    // Store Queue Instance
    //=========================================================
    store_queue #(
        .NUM_ENTRIES(SQ_ENTRIES),
        .ENTRY_BITS(3),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ROB_IDX_BITS(ROB_IDX_BITS)
    ) u_store_queue (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_valid_i      (st_alloc_valid_i),
        .alloc_ready_o      (st_alloc_ready_o),
        .alloc_idx_o        (st_alloc_idx_o),
        .alloc_rob_idx_i    (st_alloc_rob_idx_i),
        .alloc_size_i       (st_alloc_size_i),
        .addr_valid_i       (st_addr_valid_i),
        .addr_idx_i         (st_addr_idx_i),
        .addr_i             (st_addr_i),
        .data_valid_i       (st_data_valid_i),
        .data_idx_i         (st_data_idx_i),
        .data_i             (st_data_i),
        .lq_check_valid_i   (lq_sq_check_valid),
        .lq_check_addr_i    (lq_sq_check_addr),
        .lq_check_size_i    (lq_sq_check_size),
        .lq_check_rob_idx_i (lq_sq_check_rob_idx),
        .lq_fwd_valid_o     (sq_lq_fwd_valid),
        .lq_fwd_data_o      (sq_lq_fwd_data),
        .lq_conflict_o      (sq_lq_conflict),
        .cache_req_valid_o  (dcache_wr_valid_o),
        .cache_req_addr_o   (dcache_wr_addr_o),
        .cache_req_data_o   (dcache_wr_data_o),
        .cache_req_size_o   (dcache_wr_size_o),
        .cache_req_ready_i  (dcache_wr_ready_i),
        .cache_resp_valid_i (dcache_wr_resp_valid_i),
        .commit_valid_i     (st_commit_valid_i),
        .commit_idx_i       (st_commit_idx_i),
        .flush_i            (flush_i)
    );
    
    //=========================================================
    // Memory Ordering Violation Detection
    //=========================================================
    // Simplified: no violation detection in this implementation
    // A full implementation would track store addresses and compare
    // with speculatively executed loads
    assign violation_o = 1'b0;
    assign violation_rob_idx_o = 0;

endmodule
