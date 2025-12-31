//==============================================================================
// RISC-V Out-of-Order CPU - ALU Unit
// File: alu_unit.v
// Description: Arithmetic Logic Unit for integer operations
//              Single-cycle latency, supports all RV32I ALU operations
//==============================================================================

`include "cpu_defines.vh"

module alu_unit (
    input  wire                         clk,
    input  wire                         rst_n,
    
    // Input interface
    input  wire                         valid_i,
    input  wire [`ALU_OP_WIDTH-1:0]     op_i,
    input  wire [`XLEN-1:0]             src1_i,
    input  wire [`XLEN-1:0]             src2_i,
    input  wire [`PHYS_REG_BITS-1:0]    prd_i,
    input  wire [`ROB_IDX_BITS-1:0]     rob_idx_i,
    input  wire [`XLEN-1:0]             pc_i,       // For AUIPC
    
    // Output interface
    output wire                         valid_o,
    output wire [`XLEN-1:0]             result_o,
    output wire [`PHYS_REG_BITS-1:0]    prd_o,
    output wire [`ROB_IDX_BITS-1:0]     rob_idx_o
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    reg [`XLEN-1:0] result;
    
    // Shift amount (lower 5 bits of src2)
    wire [4:0] shamt = src2_i[4:0];
    
    // Signed comparison
    wire signed [`XLEN-1:0] src1_signed = src1_i;
    wire signed [`XLEN-1:0] src2_signed = src2_i;
    
    //==========================================================================
    // ALU Operations
    //==========================================================================
    
    always @(*) begin
        case (op_i)
            `ALU_OP_ADD:    result = src1_i + src2_i;
            `ALU_OP_SUB:    result = src1_i - src2_i;
            `ALU_OP_SLL:    result = src1_i << shamt;
            `ALU_OP_SLT:    result = (src1_signed < src2_signed) ? 32'd1 : 32'd0;
            `ALU_OP_SLTU:   result = (src1_i < src2_i) ? 32'd1 : 32'd0;
            `ALU_OP_XOR:    result = src1_i ^ src2_i;
            `ALU_OP_SRL:    result = src1_i >> shamt;
            `ALU_OP_SRA:    result = src1_signed >>> shamt;
            `ALU_OP_OR:     result = src1_i | src2_i;
            `ALU_OP_AND:    result = src1_i & src2_i;
            `ALU_OP_LUI:    result = src2_i;                    // LUI: pass immediate
            `ALU_OP_AUIPC:  result = pc_i + src2_i;             // AUIPC: PC + immediate
            default:        result = 32'd0;
        endcase
    end
    
    //==========================================================================
    // Output Assignment (Single-cycle, combinational)
    //==========================================================================
    
    assign valid_o   = valid_i;
    assign result_o  = result;
    assign prd_o     = prd_i;
    assign rob_idx_o = rob_idx_i;

endmodule
