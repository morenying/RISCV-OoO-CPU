//=================================================================
// Module: imm_gen
// Description: Immediate Value Generator for RISC-V
//              Supports I, S, B, U, J type immediates
//              Performs sign extension
// Requirements: 2.3
//=================================================================

`timescale 1ns/1ps

module imm_gen (
    input  wire [31:0] instr_i,
    input  wire [2:0]  imm_type_i,    // Immediate type selector
    output reg  [31:0] imm_o
);

    //=========================================================
    // Immediate Type Encoding
    //=========================================================
    localparam IMM_I = 3'b000;  // I-type: loads, ALU imm, JALR
    localparam IMM_S = 3'b001;  // S-type: stores
    localparam IMM_B = 3'b010;  // B-type: branches
    localparam IMM_U = 3'b011;  // U-type: LUI, AUIPC
    localparam IMM_J = 3'b100;  // J-type: JAL
    
    //=========================================================
    // Instruction Field Extraction
    //=========================================================
    wire [11:0] imm_i_type;
    wire [11:0] imm_s_type;
    wire [12:0] imm_b_type;
    wire [31:0] imm_u_type;
    wire [20:0] imm_j_type;
    
    // I-type: imm[11:0] = instr[31:20]
    assign imm_i_type = instr_i[31:20];
    
    // S-type: imm[11:5] = instr[31:25], imm[4:0] = instr[11:7]
    assign imm_s_type = {instr_i[31:25], instr_i[11:7]};
    
    // B-type: imm[12|10:5|4:1|11] = instr[31|30:25|11:8|7]
    assign imm_b_type = {instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
    
    // U-type: imm[31:12] = instr[31:12], imm[11:0] = 0
    assign imm_u_type = {instr_i[31:12], 12'b0};
    
    // J-type: imm[20|10:1|11|19:12] = instr[31|30:21|20|19:12]
    assign imm_j_type = {instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
    
    //=========================================================
    // Sign Extension and Output Selection
    //=========================================================
    always @(*) begin
        case (imm_type_i)
            IMM_I: imm_o = {{20{imm_i_type[11]}}, imm_i_type};
            IMM_S: imm_o = {{20{imm_s_type[11]}}, imm_s_type};
            IMM_B: imm_o = {{19{imm_b_type[12]}}, imm_b_type};
            IMM_U: imm_o = imm_u_type;
            IMM_J: imm_o = {{11{imm_j_type[20]}}, imm_j_type};
            default: imm_o = 32'b0;
        endcase
    end

endmodule
