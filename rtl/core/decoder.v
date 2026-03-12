//=================================================================
// Module: decoder
// Description: Instruction Decoder for RISC-V RV32IM + Zicsr
//              Decodes all 51 instructions
//              Generates control signals
//              Detects illegal instructions
// Requirements: 2.3, 1.1, 1.2, 1.3, 1.4
//=================================================================

`timescale 1ns/1ps

module decoder (
    input  wire [31:0] instr_i,
    input  wire [31:0] pc_i,
    
    // Register addresses
    output wire [4:0]  rd_o,
    output wire [4:0]  rs1_o,
    output wire [4:0]  rs2_o,
    
    // Immediate
    output wire [31:0] imm_o,
    
    // Instruction fields
    output wire [6:0]  opcode_o,
    output wire [2:0]  funct3_o,
    output wire [6:0]  funct7_o,
    
    // Control signals
    output reg         reg_write_o,
    output reg         mem_read_o,
    output reg         mem_write_o,
    output reg         branch_o,
    output reg         jump_o,
    output reg  [3:0]  alu_op_o,
    output reg  [1:0]  alu_src1_o,    // 00:rs1, 01:PC, 10:zero
    output reg  [1:0]  alu_src2_o,    // 00:rs2, 01:imm, 10:4
    output reg         csr_op_o,
    output reg  [2:0]  csr_type_o,
    output reg  [2:0]  imm_type_o,
    output reg  [2:0]  fu_type_o,     // Functional unit type
    output reg  [1:0]  mem_size_o,    // 00:byte, 01:half, 10:word
    output reg         mem_sign_ext_o,
    
    // Exception
    output reg         illegal_instr_o
);

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
    // ALU Operation Codes
    //=========================================================
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;
    localparam ALU_LUI  = 4'b1010;
    localparam ALU_AUIPC= 4'b1011;
    
    //=========================================================
    // Functional Unit Types
    //=========================================================
    localparam FU_ALU   = 3'b000;
    localparam FU_MUL   = 3'b001;
    localparam FU_DIV   = 3'b010;
    localparam FU_BR    = 3'b011;
    localparam FU_LSU   = 3'b100;
    localparam FU_CSR   = 3'b101;
    
    //=========================================================
    // Immediate Types
    //=========================================================
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;
    
    //=========================================================
    // Instruction Field Extraction
    //=========================================================
    assign opcode_o = instr_i[6:0];
    assign rd_o     = instr_i[11:7];
    assign funct3_o = instr_i[14:12];
    // U-type (LUI/AUIPC) and J-type (JAL) have no rs1/rs2 fields;
    // zero them to avoid false dependencies in OoO pipeline
    wire no_rs = (instr_i[6:0] == 7'b0110111)   // LUI
              || (instr_i[6:0] == 7'b0010111)   // AUIPC
              || (instr_i[6:0] == 7'b1101111);  // JAL
    assign rs1_o    = no_rs ? 5'd0 : instr_i[19:15];
    assign rs2_o    = no_rs ? 5'd0 : instr_i[24:20];
    assign funct7_o = instr_i[31:25];
    
    //=========================================================
    // Immediate Generation
    //=========================================================
    wire [31:0] imm_i_type, imm_s_type, imm_b_type, imm_u_type, imm_j_type;
    
    assign imm_i_type = {{20{instr_i[31]}}, instr_i[31:20]};
    assign imm_s_type = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
    assign imm_b_type = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
    assign imm_u_type = {instr_i[31:12], 12'b0};
    assign imm_j_type = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
    
    reg [31:0] imm_reg;
    assign imm_o = imm_reg;
    
    //=========================================================
    // M-Extension Detection
    //=========================================================
    wire is_muldiv;
    assign is_muldiv = (opcode_o == OP_REG) && (funct7_o == 7'b0000001);

    //=========================================================
    // Main Decode Logic
    //=========================================================
    always @(*) begin
        // Default values
        reg_write_o = 1'b0;
        mem_read_o = 1'b0;
        mem_write_o = 1'b0;
        branch_o = 1'b0;
        jump_o = 1'b0;
        alu_op_o = ALU_ADD;
        alu_src1_o = 2'b00;  // rs1
        alu_src2_o = 2'b00;  // rs2
        csr_op_o = 1'b0;
        csr_type_o = 3'b0;
        imm_type_o = IMM_I;
        imm_reg = 32'b0;
        fu_type_o = FU_ALU;
        mem_size_o = 2'b10;  // word
        mem_sign_ext_o = 1'b0;
        illegal_instr_o = 1'b0;
        
        case (opcode_o)
            //=================================================
            // LUI
            //=================================================
            OP_LUI: begin
                reg_write_o = 1'b1;
                alu_op_o = ALU_LUI;
                alu_src2_o = 2'b01;  // imm
                imm_type_o = IMM_U;
                imm_reg = imm_u_type;
                fu_type_o = FU_ALU;
            end
            
            //=================================================
            // AUIPC
            //=================================================
            OP_AUIPC: begin
                reg_write_o = 1'b1;
                alu_op_o = ALU_AUIPC;
                alu_src1_o = 2'b01;  // PC
                alu_src2_o = 2'b01;  // imm
                imm_type_o = IMM_U;
                imm_reg = imm_u_type;
                fu_type_o = FU_ALU;
            end
            
            //=================================================
            // JAL
            //=================================================
            OP_JAL: begin
                reg_write_o = 1'b1;
                jump_o = 1'b1;
                alu_src1_o = 2'b01;  // PC
                alu_src2_o = 2'b10;  // 4
                imm_type_o = IMM_J;
                imm_reg = imm_j_type;
                fu_type_o = FU_BR;
            end
            
            //=================================================
            // JALR
            //=================================================
            OP_JALR: begin
                if (funct3_o == 3'b000) begin
                    reg_write_o = 1'b1;
                    jump_o = 1'b1;
                    alu_src1_o = 2'b01;  // PC
                    alu_src2_o = 2'b10;  // 4
                    imm_type_o = IMM_I;
                    imm_reg = imm_i_type;
                    fu_type_o = FU_BR;
                end else begin
                    illegal_instr_o = 1'b1;
                end
            end
            
            //=================================================
            // Branch Instructions
            //=================================================
            OP_BRANCH: begin
                branch_o = 1'b1;
                imm_type_o = IMM_B;
                imm_reg = imm_b_type;
                fu_type_o = FU_BR;
                case (funct3_o)
                    3'b000: alu_op_o = ALU_SUB;  // BEQ
                    3'b001: alu_op_o = ALU_SUB;  // BNE
                    3'b100: alu_op_o = ALU_SLT;  // BLT
                    3'b101: alu_op_o = ALU_SLT;  // BGE
                    3'b110: alu_op_o = ALU_SLTU; // BLTU
                    3'b111: alu_op_o = ALU_SLTU; // BGEU
                    default: illegal_instr_o = 1'b1;
                endcase
            end

            //=================================================
            // Load Instructions
            //=================================================
            OP_LOAD: begin
                reg_write_o = 1'b1;
                mem_read_o = 1'b1;
                alu_op_o = ALU_ADD;
                alu_src2_o = 2'b01;  // imm
                imm_type_o = IMM_I;
                imm_reg = imm_i_type;
                fu_type_o = FU_LSU;
                case (funct3_o)
                    3'b000: begin mem_size_o = 2'b00; mem_sign_ext_o = 1'b1; end // LB
                    3'b001: begin mem_size_o = 2'b01; mem_sign_ext_o = 1'b1; end // LH
                    3'b010: begin mem_size_o = 2'b10; mem_sign_ext_o = 1'b0; end // LW
                    3'b100: begin mem_size_o = 2'b00; mem_sign_ext_o = 1'b0; end // LBU
                    3'b101: begin mem_size_o = 2'b01; mem_sign_ext_o = 1'b0; end // LHU
                    default: illegal_instr_o = 1'b1;
                endcase
            end
            
            //=================================================
            // Store Instructions
            //=================================================
            OP_STORE: begin
                mem_write_o = 1'b1;
                alu_op_o = ALU_ADD;
                alu_src2_o = 2'b01;  // imm
                imm_type_o = IMM_S;
                imm_reg = imm_s_type;
                fu_type_o = FU_LSU;
                case (funct3_o)
                    3'b000: mem_size_o = 2'b00;  // SB
                    3'b001: mem_size_o = 2'b01;  // SH
                    3'b010: mem_size_o = 2'b10;  // SW
                    default: illegal_instr_o = 1'b1;
                endcase
            end
            
            //=================================================
            // Immediate ALU Instructions
            //=================================================
            OP_IMM: begin
                reg_write_o = 1'b1;
                alu_src2_o = 2'b01;  // imm
                imm_type_o = IMM_I;
                imm_reg = imm_i_type;
                fu_type_o = FU_ALU;
                case (funct3_o)
                    3'b000: alu_op_o = ALU_ADD;   // ADDI
                    3'b010: alu_op_o = ALU_SLT;   // SLTI
                    3'b011: alu_op_o = ALU_SLTU;  // SLTIU
                    3'b100: alu_op_o = ALU_XOR;   // XORI
                    3'b110: alu_op_o = ALU_OR;    // ORI
                    3'b111: alu_op_o = ALU_AND;   // ANDI
                    3'b001: begin                  // SLLI
                        if (funct7_o == 7'b0000000) begin
                            alu_op_o = ALU_SLL;
                        end else begin
                            illegal_instr_o = 1'b1;
                        end
                    end
                    3'b101: begin                  // SRLI/SRAI
                        if (funct7_o == 7'b0000000) begin
                            alu_op_o = ALU_SRL;
                        end else if (funct7_o == 7'b0100000) begin
                            alu_op_o = ALU_SRA;
                        end else begin
                            illegal_instr_o = 1'b1;
                        end
                    end
                endcase
            end
            
            //=================================================
            // Register-Register ALU Instructions (R-type)
            //=================================================
            OP_REG: begin
                reg_write_o = 1'b1;
                alu_src2_o = 2'b00;  // rs2
                fu_type_o = FU_ALU;
                
                if (funct7_o == 7'b0000001) begin
                    // M-extension: MUL/DIV instructions
                    case (funct3_o)
                        3'b000: begin  // MUL
                            fu_type_o = FU_MUL;
                            alu_op_o = 4'b0000;
                        end
                        3'b001: begin  // MULH
                            fu_type_o = FU_MUL;
                            alu_op_o = 4'b0001;
                        end
                        3'b010: begin  // MULHSU
                            fu_type_o = FU_MUL;
                            alu_op_o = 4'b0010;
                        end
                        3'b011: begin  // MULHU
                            fu_type_o = FU_MUL;
                            alu_op_o = 4'b0011;
                        end
                        3'b100: begin  // DIV
                            fu_type_o = FU_DIV;
                            alu_op_o = 4'b0000;
                        end
                        3'b101: begin  // DIVU
                            fu_type_o = FU_DIV;
                            alu_op_o = 4'b0001;
                        end
                        3'b110: begin  // REM
                            fu_type_o = FU_DIV;
                            alu_op_o = 4'b0010;
                        end
                        3'b111: begin  // REMU
                            fu_type_o = FU_DIV;
                            alu_op_o = 4'b0011;
                        end
                    endcase
                end else if (funct7_o == 7'b0000000) begin
                    // Base integer instructions
                    case (funct3_o)
                        3'b000: alu_op_o = ALU_ADD;   // ADD
                        3'b001: alu_op_o = ALU_SLL;   // SLL
                        3'b010: alu_op_o = ALU_SLT;   // SLT
                        3'b011: alu_op_o = ALU_SLTU;  // SLTU
                        3'b100: alu_op_o = ALU_XOR;   // XOR
                        3'b101: alu_op_o = ALU_SRL;   // SRL
                        3'b110: alu_op_o = ALU_OR;    // OR
                        3'b111: alu_op_o = ALU_AND;   // AND
                    endcase
                end else if (funct7_o == 7'b0100000) begin
                    // SUB and SRA
                    case (funct3_o)
                        3'b000: alu_op_o = ALU_SUB;   // SUB
                        3'b101: alu_op_o = ALU_SRA;   // SRA
                        default: illegal_instr_o = 1'b1;
                    endcase
                end else begin
                    illegal_instr_o = 1'b1;
                end
            end
            
            //=================================================
            // FENCE Instructions
            //=================================================
            OP_FENCE: begin
                // FENCE and FENCE.I are treated as NOPs in this implementation
                // but we still decode them as valid
                case (funct3_o)
                    3'b000: begin  // FENCE
                        fu_type_o = FU_ALU;
                    end
                    3'b001: begin  // FENCE.I
                        fu_type_o = FU_ALU;
                    end
                    default: illegal_instr_o = 1'b1;
                endcase
            end
            
            //=================================================
            // System Instructions (CSR, ECALL, EBREAK)
            //=================================================
            OP_SYSTEM: begin
                imm_type_o = IMM_I;
                imm_reg = imm_i_type;
                
                if (funct3_o == 3'b000) begin
                    // ECALL, EBREAK, MRET, WFI
                    case (instr_i[31:20])
                        12'b000000000000: begin  // ECALL
                            fu_type_o = FU_CSR;
                        end
                        12'b000000000001: begin  // EBREAK
                            fu_type_o = FU_CSR;
                        end
                        12'b001100000010: begin  // MRET
                            fu_type_o = FU_CSR;
                        end
                        12'b000100000101: begin  // WFI
                            fu_type_o = FU_CSR;
                        end
                        default: illegal_instr_o = 1'b1;
                    endcase
                end else begin
                    // CSR instructions
                    reg_write_o = 1'b1;
                    csr_op_o = 1'b1;
                    fu_type_o = FU_CSR;
                    csr_type_o = funct3_o;
                    
                    case (funct3_o)
                        3'b001: ;  // CSRRW
                        3'b010: ;  // CSRRS
                        3'b011: ;  // CSRRC
                        3'b101: ;  // CSRRWI
                        3'b110: ;  // CSRRSI
                        3'b111: ;  // CSRRCI
                        default: illegal_instr_o = 1'b1;
                    endcase
                end
            end
            
            //=================================================
            // Default: Illegal Instruction
            //=================================================
            default: begin
                illegal_instr_o = 1'b1;
            end
        endcase
    end

endmodule
