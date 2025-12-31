//=================================================================
// Module: debug_ctrl
// Description: Debug Control Logic
//              EBREAK handling
//              Debug mode entry/exit
// Requirements: 14.2
//=================================================================

`timescale 1ns/1ps

module debug_ctrl #(
    parameter XLEN = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // Debug Mode Status
    //=========================================================
    output reg                     debug_mode_o,
    
    //=========================================================
    // Debug Entry Triggers
    //=========================================================
    input  wire                    ebreak_i,
    input  wire                    step_done_i,
    input  wire                    halt_req_i,
    input  wire [XLEN-1:0]         ebreak_pc_i,
    
    //=========================================================
    // Debug CSR Interface
    //=========================================================
    input  wire                    ebreakm_i,
    input  wire                    step_i,
    input  wire [XLEN-1:0]         dpc_i,
    
    //=========================================================
    // Debug Entry/Exit Signals
    //=========================================================
    output reg                     debug_entry_o,
    output reg  [2:0]              debug_cause_o,
    output reg  [XLEN-1:0]         debug_pc_o,
    
    //=========================================================
    // Pipeline Control
    //=========================================================
    output wire                    debug_halt_o,
    output wire                    debug_resume_o,
    output wire [XLEN-1:0]         resume_pc_o,
    
    //=========================================================
    // DRET Instruction
    //=========================================================
    input  wire                    dret_i
);

    // Debug cause codes
    localparam CAUSE_EBREAK   = 3'd1;
    localparam CAUSE_TRIGGER  = 3'd2;
    localparam CAUSE_HALTREQ  = 3'd3;
    localparam CAUSE_STEP     = 3'd4;
    localparam CAUSE_RESETHALT = 3'd5;
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam RUNNING = 2'b00;
    localparam HALTING = 2'b01;
    localparam HALTED  = 2'b10;
    localparam RESUMING = 2'b11;
    
    reg [1:0] state;
    reg step_pending;
    
    //=========================================================
    // Debug Entry Detection
    //=========================================================
    wire enter_debug = (ebreak_i && ebreakm_i) ||
                       halt_req_i ||
                       (step_done_i && step_pending);
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= RUNNING;
            debug_mode_o <= 1'b0;
            debug_entry_o <= 1'b0;
            debug_cause_o <= 3'd0;
            debug_pc_o <= 32'd0;
            step_pending <= 1'b0;
        end else begin
            debug_entry_o <= 1'b0;  // Pulse
            
            case (state)
                RUNNING: begin
                    if (enter_debug) begin
                        state <= HALTING;
                        debug_entry_o <= 1'b1;
                        debug_pc_o <= ebreak_pc_i;
                        
                        // Determine cause
                        if (ebreak_i && ebreakm_i)
                            debug_cause_o <= CAUSE_EBREAK;
                        else if (halt_req_i)
                            debug_cause_o <= CAUSE_HALTREQ;
                        else if (step_done_i && step_pending)
                            debug_cause_o <= CAUSE_STEP;
                        else
                            debug_cause_o <= 3'd0;
                        
                        step_pending <= 1'b0;
                    end
                end
                
                HALTING: begin
                    // Wait for pipeline to drain
                    state <= HALTED;
                    debug_mode_o <= 1'b1;
                end
                
                HALTED: begin
                    if (dret_i) begin
                        state <= RESUMING;
                        step_pending <= step_i;
                    end
                end
                
                RESUMING: begin
                    state <= RUNNING;
                    debug_mode_o <= 1'b0;
                end
                
                default: state <= RUNNING;
            endcase
        end
    end
    
    //=========================================================
    // Output Signals
    //=========================================================
    assign debug_halt_o = (state == HALTING) || (state == HALTED);
    assign debug_resume_o = (state == RESUMING);
    assign resume_pc_o = dpc_i;

endmodule
