//=================================================================
// Testbench: tb_pipeline_ctrl
// Description: Pipeline Control Property Tests
//              Property 14: Pipeline Stall Correctness
// Validates: Requirements 12.1, 12.2, 12.3
//=================================================================

`timescale 1ns/1ps

module tb_pipeline_ctrl;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;
    
    //=========================================================
    // Resource Availability
    //=========================================================
    reg                rob_full;
    reg                rs_alu_full;
    reg                rs_mul_full;
    reg                rs_lsu_full;
    reg                rs_br_full;
    reg                lq_full;
    reg                sq_full;
    reg                free_list_empty;
    
    //=========================================================
    // Cache Status
    //=========================================================
    reg                icache_miss;
    reg                dcache_miss;
    
    //=========================================================
    // Branch Misprediction
    //=========================================================
    reg                branch_mispredict;
    reg  [XLEN-1:0]    branch_target;
    reg  [2:0]         branch_checkpoint;
    
    //=========================================================
    // Exception
    //=========================================================
    reg                exception;
    reg  [XLEN-1:0]    exception_pc;
    
    //=========================================================
    // MRET
    //=========================================================
    reg                mret;
    reg  [XLEN-1:0]    mepc;
    
    //=========================================================
    // Trap Vector
    //=========================================================
    reg  [XLEN-1:0]    mtvec;
    
    //=========================================================
    // Stall Outputs
    //=========================================================
    wire               stall_if;
    wire               stall_id;
    wire               stall_rn;
    wire               stall_is;
    wire               stall_ex;
    wire               stall_mem;
    wire               stall_wb;
    
    //=========================================================
    // Flush Outputs
    //=========================================================
    wire               flush_if;
    wire               flush_id;
    wire               flush_rn;
    wire               flush_is;
    wire               flush_ex;
    wire               flush_mem;
    
    //=========================================================
    // Recovery Signals
    //=========================================================
    wire               recover;
    wire [2:0]         recover_checkpoint;
    
    //=========================================================
    // PC Redirect
    //=========================================================
    wire               redirect_valid;
    wire [XLEN-1:0]    redirect_pc;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================
    // DUT Instantiation
    //=========================================================
    pipeline_ctrl #(
        .XLEN(XLEN)
    ) u_pipeline_ctrl (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .rob_full_i             (rob_full),
        .rs_alu_full_i          (rs_alu_full),
        .rs_mul_full_i          (rs_mul_full),
        .rs_lsu_full_i          (rs_lsu_full),
        .rs_br_full_i           (rs_br_full),
        .lq_full_i              (lq_full),
        .sq_full_i              (sq_full),
        .free_list_empty_i      (free_list_empty),
        .icache_miss_i          (icache_miss),
        .dcache_miss_i          (dcache_miss),
        .branch_mispredict_i    (branch_mispredict),
        .branch_target_i        (branch_target),
        .branch_checkpoint_i    (branch_checkpoint),
        .exception_i            (exception),
        .exception_pc_i         (exception_pc),
        .mret_i                 (mret),
        .mepc_i                 (mepc),
        .mtvec_i                (mtvec),
        .stall_if_o             (stall_if),
        .stall_id_o             (stall_id),
        .stall_rn_o             (stall_rn),
        .stall_is_o             (stall_is),
        .stall_ex_o             (stall_ex),
        .stall_mem_o            (stall_mem),
        .stall_wb_o             (stall_wb),
        .flush_if_o             (flush_if),
        .flush_id_o             (flush_id),
        .flush_rn_o             (flush_rn),
        .flush_is_o             (flush_is),
        .flush_ex_o             (flush_ex),
        .flush_mem_o            (flush_mem),
        .recover_o              (recover),
        .recover_checkpoint_o   (recover_checkpoint),
        .redirect_valid_o       (redirect_valid),
        .redirect_pc_o          (redirect_pc)
    );

    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;

    //=========================================================
    // Helper Tasks
    //=========================================================
    
    task clear_inputs;
        begin
            rob_full = 0;
            rs_alu_full = 0;
            rs_mul_full = 0;
            rs_lsu_full = 0;
            rs_br_full = 0;
            lq_full = 0;
            sq_full = 0;
            free_list_empty = 0;
            icache_miss = 0;
            dcache_miss = 0;
            branch_mispredict = 0;
            branch_target = 0;
            branch_checkpoint = 0;
            exception = 0;
            exception_pc = 0;
            mret = 0;
        end
    endtask

    //=========================================================
    // Property 14: Pipeline Stall Correctness Tests
    //=========================================================
    
    task test_no_stall_normal;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            @(posedge clk);
            
            if (!stall_if && !stall_id && !stall_rn && !stall_is && 
                !stall_ex && !stall_mem && !stall_wb) begin
                pass_count = pass_count + 1;
                $display("[PASS] No Stall Normal: all stages running");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] No Stall Normal: unexpected stall");
            end
        end
    endtask
    
    task test_rob_full_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            rob_full = 1;
            @(posedge clk);
            
            // ROB full should stall frontend (IF through IS)
            if (stall_if && stall_id && stall_rn && stall_is) begin
                pass_count = pass_count + 1;
                $display("[PASS] ROB Full Stall: frontend stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] ROB Full Stall: stall_if=%b, stall_is=%b", stall_if, stall_is);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_free_list_empty_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            free_list_empty = 1;
            @(posedge clk);
            
            if (stall_rn && stall_is) begin
                pass_count = pass_count + 1;
                $display("[PASS] Free List Empty Stall: rename stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Free List Empty Stall: stall_rn=%b", stall_rn);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_icache_miss_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            icache_miss = 1;
            @(posedge clk);
            
            if (stall_if) begin
                pass_count = pass_count + 1;
                $display("[PASS] I-Cache Miss Stall: IF stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] I-Cache Miss Stall: stall_if=%b", stall_if);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_dcache_miss_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            dcache_miss = 1;
            @(posedge clk);
            
            if (stall_mem && stall_ex) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache Miss Stall: MEM/EX stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache Miss Stall: stall_mem=%b, stall_ex=%b", stall_mem, stall_ex);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_lsq_full_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            lq_full = 1;
            @(posedge clk);
            
            if (stall_is) begin
                pass_count = pass_count + 1;
                $display("[PASS] LQ Full Stall: issue stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] LQ Full Stall: stall_is=%b", stall_is);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_branch_mispredict_flush;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            branch_mispredict = 1;
            branch_target = 32'h8000_1000;
            branch_checkpoint = 3'd2;
            @(posedge clk);
            
            if (flush_if && flush_id && flush_rn && flush_is && flush_ex &&
                recover && recover_checkpoint == 3'd2 &&
                redirect_valid && redirect_pc == 32'h8000_1000) begin
                pass_count = pass_count + 1;
                $display("[PASS] Branch Mispredict Flush: redirect to %h", redirect_pc);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Branch Mispredict Flush: flush_if=%b, redirect=%h", 
                         flush_if, redirect_pc);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_exception_flush;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exception = 1;
            exception_pc = 32'h8000_0500;
            @(posedge clk);
            
            // Exception should flush all stages including MEM
            if (flush_if && flush_id && flush_rn && flush_is && flush_ex && flush_mem &&
                redirect_valid && redirect_pc == mtvec) begin
                pass_count = pass_count + 1;
                $display("[PASS] Exception Flush: all stages flushed, redirect to mtvec=%h", mtvec);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Exception Flush: flush_mem=%b, redirect=%h", flush_mem, redirect_pc);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_mret_redirect;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            mret = 1;
            mepc = 32'h8000_2000;
            @(posedge clk);
            
            if (flush_if && redirect_valid && redirect_pc == mepc) begin
                pass_count = pass_count + 1;
                $display("[PASS] MRET Redirect: redirect to mepc=%h", redirect_pc);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] MRET Redirect: redirect=%h, expected=%h", redirect_pc, mepc);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_wb_never_stalls;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            // Set all stall conditions
            rob_full = 1;
            free_list_empty = 1;
            icache_miss = 1;
            dcache_miss = 1;
            lq_full = 1;
            sq_full = 1;
            @(posedge clk);
            
            // WB should never stall
            if (!stall_wb) begin
                pass_count = pass_count + 1;
                $display("[PASS] WB Never Stalls: stall_wb=%b", stall_wb);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] WB Never Stalls: stall_wb=%b", stall_wb);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_all_rs_full_stall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            // All reservation stations full
            rs_alu_full = 1;
            rs_mul_full = 1;
            rs_lsu_full = 1;
            rs_br_full = 1;
            @(posedge clk);
            
            if (stall_is) begin
                pass_count = pass_count + 1;
                $display("[PASS] All RS Full Stall: issue stalled");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] All RS Full Stall: stall_is=%b", stall_is);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $display("========================================");
        $display("Pipeline Control Property Test");
        $display("Property 14: Pipeline Stall Correctness");
        $display("Validates: Requirements 12.1, 12.2, 12.3");
        $display("========================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        rst_n = 0;
        clear_inputs();
        mtvec = 32'h8000_0000;
        mepc = 0;
        
        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        
        $display("\n--- Test 1: No Stall Normal Operation ---");
        test_no_stall_normal();
        
        $display("\n--- Test 2: ROB Full Stall ---");
        test_rob_full_stall();
        
        $display("\n--- Test 3: Free List Empty Stall ---");
        test_free_list_empty_stall();
        
        $display("\n--- Test 4: I-Cache Miss Stall ---");
        test_icache_miss_stall();
        
        $display("\n--- Test 5: D-Cache Miss Stall ---");
        test_dcache_miss_stall();
        
        $display("\n--- Test 6: Load Queue Full Stall ---");
        test_lsq_full_stall();
        
        $display("\n--- Test 7: Branch Mispredict Flush ---");
        test_branch_mispredict_flush();
        
        $display("\n--- Test 8: Exception Flush ---");
        test_exception_flush();
        
        $display("\n--- Test 9: MRET Redirect ---");
        test_mret_redirect();
        
        $display("\n--- Test 10: WB Never Stalls ---");
        test_wb_never_stalls();
        
        $display("\n--- Test 11: All RS Full Stall ---");
        test_all_rs_full_stall();
        
        // Summary
        $display("\n========================================");
        $display("Test Summary:");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        
        $finish;
    end

endmodule
