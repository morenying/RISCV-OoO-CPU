//==============================================================================
// CDB 精简波形测试 - 覆盖优先级仲裁，约15周期
//==============================================================================
`timescale 1ns/1ps

module tb_cdb_wave;
    reg clk, rst_n;
    // Source 0-5 inputs
    reg src0_valid_i, src1_valid_i, src2_valid_i, src3_valid_i, src4_valid_i, src5_valid_i;
    wire src0_ready_o, src1_ready_o, src2_ready_o, src3_ready_o, src4_ready_o, src5_ready_o;
    reg [5:0] src0_preg_i, src1_preg_i, src2_preg_i, src3_preg_i, src4_preg_i, src5_preg_i;
    reg [31:0] src0_data_i, src1_data_i, src2_data_i, src3_data_i, src4_data_i, src5_data_i;
    reg [4:0] src0_rob_idx_i, src1_rob_idx_i, src2_rob_idx_i, src3_rob_idx_i, src4_rob_idx_i, src5_rob_idx_i;
    reg src0_exception_i, src1_exception_i, src2_exception_i, src3_exception_i, src4_exception_i, src5_exception_i;
    reg [3:0] src0_exc_code_i, src1_exc_code_i, src2_exc_code_i, src3_exc_code_i, src4_exc_code_i, src5_exc_code_i;
    reg src5_branch_taken_i;
    reg [31:0] src5_branch_target_i;
    // CDB output
    wire cdb_valid_o, cdb_exception_o, cdb_branch_taken_o;
    wire [5:0] cdb_preg_o;
    wire [31:0] cdb_data_o, cdb_branch_target_o;
    wire [4:0] cdb_rob_idx_o;
    wire [3:0] cdb_exc_code_o;
    wire [2:0] cdb_src_id_o;

    cdb dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/cdb_wave.vcd");
        $dumpvars(0, tb_cdb_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== CDB Wave Test ===");
        rst_n = 0;
        src0_valid_i = 0; src1_valid_i = 0; src2_valid_i = 0;
        src3_valid_i = 0; src4_valid_i = 0; src5_valid_i = 0;
        src0_preg_i = 0; src1_preg_i = 0; src2_preg_i = 0;
        src3_preg_i = 0; src4_preg_i = 0; src5_preg_i = 0;
        src0_data_i = 0; src1_data_i = 0; src2_data_i = 0;
        src3_data_i = 0; src4_data_i = 0; src5_data_i = 0;
        src0_rob_idx_i = 0; src1_rob_idx_i = 0; src2_rob_idx_i = 0;
        src3_rob_idx_i = 0; src4_rob_idx_i = 0; src5_rob_idx_i = 0;
        src0_exception_i = 0; src1_exception_i = 0; src2_exception_i = 0;
        src3_exception_i = 0; src4_exception_i = 0; src5_exception_i = 0;
        src0_exc_code_i = 0; src1_exc_code_i = 0; src2_exc_code_i = 0;
        src3_exc_code_i = 0; src4_exc_code_i = 0; src5_exc_code_i = 0;
        src5_branch_taken_i = 0; src5_branch_target_i = 0;
        #20 rst_n = 1; #10;

        // Test priority: src0 wins over src1
        @(posedge clk);
        src0_valid_i = 1; src0_preg_i = 32; src0_data_i = 32'hAAAA;
        src1_valid_i = 1; src1_preg_i = 33; src1_data_i = 32'hBBBB;
        @(posedge clk);
        @(posedge clk);
        if (cdb_src_id_o == 3'd0 && cdb_data_o == 32'hAAAA) begin
            pass = pass + 1; $display("PASS: src0 wins priority");
        end else begin
            fail = fail + 1; $display("FAIL: Priority src0");
        end

        // src0 done, src1 should win
        @(posedge clk);
        src0_valid_i = 0;
        @(posedge clk);
        @(posedge clk);
        if (cdb_src_id_o == 3'd1 && cdb_data_o == 32'hBBBB) begin
            pass = pass + 1; $display("PASS: src1 wins after src0");
        end else begin
            fail = fail + 1; $display("FAIL: Priority src1");
        end
        src1_valid_i = 0;

        // Test branch unit (src5) with branch info
        @(posedge clk);
        src5_valid_i = 1; src5_preg_i = 40; src5_data_i = 32'h1004;
        src5_branch_taken_i = 1; src5_branch_target_i = 32'h2000;
        @(posedge clk);
        @(posedge clk);
        if (cdb_branch_taken_o && cdb_branch_target_o == 32'h2000) begin
            pass = pass + 1; $display("PASS: Branch info passed");
        end else begin
            fail = fail + 1; $display("FAIL: Branch info");
        end
        src5_valid_i = 0;

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
