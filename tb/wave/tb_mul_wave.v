//==============================================================================
// MUL 精简波形测试 - 覆盖4种乘法操作，约20周期
//==============================================================================
`timescale 1ns/1ps
`include "cpu_defines.vh"

module tb_mul_wave;
    reg clk, rst_n, valid_i, flush_i;
    reg [`MUL_OP_WIDTH-1:0] op_i;
    reg [`XLEN-1:0] src1_i, src2_i;
    reg [`PHYS_REG_BITS-1:0] prd_i;
    reg [`ROB_IDX_BITS-1:0] rob_idx_i;
    wire valid_o, busy_o;
    wire [`XLEN-1:0] result_o;
    wire [`PHYS_REG_BITS-1:0] prd_o;
    wire [`ROB_IDX_BITS-1:0] rob_idx_o;

    mul_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/mul_wave.vcd");
        $dumpvars(0, tb_mul_wave);
    end

    integer pass = 0, fail = 0;

    task test_mul(input [`MUL_OP_WIDTH-1:0] op, input [`XLEN-1:0] s1, s2, exp, input [63:0] name);
        begin
            @(posedge clk);
            op_i = op; src1_i = s1; src2_i = s2; valid_i = 1; prd_i = 1; rob_idx_i = 0;
            @(posedge clk); valid_i = 0;
            repeat(3) @(posedge clk); // 3-cycle latency
            if (result_o === exp) begin pass = pass + 1; $display("PASS: %s = %h", name, result_o); end
            else begin fail = fail + 1; $display("FAIL: %s exp=%h got=%h", name, exp, result_o); end
        end
    endtask

    initial begin
        $display("=== MUL Wave Test (4 ops) ===");
        rst_n = 0; valid_i = 0; flush_i = 0; op_i = 0; src1_i = 0; src2_i = 0; prd_i = 0; rob_idx_i = 0;
        #20 rst_n = 1; #10;

        // MUL: 7 * 6 = 42
        test_mul(`MUL_OP_MUL, 32'd7, 32'd6, 32'd42, "MUL");
        // MULH: (-2) * 3 high bits
        test_mul(`MUL_OP_MULH, 32'hFFFFFFFE, 32'd3, 32'hFFFFFFFF, "MULH");
        // MULHSU: (-1) * 2 high bits
        test_mul(`MUL_OP_MULHSU, 32'hFFFFFFFF, 32'd2, 32'hFFFFFFFF, "MULHSU");
        // MULHU: 0x10000 * 0x10000 high bits
        test_mul(`MUL_OP_MULHU, 32'h00010000, 32'h00010000, 32'h00000001, "MULHU");

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
