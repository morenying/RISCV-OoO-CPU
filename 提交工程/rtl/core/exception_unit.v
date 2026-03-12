//=================================================================
// Module: exception_unit
// Description: Exception Handling Unit
//              Exception priority handling
//              Pipeline flush control
//              PC redirection
//              Bus error handling
// Requirements: 6.2, 6.3, 7.1, 7.2, 7.3
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
    
    // Bus error sources (new for 15.2/15.3)
    input  wire                instr_access_fault_i,  // Instruction fetch bus error
    input  wire                load_access_fault_i,   // Load bus error
    input  wire                store_access_fault_i,  // Store bus error
    
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
    input  wire [3:0]          irq_code_i,            // Interrupt code from INTC
    
    // Output to CSR unit
    output reg                 exception_o,
    output reg                 interrupt_o,           // Distinguish interrupt from exception
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
    // Exception Codes (RISC-V Privileged Spec)
    //=========================================================
    localparam EXC_INSTR_MISALIGN    = 4'd0;   // Instruction address misaligned
    localparam EXC_INSTR_ACCESS      = 4'd1;   // Instruction access fault
    localparam EXC_ILLEGAL_INSTR     = 4'd2;   // Illegal instruction
    localparam EXC_BREAKPOINT        = 4'd3;   // Breakpoint
    localparam EXC_LOAD_MISALIGN     = 4'd4;   // Load address misaligned
    localparam EXC_LOAD_ACCESS       = 4'd5;   // Load access fault
    localparam EXC_STORE_MISALIGN    = 4'd6;   // Store/AMO address misaligned
    localparam EXC_STORE_ACCESS      = 4'd7;   // Store/AMO access fault
    localparam EXC_ECALL_U           = 4'd8;   // Environment call from U-mode
    localparam EXC_ECALL_S           = 4'd9;   // Environment call from S-mode
    localparam EXC_ECALL_M           = 4'd11;  // Environment call from M-mode
    localparam EXC_INSTR_PAGE        = 4'd12;  // Instruction page fault
    localparam EXC_LOAD_PAGE         = 4'd13;  // Load page fault
    localparam EXC_STORE_PAGE        = 4'd15;  // Store/AMO page fault
    
    //=========================================================
    // Interrupt Codes (RISC-V Privileged Spec)
    //=========================================================
    localparam INT_SW_M              = 4'd3;   // Machine software interrupt
    localparam INT_TIMER_M           = 4'd7;   // Machine timer interrupt
    localparam INT_EXT_M             = 4'd11;  // Machine external interrupt
    
    //=========================================================
    // Exception Priority (lower number = higher priority)
    // RISC-V Spec: Interrupts have higher priority than exceptions
    // Among exceptions: instruction fetch > decode > memory
    //=========================================================
    reg        has_exception;
    reg        has_interrupt;
    reg [3:0]  exc_code;
    
    always @(*) begin
        has_exception = 1'b0;
        has_interrupt = 1'b0;
        exc_code = 4'd0;
        
        // Check for interrupts first (higher priority)
        if (mie_i && irq_pending_i) begin
            has_interrupt = 1'b1;
            exc_code = irq_code_i;
        end
        // Exception priority order (highest to lowest)
        // 1. Instruction fetch exceptions
        else if (instr_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_INSTR_MISALIGN;
        end else if (instr_access_fault_i) begin
            has_exception = 1'b1;
            exc_code = EXC_INSTR_ACCESS;
        end
        // 2. Decode exceptions
        else if (illegal_instr_i) begin
            has_exception = 1'b1;
            exc_code = EXC_ILLEGAL_INSTR;
        end else if (ebreak_i) begin
            has_exception = 1'b1;
            exc_code = EXC_BREAKPOINT;
        end else if (ecall_i) begin
            has_exception = 1'b1;
            exc_code = EXC_ECALL_M;
        end
        // 3. Memory exceptions (load before store)
        else if (load_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_LOAD_MISALIGN;
        end else if (load_access_fault_i) begin
            has_exception = 1'b1;
            exc_code = EXC_LOAD_ACCESS;
        end else if (store_misalign_i) begin
            has_exception = 1'b1;
            exc_code = EXC_STORE_MISALIGN;
        end else if (store_access_fault_i) begin
            has_exception = 1'b1;
            exc_code = EXC_STORE_ACCESS;
        end
    end
    
    //=========================================================
    // Output Logic
    //=========================================================
    always @(*) begin
        exception_o = has_exception;
        interrupt_o = has_interrupt;
        exc_code_o = exc_code;
        exc_pc_o = exc_pc_i;
        // For access faults, tval should contain the faulting address
        exc_tval_o = exc_tval_i;
    end
    
    assign mret_o = mret_i;
    
    //=========================================================
    // Pipeline Flush and Redirect
    //=========================================================
    assign flush_o = has_exception || has_interrupt || mret_i || branch_mispredict_i;
    
    // Redirect PC selection
    // mtvec modes: 0 = Direct (all traps to BASE), 1 = Vectored (interrupts to BASE + 4*cause)
    wire [1:0]      mtvec_mode = mtvec_i[1:0];
    wire [XLEN-1:0] mtvec_base = {mtvec_i[XLEN-1:2], 2'b00};
    
    reg [XLEN-1:0] redirect_pc;
    
    always @(*) begin
        if (has_interrupt) begin
            // Interrupt: check vectored mode
            if (mtvec_mode == 2'b01) begin
                // Vectored mode: BASE + 4 * cause
                redirect_pc = mtvec_base + {26'b0, exc_code, 2'b00};
            end else begin
                // Direct mode: all to BASE
                redirect_pc = mtvec_base;
            end
        end else if (has_exception) begin
            // Exception: always to BASE (even in vectored mode)
            redirect_pc = mtvec_base;
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
