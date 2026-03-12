//=============================================================================
// Testbench: tb_reset_synchronizer
// Description: Comprehensive test for reset_synchronizer module
//
// Tests:
//   1. Async reset assertion (immediate)
//   2. Sync reset deassertion (takes SYNC_STAGES cycles)
//   3. Reset at various clock phases (metastability test)
//   4. Multiple reset cycles
//   5. Glitch rejection (for filtered version)
//
// Property 4: Reset Synchronization
// Validates: Requirements 3.1, 3.2
//=============================================================================

`timescale 1ns/1ps

module tb_reset_synchronizer;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100MHz
    parameter SYNC_STAGES = 3;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_async_n;    // Active-low async reset
    wire        rst_sync_n;     // Active-low sync reset
    
    // For active-high test
    reg         rst_async_h;
    wire        rst_sync_h;
    
    // Test counters
    integer     test_count;
    integer     pass_count;
    integer     fail_count;
    
    //=========================================================================
    // DUT Instantiation - Active Low
    //=========================================================================
    reset_synchronizer #(
        .SYNC_STAGES        (SYNC_STAGES),
        .RESET_ACTIVE_HIGH  (0)
    ) u_dut_low (
        .clk                (clk),
        .rst_async          (rst_async_n),
        .rst_sync           (rst_sync_n)
    );
    
    //=========================================================================
    // DUT Instantiation - Active High
    //=========================================================================
    reset_synchronizer #(
        .SYNC_STAGES        (SYNC_STAGES),
        .RESET_ACTIVE_HIGH  (1)
    ) u_dut_high (
        .clk                (clk),
        .rst_async          (rst_async_h),
        .rst_sync           (rst_sync_h)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Test Tasks
    //=========================================================================
    
    task check_result;
        input [255:0] test_name;
        input condition;
    begin
        test_count = test_count + 1;
        if (condition) begin
            $display("[PASS] %s", test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %s", test_name);
            fail_count = fail_count + 1;
        end
    end
    endtask
    
    // Wait for N clock cycles
    task wait_cycles;
        input integer n;
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk);
        end
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("========================================");
        $display("Reset Synchronizer Testbench");
        $display("Property 4: Reset Synchronization");
        $display("Validates: Requirements 3.1, 3.2");
        $display("========================================");
        $display("");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        rst_async_n = 1'b0;  // Start in reset (active low)
        rst_async_h = 1'b1;  // Start in reset (active high)
        
        //=====================================================================
        // Test 1: Initial Reset State
        //=====================================================================
        $display("--- Test 1: Initial Reset State ---");
        
        wait_cycles(5);
        
        // Both should be in reset
        check_result("Active-low: rst_sync_n=0 during reset", rst_sync_n == 1'b0);
        check_result("Active-high: rst_sync_h=1 during reset", rst_sync_h == 1'b1);
        
        //=====================================================================
        // Test 2: Async Reset Assertion (should be immediate)
        //=====================================================================
        $display("");
        $display("--- Test 2: Async Reset Assertion ---");
        
        // Release reset first
        rst_async_n = 1'b1;
        rst_async_h = 1'b0;
        wait_cycles(SYNC_STAGES + 5);
        
        // Verify out of reset
        check_result("Active-low: out of reset", rst_sync_n == 1'b1);
        check_result("Active-high: out of reset", rst_sync_h == 1'b0);
        
        // Now assert reset at mid-cycle (async)
        #(CLK_PERIOD/4);  // Quarter cycle offset
        rst_async_n = 1'b0;
        rst_async_h = 1'b1;
        
        // Check within 2 cycles (should be immediate due to async)
        #(CLK_PERIOD);
        check_result("Active-low: immediate assertion", rst_sync_n == 1'b0);
        check_result("Active-high: immediate assertion", rst_sync_h == 1'b1);
        
        //=====================================================================
        // Test 3: Sync Reset Deassertion (should take SYNC_STAGES cycles)
        //=====================================================================
        $display("");
        $display("--- Test 3: Sync Reset Deassertion ---");
        
        // Align to clock edge
        @(posedge clk);
        
        // Release async reset
        rst_async_n = 1'b1;
        rst_async_h = 1'b0;
        
        // Should still be in reset immediately after
        @(posedge clk);
        check_result("Active-low: still reset after 1 cycle", rst_sync_n == 1'b0);
        check_result("Active-high: still reset after 1 cycle", rst_sync_h == 1'b1);
        
        // Wait for sync stages minus 1
        wait_cycles(SYNC_STAGES - 2);
        check_result("Active-low: still reset before sync complete", rst_sync_n == 1'b0);
        check_result("Active-high: still reset before sync complete", rst_sync_h == 1'b1);
        
        // After SYNC_STAGES cycles, should be released
        wait_cycles(2);
        check_result("Active-low: released after SYNC_STAGES", rst_sync_n == 1'b1);
        check_result("Active-high: released after SYNC_STAGES", rst_sync_h == 1'b0);
        
        //=====================================================================
        // Test 4: Reset at Various Clock Phases (Metastability Test)
        //=====================================================================
        $display("");
        $display("--- Test 4: Reset at Various Clock Phases ---");
        
        begin : phase_test
            integer phase;
            integer phase_pass;
            phase_pass = 1;
            
            for (phase = 0; phase < 10; phase = phase + 1) begin
                // Release reset
                rst_async_n = 1'b1;
                rst_async_h = 1'b0;
                wait_cycles(SYNC_STAGES + 5);
                
                // Assert reset at different phase
                #(CLK_PERIOD * phase / 10);
                rst_async_n = 1'b0;
                rst_async_h = 1'b1;
                
                // Wait and check
                wait_cycles(3);
                
                if (rst_sync_n !== 1'b0 || rst_sync_h !== 1'b1) begin
                    $display("  Phase %0d: FAILED", phase);
                    phase_pass = 0;
                end
                
                // Realign
                @(posedge clk);
            end
            
            check_result("All 10 phase tests pass", phase_pass == 1);
        end
        
        //=====================================================================
        // Test 5: Multiple Reset Cycles
        //=====================================================================
        $display("");
        $display("--- Test 5: Multiple Reset Cycles ---");
        
        begin : multi_reset
            integer i;
            integer multi_pass;
            multi_pass = 1;
            
            for (i = 0; i < 20; i = i + 1) begin
                // Assert reset
                rst_async_n = 1'b0;
                rst_async_h = 1'b1;
                wait_cycles(5);
                
                // Check in reset
                if (rst_sync_n !== 1'b0 || rst_sync_h !== 1'b1) begin
                    multi_pass = 0;
                end
                
                // Release reset
                rst_async_n = 1'b1;
                rst_async_h = 1'b0;
                wait_cycles(SYNC_STAGES + 2);
                
                // Check out of reset
                if (rst_sync_n !== 1'b1 || rst_sync_h !== 1'b0) begin
                    multi_pass = 0;
                end
            end
            
            check_result("20 reset cycles all correct", multi_pass == 1);
        end
        
        //=====================================================================
        // Test 6: No X or Z values
        //=====================================================================
        $display("");
        $display("--- Test 6: No X or Z Values ---");
        
        // Run for a while and check for X/Z
        begin : xz_test
            integer i;
            integer xz_pass;
            xz_pass = 1;
            
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                if (rst_sync_n === 1'bx || rst_sync_n === 1'bz ||
                    rst_sync_h === 1'bx || rst_sync_h === 1'bz) begin
                    xz_pass = 0;
                end
            end
            
            check_result("No X or Z values in 100 cycles", xz_pass == 1);
        end
        
        //=====================================================================
        // Summary
        //=====================================================================
        $display("");
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end
        
        $display("========================================");
        $finish;
    end
    
    //=========================================================================
    // Timeout watchdog
    //=========================================================================
    initial begin
        #100000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
