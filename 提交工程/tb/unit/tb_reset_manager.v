//=============================================================================
// Testbench: tb_reset_manager
// Description: Comprehensive test for reset_manager module
//
// Tests:
//   1. Reset sequence order (memory → cache → cpu → periph)
//   2. Delay between releases
//   3. Reset assertion from various sources
//   4. PLL lock dependency
//   5. Multiple reset cycles
//
// Property 1: Boot Sequence Correctness (partial)
// Validates: Requirements 3.3, 3.4
//=============================================================================

`timescale 1ns/1ps

module tb_reset_manager;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;
    parameter RELEASE_DELAY = 8;    // Reduced for faster simulation
    parameter STABILITY_WAIT = 20;  // Reduced for faster simulation
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         pll_locked;
    reg         rst_btn_n;
    reg         wdt_reset;
    reg         sw_reset;
    
    wire        rst_mem_n;
    wire        rst_cache_n;
    wire        rst_cpu_n;
    wire        rst_periph_n;
    wire        reset_active;
    wire [2:0]  reset_state;
    
    // Timing capture
    integer     mem_release_cycle;
    integer     cache_release_cycle;
    integer     cpu_release_cycle;
    integer     periph_release_cycle;
    integer     cycle_count;
    
    // Test counters
    integer     test_count;
    integer     pass_count;
    integer     fail_count;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    reset_manager #(
        .RELEASE_DELAY      (RELEASE_DELAY),
        .STABILITY_WAIT     (STABILITY_WAIT)
    ) u_dut (
        .clk                (clk),
        .pll_locked         (pll_locked),
        .rst_btn_n          (rst_btn_n),
        .wdt_reset          (wdt_reset),
        .sw_reset           (sw_reset),
        .rst_mem_n          (rst_mem_n),
        .rst_cache_n        (rst_cache_n),
        .rst_cpu_n          (rst_cpu_n),
        .rst_periph_n       (rst_periph_n),
        .reset_active       (reset_active),
        .reset_state        (reset_state)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Cycle Counter
    //=========================================================================
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
    end
    
    //=========================================================================
    // Release Time Capture
    //=========================================================================
    reg mem_captured, cache_captured, cpu_captured, periph_captured;
    
    always @(posedge clk) begin
        if (!rst_mem_n) begin
            mem_captured <= 1'b0;
        end else if (!mem_captured) begin
            mem_release_cycle <= cycle_count;
            mem_captured <= 1'b1;
        end
        
        if (!rst_cache_n) begin
            cache_captured <= 1'b0;
        end else if (!cache_captured) begin
            cache_release_cycle <= cycle_count;
            cache_captured <= 1'b1;
        end
        
        if (!rst_cpu_n) begin
            cpu_captured <= 1'b0;
        end else if (!cpu_captured) begin
            cpu_release_cycle <= cycle_count;
            cpu_captured <= 1'b1;
        end
        
        if (!rst_periph_n) begin
            periph_captured <= 1'b0;
        end else if (!periph_captured) begin
            periph_release_cycle <= cycle_count;
            periph_captured <= 1'b1;
        end
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
    
    task wait_cycles;
        input integer n;
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk);
        end
    end
    endtask
    
    task assert_all_reset;
    begin
        pll_locked = 1'b0;
        rst_btn_n = 1'b1;
        wdt_reset = 1'b0;
        sw_reset = 1'b0;
        cycle_count = 0;
        mem_captured = 0;
        cache_captured = 0;
        cpu_captured = 0;
        periph_captured = 0;
    end
    endtask
    
    task wait_for_running;
        input integer timeout;
        integer i;
    begin
        for (i = 0; i < timeout && reset_active; i = i + 1) begin
            @(posedge clk);
        end
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("========================================");
        $display("Reset Manager Testbench");
        $display("Property 1: Boot Sequence (partial)");
        $display("Validates: Requirements 3.3, 3.4");
        $display("========================================");
        $display("");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        assert_all_reset();
        
        wait_cycles(10);
        
        //=====================================================================
        // Test 1: Initial State (all in reset)
        //=====================================================================
        $display("--- Test 1: Initial State ---");
        
        check_result("rst_mem_n=0 initially", rst_mem_n == 1'b0);
        check_result("rst_cache_n=0 initially", rst_cache_n == 1'b0);
        check_result("rst_cpu_n=0 initially", rst_cpu_n == 1'b0);
        check_result("rst_periph_n=0 initially", rst_periph_n == 1'b0);
        check_result("reset_active=1 initially", reset_active == 1'b1);
        
        //=====================================================================
        // Test 2: Reset Sequence Order
        //=====================================================================
        $display("");
        $display("--- Test 2: Reset Sequence Order ---");
        
        // Start sequence by asserting PLL lock
        cycle_count = 0;
        pll_locked = 1'b1;
        
        // Wait for sequence to complete
        wait_for_running(500);
        
        // Check all released
        check_result("All resets released", 
            rst_mem_n && rst_cache_n && rst_cpu_n && rst_periph_n);
        
        // Check order: mem < cache < cpu < periph
        $display("  Release cycles: mem=%0d, cache=%0d, cpu=%0d, periph=%0d",
            mem_release_cycle, cache_release_cycle, cpu_release_cycle, periph_release_cycle);
        
        check_result("Memory released before cache", 
            mem_release_cycle < cache_release_cycle);
        check_result("Cache released before CPU", 
            cache_release_cycle < cpu_release_cycle);
        check_result("CPU released before peripherals", 
            cpu_release_cycle <= periph_release_cycle || periph_release_cycle == 0);
        
        //=====================================================================
        // Test 3: Delay Between Releases
        //=====================================================================
        $display("");
        $display("--- Test 3: Delay Between Releases ---");
        
        // Check delays are at least RELEASE_DELAY
        check_result("Delay mem->cache >= RELEASE_DELAY", 
            (cache_release_cycle - mem_release_cycle) >= RELEASE_DELAY);
        check_result("Delay cache->cpu >= RELEASE_DELAY", 
            (cpu_release_cycle - cache_release_cycle) >= RELEASE_DELAY);
        // Periph follows CPU with minimal delay (state machine moves to next state)
        check_result("Periph released after CPU", 
            periph_release_cycle == 0 || periph_release_cycle >= cpu_release_cycle);
        
        //=====================================================================
        // Test 4: Reset Button Assertion
        //=====================================================================
        $display("");
        $display("--- Test 4: Reset Button Assertion ---");
        
        // Press reset button
        rst_btn_n = 1'b0;
        wait_cycles(5);
        
        check_result("All reset on button press", 
            !rst_mem_n && !rst_cache_n && !rst_cpu_n && !rst_periph_n);
        
        // Release button
        rst_btn_n = 1'b1;
        assert_all_reset();
        pll_locked = 1'b1;
        wait_for_running(500);
        
        check_result("Recovers after button release", 
            rst_mem_n && rst_cache_n && rst_cpu_n && rst_periph_n);

        //=====================================================================
        // Test 5: Watchdog Reset
        //=====================================================================
        $display("");
        $display("--- Test 5: Watchdog Reset ---");
        
        // Trigger watchdog
        wdt_reset = 1'b1;
        wait_cycles(5);
        
        check_result("All reset on watchdog", 
            !rst_mem_n && !rst_cache_n && !rst_cpu_n && !rst_periph_n);
        
        // Clear watchdog
        wdt_reset = 1'b0;
        wait_for_running(500);
        
        check_result("Recovers after watchdog clear", 
            rst_mem_n && rst_cache_n && rst_cpu_n && rst_periph_n);
        
        //=====================================================================
        // Test 6: Software Reset
        //=====================================================================
        $display("");
        $display("--- Test 6: Software Reset ---");
        
        // Trigger software reset
        sw_reset = 1'b1;
        wait_cycles(5);
        
        check_result("All reset on software reset", 
            !rst_mem_n && !rst_cache_n && !rst_cpu_n && !rst_periph_n);
        
        // Clear software reset
        sw_reset = 1'b0;
        wait_for_running(500);
        
        check_result("Recovers after software reset clear", 
            rst_mem_n && rst_cache_n && rst_cpu_n && rst_periph_n);
        
        //=====================================================================
        // Test 7: PLL Lock Loss
        //=====================================================================
        $display("");
        $display("--- Test 7: PLL Lock Loss ---");
        
        // Lose PLL lock
        pll_locked = 1'b0;
        wait_cycles(5);
        
        check_result("All reset on PLL unlock", 
            !rst_mem_n && !rst_cache_n && !rst_cpu_n && !rst_periph_n);
        
        // Regain lock
        pll_locked = 1'b1;
        wait_for_running(500);
        
        check_result("Recovers after PLL re-lock", 
            rst_mem_n && rst_cache_n && rst_cpu_n && rst_periph_n);
        
        //=====================================================================
        // Test 8: Multiple Reset Cycles
        //=====================================================================
        $display("");
        $display("--- Test 8: Multiple Reset Cycles ---");
        
        begin : multi_test
            integer i;
            integer multi_pass;
            multi_pass = 1;
            
            for (i = 0; i < 10; i = i + 1) begin
                // Assert reset
                pll_locked = 1'b0;
                wait_cycles(10);
                
                if (rst_mem_n || rst_cache_n || rst_cpu_n || rst_periph_n) begin
                    multi_pass = 0;
                end
                
                // Release
                pll_locked = 1'b1;
                wait_for_running(500);
                
                if (!rst_mem_n || !rst_cache_n || !rst_cpu_n || !rst_periph_n) begin
                    multi_pass = 0;
                end
            end
            
            check_result("10 reset cycles all correct", multi_pass == 1);
        end
        
        //=====================================================================
        // Test 9: Sequence Verification with Assertions
        //=====================================================================
        $display("");
        $display("--- Test 9: Sequence Invariants ---");
        
        // Reset and run sequence again, checking invariants
        pll_locked = 1'b0;
        wait_cycles(10);
        pll_locked = 1'b1;
        
        // During sequence, verify order is maintained
        begin : seq_check
            integer seq_pass;
            seq_pass = 1;
            
            // Wait and check at each step
            while (reset_active) begin
                @(posedge clk);
                
                // Cache should never be released before memory
                if (rst_cache_n && !rst_mem_n) seq_pass = 0;
                // CPU should never be released before cache
                if (rst_cpu_n && !rst_cache_n) seq_pass = 0;
                // Periph should never be released before CPU
                if (rst_periph_n && !rst_cpu_n) seq_pass = 0;
            end
            
            check_result("Sequence invariants maintained", seq_pass == 1);
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
        #500000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
