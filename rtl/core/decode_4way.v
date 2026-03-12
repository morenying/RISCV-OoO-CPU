//=================================================================
// Module: decode_4way
// Description: 4-Way Superscalar Instruction Decoder
//              Decodes 4 instructions per cycle
//              Outputs decoded information for rename stage
//=================================================================

`timescale 1ns/1ps

module decode_4way #(
    parameter XLEN = 32,
    parameter FETCH_WIDTH = 4  // 4 instructions per cycle
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    //=========================================================
    // Fetch Interface (4 instructions)
    //=========================================================
    input  wire                 fetch_valid_i,
    input  wire [127:0]         fetch_insts_i,        // 4 x 32-bit instructions
    input  wire [XLEN-1:0]      fetch_pc_i,
    input  wire [3:0]           fetch_valid_mask_i,   // Which instructions are valid
    output wire                 fetch_ready_o,
    
    //=========================================================
    // Decoded Output (to Rename)
    //=========================================================
    output reg                  dec_valid_o,
    output reg  [3:0]           dec_valid_mask_o,
    
    // Per-instruction decoded signals (4 slots)
    output reg  [XLEN-1:0]      dec_pc_o        [0:FETCH_WIDTH-1],
    output reg  [31:0]          dec_inst_o      [0:FETCH_WIDTH-1],
    
    // Register specifiers
    output reg  [4:0]           dec_rs1_o       [0:FETCH_WIDTH-1],
    output reg  [4:0]           dec_rs2_o       [0:FETCH_WIDTH-1],
    output reg  [4:0]           dec_rd_o        [0:FETCH_WIDTH-1],
    output reg                  dec_rs1_valid_o [0:FETCH_WIDTH-1],
    output reg                  dec_rs2_valid_o [0:FETCH_WIDTH-1],
    output reg                  dec_rd_valid_o  [0:FETCH_WIDTH-1],
    
    // Immediate
    output reg  [XLEN-1:0]      dec_imm_o       [0:FETCH_WIDTH-1],
    output reg                  dec_use_imm_o   [0:FETCH_WIDTH-1],
    
    // ALU/FU type
    output reg  [3:0]           dec_alu_op_o    [0:FETCH_WIDTH-1],
    output reg  [2:0]           dec_fu_type_o   [0:FETCH_WIDTH-1],
    
    // Memory
    output reg                  dec_is_load_o   [0:FETCH_WIDTH-1],
    output reg                  dec_is_store_o  [0:FETCH_WIDTH-1],
    output reg  [2:0]           dec_mem_size_o  [0:FETCH_WIDTH-1],
    output reg                  dec_mem_signed_o[0:FETCH_WIDTH-1],
    
    // Branch/Jump
    output reg                  dec_is_branch_o [0:FETCH_WIDTH-1],
    output reg                  dec_is_jal_o    [0:FETCH_WIDTH-1],
    output reg                  dec_is_jalr_o   [0:FETCH_WIDTH-1],
    output reg  [2:0]           dec_branch_type_o[0:FETCH_WIDTH-1],
    
    // Special
    output reg                  dec_is_csr_o    [0:FETCH_WIDTH-1],
    output reg                  dec_is_fence_o  [0:FETCH_WIDTH-1],
    output reg                  dec_is_mret_o   [0:FETCH_WIDTH-1],
    output reg                  dec_is_sret_o   [0:FETCH_WIDTH-1],
    output reg                  dec_is_ecall_o  [0:FETCH_WIDTH-1],
    output reg                  dec_is_ebreak_o [0:FETCH_WIDTH-1],
    output reg                  dec_is_wfi_o    [0:FETCH_WIDTH-1],
    output reg                  dec_is_sfence_o [0:FETCH_WIDTH-1],
    output reg                  dec_is_atomic_o [0:FETCH_WIDTH-1],
    output reg  [4:0]           dec_atomic_op_o [0:FETCH_WIDTH-1],
    
    output reg                  dec_illegal_o   [0:FETCH_WIDTH-1],
    
    //=========================================================
    // Pipeline Control
    //=========================================================
    input  wire                 stall_i,
    input  wire                 flush_i
);

    //=========================================================
    // Opcode Constants
    //=========================================================
    localparam OP_LOAD      = 7'b0000011;
    localparam OP_STORE     = 7'b0100011;
    localparam OP_BRANCH    = 7'b1100011;
    localparam OP_JAL       = 7'b1101111;
    localparam OP_JALR      = 7'b1100111;
    localparam OP_IMM       = 7'b0010011;
    localparam OP_REG       = 7'b0110011;
    localparam OP_LUI       = 7'b0110111;
    localparam OP_AUIPC     = 7'b0010111;
    localparam OP_SYSTEM    = 7'b1110011;
    localparam OP_FENCE     = 7'b0001111;
    localparam OP_AMO       = 7'b0101111;
    
    //=========================================================
    // FU Types
    //=========================================================
    localparam FU_ALU    = 3'd0;
    localparam FU_MUL    = 3'd1;
    localparam FU_DIV    = 3'd2;
    localparam FU_LSU    = 3'd3;
    localparam FU_BRU    = 3'd4;
    localparam FU_CSR    = 3'd5;
    localparam FU_AMO    = 3'd6;
    
    //=========================================================
    // Extract Instructions
    //=========================================================
    wire [31:0] inst [0:FETCH_WIDTH-1];
    assign inst[0] = fetch_insts_i[31:0];
    assign inst[1] = fetch_insts_i[63:32];
    assign inst[2] = fetch_insts_i[95:64];
    assign inst[3] = fetch_insts_i[127:96];
    
    //=========================================================
    // Ready signal
    //=========================================================
    assign fetch_ready_o = !stall_i;
    
    //=========================================================
    // Decode each instruction
    //=========================================================
    genvar g;
    generate
        for (g = 0; g < FETCH_WIDTH; g = g + 1) begin : gen_decode
            // Instruction fields
            wire [6:0] opcode = inst[g][6:0];
            wire [4:0] rd     = inst[g][11:7];
            wire [2:0] funct3 = inst[g][14:12];
            wire [4:0] rs1    = inst[g][19:15];
            wire [4:0] rs2    = inst[g][24:20];
            wire [6:0] funct7 = inst[g][31:25];
            
            // Immediate generation
            wire [XLEN-1:0] imm_i = {{20{inst[g][31]}}, inst[g][31:20]};
            wire [XLEN-1:0] imm_s = {{20{inst[g][31]}}, inst[g][31:25], inst[g][11:7]};
            wire [XLEN-1:0] imm_b = {{19{inst[g][31]}}, inst[g][31], inst[g][7], inst[g][30:25], inst[g][11:8], 1'b0};
            wire [XLEN-1:0] imm_u = {inst[g][31:12], 12'b0};
            wire [XLEN-1:0] imm_j = {{11{inst[g][31]}}, inst[g][31], inst[g][19:12], inst[g][20], inst[g][30:21], 1'b0};
            
            // Decode logic (combinational)
            always @(*) begin
                // Defaults
                dec_rs1_o[g] = rs1;
                dec_rs2_o[g] = rs2;
                dec_rd_o[g] = rd;
                dec_rs1_valid_o[g] = 0;
                dec_rs2_valid_o[g] = 0;
                dec_rd_valid_o[g] = 0;
                dec_imm_o[g] = 0;
                dec_use_imm_o[g] = 0;
                dec_alu_op_o[g] = 0;
                dec_fu_type_o[g] = FU_ALU;
                dec_is_load_o[g] = 0;
                dec_is_store_o[g] = 0;
                dec_mem_size_o[g] = funct3;
                dec_mem_signed_o[g] = !funct3[2];
                dec_is_branch_o[g] = 0;
                dec_is_jal_o[g] = 0;
                dec_is_jalr_o[g] = 0;
                dec_branch_type_o[g] = funct3;
                dec_is_csr_o[g] = 0;
                dec_is_fence_o[g] = 0;
                dec_is_mret_o[g] = 0;
                dec_is_sret_o[g] = 0;
                dec_is_ecall_o[g] = 0;
                dec_is_ebreak_o[g] = 0;
                dec_is_wfi_o[g] = 0;
                dec_is_sfence_o[g] = 0;
                dec_is_atomic_o[g] = 0;
                dec_atomic_op_o[g] = funct7[6:2];
                dec_illegal_o[g] = 0;
                
                case (opcode)
                    OP_LUI: begin
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_u;
                        dec_use_imm_o[g] = 1;
                        dec_alu_op_o[g] = 4'd0;  // Pass through
                    end
                    
                    OP_AUIPC: begin
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_u;
                        dec_use_imm_o[g] = 1;
                        dec_alu_op_o[g] = 4'd1;  // ADD to PC
                    end
                    
                    OP_JAL: begin
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_j;
                        dec_is_jal_o[g] = 1;
                        dec_fu_type_o[g] = FU_BRU;
                        dec_alu_op_o[g] = 4'b1000;  // JAL: bit[3]=1 (unconditional), bit[4]=0
                    end
                    
                    OP_JALR: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_i;
                        dec_use_imm_o[g] = 1;
                        dec_is_jalr_o[g] = 1;
                        dec_fu_type_o[g] = FU_BRU;
                        dec_alu_op_o[g] = 4'b1001;  // JALR: bit[3]=1, bit[0]=1 to distinguish
                    end
                    
                    OP_BRANCH: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rs2_valid_o[g] = 1;
                        dec_imm_o[g] = imm_b;
                        dec_is_branch_o[g] = 1;
                        dec_fu_type_o[g] = FU_BRU;
                    end
                    
                    OP_LOAD: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_i;
                        dec_use_imm_o[g] = 1;
                        dec_is_load_o[g] = 1;
                        dec_fu_type_o[g] = FU_LSU;
                    end
                    
                    OP_STORE: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rs2_valid_o[g] = 1;
                        dec_imm_o[g] = imm_s;
                        dec_use_imm_o[g] = 1;
                        dec_is_store_o[g] = 1;
                        dec_fu_type_o[g] = FU_LSU;
                    end
                    
                    OP_IMM: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rd_valid_o[g] = 1;
                        dec_imm_o[g] = imm_i;
                        dec_use_imm_o[g] = 1;
                        dec_alu_op_o[g] = {1'b0, funct3};
                        
                        // SRAI vs SRLI
                        if (funct3 == 3'b101 && funct7[5]) begin
                            dec_alu_op_o[g] = 4'b1101;
                        end
                    end
                    
                    OP_REG: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rs2_valid_o[g] = 1;
                        dec_rd_valid_o[g] = 1;
                        dec_alu_op_o[g] = {funct7[5], funct3};
                        
                        // MUL/DIV extension
                        if (funct7 == 7'b0000001) begin
                            if (funct3[2]) begin
                                dec_fu_type_o[g] = FU_DIV;
                            end else begin
                                dec_fu_type_o[g] = FU_MUL;
                            end
                        end
                    end
                    
                    OP_FENCE: begin
                        dec_is_fence_o[g] = 1;
                    end
                    
                    OP_SYSTEM: begin
                        if (funct3 == 3'b000) begin
                            case (inst[g][31:20])
                                12'h000: dec_is_ecall_o[g] = 1;
                                12'h001: dec_is_ebreak_o[g] = 1;
                                12'h302: dec_is_mret_o[g] = 1;
                                12'h102: dec_is_sret_o[g] = 1;
                                12'h105: dec_is_wfi_o[g] = 1;
                                default: begin
                                    if (funct7 == 7'b0001001) begin
                                        dec_is_sfence_o[g] = 1;
                                        dec_rs1_valid_o[g] = 1;
                                        dec_rs2_valid_o[g] = 1;
                                    end else begin
                                        dec_illegal_o[g] = 1;
                                    end
                                end
                            endcase
                        end else begin
                            // CSR instructions
                            dec_is_csr_o[g] = 1;
                            dec_rd_valid_o[g] = 1;
                            dec_fu_type_o[g] = FU_CSR;
                            
                            if (!funct3[2]) begin
                                dec_rs1_valid_o[g] = 1;
                            end else begin
                                dec_imm_o[g] = {27'b0, rs1};  // UIMM
                                dec_use_imm_o[g] = 1;
                            end
                        end
                    end
                    
                    OP_AMO: begin
                        dec_rs1_valid_o[g] = 1;
                        dec_rd_valid_o[g] = 1;
                        dec_is_atomic_o[g] = 1;
                        dec_fu_type_o[g] = FU_AMO;
                        
                        // LR doesn't use rs2
                        if (funct7[6:2] != 5'b00010) begin
                            dec_rs2_valid_o[g] = 1;
                        end
                    end
                    
                    default: begin
                        dec_illegal_o[g] = 1;
                    end
                endcase
            end
        end
    endgenerate
    
    //=========================================================
    // Pipeline Register
    //=========================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            dec_valid_o <= 0;
            dec_valid_mask_o <= 0;
            
            for (i = 0; i < FETCH_WIDTH; i = i + 1) begin
                dec_pc_o[i] <= 0;
                dec_inst_o[i] <= 0;
            end
        end else if (!stall_i) begin
            dec_valid_o <= fetch_valid_i;
            dec_valid_mask_o <= fetch_valid_mask_i;
            
            for (i = 0; i < FETCH_WIDTH; i = i + 1) begin
                dec_pc_o[i] <= fetch_pc_i + (i << 2);
                dec_inst_o[i] <= inst[i];
            end
        end
    end

endmodule
