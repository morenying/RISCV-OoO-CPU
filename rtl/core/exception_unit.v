//=================================================================
// Module: exception_unit
// Description: Exception Handling Unit
//              Exception priority handling
//              Pipeline flush control
//              PC redirection
// Requirements: 6.2, 6.3
//=================================================================

`timescale 1ns/1ps

module exception_unit #(
    parameter XLEN = 32
)(
    input  wire                clk,
    input  wire                rst_n,
    
    // Exception sources
    input  wire                illegal_instr_i,
    input  wire                instr_misalign_i,
    input  wire                load_misalign_i,
    input  wire                store_misalign_i,
    input  wire                ecall_i,
    input  wire                ebreak_i,
    input  wire                mret_i,
    
    // Exception info
    input  wire [XLEN-1:0]     exc_pc_i,
    input  wire [XLEN-1:0]     exc_tval_i,
    
    // Branch misprediction
    input  wire                branch_mispredict_i,
    input  wire [XLEN-1:0]     branch_target_i,
    
    // CSR interface
    input  wire [XLEN-1:0]     mtvec_i,
    input  wire [XLEN-1:0]     mepc_i,
    input  wire                mie_i,
    input  wire                irq_pending_i,
    
    // Output to CSR unit
    output reg                 exception_o,
    output reg  [3:0]          exc_code_o,
    output reg  [XLEN-1:0]     exc_pc_o,
    output reg  [XLEN-1:0]     exc_tval_o,
    output wire                mret_o,
    
    // Pipeline control
    output wire                flush_o,
    output wire [XLEN-1:0]     redirect_pc_o,
    output wire                redirect_valid_o
);

    //=========================================================
    // Exception Codes
    //=========================================================
    localparam EXC_INSTR_MISALIGN = 4'd0;
    localparam EXC_ILLEGAL_INSTR  = 4'd2;
    localparam EXC_BREAKPOINT     = 4'd3;
    localparam EXC_LOAD_MISALIGN  = 4'd4;
    localparam EXC_STORE_MISALIGN = 4'd6;
    localparam EXC_ECALL_M        = 4'd11;
    
    //=========================================================
    // Exception Priority (lower number = higher priority)
    //=========================================================
    reg        has_exception;
    reg [3:0]  exc_code;
    
    always @(*) begin
        has_exception = 1'b0;
        exc_code = 4'd0;
        
        // Priority order (highest to lowest)
        if (instr_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_INSTR_MISALIGN;
        end else if (illegal_instr_i) begin
            has_exception = 1'b1;
            exc_code = EXC_ILLEGAL_INSTR;
        end else if (ebreak_i) begin
            has_exception = 1'b1;
            exc_code = EXC_BREAKPOINT;
        end else if (ecall_i) begin
            has_exception = 1'b1;
            exc_code = EXC_ECALL_M;
        end else if (load_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_LOAD_MISALIGN;
        end else if (store_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_STORE_MISALIGN;
        end
    end
    
    //=========================================================
    // Output Logic
    //=========================================================
    always @(*) begin
        exception_o = has_exception;
        exc_code_o = exc_code;
        exc_pc_o = exc_pc_i;
        exc_tval_o = exc_tval_i;
    end
    
    assign mret_o = mret_i;
    
    //=========================================================
    // Pipeline Flush and Redirect
    //=========================================================
    assign flush_o = has_exception || mret_i || branch_mispredict_i || 
                     (mie_i && irq_pending_i);
    
    // Redirect PC selection
    reg [XLEN-1:0] redirect_pc;
    
    always @(*) begin
        if (has_exception || (mie_i && irq_pending_i)) begin
            // Exception or interrupt: jump to trap vector
            redirect_pc = mtvec_i;
        end else if (mret_i) begin
            // MRET: return to saved PC
            redirect_pc = mepc_i;
        end else if (branch_mispredict_i) begin
            // Branch misprediction: correct target
            redirect_pc = branch_target_i;
        end else begin
            redirect_pc = exc_pc_i + 4;
        end
    end
    
    assign redirect_pc_o = redirect_pc;
    assign redirect_valid_o = flush_o;

endmodule
