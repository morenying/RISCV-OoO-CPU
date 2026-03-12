//==============================================================================
// Decoder 精简波形测试 - 覆盖主要指令类型，约20周期
//==============================================================================
`timescale 1ns/1ps

module tb_decoder_wave;
    reg  [31:0] instr_i, pc_i;
    wire [4:0]  rd_o, rs1_o, rs2_o;
    wire [31:0] imm_o;
    wire [6:0]  opcode_o;
    wire [2:0]  funct3_o, fu_type_o;
    wire [6:0]  funct7_o;
    wire        reg_write_o, mem_read_o, mem_write_o, branch_o, jump_o;
    wire [3:0]  alu_op_o;
    wire        illegal_instr_o;

    decoder dut (
        .instr_i(instr_i), .pc_i(pc_i),
        .rd_o(rd_o), .rs1_o(rs1_o), .rs2_o(rs2_o), .imm_o(imm_o),
        .opcode_o(opcode_o), .funct3_o(funct3_o), .funct7_o(funct7_o),
        .reg_write_o(reg_write_o), .mem_read_o(mem_read_o), .mem_write_o(mem_write_o),
        .branch_o(branch_o), .jump_o(jump_o), .alu_op_o(alu_op_o),
        .fu_type_o(fu_type_o), .illegal_instr_o(illegal_instr_o)
    );

    reg clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/decoder_wave.vcd");
        $dumpvars(0, tb_decoder_wave);
    end

    integer pass = 0, fail = 0;

    task test_instr(input [31:0] instr, input [63:0] name, input exp_illegal);
        begin
            @(posedge clk);
            instr_i = instr;
            #1;
            if (illegal_instr_o === exp_illegal) begin
                pass = pass + 1;
                $display("PASS: %s opcode=%b fu=%d", name, opcode_o, fu_type_o);
            end else begin
                fail = fail + 1;
                $display("FAIL: %s illegal=%b exp=%b", name, illegal_instr_o, exp_illegal);
            end
        end
    endtask

    initial begin
        $display("=== Decoder Wave Test ===");
        pc_i = 32'h1000; instr_i = 0;
        #20;

        // R-type: ADD x1, x2, x3
        test_instr(32'h003100B3, "ADD", 0);
        // I-type: ADDI x1, x2, 100
        test_instr(32'h06410093, "ADDI", 0);
        // Load: LW x1, 0(x2)
        test_instr(32'h00012083, "LW", 0);
        // Store: SW x1, 0(x2)
        test_instr(32'h00112023, "SW", 0);
        // Branch: BEQ x1, x2, 8
        test_instr(32'h00208463, "BEQ", 0);
        // JAL x1, 100
        test_instr(32'h064000EF, "JAL", 0);
        // JALR x1, x2, 0
        test_instr(32'h000100E7, "JALR", 0);
        // LUI x1, 0x12345
        test_instr(32'h123450B7, "LUI", 0);
        // AUIPC x1, 0x12345
        test_instr(32'h12345097, "AUIPC", 0);
        // MUL x1, x2, x3
        test_instr(32'h023100B3, "MUL", 0);
        // DIV x1, x2, x3
        test_instr(32'h023140B3, "DIV", 0);
        // Illegal instruction
        test_instr(32'hFFFFFFFF, "ILLEGAL", 1);

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
