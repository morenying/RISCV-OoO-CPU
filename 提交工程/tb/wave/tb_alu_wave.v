//==============================================================================
// ALU 精简波形测试 - 覆盖全部12种操作，约15周期
//==============================================================================
`timescale 1ns/1ps
`include "cpu_defines.vh"

module tb_alu_wave;
    reg clk, rst_n, valid_i;
    reg [`ALU_OP_WIDTH-1:0] op_i;
    reg [`XLEN-1:0] src1_i, src2_i, pc_i;
    reg [`PHYS_REG_BITS-1:0] prd_i;
    reg [`ROB_IDX_BITS-1:0] rob_idx_i;
    wire valid_o;
    wire [`XLEN-1:0] result_o;
    wire [`PHYS_REG_BITS-1:0] prd_o;
    wire [`ROB_IDX_BITS-1:0] rob_idx_o;

    alu_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    // 波形输出
    initial begin
        $dumpfile("sim/waves/alu_wave.vcd");
        $dumpvars(0, tb_alu_wave);
    end

    integer pass = 0, fail = 0;
    reg [`XLEN-1:0] expected;

    task test_op(input [`ALU_OP_WIDTH-1:0] op, input [`XLEN-1:0] s1, s2, exp, input [63:0] name);
        begin
            @(posedge clk);
            op_i = op; src1_i = s1; src2_i = s2; valid_i = 1;
            #1;
            if (result_o === exp) begin pass = pass + 1; $display("PASS: %s", name); end
            else begin fail = fail + 1; $display("FAIL: %s exp=%h got=%h", name, exp, result_o); end
        end
    endtask

    initial begin
        $display("=== ALU Wave Test (12 ops) ===");
        rst_n = 0; valid_i = 0; op_i = 0; src1_i = 0; src2_i = 0; pc_i = 32'h1000; prd_i = 1; rob_idx_i = 0;
        #20 rst_n = 1; #10;

        // 12种操作各测1个典型用例
        test_op(`ALU_OP_ADD,  32'h0000_0005, 32'h0000_0003, 32'h0000_0008, "ADD");
        test_op(`ALU_OP_SUB,  32'h0000_000A, 32'h0000_0003, 32'h0000_0007, "SUB");
        test_op(`ALU_OP_AND,  32'hFFFF_0000, 32'h0F0F_0F0F, 32'h0F0F_0000, "AND");
        test_op(`ALU_OP_OR,   32'hFF00_0000, 32'h00FF_0000, 32'hFFFF_0000, "OR");
        test_op(`ALU_OP_XOR,  32'hAAAA_AAAA, 32'h5555_5555, 32'hFFFF_FFFF, "XOR");
        test_op(`ALU_OP_SLL,  32'h0000_0001, 32'h0000_0004, 32'h0000_0010, "SLL");
        test_op(`ALU_OP_SRL,  32'h0000_0080, 32'h0000_0004, 32'h0000_0008, "SRL");
        test_op(`ALU_OP_SRA,  32'h8000_0000, 32'h0000_0004, 32'hF800_0000, "SRA");
        test_op(`ALU_OP_SLT,  32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0001, "SLT");  // -1 < 1
        test_op(`ALU_OP_SLTU, 32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0001, "SLTU"); // 1 < 0xFFFFFFFF
        test_op(`ALU_OP_LUI,  32'h0000_0000, 32'h1234_5000, 32'h1234_5000, "LUI");
        test_op(`ALU_OP_AUIPC,32'h0000_0000, 32'h0000_1000, 32'h0000_2000, "AUIPC"); // pc=0x1000

        valid_i = 0;
        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
