//=================================================================
// Module: golden_model
// Description: RISC-V RV32IM Golden Reference Model
//              Simplified ISA simulator for verification
//              Executes instructions and maintains expected state
// Validates: Requirements 1.1, 1.2, 7.4
//=================================================================

`timescale 1ns/1ps

module golden_model #(
    parameter XLEN = 32,
    parameter MEM_SIZE = 65536  // 64KB
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Instruction commit interface
    input  wire                 commit_valid_i,
    input  wire [XLEN-1:0]      commit_pc_i,
    input  wire [XLEN-1:0]      commit_instr_i,
    
    // Expected state output
    output reg  [XLEN-1:0]      expected_pc,
    output wire [XLEN-1:0]      expected_reg_0,
    output wire [XLEN-1:0]      expected_reg_1,
    output wire [XLEN-1:0]      expected_reg_2,
    output wire [XLEN-1:0]      expected_reg_3,
    output wire [XLEN-1:0]      expected_reg_4,
    output wire [XLEN-1:0]      expected_reg_5,
    output wire [XLEN-1:0]      expected_reg_6,
    output wire [XLEN-1:0]      expected_reg_7,
    
    // Comparison interface
    input  wire [XLEN-1:0]      actual_pc_i,
    input  wire [XLEN-1:0]      actual_reg_0_i,
    input  wire [XLEN-1:0]      actual_reg_1_i,
    input  wire [XLEN-1:0]      actual_reg_2_i,
    input  wire [XLEN-1:0]      actual_reg_3_i,
    input  wire [XLEN-1:0]      actual_reg_4_i,
    input  wire [XLEN-1:0]      actual_reg_5_i,
    input  wire [XLEN-1:0]      actual_reg_6_i,
    input  wire [XLEN-1:0]      actual_reg_7_i,
    output wire                 mismatch_o,
    output wire [4:0]           mismatch_reg_o
);

    //=========================================================
    // Register File
    //=========================================================
    reg [XLEN-1:0] regs [0:31];
    
    // Output some registers for debugging
    assign expected_reg_0 = regs[0];
    assign expected_reg_1 = regs[1];
    assign expected_reg_2 = regs[2];
    assign expected_reg_3 = regs[3];
    assign expected_reg_4 = regs[4];
    assign expected_reg_5 = regs[5];
    assign expected_reg_6 = regs[6];
    assign expected_reg_7 = regs[7];
    
    //=========================================================
    // Memory (for load/store simulation)
    //=========================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    
    //=========================================================
    // Instruction Decode Fields
    //=========================================================
    wire [6:0]  opcode;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    
    assign opcode = commit_instr_i[6:0];
    assign rd     = commit_instr_i[11:7];
    assign funct3 = commit_instr_i[14:12];
    assign rs1    = commit_instr_i[19:15];
    assign rs2    = commit_instr_i[24:20];
    assign funct7 = commit_instr_i[31:25];
    
    // Immediate generation
    assign imm_i = {{20{commit_instr_i[31]}}, commit_instr_i[31:20]};
    assign imm_s = {{20{commit_instr_i[31]}}, commit_instr_i[31:25], commit_instr_i[11:7]};
    assign imm_b = {{19{commit_instr_i[31]}}, commit_instr_i[31], commit_instr_i[7], 
                   commit_instr_i[30:25], commit_instr_i[11:8], 1'b0};
    assign imm_u = {commit_instr_i[31:12], 12'b0};
    assign imm_j = {{11{commit_instr_i[31]}}, commit_instr_i[31], commit_instr_i[19:12],
                   commit_instr_i[20], commit_instr_i[30:21], 1'b0};
    
    //=========================================================
    // Opcode Definitions
    //=========================================================
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_FENCE  = 7'b0001111;
    localparam OP_SYSTEM = 7'b1110011;
    
    //=========================================================
    // ALU Operations
    //=========================================================
    function [XLEN-1:0] alu_op;
        input [XLEN-1:0] a, b;
        input [2:0] funct3_in;
        input [6:0] funct7_in;
        input is_imm;
        reg [XLEN-1:0] result;
        reg [4:0] shamt;
        begin
            shamt = b[4:0];
            case (funct3_in)
                3'b000: begin  // ADD/SUB
                    if (!is_imm && funct7_in[5])
                        result = a - b;
                    else
                        result = a + b;
                end
                3'b001: result = a << shamt;  // SLL
                3'b010: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;  // SLT
                3'b011: result = (a < b) ? 32'd1 : 32'd0;  // SLTU
                3'b100: result = a ^ b;  // XOR
                3'b101: begin  // SRL/SRA
                    if (funct7_in[5])
                        result = $signed(a) >>> shamt;
                    else
                        result = a >> shamt;
                end
                3'b110: result = a | b;  // OR
                3'b111: result = a & b;  // AND
                default: result = 0;
            endcase
            alu_op = result;
        end
    endfunction

    //=========================================================
    // Branch Condition Check
    //=========================================================
    function branch_taken;
        input [XLEN-1:0] a, b;
        input [2:0] funct3_in;
        begin
            case (funct3_in)
                3'b000: branch_taken = (a == b);  // BEQ
                3'b001: branch_taken = (a != b);  // BNE
                3'b100: branch_taken = ($signed(a) < $signed(b));  // BLT
                3'b101: branch_taken = ($signed(a) >= $signed(b)); // BGE
                3'b110: branch_taken = (a < b);   // BLTU
                3'b111: branch_taken = (a >= b);  // BGEU
                default: branch_taken = 0;
            endcase
        end
    endfunction
    
    //=========================================================
    // Memory Access Functions
    //=========================================================
    function [XLEN-1:0] load_memory;
        input [XLEN-1:0] addr;
        input [2:0] funct3_in;
        reg [XLEN-1:0] data;
        reg [15:0] addr_offset;
        begin
            addr_offset = addr[15:0];
            case (funct3_in)
                3'b000: begin  // LB
                    data = {{24{memory[addr_offset][7]}}, memory[addr_offset]};
                end
                3'b001: begin  // LH
                    data = {{16{memory[addr_offset+1][7]}}, memory[addr_offset+1], memory[addr_offset]};
                end
                3'b010: begin  // LW
                    data = {memory[addr_offset+3], memory[addr_offset+2], 
                            memory[addr_offset+1], memory[addr_offset]};
                end
                3'b100: begin  // LBU
                    data = {24'd0, memory[addr_offset]};
                end
                3'b101: begin  // LHU
                    data = {16'd0, memory[addr_offset+1], memory[addr_offset]};
                end
                default: data = 0;
            endcase
            load_memory = data;
        end
    endfunction
    
    task store_memory;
        input [XLEN-1:0] addr;
        input [XLEN-1:0] data;
        input [2:0] funct3_in;
        reg [15:0] addr_offset;
        begin
            addr_offset = addr[15:0];
            case (funct3_in)
                3'b000: begin  // SB
                    memory[addr_offset] = data[7:0];
                end
                3'b001: begin  // SH
                    memory[addr_offset] = data[7:0];
                    memory[addr_offset+1] = data[15:8];
                end
                3'b010: begin  // SW
                    memory[addr_offset] = data[7:0];
                    memory[addr_offset+1] = data[15:8];
                    memory[addr_offset+2] = data[23:16];
                    memory[addr_offset+3] = data[31:24];
                end
            endcase
        end
    endtask

    //=========================================================
    // RV32M Multiplication
    //=========================================================
    function [XLEN-1:0] mul_op;
        input [XLEN-1:0] a, b;
        input [2:0] funct3_in;
        reg signed [63:0] prod_ss;
        reg [63:0] prod_uu;
        reg signed [63:0] prod_su;
        begin
            prod_ss = $signed(a) * $signed(b);
            prod_uu = a * b;
            prod_su = $signed(a) * b;
            
            case (funct3_in)
                3'b000: mul_op = prod_ss[31:0];   // MUL
                3'b001: mul_op = prod_ss[63:32];  // MULH
                3'b010: mul_op = prod_su[63:32];  // MULHSU
                3'b011: mul_op = prod_uu[63:32];  // MULHU
                default: mul_op = 0;
            endcase
        end
    endfunction
    
    //=========================================================
    // RV32M Division
    //=========================================================
    function [XLEN-1:0] div_op;
        input [XLEN-1:0] a, b;
        input [2:0] funct3_in;
        reg signed [XLEN-1:0] a_s, b_s;
        begin
            a_s = $signed(a);
            b_s = $signed(b);
            
            case (funct3_in)
                3'b100: begin  // DIV
                    if (b == 0)
                        div_op = 32'hFFFFFFFF;
                    else if (a == 32'h80000000 && b == 32'hFFFFFFFF)
                        div_op = 32'h80000000;
                    else
                        div_op = a_s / b_s;
                end
                3'b101: begin  // DIVU
                    if (b == 0)
                        div_op = 32'hFFFFFFFF;
                    else
                        div_op = a / b;
                end
                3'b110: begin  // REM
                    if (b == 0)
                        div_op = a;
                    else if (a == 32'h80000000 && b == 32'hFFFFFFFF)
                        div_op = 0;
                    else
                        div_op = a_s % b_s;
                end
                3'b111: begin  // REMU
                    if (b == 0)
                        div_op = a;
                    else
                        div_op = a % b;
                end
                default: div_op = 0;
            endcase
        end
    endfunction

    //=========================================================
    // Instruction Execution
    //=========================================================
    reg [XLEN-1:0] next_pc;
    reg [XLEN-1:0] result;
    reg [XLEN-1:0] addr;
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_pc <= 32'h8000_0000;
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 0;
            end
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] <= 0;
            end
        end else if (commit_valid_i) begin
            next_pc = commit_pc_i + 4;
            
            case (opcode)
                OP_LUI: begin
                    if (rd != 0) regs[rd] <= imm_u;
                end
                
                OP_AUIPC: begin
                    if (rd != 0) regs[rd] <= commit_pc_i + imm_u;
                end
                
                OP_JAL: begin
                    if (rd != 0) regs[rd] <= commit_pc_i + 4;
                    next_pc = commit_pc_i + imm_j;
                end
                
                OP_JALR: begin
                    if (rd != 0) regs[rd] <= commit_pc_i + 4;
                    next_pc = (regs[rs1] + imm_i) & ~32'd1;
                end
                
                OP_BRANCH: begin
                    if (branch_taken(regs[rs1], regs[rs2], funct3))
                        next_pc = commit_pc_i + imm_b;
                end
                
                OP_LOAD: begin
                    addr = regs[rs1] + imm_i;
                    if (rd != 0) regs[rd] <= load_memory(addr, funct3);
                end
                
                OP_STORE: begin
                    addr = regs[rs1] + imm_s;
                    store_memory(addr, regs[rs2], funct3);
                end
                
                OP_IMM: begin
                    result = alu_op(regs[rs1], imm_i, funct3, funct7, 1'b1);
                    if (rd != 0) regs[rd] <= result;
                end
                
                OP_REG: begin
                    if (funct7 == 7'b0000001) begin
                        // RV32M
                        if (funct3[2] == 0)
                            result = mul_op(regs[rs1], regs[rs2], funct3);
                        else
                            result = div_op(regs[rs1], regs[rs2], funct3);
                    end else begin
                        // RV32I
                        result = alu_op(regs[rs1], regs[rs2], funct3, funct7, 1'b0);
                    end
                    if (rd != 0) regs[rd] <= result;
                end
                
                OP_FENCE: begin
                    // NOP for now
                end
                
                OP_SYSTEM: begin
                    // ECALL, EBREAK, CSR - simplified
                end
            endcase
            
            expected_pc <= next_pc;
            regs[0] <= 0;  // x0 is always 0
        end
    end
    
    //=========================================================
    // State Comparison
    //=========================================================
    reg mismatch;
    reg [4:0] mismatch_reg;
    
    always @(*) begin
        mismatch = 0;
        mismatch_reg = 0;
        
        if (expected_pc != actual_pc_i) begin
            mismatch = 1;
        end
        
        // Compare first 8 registers (simplified for Verilog 2001)
        if (regs[0] != actual_reg_0_i) begin mismatch = 1; mismatch_reg = 5'd0; end
        if (regs[1] != actual_reg_1_i) begin mismatch = 1; mismatch_reg = 5'd1; end
        if (regs[2] != actual_reg_2_i) begin mismatch = 1; mismatch_reg = 5'd2; end
        if (regs[3] != actual_reg_3_i) begin mismatch = 1; mismatch_reg = 5'd3; end
        if (regs[4] != actual_reg_4_i) begin mismatch = 1; mismatch_reg = 5'd4; end
        if (regs[5] != actual_reg_5_i) begin mismatch = 1; mismatch_reg = 5'd5; end
        if (regs[6] != actual_reg_6_i) begin mismatch = 1; mismatch_reg = 5'd6; end
        if (regs[7] != actual_reg_7_i) begin mismatch = 1; mismatch_reg = 5'd7; end
    end
    
    assign mismatch_o = mismatch;
    assign mismatch_reg_o = mismatch_reg;

endmodule
