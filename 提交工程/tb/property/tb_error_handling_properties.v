//=============================================================================
// Error Handling Property Tests
//
// Description:
//   Property-based tests for exception handling, bus errors, and error recovery.
//   Tests Property 11 (Exception Handling), Property 12 (ECC - optional),
//   and Property 13 (Watchdog Reset - already tested).
//
// Properties Tested:
//   - Property 11: Exception Handling
//     * Illegal instruction triggers exception
//     * Misaligned access triggers exception
//     * Bus error triggers exception
//     * mepc, mcause, mtval set correctly
//
//   - Bus Error Handling:
//     * Load access fault detection
//     * Store access fault detection
//     * Instruction access fault detection
//     * Error address recorded in mtval
//
// Requirements: 7.1, 7.2, 7.3
//=============================================================================

`timescale 1ns/1ps

module tb_error_handling_properties;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter NUM_ITERATIONS = 50;
    
    //=========================================================================
    // Exception Codes
    //=========================================================================
    localparam EXC_INSTR_MISALIGN = 4'd0;
    localparam EXC_INSTR_ACCESS   = 4'd1;
    localparam EXC_ILLEGAL_INSTR  = 4'd2;
    localparam EXC_BREAKPOINT     = 4'd3;
    localparam EXC_LOAD_MISALIGN  = 4'd4;
    localparam EXC_LOAD_ACCESS    = 4'd5;
    localparam EXC_STORE_MISALIGN = 4'd6;
    localparam EXC_STORE_ACCESS   = 4'd7;
    localparam EXC_ECALL_M        = 4'd11;
    
    //=========================================================================
    // Test Signals
    //=========================================================================
    reg clk;
    reg rst_n;
    
    // Exception unit inputs
    reg illegal_instr;
    reg instr_misalign;
    reg load_misalign;
    reg store_misalign;
    reg ecall;
    reg ebreak;
    reg mret;
    reg instr_access_fault;
    reg load_access_fault;
    reg store_access_fault;
    reg [XLEN-1:0] exc_pc;
    reg [XLEN-1:0] exc_tval;
    reg branch_mispredict;
    reg [XLEN-1:0] branch_target;
    
    // CSR interface
    reg [XLEN-1:0] mtvec;
    reg [XLEN-1:0] mepc_in;
    reg mie;
    reg irq_pending;
    reg [3:0] irq_code;
    
    // Exception unit outputs
    wire exception_out;
    wire interrupt_out;
    wire [3:0] exc_code_out;
    wire [XLEN-1:0] exc_pc_out;
    wire [XLEN-1:0] exc_tval_out;
    wire mret_out;
    wire flush;
    wire [XLEN-1:0] redirect_pc;
    wire redirect_valid;
    
    //=========================================================================
    // DUT: Exception Unit
    //=========================================================================
    exception_unit #(
        .XLEN(XLEN)
    ) dut_exception (
        .clk(clk),
        .rst_n(rst_n),
        .illegal_instr_i(illegal_instr),
        .instr_misalign_i(instr_misalign),
        .load_misalign_i(load_misalign),
        .store_misalign_i(store_misalign),
        .ecall_i(ecall),
        .ebreak_i(ebreak),
        .mret_i(mret),
        .instr_access_fault_i(instr_access_fault),
        .load_access_fault_i(load_access_fault),
        .store_access_fault_i(store_access_fault),
        .exc_pc_i(exc_pc),
        .exc_tval_i(exc_tval),
        .branch_mispredict_i(branch_mispredict),
        .branch_target_i(branch_target),
        .mtvec_i(mtvec),
        .mepc_i(mepc_in),
        .mie_i(mie),
        .irq_pending_i(irq_pending),
        .irq_code_i(irq_code),
        .exception_o(exception_out),
        .interrupt_o(interrupt_out),
        .exc_code_o(exc_code_out),
        .exc_pc_o(exc_pc_out),
        .exc_tval_o(exc_tval_out),
        .mret_o(mret_out),
        .flush_o(flush),
        .redirect_pc_o(redirect_pc),
        .redirect_valid_o(redirect_valid)
    );
    
    //=========================================================================
    // CSR Unit for mcause verification
    //=========================================================================
    reg csr_valid;
    reg [11:0] csr_addr;
    reg [2:0] csr_op;
    reg [XLEN-1:0] csr_wdata;
    wire [XLEN-1:0] csr_rdata;
    wire csr_illegal;
    wire [XLEN-1:0] mtvec_csr;
    wire [XLEN-1:0] mepc_csr;
    wire mie_csr;
    wire irq_pending_csr;
    wire [3:0] irq_code_csr;
    
    csr_unit #(
        .XLEN(XLEN)
    ) dut_csr (
        .clk(clk),
        .rst_n(rst_n),
        .csr_valid_i(csr_valid),
        .csr_addr_i(csr_addr),
        .csr_op_i(csr_op),
        .csr_wdata_i(csr_wdata),
        .csr_rdata_o(csr_rdata),
        .csr_illegal_o(csr_illegal),
        .exception_i(exception_out),
        .interrupt_i(interrupt_out),
        .exc_code_i(exc_code_out),
        .exc_pc_i(exc_pc_out),
        .exc_tval_i(exc_tval_out),
        .mret_i(mret_out),
        .ext_irq_i(1'b0),
        .timer_irq_i(1'b0),
        .sw_irq_i(1'b0),
        .irq_pending_o(irq_pending_csr),
        .irq_code_o(irq_code_csr),
        .mtvec_o(mtvec_csr),
        .mepc_o(mepc_csr),
        .mie_o(mie_csr),
        .hart_id_i(32'h0),
        .instr_retire_i(1'b0)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================================
    // Test Counters
    //=========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer i;
    reg [31:0] seed;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    task reset_inputs;
    begin
        illegal_instr <= 0;
        instr_misalign <= 0;
        load_misalign <= 0;
        store_misalign <= 0;
        ecall <= 0;
        ebreak <= 0;
        mret <= 0;
        instr_access_fault <= 0;
        load_access_fault <= 0;
        store_access_fault <= 0;
        exc_pc <= 0;
        exc_tval <= 0;
        branch_mispredict <= 0;
        branch_target <= 0;
        mtvec <= 32'h0000_1000;
        mepc_in <= 0;
        mie <= 0;
        irq_pending <= 0;
        irq_code <= 0;
        csr_valid <= 0;
        csr_addr <= 0;
        csr_op <= 0;
        csr_wdata <= 0;
    end
    endtask
    
    task wait_cycles(input integer n);
        integer j;
    begin
        for (j = 0; j < n; j = j + 1) @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11a: Illegal Instruction Exception
    //=========================================================================
    task test_illegal_instruction;
        reg [31:0] test_pc;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;  // Aligned PC
        
        reset_inputs();
        exc_pc <= test_pc;
        illegal_instr <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_ILLEGAL_INSTR && 
            exc_pc_out == test_pc && flush && redirect_valid) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Illegal instruction - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_ILLEGAL_INSTR);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11b: Load Misalign Exception
    //=========================================================================
    task test_load_misalign;
        reg [31:0] test_pc;
        reg [31:0] test_addr;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_addr = ($random(seed) & 32'hFFFF_FFFC) | 2'b01;  // Misaligned
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_addr;
        load_misalign <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_LOAD_MISALIGN && 
            exc_tval_out == test_addr && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Load misalign - exception=%b, code=%d, tval=%h",
                     exception_out, exc_code_out, exc_tval_out);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11c: Store Misalign Exception
    //=========================================================================
    task test_store_misalign;
        reg [31:0] test_pc;
        reg [31:0] test_addr;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_addr = ($random(seed) & 32'hFFFF_FFFC) | 2'b11;  // Misaligned
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_addr;
        store_misalign <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_STORE_MISALIGN && 
            exc_tval_out == test_addr && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Store misalign - exception=%b, code=%d, tval=%h",
                     exception_out, exc_code_out, exc_tval_out);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11d: Load Access Fault (Bus Error)
    //=========================================================================
    task test_load_access_fault;
        reg [31:0] test_pc;
        reg [31:0] test_addr;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_addr = $random(seed);
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_addr;
        load_access_fault <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_LOAD_ACCESS && 
            exc_tval_out == test_addr && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Load access fault - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_LOAD_ACCESS);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11e: Store Access Fault (Bus Error)
    //=========================================================================
    task test_store_access_fault;
        reg [31:0] test_pc;
        reg [31:0] test_addr;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_addr = $random(seed);
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_addr;
        store_access_fault <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_STORE_ACCESS && 
            exc_tval_out == test_addr && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Store access fault - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_STORE_ACCESS);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11f: Instruction Access Fault
    //=========================================================================
    task test_instr_access_fault;
        reg [31:0] test_pc;
        reg [31:0] test_addr;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_addr = test_pc;  // Faulting instruction address
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_addr;
        instr_access_fault <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_INSTR_ACCESS && 
            exc_tval_out == test_addr && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Instr access fault - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_INSTR_ACCESS);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11g: ECALL Exception
    //=========================================================================
    task test_ecall;
        reg [31:0] test_pc;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        
        reset_inputs();
        exc_pc <= test_pc;
        ecall <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_ECALL_M && 
            exc_pc_out == test_pc && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: ECALL - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_ECALL_M);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11h: EBREAK Exception
    //=========================================================================
    task test_ebreak;
        reg [31:0] test_pc;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        
        reset_inputs();
        exc_pc <= test_pc;
        ebreak <= 1;
        
        @(posedge clk);
        #1;
        
        if (exception_out && exc_code_out == EXC_BREAKPOINT && 
            exc_pc_out == test_pc && flush) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: EBREAK - exception=%b, code=%d, expected=%d",
                     exception_out, exc_code_out, EXC_BREAKPOINT);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11i: Exception Priority (Instruction > Decode > Memory)
    //=========================================================================
    task test_exception_priority;
    begin
        test_count = test_count + 1;
        
        reset_inputs();
        exc_pc <= 32'h1000;
        
        // Trigger multiple exceptions simultaneously
        instr_misalign <= 1;  // Highest priority
        illegal_instr <= 1;
        load_misalign <= 1;
        
        @(posedge clk);
        #1;
        
        // Instruction misalign should win
        if (exception_out && exc_code_out == EXC_INSTR_MISALIGN) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Exception priority - code=%d, expected=%d",
                     exc_code_out, EXC_INSTR_MISALIGN);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Property 11j: Redirect to mtvec on Exception
    //=========================================================================
    task test_redirect_to_mtvec;
        reg [31:0] test_mtvec;
    begin
        test_count = test_count + 1;
        test_mtvec = ($random(seed) & 32'hFFFF_FFFC);  // Aligned
        
        reset_inputs();
        mtvec <= test_mtvec;
        exc_pc <= 32'h2000;
        illegal_instr <= 1;
        
        @(posedge clk);
        #1;
        
        if (redirect_valid && redirect_pc == test_mtvec) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Redirect to mtvec - redirect_pc=%h, expected=%h",
                     redirect_pc, test_mtvec);
        end
        
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // CSR Update Test: Verify mepc, mcause, mtval after exception
    //=========================================================================
    task test_csr_update_on_exception;
        reg [31:0] test_pc;
        reg [31:0] test_tval;
    begin
        test_count = test_count + 1;
        test_pc = $random(seed) & 32'hFFFF_FFFC;
        test_tval = $random(seed);
        
        reset_inputs();
        exc_pc <= test_pc;
        exc_tval <= test_tval;
        load_access_fault <= 1;
        
        @(posedge clk);
        @(posedge clk);  // Wait for CSR update
        #1;
        
        // Check mepc
        if (mepc_csr == test_pc) begin
            // Check mcause (read via CSR interface)
            csr_valid <= 1;
            csr_addr <= 12'h342;  // mcause
            csr_op <= 3'b010;     // CSRRS (read)
            csr_wdata <= 0;
            
            @(posedge clk);
            #1;
            
            if (csr_rdata[3:0] == EXC_LOAD_ACCESS && csr_rdata[31] == 0) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: CSR mcause - got=%h, expected code=%d, interrupt=0",
                         csr_rdata, EXC_LOAD_ACCESS);
            end
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: CSR mepc - got=%h, expected=%h", mepc_csr, test_pc);
        end
        
        csr_valid <= 0;
        reset_inputs();
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("=================================================");
        $display("Error Handling Property Tests");
        $display("=================================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        seed = 32'hDEAD_BEEF;
        
        // Reset
        rst_n = 0;
        reset_inputs();
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        //=====================================================================
        // Property 11: Exception Handling Tests
        //=====================================================================
        $display("\n--- Property 11: Exception Handling ---");
        
        // 11a: Illegal Instruction
        $display("Testing illegal instruction exceptions...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_illegal_instruction();
        end
        
        // 11b: Load Misalign
        $display("Testing load misalign exceptions...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_load_misalign();
        end
        
        // 11c: Store Misalign
        $display("Testing store misalign exceptions...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_store_misalign();
        end
        
        // 11d: Load Access Fault
        $display("Testing load access fault (bus error)...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_load_access_fault();
        end
        
        // 11e: Store Access Fault
        $display("Testing store access fault (bus error)...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_store_access_fault();
        end
        
        // 11f: Instruction Access Fault
        $display("Testing instruction access fault...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_instr_access_fault();
        end
        
        // 11g: ECALL
        $display("Testing ECALL exceptions...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_ecall();
        end
        
        // 11h: EBREAK
        $display("Testing EBREAK exceptions...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_ebreak();
        end
        
        // 11i: Exception Priority
        $display("Testing exception priority...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_exception_priority();
        end
        
        // 11j: Redirect to mtvec
        $display("Testing redirect to mtvec...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_redirect_to_mtvec();
        end
        
        // CSR Update Test
        $display("Testing CSR update on exception...");
        for (i = 0; i < NUM_ITERATIONS/5; i = i + 1) begin
            test_csr_update_on_exception();
        end
        
        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n=================================================");
        $display("Error Handling Property Test Results");
        $display("=================================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("=================================================");
        
        if (fail_count == 0) begin
            $display("ALL PROPERTY TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #1000000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
