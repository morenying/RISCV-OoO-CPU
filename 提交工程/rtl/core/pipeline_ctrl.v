//=================================================================
// Module: pipeline_ctrl
// Description: Pipeline Controller
//              Stall signal generation
//              Flush signal generation
//              Branch misprediction recovery
//              Exception handling coordination
// Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6
//=================================================================

`timescale 1ns/1ps

module pipeline_ctrl #(
    parameter XLEN = 32
)(
    input  wire                clk,
    input  wire                rst_n,
    
    // Resource availability
    input  wire                rob_full_i,
    input  wire                rs_alu_full_i,
    input  wire                rs_mul_full_i,
    input  wire                rs_lsu_full_i,
    input  wire                rs_br_full_i,
    input  wire                lq_full_i,
    input  wire                sq_full_i,
    input  wire                free_list_empty_i,
    
    // Cache status
    input  wire                icache_miss_i,
    input  wire                dcache_miss_i,
    
    // Branch misprediction
    input  wire                branch_mispredict_i,
    input  wire [XLEN-1:0]     branch_target_i,
    input  wire [2:0]          branch_checkpoint_i,
    
    // Exception
    input  wire                exception_i,
    input  wire [XLEN-1:0]     exception_pc_i,
    
    // MRET
    input  wire                mret_i,
    input  wire [XLEN-1:0]     mepc_i,
    
    // Trap vector
    input  wire [XLEN-1:0]     mtvec_i,
    
    // Stall outputs (per stage)
    output wire                stall_if_o,
    output wire                stall_id_o,
    output wire                stall_rn_o,
    output wire                stall_is_o,
    output wire                stall_ex_o,
    output wire                stall_mem_o,
    output wire                stall_wb_o,
    
    // Flush outputs (per stage)
    output wire                flush_if_o,
    output wire                flush_id_o,
    output wire                flush_rn_o,
    output wire                flush_is_o,
    output wire                flush_ex_o,
    output wire                flush_mem_o,
    
    // Recovery signals
    output wire                recover_o,
    output wire [2:0]          recover_checkpoint_o,
    
    // PC redirect
    output wire                redirect_valid_o,
    output wire [XLEN-1:0]     redirect_pc_o
);

    //=========================================================
    // Stall Conditions
    //=========================================================
    // Backend stall: resources exhausted
    wire backend_stall;
    assign backend_stall = rob_full_i || free_list_empty_i ||
                           (rs_alu_full_i && rs_mul_full_i && rs_lsu_full_i && rs_br_full_i) ||
                           lq_full_i || sq_full_i;
    
    // Frontend stall: I-cache miss
    wire frontend_stall;
    assign frontend_stall = icache_miss_i;
    
    // Memory stall: D-cache miss
    wire memory_stall;
    assign memory_stall = dcache_miss_i;
    
    //=========================================================
    // Stall Signal Generation
    //=========================================================
    // Stalls propagate backwards
    assign stall_wb_o = 1'b0;  // WB never stalls
    assign stall_mem_o = memory_stall;
    assign stall_ex_o = stall_mem_o;
    assign stall_is_o = stall_ex_o || backend_stall;
    assign stall_rn_o = stall_is_o;
    assign stall_id_o = stall_rn_o;
    assign stall_if_o = stall_id_o || frontend_stall;
    
    //=========================================================
    // Flush Conditions
    //=========================================================
    wire flush_all;
    assign flush_all = exception_i || mret_i;
    
    wire flush_speculative;
    assign flush_speculative = branch_mispredict_i;
    
    //=========================================================
    // Flush Signal Generation
    //=========================================================
    // Exception/MRET flushes everything
    // Branch misprediction flushes speculative instructions
    assign flush_if_o = flush_all || flush_speculative;
    assign flush_id_o = flush_all || flush_speculative;
    assign flush_rn_o = flush_all || flush_speculative;
    assign flush_is_o = flush_all || flush_speculative;
    assign flush_ex_o = flush_all || flush_speculative;
    assign flush_mem_o = flush_all;  // Only exception flushes MEM
    
    //=========================================================
    // Recovery Signals
    //=========================================================
    assign recover_o = branch_mispredict_i;
    assign recover_checkpoint_o = branch_checkpoint_i;
    
    //=========================================================
    // PC Redirect
    //=========================================================
    assign redirect_valid_o = exception_i || mret_i || branch_mispredict_i;
    
    reg [XLEN-1:0] redirect_pc;
    always @(*) begin
        if (exception_i) begin
            redirect_pc = mtvec_i;
        end else if (mret_i) begin
            redirect_pc = mepc_i;
        end else if (branch_mispredict_i) begin
            redirect_pc = branch_target_i;
        end else begin
            redirect_pc = 32'h0;
        end
    end
    
    assign redirect_pc_o = redirect_pc;

endmodule
