//==============================================================================
// DIV 精简波形测试 - 覆盖4种除法操作+边界情况，约150周期
//==============================================================================
`timescale 1ns/1ps

module tb_div_wave;
    reg clk, rst_n, valid_i;
    reg [1:0] op_i;
    reg [31:0] src1_i, src2_i;
    reg [5:0] prd_i;
    reg [4:0] rob_idx_i;
    wire done_o, busy_o;
    wire [31:0] result_o;
    wire [5:0] result_prd_o;
    wire [4:0] result_rob_idx_o;

    div_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/div_wave.vcd");
        $dumpvars(0, tb_div_wave);
    end

    integer pass = 0, fail = 0;

    task test_div(input [1:0] op, input [31:0] s1, s2, exp, input [63:0] name);
        begin
            @(posedge clk);
            op_i = op; src1_i = s1; src2_i = s2; valid_i = 1; prd_i = 1; rob_idx_i = 0;
            @(posedge clk); valid_i = 0;
            wait(done_o); @(posedge clk);
            if (result_o === exp) begin pass = pass + 1; $display("PASS: %s = %h", name, result_o); end
            else begin fail = fail + 1; $display("FAIL: %s exp=%h got=%h", name, exp, result_o); end
        end
    endtask

    initial begin
        $display("=== DIV Wave Test ===");
        rst_n = 0; valid_i = 0; op_i = 0; src1_i = 0; src2_i = 0; prd_i = 0; rob_idx_i = 0;
        #20 rst_n = 1; #10;

        // DIV: 20 / 3 = 6
        test_div(2'b00, 32'd20, 32'd3, 32'd6, "DIV");
        // DIVU: 20 / 3 = 6
        test_div(2'b01, 32'd20, 32'd3, 32'd6, "DIVU");
        // REM: 20 % 3 = 2
        test_div(2'b10, 32'd20, 32'd3, 32'd2, "REM");
        // REMU: 20 % 3 = 2
        test_div(2'b11, 32'd20, 32'd3, 32'd2, "REMU");
        // DIV by zero
        test_div(2'b00, 32'd10, 32'd0, 32'hFFFFFFFF, "DIV_ZERO");

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
