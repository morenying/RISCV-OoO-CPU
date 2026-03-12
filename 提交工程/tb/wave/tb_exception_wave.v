//==============================================================================
// Exception Unit 精简波形测试 - 覆盖各种异常类型，约20周期
//==============================================================================
`timescale 1ns/1ps

module tb_exception_wave;
    reg clk, rst_n;
    // Exception sources
    reg illegal_instr_i, instr_misalign_i, load_misalign_i, store_misalign_i;
    reg ecall_i, ebreak_i, mret_i;
    // Exception info
    reg [31:0] exc_pc_i, exc_tval_i;
    // Branch misprediction
    reg branch_mispredict_i;
    reg [31:0] branch_target_i;
    // CSR interface
    reg [31:0] mtvec_i, mepc_i;
    reg mie_i, irq_pending_i;
    // Outputs
    wire exception_o, mret_o, flush_o, redirect_valid_o;
    wire [3:0] exc_code_o;
    wire [31:0] exc_pc_o, exc_tval_o, redirect_pc_o;

    exception_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/exception_wave.vcd");
        $dumpvars(0, tb_exception_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== Exception Unit Wave Test ===");
        rst_n = 0;
        illegal_instr_i = 0; instr_misalign_i = 0; load_misalign_i = 0; store_misalign_i = 0;
        ecall_i = 0; ebreak_i = 0; mret_i = 0;
        exc_pc_i = 32'h1000; exc_tval_i = 0;
        branch_mispredict_i = 0; branch_target_i = 0;
        mtvec_i = 32'h100; mepc_i = 32'h2000; mie_i = 0; irq_pending_i = 0;
        #20 rst_n = 1; #10;

        // Test illegal instruction
        @(posedge clk);
        illegal_instr_i = 1;
        #1;
        if (exception_o && exc_code_o == 4'd2) begin
            pass = pass + 1; $display("PASS: Illegal instr exc_code=2");
        end else begin
            fail = fail + 1; $display("FAIL: Illegal instr");
        end
        @(posedge clk);
        illegal_instr_i = 0;

        // Test ECALL
        @(posedge clk);
        ecall_i = 1;
        #1;
        if (exception_o && exc_code_o == 4'd11) begin
            pass = pass + 1; $display("PASS: ECALL exc_code=11");
        end else begin
            fail = fail + 1; $display("FAIL: ECALL");
        end
        @(posedge clk);
        ecall_i = 0;

        // Test load misalign
        @(posedge clk);
        load_misalign_i = 1;
        #1;
        if (exception_o && exc_code_o == 4'd4) begin
            pass = pass + 1; $display("PASS: Load misalign exc_code=4");
        end else begin
            fail = fail + 1; $display("FAIL: Load misalign");
        end
        @(posedge clk);
        load_misalign_i = 0;

        // Test MRET
        @(posedge clk);
        mret_i = 1;
        #1;
        if (mret_o && redirect_pc_o == mepc_i) begin
            pass = pass + 1; $display("PASS: MRET redirect to mepc");
        end else begin
            fail = fail + 1; $display("FAIL: MRET");
        end
        @(posedge clk);
        mret_i = 0;

        // Test priority: instr_misalign > illegal
        @(posedge clk);
        instr_misalign_i = 1; illegal_instr_i = 1;
        #1;
        if (exc_code_o == 4'd0) begin
            pass = pass + 1; $display("PASS: Priority instr_misalign > illegal");
        end else begin
            fail = fail + 1; $display("FAIL: Exception priority");
        end
        @(posedge clk);
        instr_misalign_i = 0; illegal_instr_i = 0;

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
