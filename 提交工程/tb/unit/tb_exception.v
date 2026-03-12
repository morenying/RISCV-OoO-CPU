//=================================================================
// Testbench: tb_exception
// Description: Exception Handling Property Tests
//              Property 8: Precise Exception
// Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5
//=================================================================

`timescale 1ns/1ps

module tb_exception;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;
    
    //=========================================================
    // Exception Sources
    //=========================================================
    reg                illegal_instr;
    reg                instr_misalign;
    reg                load_misalign;
    reg                store_misalign;
    reg                ecall;
    reg                ebreak;
    reg                mret;
    
    //=========================================================
    // Exception Info
    //=========================================================
    reg  [XLEN-1:0]    exc_pc;
    reg  [XLEN-1:0]    exc_tval;
    
    //=========================================================
    // Branch Misprediction
    //=========================================================
    reg                branch_mispredict;
    reg  [XLEN-1:0]    branch_target;
    
    //=========================================================
    // CSR Interface
    //=========================================================
    reg  [XLEN-1:0]    mtvec;
    reg  [XLEN-1:0]    mepc;
    reg                mie;
    reg                irq_pending;
    
    //=========================================================
    // Outputs
    //=========================================================
    wire               exception_o;
    wire [3:0]         exc_code_o;
    wire [XLEN-1:0]    exc_pc_o;
    wire [XLEN-1:0]    exc_tval_o;
    wire               mret_o;
    wire               flush_o;
    wire [XLEN-1:0]    redirect_pc_o;
    wire               redirect_valid_o;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================
    // DUT Instantiation
    //=========================================================
    exception_unit #(
        .XLEN(XLEN)
    ) u_exception_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .illegal_instr_i    (illegal_instr),
        .instr_misalign_i   (instr_misalign),
        .load_misalign_i    (load_misalign),
        .store_misalign_i   (store_misalign),
        .ecall_i            (ecall),
        .ebreak_i           (ebreak),
        .mret_i             (mret),
        .exc_pc_i           (exc_pc),
        .exc_tval_i         (exc_tval),
        .branch_mispredict_i(branch_mispredict),
        .branch_target_i    (branch_target),
        .mtvec_i            (mtvec),
        .mepc_i             (mepc),
        .mie_i              (mie),
        .irq_pending_i      (irq_pending),
        .exception_o        (exception_o),
        .exc_code_o         (exc_code_o),
        .exc_pc_o           (exc_pc_o),
        .exc_tval_o         (exc_tval_o),
        .mret_o             (mret_o),
        .flush_o            (flush_o),
        .redirect_pc_o      (redirect_pc_o),
        .redirect_valid_o   (redirect_valid_o)
    );

    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // Exception codes
    localparam EXC_INSTR_MISALIGN = 4'd0;
    localparam EXC_ILLEGAL_INSTR  = 4'd2;
    localparam EXC_BREAKPOINT     = 4'd3;
    localparam EXC_LOAD_MISALIGN  = 4'd4;
    localparam EXC_STORE_MISALIGN = 4'd6;
    localparam EXC_ECALL_M        = 4'd11;

    //=========================================================
    // Helper Tasks
    //=========================================================
    
    task clear_inputs;
        begin
            illegal_instr = 0;
            instr_misalign = 0;
            load_misalign = 0;
            store_misalign = 0;
            ecall = 0;
            ebreak = 0;
            mret = 0;
            branch_mispredict = 0;
            irq_pending = 0;
        end
    endtask

    //=========================================================
    // Property 8: Precise Exception Tests
    //=========================================================
    
    task test_illegal_instruction;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0100;
            exc_tval = 32'hDEADBEEF;  // Bad instruction encoding
            illegal_instr = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_ILLEGAL_INSTR && 
                flush_o && redirect_pc_o == mtvec) begin
                pass_count = pass_count + 1;
                $display("[PASS] Illegal Instruction: code=%d, redirect=%h", exc_code_o, redirect_pc_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Illegal Instruction: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_instruction_misalign;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0102;  // Misaligned PC
            instr_misalign = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_INSTR_MISALIGN && flush_o) begin
                pass_count = pass_count + 1;
                $display("[PASS] Instruction Misalign: code=%d", exc_code_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Instruction Misalign: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_load_misalign;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0200;
            exc_tval = 32'h8000_1001;  // Misaligned load address
            load_misalign = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_LOAD_MISALIGN && flush_o) begin
                pass_count = pass_count + 1;
                $display("[PASS] Load Misalign: code=%d, tval=%h", exc_code_o, exc_tval_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Load Misalign: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_store_misalign;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0300;
            exc_tval = 32'h8000_2003;  // Misaligned store address
            store_misalign = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_STORE_MISALIGN && flush_o) begin
                pass_count = pass_count + 1;
                $display("[PASS] Store Misalign: code=%d, tval=%h", exc_code_o, exc_tval_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Store Misalign: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_ecall;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0400;
            ecall = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_ECALL_M && flush_o) begin
                pass_count = pass_count + 1;
                $display("[PASS] ECALL: code=%d, redirect=%h", exc_code_o, redirect_pc_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] ECALL: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_ebreak;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_0500;
            ebreak = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_BREAKPOINT && flush_o) begin
                pass_count = pass_count + 1;
                $display("[PASS] EBREAK: code=%d", exc_code_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] EBREAK: exception=%b, code=%d", exception_o, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_mret;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            mepc = 32'h8000_0600;
            mret = 1;
            
            @(posedge clk);
            
            if (mret_o && flush_o && redirect_pc_o == mepc) begin
                pass_count = pass_count + 1;
                $display("[PASS] MRET: redirect to mepc=%h", redirect_pc_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] MRET: mret_o=%b, redirect=%h", mret_o, redirect_pc_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_exception_priority;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            // Multiple exceptions - instruction misalign has highest priority
            exc_pc = 32'h8000_0700;
            instr_misalign = 1;
            illegal_instr = 1;
            load_misalign = 1;
            
            @(posedge clk);
            
            if (exception_o && exc_code_o == EXC_INSTR_MISALIGN) begin
                pass_count = pass_count + 1;
                $display("[PASS] Exception Priority: instr_misalign wins, code=%d", exc_code_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Exception Priority: expected code=%d, got=%d", 
                         EXC_INSTR_MISALIGN, exc_code_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_branch_mispredict_redirect;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            branch_target = 32'h8000_1000;
            branch_mispredict = 1;
            
            @(posedge clk);
            
            if (flush_o && redirect_valid_o && redirect_pc_o == branch_target) begin
                pass_count = pass_count + 1;
                $display("[PASS] Branch Mispredict: redirect to %h", redirect_pc_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Branch Mispredict: flush=%b, redirect=%h", flush_o, redirect_pc_o);
            end
            
            clear_inputs();
            @(posedge clk);
        end
    endtask
    
    task test_pc_preservation;
        begin
            test_count = test_count + 1;
            clear_inputs();
            
            exc_pc = 32'h8000_ABCD;
            exc_tval = 32'h12345678;
            illegal_instr = 1;
            
            @(posedge clk);
            
            if (exc_pc_o == 32'h8000_ABCD && exc_tval_o == 32'h12345678) begin
                pass_count = pass_count + 1;
                $display("[PASS] PC Preservation: pc=%h, tval=%h", exc_pc_o, exc_tval_o);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] PC Preservation: expected pc=%h, got=%h", 32'h8000_ABCD, exc_pc_o);
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
        $display("Exception Handling Property Test");
        $display("Property 8: Precise Exception");
        $display("Validates: Requirements 6.1-6.5");
        $display("========================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        rst_n = 0;
        clear_inputs();
        exc_pc = 0;
        exc_tval = 0;
        branch_target = 0;
        mtvec = 32'h8000_0000;
        mepc = 0;
        mie = 0;
        
        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);
        
        $display("\n--- Test 1: Illegal Instruction ---");
        test_illegal_instruction();
        
        $display("\n--- Test 2: Instruction Misalign ---");
        test_instruction_misalign();
        
        $display("\n--- Test 3: Load Misalign ---");
        test_load_misalign();
        
        $display("\n--- Test 4: Store Misalign ---");
        test_store_misalign();
        
        $display("\n--- Test 5: ECALL ---");
        test_ecall();
        
        $display("\n--- Test 6: EBREAK ---");
        test_ebreak();
        
        $display("\n--- Test 7: MRET ---");
        test_mret();
        
        $display("\n--- Test 8: Exception Priority ---");
        test_exception_priority();
        
        $display("\n--- Test 9: Branch Mispredict Redirect ---");
        test_branch_mispredict_redirect();
        
        $display("\n--- Test 10: PC Preservation ---");
        test_pc_preservation();
        
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
