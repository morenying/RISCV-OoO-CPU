//==============================================================================
// RISC-V Out-of-Order CPU - Multiplier Unit
// File: mul_unit.v
// Description: Pipelined multiplier for RV32M extension
//              3-cycle latency, supports MUL/MULH/MULHSU/MULHU
//==============================================================================

`timescale 1ns/1ps

`include "cpu_defines.vh"

module mul_unit #(
    parameter LATENCY = 3               // Pipeline stages
) (
    input  wire                         clk,
    input  wire                         rst_n,
    
    // Input interface
    input  wire                         valid_i,
    input  wire [`MUL_OP_WIDTH-1:0]     op_i,
    input  wire [`XLEN-1:0]             src1_i,
    input  wire [`XLEN-1:0]             src2_i,
    input  wire [`PHYS_REG_BITS-1:0]    prd_i,
    input  wire [`ROB_IDX_BITS-1:0]     rob_idx_i,
    
    // Output interface
    output wire                         valid_o,
    output wire [`XLEN-1:0]             result_o,
    output wire [`PHYS_REG_BITS-1:0]    prd_o,
    output wire [`ROB_IDX_BITS-1:0]     rob_idx_o,
    
    // Status
    output wire                         busy_o,
    
    // Flush
    input  wire                         flush_i
);

    //==========================================================================
    // Pipeline Registers
    //==========================================================================
    
    // Stage 1: Input capture and sign extension
    reg                         stage1_valid;
    reg [`MUL_OP_WIDTH-1:0]     stage1_op;
    reg [32:0]                  stage1_src1;    // 33-bit for signed extension
    reg [32:0]                  stage1_src2;    // 33-bit for signed extension
    reg [`PHYS_REG_BITS-1:0]    stage1_prd;
    reg [`ROB_IDX_BITS-1:0]     stage1_rob_idx;
    
    // Stage 2: Multiplication
    reg                         stage2_valid;
    reg [`MUL_OP_WIDTH-1:0]     stage2_op;
    reg [65:0]                  stage2_product; // 66-bit product
    reg [`PHYS_REG_BITS-1:0]    stage2_prd;
    reg [`ROB_IDX_BITS-1:0]     stage2_rob_idx;
    
    // Stage 3: Result selection
    reg                         stage3_valid;
    reg [`XLEN-1:0]             stage3_result;
    reg [`PHYS_REG_BITS-1:0]    stage3_prd;
    reg [`ROB_IDX_BITS-1:0]     stage3_rob_idx;
    
    //==========================================================================
    // Stage 1: Input Capture and Sign Extension
    //==========================================================================
    
    wire src1_signed = (op_i == `MUL_OP_MUL) || (op_i == `MUL_OP_MULH) || (op_i == `MUL_OP_MULHSU);
    wire src2_signed = (op_i == `MUL_OP_MUL) || (op_i == `MUL_OP_MULH);
    
    wire [32:0] src1_ext = src1_signed ? {src1_i[31], src1_i} : {1'b0, src1_i};
    wire [32:0] src2_ext = src2_signed ? {src2_i[31], src2_i} : {1'b0, src2_i};
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid   <= 1'b0;
            stage1_op      <= 2'b0;
            stage1_src1    <= 33'b0;
            stage1_src2    <= 33'b0;
            stage1_prd     <= {`PHYS_REG_BITS{1'b0}};
            stage1_rob_idx <= {`ROB_IDX_BITS{1'b0}};
        end else if (flush_i) begin
            stage1_valid   <= 1'b0;
        end else begin
            stage1_valid   <= valid_i;
            stage1_op      <= op_i;
            stage1_src1    <= src1_ext;
            stage1_src2    <= src2_ext;
            stage1_prd     <= prd_i;
            stage1_rob_idx <= rob_idx_i;
        end
    end
    
    //==========================================================================
    // Stage 2: Multiplication (signed 33x33 -> 66 bits)
    //==========================================================================
    
    wire signed [32:0] stage1_src1_signed = stage1_src1;
    wire signed [32:0] stage1_src2_signed = stage1_src2;
    wire signed [65:0] product_signed = stage1_src1_signed * stage1_src2_signed;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage2_valid   <= 1'b0;
            stage2_op      <= 2'b0;
            stage2_product <= 66'b0;
            stage2_prd     <= {`PHYS_REG_BITS{1'b0}};
            stage2_rob_idx <= {`ROB_IDX_BITS{1'b0}};
        end else if (flush_i) begin
            stage2_valid   <= 1'b0;
        end else begin
            stage2_valid   <= stage1_valid;
            stage2_op      <= stage1_op;
            stage2_product <= product_signed;
            stage2_prd     <= stage1_prd;
            stage2_rob_idx <= stage1_rob_idx;
        end
    end
    
    //==========================================================================
    // Stage 3: Result Selection
    //==========================================================================
    
    wire [`XLEN-1:0] result_low  = stage2_product[31:0];
    wire [`XLEN-1:0] result_high = stage2_product[63:32];
    
    reg [`XLEN-1:0] result_mux;
    
    always @(*) begin
        case (stage2_op)
            `MUL_OP_MUL:    result_mux = result_low;
            `MUL_OP_MULH:   result_mux = result_high;
            `MUL_OP_MULHSU: result_mux = result_high;
            `MUL_OP_MULHU:  result_mux = result_high;
            default:        result_mux = result_low;
        endcase
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage3_valid   <= 1'b0;
            stage3_result  <= {`XLEN{1'b0}};
            stage3_prd     <= {`PHYS_REG_BITS{1'b0}};
            stage3_rob_idx <= {`ROB_IDX_BITS{1'b0}};
        end else if (flush_i) begin
            stage3_valid   <= 1'b0;
        end else begin
            stage3_valid   <= stage2_valid;
            stage3_result  <= result_mux;
            stage3_prd     <= stage2_prd;
            stage3_rob_idx <= stage2_rob_idx;
        end
    end
    
    //==========================================================================
    // Output Assignment
    //==========================================================================
    
    assign valid_o   = stage3_valid;
    assign result_o  = stage3_result;
    assign prd_o     = stage3_prd;
    assign rob_idx_o = stage3_rob_idx;
    
    // Busy when any stage has valid data
    assign busy_o = stage1_valid | stage2_valid | stage3_valid;

endmodule
