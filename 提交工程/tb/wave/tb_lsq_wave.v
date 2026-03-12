//==============================================================================
// LSQ 精简波形测试 - 覆盖Load/Store分配和转发，约30周期
//==============================================================================
`timescale 1ns/1ps

module tb_lsq_wave;
    reg clk, rst_n, flush_i;
    // Load allocation
    reg ld_alloc_valid_i;
    reg [4:0] ld_alloc_rob_idx_i;
    reg [5:0] ld_alloc_dst_preg_i;
    reg [1:0] ld_alloc_size_i;
    reg ld_alloc_sign_ext_i;
    wire ld_alloc_ready_o;
    wire [2:0] ld_alloc_idx_o;
    // Store allocation
    reg st_alloc_valid_i;
    reg [4:0] st_alloc_rob_idx_i;
    reg [1:0] st_alloc_size_i;
    wire st_alloc_ready_o;
    wire [2:0] st_alloc_idx_o;
    // Load address
    reg ld_addr_valid_i;
    reg [2:0] ld_addr_idx_i;
    reg [31:0] ld_addr_i;
    // Store address/data
    reg st_addr_valid_i, st_data_valid_i;
    reg [2:0] st_addr_idx_i, st_data_idx_i;
    reg [31:0] st_addr_i, st_data_i;
    // D-Cache interface (stub)
    wire dcache_rd_valid_o, dcache_wr_valid_o;
    wire [31:0] dcache_rd_addr_o, dcache_wr_addr_o, dcache_wr_data_o;
    wire [1:0] dcache_wr_size_o;
    reg dcache_rd_ready_i, dcache_rd_resp_valid_i, dcache_wr_ready_i, dcache_wr_resp_valid_i;
    reg [31:0] dcache_rd_resp_data_i;
    // Load completion
    wire ld_complete_valid_o;
    wire [5:0] ld_complete_preg_o;
    wire [31:0] ld_complete_data_o;
    wire [4:0] ld_complete_rob_idx_o;
    reg ld_complete_ready_i;
    // Commit
    reg ld_commit_valid_i, st_commit_valid_i;
    reg [2:0] ld_commit_idx_i, st_commit_idx_i;
    // Violation
    wire violation_o;
    wire [4:0] violation_rob_idx_o;

    lsq dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/lsq_wave.vcd");
        $dumpvars(0, tb_lsq_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== LSQ Wave Test ===");
        rst_n = 0; flush_i = 0;
        ld_alloc_valid_i = 0; st_alloc_valid_i = 0;
        ld_addr_valid_i = 0; st_addr_valid_i = 0; st_data_valid_i = 0;
        dcache_rd_ready_i = 1; dcache_rd_resp_valid_i = 0; dcache_rd_resp_data_i = 0;
        dcache_wr_ready_i = 1; dcache_wr_resp_valid_i = 0;
        ld_complete_ready_i = 1;
        ld_commit_valid_i = 0; st_commit_valid_i = 0;
        ld_alloc_rob_idx_i = 0; ld_alloc_dst_preg_i = 0; ld_alloc_size_i = 2'b10; ld_alloc_sign_ext_i = 0;
        st_alloc_rob_idx_i = 0; st_alloc_size_i = 2'b10;
        ld_addr_idx_i = 0; ld_addr_i = 0;
        st_addr_idx_i = 0; st_addr_i = 0; st_data_idx_i = 0; st_data_i = 0;
        ld_commit_idx_i = 0; st_commit_idx_i = 0;
        #20 rst_n = 1; #10;

        // Allocate a store
        @(posedge clk);
        st_alloc_valid_i = 1; st_alloc_rob_idx_i = 0;
        @(posedge clk);
        st_alloc_valid_i = 0;
        if (st_alloc_ready_o) begin
            pass = pass + 1; $display("PASS: Store allocated idx=%d", st_alloc_idx_o);
        end else begin
            fail = fail + 1; $display("FAIL: Store allocation");
        end

        // Provide store address and data
        @(posedge clk);
        st_addr_valid_i = 1; st_addr_idx_i = 0; st_addr_i = 32'h1000;
        st_data_valid_i = 1; st_data_idx_i = 0; st_data_i = 32'hDEADBEEF;
        @(posedge clk);
        st_addr_valid_i = 0; st_data_valid_i = 0;

        // Allocate a load
        @(posedge clk);
        ld_alloc_valid_i = 1; ld_alloc_rob_idx_i = 1; ld_alloc_dst_preg_i = 32;
        @(posedge clk);
        ld_alloc_valid_i = 0;

        // Provide load address (same as store - should forward)
        @(posedge clk);
        ld_addr_valid_i = 1; ld_addr_idx_i = 0; ld_addr_i = 32'h1000;
        @(posedge clk);
        ld_addr_valid_i = 0;

        repeat(5) @(posedge clk);

        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
