//==============================================================================
// AGU 精简波形测试 - 覆盖地址计算和对齐检测，约15周期
//==============================================================================
`timescale 1ns/1ps

module tb_agu_wave;
    reg clk, rst_n, valid_i, is_store_i, sign_ext_i;
    reg [31:0] base_i, offset_i, store_data_i;
    reg [1:0] size_i;
    reg [5:0] prd_i;
    reg [4:0] rob_idx_i;
    wire done_o, misaligned_o, is_store_o, sign_ext_o;
    wire [31:0] addr_o, data_o;
    wire [1:0] size_o;
    wire [5:0] result_prd_o;
    wire [4:0] result_rob_idx_o;

    agu_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/agu_wave.vcd");
        $dumpvars(0, tb_agu_wave);
    end

    integer pass = 0, fail = 0;

    task test_agu(input [31:0] base, offset, input [1:0] size, input exp_misalign, input [63:0] name);
        begin
            valid_i = 1; base_i = base; offset_i = offset; size_i = size;
            is_store_i = 0; store_data_i = 0; sign_ext_i = 0; prd_i = 1; rob_idx_i = 0;
            #10; // 等待一个时钟周期
            valid_i = 0;
            #10; // 再等待一个时钟周期，输出有效
            #2;  // 额外延时确保稳定
            if (misaligned_o === exp_misalign) begin
                pass = pass + 1;
                $display("PASS: %s addr=%h misalign=%b", name, addr_o, misaligned_o);
            end else begin
                fail = fail + 1;
                $display("FAIL: %s exp_misalign=%b got=%b", name, exp_misalign, misaligned_o);
            end
            #10; // 等待下一个测试
        end
    endtask

    initial begin
        $display("=== AGU Wave Test ===");
        rst_n = 0; valid_i = 0; is_store_i = 0; base_i = 0; offset_i = 0;
        store_data_i = 0; size_i = 0; sign_ext_i = 0; prd_i = 0; rob_idx_i = 0;
        #20 rst_n = 1; #10;

        // Word aligned access
        test_agu(32'h1000, 32'd0, 2'b10, 0, "WORD_ALIGN");
        // Word misaligned access
        test_agu(32'h1001, 32'd0, 2'b10, 1, "WORD_MISALIGN");
        // Half aligned access
        test_agu(32'h1002, 32'd0, 2'b01, 0, "HALF_ALIGN");
        // Half misaligned access
        test_agu(32'h1001, 32'd0, 2'b01, 1, "HALF_MISALIGN");
        // Byte access (always aligned)
        test_agu(32'h1001, 32'd0, 2'b00, 0, "BYTE");
        // Address calculation: base + offset
        test_agu(32'h1000, 32'd100, 2'b10, 0, "ADDR_CALC");

        // Store with data passthrough
        valid_i = 1; is_store_i = 1; base_i = 32'h2000; offset_i = 32'd4;
        store_data_i = 32'hDEADBEEF; size_i = 2'b10;
        #10; // 等待一个时钟周期
        valid_i = 0;
        #10; // 再等待一个时钟周期
        #2;
        if (addr_o == 32'h2004 && data_o == 32'hDEADBEEF && is_store_o) begin
            pass = pass + 1; $display("PASS: Store data passthrough");
        end else begin
            fail = fail + 1; $display("FAIL: Store data");
        end

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
