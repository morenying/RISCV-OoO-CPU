//=================================================================
// Testbench: tb_decoder
// Description: Testbench for RISC-V RV32IM + Zicsr Decoder
//              Tests all 51 instructions
//              Validates control signal generation
//              Tests illegal instruction detection
// Requirements: 1.1, 1.2, 1.3, 1.4, 2.3
//=================================================================

`timescale 1ns/1ps

module tb_decoder;

    //=========================================================
    // Test Signals
    //=========================================================
    reg  [31:0] instr;
    reg  [31:0] pc;
    
    wire [4:0]  rd;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [31:0] imm;
    wire [6:0]  opcode;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire        reg_write;
    wire        mem_read;
    wire        mem_write;
    wire        branch;
    wire        jump;
    wire [3:0]  alu_op;
    wire [1:0]  alu_src1;
    wire [1:0]  alu_src2;
    wire        csr_op;
    wire [2:0]  csr_type;
    wire [2:0]  imm_type;
    wire [2:0]  fu_type;
    wire [1:0]  mem_size;
    wire        mem_sign_ext;
    wire        illegal_instr;

    //=========================================================
    // DUT Instantiation
    //=========================================================
    decoder dut (
        .instr_i        (instr),
        .pc_i           (pc),
        .rd_o           (rd),
        .rs1_o          (rs1),
        .rs2_o          (rs2),
        .imm_o          (imm),
        .opcode_o       (opcode),
        .funct3_o       (funct3),
        .funct7_o       (funct7),
        .reg_write_o    (reg_write),
        .mem_read_o     (mem_read),
        .mem_write_o    (mem_write),
        .branch_o       (branch),
        .jump_o         (jump),
        .alu_op_o       (alu_op),
        .alu_src1_o     (alu_src1),
        .alu_src2_o     (alu_src2),
        .csr_op_o       (csr_op),
        .csr_type_o     (csr_type),
        .imm_type_o     (imm_type),
        .fu_type_o      (fu_type),
        .mem_size_o     (mem_size),
        .mem_sign_ext_o (mem_sign_ext),
        .illegal_instr_o(illegal_instr)
    );

    //=========================================================
    // Test Counters
    //=========================================================
    integer test_count;
    integer pass_count;
    integer fail_count;

    //=========================================================
    // Functional Unit Type Constants
    //=========================================================
    localparam FU_ALU = 3'b000;
    localparam FU_MUL = 3'b001;
    localparam FU_DIV = 3'b010;
    localparam FU_BR  = 3'b011;
    localparam FU_LSU = 3'b100;
    localparam FU_CSR = 3'b101;

    //=========================================================
    // Test Tasks
    //=========================================================
    task check_result;
        input [255:0] test_name;
        input         expected_illegal;
        input         expected_reg_write;
        input         expected_mem_read;
        input         expected_mem_write;
        input         expected_branch;
        input         expected_jump;
        input [2:0]   expected_fu_type;
        begin
            test_count = test_count + 1;
            if (illegal_instr !== expected_illegal ||
                reg_write !== expected_reg_write ||
                mem_read !== expected_mem_read ||
                mem_write !== expected_mem_write ||
                branch !== expected_branch ||
                jump !== expected_jump ||
                fu_type !== expected_fu_type) begin
                fail_count = fail_count + 1;
                $display("FAIL: %s", test_name);
                $display("  illegal: exp=%b got=%b", expected_illegal, illegal_instr);
                $display("  reg_write: exp=%b got=%b", expected_reg_write, reg_write);
                $display("  mem_read: exp=%b got=%b", expected_mem_read, mem_read);
                $display("  mem_write: exp=%b got=%b", expected_mem_write, mem_write);
                $display("  branch: exp=%b got=%b", expected_branch, branch);
                $display("  jump: exp=%b got=%b", expected_jump, jump);
                $display("  fu_type: exp=%b got=%b", expected_fu_type, fu_type);
            end else begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
            end
        end
    endtask

    task check_imm;
        input [255:0] test_name;
        input [31:0]  expected_imm;
        begin
            test_count = test_count + 1;
            if (imm !== expected_imm) begin
                fail_count = fail_count + 1;
                $display("FAIL: %s - imm: exp=%h got=%h", test_name, expected_imm, imm);
            end else begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
            end
        end
    endtask

    task check_regs;
        input [255:0] test_name;
        input [4:0]   expected_rd;
        input [4:0]   expected_rs1;
        input [4:0]   expected_rs2;
        begin
            test_count = test_count + 1;
            if (rd !== expected_rd || rs1 !== expected_rs1 || rs2 !== expected_rs2) begin
                fail_count = fail_count + 1;
                $display("FAIL: %s", test_name);
                $display("  rd: exp=%d got=%d", expected_rd, rd);
                $display("  rs1: exp=%d got=%d", expected_rs1, rs1);
                $display("  rs2: exp=%d got=%d", expected_rs2, rs2);
            end else begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
            end
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $display("========================================");
        $display("Decoder Testbench Starting");
        $display("========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        pc = 32'h8000_0000;
        
        //=====================================================
        // Test LUI
        //=====================================================
        $display("\n--- Testing LUI ---");
        // lui x1, 0x12345
        instr = 32'h12345_0B7;  // lui x1, 0x12345
        #1;
        check_result("LUI basic", 0, 1, 0, 0, 0, 0, FU_ALU);
        check_imm("LUI imm", 32'h12345000);
        check_regs("LUI regs", 5'd1, 5'd0, 5'd0);
        
        //=====================================================
        // Test AUIPC
        //=====================================================
        $display("\n--- Testing AUIPC ---");
        // auipc x2, 0xABCDE
        instr = 32'hABCDE_117;
        #1;
        check_result("AUIPC basic", 0, 1, 0, 0, 0, 0, FU_ALU);
        check_imm("AUIPC imm", 32'hABCDE000);
        
        //=====================================================
        // Test JAL
        //=====================================================
        $display("\n--- Testing JAL ---");
        // jal x1, offset
        instr = 32'h008000EF;  // jal x1, 8
        #1;
        check_result("JAL basic", 0, 1, 0, 0, 0, 1, FU_BR);
        
        //=====================================================
        // Test JALR
        //=====================================================
        $display("\n--- Testing JALR ---");
        // jalr x1, x2, 0
        instr = 32'h000100E7;  // jalr x1, x2, 0
        #1;
        check_result("JALR basic", 0, 1, 0, 0, 0, 1, FU_BR);
        
        // Invalid JALR (funct3 != 0)
        instr = 32'h001110E7;  // funct3=001, invalid for JALR
        #1;
        check_result("JALR invalid funct3", 1, 0, 0, 0, 0, 0, FU_ALU);
        
        //=====================================================
        // Test Branch Instructions
        //=====================================================
        $display("\n--- Testing Branch Instructions ---");
        
        // BEQ
        instr = 32'h00208463;  // beq x1, x2, 8
        #1;
        check_result("BEQ", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // BNE
        instr = 32'h00209463;  // bne x1, x2, 8
        #1;
        check_result("BNE", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // BLT
        instr = 32'h0020C463;  // blt x1, x2, 8
        #1;
        check_result("BLT", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // BGE
        instr = 32'h0020D463;  // bge x1, x2, 8
        #1;
        check_result("BGE", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // BLTU
        instr = 32'h0020E463;  // bltu x1, x2, 8
        #1;
        check_result("BLTU", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // BGEU
        instr = 32'h0020F463;  // bgeu x1, x2, 8
        #1;
        check_result("BGEU", 0, 0, 0, 0, 1, 0, FU_BR);
        
        // Invalid branch funct3
        instr = 32'h0020A463;  // Invalid funct3=010
        #1;
        check_result("Branch invalid funct3", 1, 0, 0, 0, 1, 0, FU_BR);

        //=====================================================
        // Test Load Instructions
        //=====================================================
        $display("\n--- Testing Load Instructions ---");
        
        // LB
        instr = 32'h00008083;  // lb x1, 0(x1)
        #1;
        check_result("LB", 0, 1, 1, 0, 0, 0, FU_LSU);
        if (mem_size !== 2'b00 || mem_sign_ext !== 1'b1) begin
            fail_count = fail_count + 1;
            $display("FAIL: LB mem_size/sign_ext");
        end else begin
            pass_count = pass_count + 1;
            $display("PASS: LB mem_size/sign_ext");
        end
        test_count = test_count + 1;
        
        // LH
        instr = 32'h00009083;  // lh x1, 0(x1)
        #1;
        check_result("LH", 0, 1, 1, 0, 0, 0, FU_LSU);
        
        // LW
        instr = 32'h0000A083;  // lw x1, 0(x1)
        #1;
        check_result("LW", 0, 1, 1, 0, 0, 0, FU_LSU);
        
        // LBU
        instr = 32'h0000C083;  // lbu x1, 0(x1)
        #1;
        check_result("LBU", 0, 1, 1, 0, 0, 0, FU_LSU);
        if (mem_sign_ext !== 1'b0) begin
            fail_count = fail_count + 1;
            $display("FAIL: LBU sign_ext should be 0");
        end else begin
            pass_count = pass_count + 1;
            $display("PASS: LBU sign_ext");
        end
        test_count = test_count + 1;
        
        // LHU
        instr = 32'h0000D083;  // lhu x1, 0(x1)
        #1;
        check_result("LHU", 0, 1, 1, 0, 0, 0, FU_LSU);
        
        // Invalid load funct3
        instr = 32'h0000B083;  // Invalid funct3=011
        #1;
        check_result("Load invalid funct3", 1, 1, 1, 0, 0, 0, FU_LSU);
        
        //=====================================================
        // Test Store Instructions
        //=====================================================
        $display("\n--- Testing Store Instructions ---");
        
        // SB
        instr = 32'h00108023;  // sb x1, 0(x1)
        #1;
        check_result("SB", 0, 0, 0, 1, 0, 0, FU_LSU);
        
        // SH
        instr = 32'h00109023;  // sh x1, 0(x1)
        #1;
        check_result("SH", 0, 0, 0, 1, 0, 0, FU_LSU);
        
        // SW
        instr = 32'h0010A023;  // sw x1, 0(x1)
        #1;
        check_result("SW", 0, 0, 0, 1, 0, 0, FU_LSU);
        
        // Invalid store funct3
        instr = 32'h0010B023;  // Invalid funct3=011
        #1;
        check_result("Store invalid funct3", 1, 0, 0, 1, 0, 0, FU_LSU);
        
        //=====================================================
        // Test I-type ALU Instructions
        //=====================================================
        $display("\n--- Testing I-type ALU Instructions ---");
        
        // ADDI
        instr = 32'h00108093;  // addi x1, x1, 1
        #1;
        check_result("ADDI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLTI
        instr = 32'h0010A093;  // slti x1, x1, 1
        #1;
        check_result("SLTI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLTIU
        instr = 32'h0010B093;  // sltiu x1, x1, 1
        #1;
        check_result("SLTIU", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // XORI
        instr = 32'h0010C093;  // xori x1, x1, 1
        #1;
        check_result("XORI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // ORI
        instr = 32'h0010E093;  // ori x1, x1, 1
        #1;
        check_result("ORI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // ANDI
        instr = 32'h0010F093;  // andi x1, x1, 1
        #1;
        check_result("ANDI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLLI
        instr = 32'h00109093;  // slli x1, x1, 1
        #1;
        check_result("SLLI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SRLI
        instr = 32'h0010D093;  // srli x1, x1, 1
        #1;
        check_result("SRLI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SRAI
        instr = 32'h4010D093;  // srai x1, x1, 1
        #1;
        check_result("SRAI", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // Invalid SLLI (bad funct7)
        instr = 32'h40109093;  // Invalid funct7 for SLLI
        #1;
        check_result("SLLI invalid funct7", 1, 1, 0, 0, 0, 0, FU_ALU);
        
        //=====================================================
        // Test R-type ALU Instructions
        //=====================================================
        $display("\n--- Testing R-type ALU Instructions ---");
        
        // ADD
        instr = 32'h002080B3;  // add x1, x1, x2
        #1;
        check_result("ADD", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SUB
        instr = 32'h402080B3;  // sub x1, x1, x2
        #1;
        check_result("SUB", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLL
        instr = 32'h002090B3;  // sll x1, x1, x2
        #1;
        check_result("SLL", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLT
        instr = 32'h0020A0B3;  // slt x1, x1, x2
        #1;
        check_result("SLT", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SLTU
        instr = 32'h0020B0B3;  // sltu x1, x1, x2
        #1;
        check_result("SLTU", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // XOR
        instr = 32'h0020C0B3;  // xor x1, x1, x2
        #1;
        check_result("XOR", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SRL
        instr = 32'h0020D0B3;  // srl x1, x1, x2
        #1;
        check_result("SRL", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // SRA
        instr = 32'h4020D0B3;  // sra x1, x1, x2
        #1;
        check_result("SRA", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // OR
        instr = 32'h0020E0B3;  // or x1, x1, x2
        #1;
        check_result("OR", 0, 1, 0, 0, 0, 0, FU_ALU);
        
        // AND
        instr = 32'h0020F0B3;  // and x1, x1, x2
        #1;
        check_result("AND", 0, 1, 0, 0, 0, 0, FU_ALU);

        //=====================================================
        // Test M-extension Instructions
        //=====================================================
        $display("\n--- Testing M-extension Instructions ---");
        
        // MUL
        instr = 32'h022080B3;  // mul x1, x1, x2
        #1;
        check_result("MUL", 0, 1, 0, 0, 0, 0, FU_MUL);
        
        // MULH
        instr = 32'h022090B3;  // mulh x1, x1, x2
        #1;
        check_result("MULH", 0, 1, 0, 0, 0, 0, FU_MUL);
        
        // MULHSU
        instr = 32'h0220A0B3;  // mulhsu x1, x1, x2
        #1;
        check_result("MULHSU", 0, 1, 0, 0, 0, 0, FU_MUL);
        
        // MULHU
        instr = 32'h0220B0B3;  // mulhu x1, x1, x2
        #1;
        check_result("MULHU", 0, 1, 0, 0, 0, 0, FU_MUL);
        
        // DIV
        instr = 32'h0220C0B3;  // div x1, x1, x2
        #1;
        check_result("DIV", 0, 1, 0, 0, 0, 0, FU_DIV);
        
        // DIVU
        instr = 32'h0220D0B3;  // divu x1, x1, x2
        #1;
        check_result("DIVU", 0, 1, 0, 0, 0, 0, FU_DIV);
        
        // REM
        instr = 32'h0220E0B3;  // rem x1, x1, x2
        #1;
        check_result("REM", 0, 1, 0, 0, 0, 0, FU_DIV);
        
        // REMU
        instr = 32'h0220F0B3;  // remu x1, x1, x2
        #1;
        check_result("REMU", 0, 1, 0, 0, 0, 0, FU_DIV);
        
        //=====================================================
        // Test FENCE Instructions
        //=====================================================
        $display("\n--- Testing FENCE Instructions ---");
        
        // FENCE
        instr = 32'h0FF0000F;  // fence
        #1;
        check_result("FENCE", 0, 0, 0, 0, 0, 0, FU_ALU);
        
        // FENCE.I
        instr = 32'h0000100F;  // fence.i
        #1;
        check_result("FENCE.I", 0, 0, 0, 0, 0, 0, FU_ALU);
        
        //=====================================================
        // Test System Instructions
        //=====================================================
        $display("\n--- Testing System Instructions ---");
        
        // ECALL
        instr = 32'h00000073;  // ecall
        #1;
        check_result("ECALL", 0, 0, 0, 0, 0, 0, FU_CSR);
        
        // EBREAK
        instr = 32'h00100073;  // ebreak
        #1;
        check_result("EBREAK", 0, 0, 0, 0, 0, 0, FU_CSR);
        
        // MRET
        instr = 32'h30200073;  // mret
        #1;
        check_result("MRET", 0, 0, 0, 0, 0, 0, FU_CSR);
        
        //=====================================================
        // Test CSR Instructions
        //=====================================================
        $display("\n--- Testing CSR Instructions ---");
        
        // CSRRW
        instr = 32'h300090F3;  // csrrw x1, mstatus, x1
        #1;
        check_result("CSRRW", 0, 1, 0, 0, 0, 0, FU_CSR);
        if (csr_op !== 1'b1 || csr_type !== 3'b001) begin
            fail_count = fail_count + 1;
            $display("FAIL: CSRRW csr_op/type");
        end else begin
            pass_count = pass_count + 1;
            $display("PASS: CSRRW csr_op/type");
        end
        test_count = test_count + 1;
        
        // CSRRS
        instr = 32'h3000A0F3;  // csrrs x1, mstatus, x1
        #1;
        check_result("CSRRS", 0, 1, 0, 0, 0, 0, FU_CSR);
        
        // CSRRC
        instr = 32'h3000B0F3;  // csrrc x1, mstatus, x1
        #1;
        check_result("CSRRC", 0, 1, 0, 0, 0, 0, FU_CSR);
        
        // CSRRWI
        instr = 32'h3000D0F3;  // csrrwi x1, mstatus, 1
        #1;
        check_result("CSRRWI", 0, 1, 0, 0, 0, 0, FU_CSR);
        
        // CSRRSI
        instr = 32'h3000E0F3;  // csrrsi x1, mstatus, 1
        #1;
        check_result("CSRRSI", 0, 1, 0, 0, 0, 0, FU_CSR);
        
        // CSRRCI
        instr = 32'h3000F0F3;  // csrrci x1, mstatus, 1
        #1;
        check_result("CSRRCI", 0, 1, 0, 0, 0, 0, FU_CSR);
        
        //=====================================================
        // Test Illegal Instructions
        //=====================================================
        $display("\n--- Testing Illegal Instructions ---");
        
        // Invalid opcode
        instr = 32'h00000000;  // All zeros
        #1;
        check_result("Invalid opcode 0x00", 1, 0, 0, 0, 0, 0, FU_ALU);
        
        // Invalid opcode
        instr = 32'hFFFFFFFF;  // All ones
        #1;
        check_result("Invalid opcode 0xFF", 1, 0, 0, 0, 0, 0, FU_ALU);
        
        // Invalid R-type funct7
        instr = 32'h802080B3;  // Invalid funct7
        #1;
        check_result("R-type invalid funct7", 1, 1, 0, 0, 0, 0, FU_ALU);
        
        //=====================================================
        // Test Immediate Extraction
        //=====================================================
        $display("\n--- Testing Immediate Extraction ---");
        
        // I-type positive immediate
        instr = 32'h7FF08093;  // addi x1, x1, 2047
        #1;
        check_imm("I-type positive imm", 32'h000007FF);
        
        // I-type negative immediate
        instr = 32'hFFF08093;  // addi x1, x1, -1
        #1;
        check_imm("I-type negative imm", 32'hFFFFFFFF);
        
        // S-type immediate
        instr = 32'h7E108FA3;  // sb x1, 2047(x1)
        #1;
        check_imm("S-type imm", 32'h000007FF);
        
        // U-type immediate
        instr = 32'h12345_0B7;  // lui x1, 0x12345
        #1;
        check_imm("U-type imm", 32'h12345000);
        
        //=====================================================
        // Test Register Field Extraction
        //=====================================================
        $display("\n--- Testing Register Field Extraction ---");
        
        // R-type with all different registers
        instr = 32'h003100B3;  // add x1, x2, x3
        #1;
        check_regs("R-type regs", 5'd1, 5'd2, 5'd3);
        
        // Max register numbers
        instr = 32'h01FF8FB3;  // add x31, x31, x31
        #1;
        check_regs("Max regs", 5'd31, 5'd31, 5'd31);
        
        //=====================================================
        // Summary
        //=====================================================
        $display("\n========================================");
        $display("Decoder Testbench Complete");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        
        $finish;
    end

endmodule
