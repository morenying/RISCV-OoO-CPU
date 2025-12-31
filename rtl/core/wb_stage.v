//=================================================================
// Module: wb_stage
// Description: Writeback Stage
//              ROB commit logic
//              ARF update (via RAT)
//              Physical register release
// Requirements: 2.1, 2.9
//=================================================================

`timescale 1ns/1ps

module wb_stage #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter ARCH_REG_BITS = 5,
    parameter ROB_IDX_BITS = 5,
    parameter EXC_CODE_WIDTH = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // ROB Commit Interface
    //=========================================================
    input  wire                    rob_commit_valid_i,
    output wire                    rob_commit_ready_o,
    input  wire [ROB_IDX_BITS-1:0] rob_commit_idx_i,
    input  wire [ARCH_REG_BITS-1:0] rob_commit_rd_arch_i,
    input  wire [PHYS_REG_BITS-1:0] rob_commit_rd_phys_i,
    input  wire [PHYS_REG_BITS-1:0] rob_commit_rd_phys_old_i,
    input  wire [XLEN-1:0]         rob_commit_result_i,
    input  wire [XLEN-1:0]         rob_commit_pc_i,
    input  wire                    rob_commit_is_branch_i,
    input  wire                    rob_commit_branch_taken_i,
    input  wire [XLEN-1:0]         rob_commit_branch_target_i,
    input  wire                    rob_commit_is_store_i,
    input  wire                    rob_commit_exception_i,
    input  wire [EXC_CODE_WIDTH-1:0] rob_commit_exc_code_i,
    
    //=========================================================
    // Free List Release Interface
    //=========================================================
    output wire                    fl_release_valid_o,
    output wire [PHYS_REG_BITS-1:0] fl_release_preg_o,
    
    //=========================================================
    // RAT Commit Interface
    //=========================================================
    output wire                    rat_commit_valid_o,
    output wire [ARCH_REG_BITS-1:0] rat_commit_rd_arch_o,
    output wire [PHYS_REG_BITS-1:0] rat_commit_rd_phys_o,
    
    //=========================================================
    // Store Commit Interface (to MEM stage)
    //=========================================================
    output wire                    store_commit_valid_o,
    output wire [ROB_IDX_BITS-1:0] store_commit_rob_idx_o,
    
    //=========================================================
    // Exception Interface (to Exception Unit)
    //=========================================================
    output wire                    exception_valid_o,
    output wire [XLEN-1:0]         exception_pc_o,
    output wire [EXC_CODE_WIDTH-1:0] exception_code_o,
    output wire [XLEN-1:0]         exception_tval_o,
    
    //=========================================================
    // BPU Update Interface
    //=========================================================
    output wire                    bpu_update_valid_o,
    output wire [XLEN-1:0]         bpu_update_pc_o,
    output wire                    bpu_update_taken_o,
    output wire [XLEN-1:0]         bpu_update_target_o,
    
    //=========================================================
    // Performance Counters
    //=========================================================
    output wire                    instr_commit_o,
    output wire                    branch_commit_o,
    output wire                    store_commit_o
);

    //=========================================================
    // Commit Logic
    //=========================================================
    
    // Can commit if no exception, or if exception handling is ready
    wire can_commit = rob_commit_valid_i;
    
    // Always ready to accept commits
    assign rob_commit_ready_o = 1'b1;
    
    // Commit happens when valid and ready
    wire do_commit = rob_commit_valid_i && rob_commit_ready_o;
    
    //=========================================================
    // Register Release
    //=========================================================
    // Release old physical register when committing a write
    // Don't release P0 (hardwired zero)
    wire has_rd = (rob_commit_rd_arch_i != 5'd0);
    wire release_old = do_commit && has_rd && !rob_commit_exception_i &&
                       (rob_commit_rd_phys_old_i != 6'd0);
    
    assign fl_release_valid_o = release_old;
    assign fl_release_preg_o = rob_commit_rd_phys_old_i;
    
    //=========================================================
    // RAT Commit
    //=========================================================
    // Update architectural state in RAT
    assign rat_commit_valid_o = do_commit && has_rd && !rob_commit_exception_i;
    assign rat_commit_rd_arch_o = rob_commit_rd_arch_i;
    assign rat_commit_rd_phys_o = rob_commit_rd_phys_i;
    
    //=========================================================
    // Store Commit
    //=========================================================
    assign store_commit_valid_o = do_commit && rob_commit_is_store_i && !rob_commit_exception_i;
    assign store_commit_rob_idx_o = rob_commit_idx_i;
    
    //=========================================================
    // Exception Handling
    //=========================================================
    assign exception_valid_o = do_commit && rob_commit_exception_i;
    assign exception_pc_o = rob_commit_pc_i;
    assign exception_code_o = rob_commit_exc_code_i;
    assign exception_tval_o = 32'd0;  // Could be faulting address for memory exceptions
    
    //=========================================================
    // BPU Update
    //=========================================================
    assign bpu_update_valid_o = do_commit && rob_commit_is_branch_i && !rob_commit_exception_i;
    assign bpu_update_pc_o = rob_commit_pc_i;
    assign bpu_update_taken_o = rob_commit_branch_taken_i;
    assign bpu_update_target_o = rob_commit_branch_target_i;
    
    //=========================================================
    // Performance Counters
    //=========================================================
    assign instr_commit_o = do_commit && !rob_commit_exception_i;
    assign branch_commit_o = do_commit && rob_commit_is_branch_i && !rob_commit_exception_i;
    assign store_commit_o = do_commit && rob_commit_is_store_i && !rob_commit_exception_i;

endmodule
