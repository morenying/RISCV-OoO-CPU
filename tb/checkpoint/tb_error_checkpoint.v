//=============================================================================
// Checkpoint 16: Error Handling Verification
//
// Description:
//   Comprehensive checkpoint tests for error handling subsystem including:
//   - Exception handling (all types)
//   - Bus error detection and propagation
//   - CSR state management
//   - Watchdog integration
//
// Requirements: 7.1, 7.2, 7.3, 7.4, 5.5
//=============================================================================

`timescale 1ns/1ps

module tb_error_checkpoint;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    
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
    
    // Exception unit signals
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
    reg [XLEN-1:0] mtvec;
    reg [XLEN-1:0] mepc_in;
    reg mie;
    reg irq_pending;
    reg [3:0] irq_code;
    
    wire exception_out;
    wire interrupt_out;
    wire [3:0] exc_code_out;
    wire [XLEN-1:0] exc_pc_out;
    wire [XLEN-1:0] exc_tval_out;
    wire mret_out;
    wire flush;
    wire [XLEN-1:0] redirect_pc;
    wire redirect_valid;
    
    // CSR unit signals
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
    
    // Watchdog signals
    reg wdt_enable;
    reg wdt_kick;
    reg [31:0] wdt_pc;
    reg wdt_pc_valid;
    reg [31:0] wdt_timeout_val;
    reg wdt_timeout_load;
    wire wdt_timeout;
    wire [31:0] wdt_last_pc;
    wire wdt_reset;
    wire [31:0] wdt_counter;
    wire wdt_running;
    
    //=========================================================================
    // DUT Instances
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
    
    watchdog #(
        .XLEN(32),
        .DEFAULT_TIMEOUT(100),  // Short timeout for testing
        .COUNTER_WIDTH(32)
    ) dut_watchdog (
        .clk(clk),
        .rst_n(rst_n),
        .enable(wdt_enable),
        .kick(wdt_kick),
        .timeout_val(wdt_timeout_val),
        .timeout_load(wdt_timeout_load),
        .cpu_pc(wdt_pc),
        .cpu_valid(wdt_pc_valid),
        .timeout(wdt_timeout),
        .wdt_reset(wdt_reset),
        .last_pc(wdt_last_pc),
        .counter_val(wdt_counter),
        .running(wdt_running)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================================
    // Test Counters
    //=========================================================================
    integer test_num;
    integer pass_count;
    integer fail_count;
    integer i;
    
    //=========================================================================
    // Test Variables (moved to module level for Verilog compatibility)
    //=========================================================================
    reg [3:0] expected_codes [0:8];
    reg [8:0] test_pass_mask;
    reg test_pass;
    reg [2:0] test_pass_3bit;
    reg reset_seen;
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    task reset_all;
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
        wdt_enable <= 0;
        wdt_kick <= 0;
        wdt_pc <= 0;
        wdt_pc_valid <= 0;
        wdt_timeout_val <= 100;
        wdt_timeout_load <= 0;
    end
    endtask
    
    task wait_cycles(input integer n);
        integer j;
    begin
        for (j = 0; j < n; j = j + 1) @(posedge clk);
    end
    endtask
    
    task read_csr(input [11:0] addr);
    begin
        csr_valid <= 1;
        csr_addr <= addr;
        csr_op <= 3'b010;  // CSRRS (read)
        csr_wdata <= 0;
        @(posedge clk);
        csr_valid <= 0;
        @(posedge clk);
    end
    endtask
    
    task write_csr(input [11:0] addr, input [31:0] data);
    begin
        csr_valid <= 1;
        csr_addr <= addr;
        csr_op <= 3'b001;  // CSRRW
        csr_wdata <= data;
        @(posedge clk);
        csr_valid <= 0;
        @(posedge clk);
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("=================================================");
        $display("Checkpoint 16: Error Handling Verification");
        $display("=================================================");
        
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Reset
        rst_n = 0;
        reset_all();
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        //=====================================================================
        // Test 1: All Exception Types
        //=====================================================================
        $display("\n--- Test 1: All Exception Types ---");
        test_num = test_num + 1;
        
        // Test each exception type
        begin
            expected_codes[0] = EXC_INSTR_MISALIGN;
            expected_codes[1] = EXC_INSTR_ACCESS;
            expected_codes[2] = EXC_ILLEGAL_INSTR;
            expected_codes[3] = EXC_BREAKPOINT;
            expected_codes[4] = EXC_LOAD_MISALIGN;
            expected_codes[5] = EXC_LOAD_ACCESS;
            expected_codes[6] = EXC_STORE_MISALIGN;
            expected_codes[7] = EXC_STORE_ACCESS;
            expected_codes[8] = EXC_ECALL_M;
            
            test_pass_mask = 9'b0;
            
            // Instruction misalign
            reset_all();
            exc_pc <= 32'h1000;
            instr_misalign <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_INSTR_MISALIGN) test_pass_mask[0] = 1;
            
            // Instruction access fault
            reset_all();
            exc_pc <= 32'h2000;
            instr_access_fault <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_INSTR_ACCESS) test_pass_mask[1] = 1;
            
            // Illegal instruction
            reset_all();
            exc_pc <= 32'h3000;
            illegal_instr <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_ILLEGAL_INSTR) test_pass_mask[2] = 1;
            
            // Breakpoint
            reset_all();
            exc_pc <= 32'h4000;
            ebreak <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_BREAKPOINT) test_pass_mask[3] = 1;
            
            // Load misalign
            reset_all();
            exc_pc <= 32'h5000;
            load_misalign <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_LOAD_MISALIGN) test_pass_mask[4] = 1;
            
            // Load access fault
            reset_all();
            exc_pc <= 32'h6000;
            load_access_fault <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_LOAD_ACCESS) test_pass_mask[5] = 1;
            
            // Store misalign
            reset_all();
            exc_pc <= 32'h7000;
            store_misalign <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_STORE_MISALIGN) test_pass_mask[6] = 1;
            
            // Store access fault
            reset_all();
            exc_pc <= 32'h8000;
            store_access_fault <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_STORE_ACCESS) test_pass_mask[7] = 1;
            
            // ECALL
            reset_all();
            exc_pc <= 32'h9000;
            ecall <= 1;
            @(posedge clk); #1;
            if (exception_out && exc_code_out == EXC_ECALL_M) test_pass_mask[8] = 1;
            
            if (test_pass_mask == 9'b111111111) begin
                $display("  PASS: All 9 exception types detected correctly");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Exception type test - pass_mask=%b", test_pass_mask);
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 2: CSR State on Exception
        //=====================================================================
        $display("\n--- Test 2: CSR State on Exception ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            // Setup mtvec
            write_csr(12'h305, 32'h0000_2000);  // mtvec
            
            // Trigger exception
            reset_all();
            mtvec <= 32'h0000_2000;
            exc_pc <= 32'hABCD_1234;
            exc_tval <= 32'h1234_5678;
            load_access_fault <= 1;
            
            @(posedge clk);
            @(posedge clk);  // Wait for CSR update
            #1;
            
            // Check mepc
            if (mepc_csr != 32'hABCD_1234) begin
                $display("  FAIL: mepc=%h, expected=%h", mepc_csr, 32'hABCD_1234);
                test_pass = 0;
            end
            
            // Check mcause
            read_csr(12'h342);
            #1;
            if (csr_rdata[3:0] != EXC_LOAD_ACCESS || csr_rdata[31] != 0) begin
                $display("  FAIL: mcause=%h, expected code=%d, interrupt=0", csr_rdata, EXC_LOAD_ACCESS);
                test_pass = 0;
            end
            
            // Check mtval
            read_csr(12'h343);
            #1;
            if (csr_rdata != 32'h1234_5678) begin
                $display("  FAIL: mtval=%h, expected=%h", csr_rdata, 32'h1234_5678);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: CSR state correct (mepc, mcause, mtval)");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 3: Exception Priority
        //=====================================================================
        $display("\n--- Test 3: Exception Priority ---");
        test_num = test_num + 1;
        
        begin
            test_pass_3bit = 3'b0;
            
            // Test 1: Instruction > Decode
            reset_all();
            instr_misalign <= 1;
            illegal_instr <= 1;
            @(posedge clk); #1;
            if (exc_code_out == EXC_INSTR_MISALIGN) test_pass_3bit[0] = 1;
            
            // Test 2: Decode > Memory
            reset_all();
            illegal_instr <= 1;
            load_misalign <= 1;
            @(posedge clk); #1;
            if (exc_code_out == EXC_ILLEGAL_INSTR) test_pass_3bit[1] = 1;
            
            // Test 3: Instr access > Illegal
            reset_all();
            instr_access_fault <= 1;
            illegal_instr <= 1;
            @(posedge clk); #1;
            if (exc_code_out == EXC_INSTR_ACCESS) test_pass_3bit[2] = 1;
            
            if (test_pass_3bit == 3'b111) begin
                $display("  PASS: Exception priority correct");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Priority test - pass_mask=%b", test_pass_3bit);
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 4: Pipeline Flush on Exception
        //=====================================================================
        $display("\n--- Test 4: Pipeline Flush on Exception ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            exc_pc <= 32'h1000;
            illegal_instr <= 1;
            
            @(posedge clk); #1;
            
            if (!flush || !redirect_valid) begin
                $display("  FAIL: flush=%b, redirect_valid=%b", flush, redirect_valid);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Pipeline flush asserted on exception");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 5: Redirect to mtvec
        //=====================================================================
        $display("\n--- Test 5: Redirect to mtvec ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            mtvec <= 32'h0000_3000;
            exc_pc <= 32'h1000;
            illegal_instr <= 1;
            
            @(posedge clk); #1;
            
            if (redirect_pc != 32'h0000_3000) begin
                $display("  FAIL: redirect_pc=%h, expected=%h", redirect_pc, 32'h0000_3000);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Redirect to mtvec correct");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 6: MRET Return
        //=====================================================================
        $display("\n--- Test 6: MRET Return ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            mepc_in <= 32'h0000_5000;
            mret <= 1;
            
            @(posedge clk); #1;
            
            if (redirect_pc != 32'h0000_5000 || !redirect_valid) begin
                $display("  FAIL: redirect_pc=%h, expected=%h", redirect_pc, 32'h0000_5000);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: MRET returns to mepc");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 7: Watchdog Timeout
        //=====================================================================
        $display("\n--- Test 7: Watchdog Timeout ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            wdt_enable <= 1;
            wdt_pc <= 32'hDEAD_BEEF;
            wdt_pc_valid <= 1;
            wdt_timeout_val <= 100;
            wdt_timeout_load <= 1;
            @(posedge clk);
            wdt_timeout_load <= 0;
            
            // Wait for timeout (100 cycles)
            wait_cycles(110);
            
            if (!wdt_timeout) begin
                $display("  FAIL: Watchdog did not timeout");
                test_pass = 0;
            end
            
            if (wdt_last_pc != 32'hDEAD_BEEF) begin
                $display("  FAIL: last_pc=%h, expected=%h", wdt_last_pc, 32'hDEAD_BEEF);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Watchdog timeout and PC capture");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 8: Watchdog Kick Prevents Timeout
        //=====================================================================
        $display("\n--- Test 8: Watchdog Kick Prevents Timeout ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            wdt_enable <= 1;
            wdt_timeout_val <= 100;
            wdt_timeout_load <= 1;
            @(posedge clk);
            wdt_timeout_load <= 0;
            
            // Kick every 50 cycles (before 100 cycle timeout)
            for (i = 0; i < 5; i = i + 1) begin
                wait_cycles(50);
                wdt_kick <= 1;
                @(posedge clk);
                wdt_kick <= 0;
            end
            
            if (wdt_timeout) begin
                $display("  FAIL: Watchdog timed out despite kicks");
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Watchdog kick prevents timeout");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 9: Watchdog Reset Pulse
        //=====================================================================
        $display("\n--- Test 9: Watchdog Reset Pulse ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            reset_seen = 0;
            
            reset_all();
            wdt_enable <= 1;
            wdt_timeout_val <= 100;
            wdt_timeout_load <= 1;
            @(posedge clk);
            wdt_timeout_load <= 0;
            
            // Wait for timeout and reset
            for (i = 0; i < 120; i = i + 1) begin
                @(posedge clk);
                if (wdt_reset) reset_seen = 1;
            end
            
            if (!reset_seen) begin
                $display("  FAIL: Watchdog reset pulse not generated");
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Watchdog reset pulse generated");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        reset_all();
        wait_cycles(5);
        
        //=====================================================================
        // Test 10: Bus Error Address in mtval
        //=====================================================================
        $display("\n--- Test 10: Bus Error Address in mtval ---");
        test_num = test_num + 1;
        
        begin
            test_pass = 1;
            
            reset_all();
            exc_pc <= 32'h1000;
            exc_tval <= 32'hBADA_DD00;  // Faulting address
            load_access_fault <= 1;
            
            @(posedge clk); #1;
            
            if (exc_tval_out != 32'hBADA_DD00) begin
                $display("  FAIL: exc_tval=%h, expected=%h", exc_tval_out, 32'hBADA_DD00);
                test_pass = 0;
            end
            
            if (test_pass) begin
                $display("  PASS: Bus error address captured in mtval");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end
        
        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n=================================================");
        $display("Checkpoint 16: Error Handling Results");
        $display("=================================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("=================================================");
        
        if (fail_count == 0) begin
            $display("CHECKPOINT 16 PASSED!");
        end else begin
            $display("CHECKPOINT 16 FAILED!");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #500000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
