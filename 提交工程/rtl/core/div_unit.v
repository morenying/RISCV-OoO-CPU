//=================================================================
// Module: div_unit
// Description: Division Unit for RISC-V RV32M Extension
//              Implements DIV, DIVU, REM, REMU operations
//              Uses non-restoring division algorithm
//              Variable latency: up to 32 cycles
// Requirements: 11.3, 1.2
//=================================================================

`timescale 1ns/1ps

module div_unit #(
    parameter MAX_LATENCY = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input interface
    input  wire        valid_i,
    input  wire [1:0]  op_i,        // 00:DIV, 01:DIVU, 10:REM, 11:REMU
    input  wire [31:0] src1_i,      // Dividend
    input  wire [31:0] src2_i,      // Divisor
    input  wire [5:0]  prd_i,
    input  wire [4:0]  rob_idx_i,
    
    // Output interface
    output reg         done_o,
    output reg  [31:0] result_o,
    output reg  [5:0]  result_prd_o,
    output reg  [4:0]  result_rob_idx_o,
    
    // Status
    output wire        busy_o
);

    //=========================================================
    // Local Parameters
    //=========================================================
    localparam OP_DIV  = 2'b00;
    localparam OP_DIVU = 2'b01;
    localparam OP_REM  = 2'b10;
    localparam OP_REMU = 2'b11;
    
    localparam STATE_IDLE    = 3'b000;
    localparam STATE_INIT    = 3'b001;
    localparam STATE_COMPUTE = 3'b010;
    localparam STATE_ADJUST  = 3'b011;
    localparam STATE_DONE    = 3'b100;
    
    //=========================================================
    // Internal Signals
    //=========================================================
    reg [2:0]  state, next_state;
    reg [5:0]  cycle_count;
    
    // Operand registers
    reg [1:0]  op_reg;
    reg [5:0]  prd_reg;
    reg [4:0]  rob_idx_reg;
    reg        dividend_sign;
    reg        divisor_sign;
    reg        result_sign;
    reg        remainder_sign;
    
    // Division registers
    reg [31:0] dividend_abs;
    reg [31:0] divisor_abs;
    reg [63:0] partial_remainder;
    reg [31:0] quotient;
    
    // Special case flags
    reg        div_by_zero;
    reg        overflow;
    
    // Intermediate signals
    wire [32:0] sub_result;
    wire        sub_negative;

    //=========================================================
    // Status Output
    //=========================================================
    assign busy_o = (state != STATE_IDLE);
    
    //=========================================================
    // Subtraction for division step
    //=========================================================
    assign sub_result = {1'b0, partial_remainder[62:31]} - {1'b0, divisor_abs};
    assign sub_negative = sub_result[32];
    
    //=========================================================
    // State Machine
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE: begin
                if (valid_i) begin
                    next_state = STATE_INIT;
                end
            end
            STATE_INIT: begin
                if (div_by_zero || overflow) begin
                    next_state = STATE_DONE;
                end else begin
                    next_state = STATE_COMPUTE;
                end
            end
            STATE_COMPUTE: begin
                if (cycle_count == 6'd31) begin
                    next_state = STATE_ADJUST;
                end
            end
            STATE_ADJUST: begin
                next_state = STATE_DONE;
            end
            STATE_DONE: begin
                next_state = STATE_IDLE;
            end
            default: next_state = STATE_IDLE;
        endcase
    end
    
    //=========================================================
    // Division Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_reg <= 2'b0;
            prd_reg <= 6'b0;
            rob_idx_reg <= 5'b0;
            dividend_sign <= 1'b0;
            divisor_sign <= 1'b0;
            result_sign <= 1'b0;
            remainder_sign <= 1'b0;
            dividend_abs <= 32'b0;
            divisor_abs <= 32'b0;
            partial_remainder <= 64'b0;
            quotient <= 32'b0;
            div_by_zero <= 1'b0;
            overflow <= 1'b0;
            cycle_count <= 6'b0;
            done_o <= 1'b0;
            result_o <= 32'b0;
            result_prd_o <= 6'b0;
            result_rob_idx_o <= 5'b0;
        end else begin
            done_o <= 1'b0;
            
            case (state)
                STATE_IDLE: begin
                    if (valid_i) begin
                        op_reg <= op_i;
                        prd_reg <= prd_i;
                        rob_idx_reg <= rob_idx_i;
                        
                        // Check for division by zero
                        div_by_zero <= (src2_i == 32'b0);
                        
                        // Check for signed overflow: -2^31 / -1
                        overflow <= (op_i == OP_DIV || op_i == OP_REM) && 
                                   (src1_i == 32'h80000000) && 
                                   (src2_i == 32'hFFFFFFFF);
                        
                        // Determine signs for signed operations
                        if (op_i == OP_DIV || op_i == OP_REM) begin
                            dividend_sign <= src1_i[31];
                            divisor_sign <= src2_i[31];
                            result_sign <= src1_i[31] ^ src2_i[31];
                            remainder_sign <= src1_i[31];
                            
                            // Get absolute values
                            dividend_abs <= src1_i[31] ? (~src1_i + 1'b1) : src1_i;
                            divisor_abs <= src2_i[31] ? (~src2_i + 1'b1) : src2_i;
                        end else begin
                            dividend_sign <= 1'b0;
                            divisor_sign <= 1'b0;
                            result_sign <= 1'b0;
                            remainder_sign <= 1'b0;
                            dividend_abs <= src1_i;
                            divisor_abs <= src2_i;
                        end
                        
                        cycle_count <= 6'b0;
                    end
                end

                STATE_INIT: begin
                    if (div_by_zero) begin
                        // Division by zero: return all 1s for quotient, dividend for remainder
                        case (op_reg)
                            OP_DIV:  result_o <= 32'hFFFFFFFF;
                            OP_DIVU: result_o <= 32'hFFFFFFFF;
                            OP_REM:  result_o <= dividend_abs;
                            OP_REMU: result_o <= dividend_abs;
                        endcase
                    end else if (overflow) begin
                        // Overflow: -2^31 / -1 = -2^31, remainder = 0
                        case (op_reg)
                            OP_DIV:  result_o <= 32'h80000000;
                            OP_REM:  result_o <= 32'h0;
                            default: result_o <= 32'h0;
                        endcase
                    end else begin
                        // Initialize for division
                        partial_remainder <= {32'b0, dividend_abs};
                        quotient <= 32'b0;
                    end
                end
                
                STATE_COMPUTE: begin
                    // Non-restoring division step
                    // Shift left and subtract/add
                    if (!sub_negative) begin
                        // Subtraction successful
                        partial_remainder <= {sub_result[31:0], partial_remainder[30:0], 1'b0};
                        quotient <= {quotient[30:0], 1'b1};
                    end else begin
                        // Subtraction failed, shift only
                        partial_remainder <= {partial_remainder[62:0], 1'b0};
                        quotient <= {quotient[30:0], 1'b0};
                    end
                    
                    cycle_count <= cycle_count + 1'b1;
                end
                
                STATE_ADJUST: begin
                    // Final adjustment and sign correction
                    case (op_reg)
                        OP_DIV: begin
                            result_o <= result_sign ? (~quotient + 1'b1) : quotient;
                        end
                        OP_DIVU: begin
                            result_o <= quotient;
                        end
                        OP_REM: begin
                            result_o <= remainder_sign ? 
                                       (~partial_remainder[63:32] + 1'b1) : 
                                       partial_remainder[63:32];
                        end
                        OP_REMU: begin
                            result_o <= partial_remainder[63:32];
                        end
                    endcase
                end
                
                STATE_DONE: begin
                    done_o <= 1'b1;
                    result_prd_o <= prd_reg;
                    result_rob_idx_o <= rob_idx_reg;
                end
            endcase
        end
    end

endmodule
