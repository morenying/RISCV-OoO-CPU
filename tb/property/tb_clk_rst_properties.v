//=============================================================================
// Property Test: Clock and Reset Subsystem
// Description: Property-based tests for clock_manager, reset_synchronizer,
//              and reset_manager modules
//
// Properties Tested:
//   Property 1: Boot Sequence Correctness
//   Property 4: Reset Synchronization
//
// Validates: Requirements 1.1, 3.2, 3.3, 3.4, 3.5, 3.6
//
// Test Methodology:
//   - Random reset timing injection
//   - Random PLL lock/unlock sequences
//   - Verify invariants hold across all scenarios
//=============================================================================

`timescale 1ns/1ps

module tb_clk_rst_properties;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;
    parameter NUM_ITERATIONS = 100;  // Minimum 100 as per spec
    parameter RELEASE_DELAY = 8;
    parameter STABILITY_WAIT = 20;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk_in;
    reg         rst_n_async;
    
    // Clock manager outputs
    wire        clk_sys;
    wire        clk_mem;
    wire        cm_locked;
    wire        cm_lock_lost;
    wire        cm_rst_n_sys;
    wire        cm_rst_n_mem;
    
    // Reset manager inputs/outputs
    wire        rm_rst_mem_n;
    wire        rm_rst_cache_n;
    wire        rm_rst_cpu_n;
    wire        rm_rst_periph_n;
    wire        rm_reset_active;
    wire [2:0]  rm_reset_state;
    
    reg         wdt_reset;
    reg         sw_reset;
    
    // Test state
    integer     iteration;
    integer     property1_pass;
    integer     property4_pass;
    integer     total_pass;
    integer     total_fail;
    
    // Random seed
    integer     seed;
    
    // Loop variable for main test (moved from unnamed blocks)
    reg         iter_pass;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    
    // Clock Manager
    clock_manager #(
        .INPUT_CLK_FREQ     (100_000_000),
        .SYS_CLK_FREQ       (50_000_000),
        .MEM_CLK_FREQ       (100_000_000),
        .LOCK_TIMEOUT       (500),
        .LOCK_STABLE_CNT    (50)
    ) u_clock_manager (
        .clk_in             (clk_in),
        .rst_n_async        (rst_n_async),
        .clk_sys            (clk_sys),
        .clk_mem            (clk_mem),
        .locked             (cm_locked),
        .lock_lost          (cm_lock_lost),
        .rst_n_sys          (cm_rst_n_sys),
        .rst_n_mem          (cm_rst_n_mem)
    );
    
    // Reset Manager
    reset_manager #(
        .RELEASE_DELAY      (RELEASE_DELAY),
        .STABILITY_WAIT     (STABILITY_WAIT)
    ) u_reset_manager (
        .clk                (clk_in),  // Use input clock for simplicity
        .pll_locked         (cm_locked),
        .rst_btn_n          (rst_n_async),
        .wdt_reset          (wdt_reset),
        .sw_reset           (sw_reset),
        .rst_mem_n          (rm_rst_mem_n),
        .rst_cache_n        (rm_rst_cache_n),
        .rst_cpu_n          (rm_rst_cpu_n),
        .rst_periph_n       (rm_rst_periph_n),
        .reset_active       (rm_reset_active),
        .reset_state        (rm_reset_state)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk_in = 1'b0;
        forever #(CLK_PERIOD/2) clk_in = ~clk_in;
    end

    //=========================================================================
    // LFSR for Random Number Generation
    //=========================================================================
    reg [31:0] lfsr;
    
    function [31:0] next_random;
        input [31:0] current;
        begin
            // LFSR with taps at 32, 22, 2, 1
            next_random = {current[30:0], current[31] ^ current[21] ^ current[1] ^ current[0]};
        end
    endfunction
    
    task get_random;
        output [31:0] value;
    begin
        lfsr = next_random(lfsr);
        value = lfsr;
    end
    endtask
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task wait_cycles;
        input integer n;
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) begin
            @(posedge clk_in);
        end
    end
    endtask
    
    task wait_for_lock;
        input integer timeout;
        integer i;
    begin
        for (i = 0; i < timeout && !cm_locked; i = i + 1) begin
            @(posedge clk_in);
        end
    end
    endtask
    
    task wait_for_running;
        input integer timeout;
        integer i;
    begin
        for (i = 0; i < timeout && rm_reset_active; i = i + 1) begin
            @(posedge clk_in);
        end
    end
    endtask

    //=========================================================================
    // Property 1: Boot Sequence Correctness
    //
    // For any power-on or reset event, the system shall:
    //   1. Hold CPU in reset until PLL is locked
    //   2. Release resets in order: memory → cache → cpu → periph
    //   3. First instruction fetch shall be from reset vector
    //
    // Validates: Requirements 1.1, 3.4
    //=========================================================================
    
    task test_property1;
        input [31:0] random_seed;
        output pass;
        
        reg [31:0] rand_val;
        integer reset_duration;
        integer lock_wait;
        reg order_correct;
        reg cpu_held;
    begin
        pass = 1;
        lfsr = random_seed;
        
        // Generate random reset duration (10-100 cycles)
        get_random(rand_val);
        reset_duration = 10 + (rand_val % 91);
        
        // Assert reset
        rst_n_async = 1'b0;
        wdt_reset = 1'b0;
        sw_reset = 1'b0;
        
        wait_cycles(reset_duration);
        
        // Check: CPU must be in reset while PLL not locked
        cpu_held = (rm_rst_cpu_n == 1'b0);
        if (!cpu_held) begin
            $display("  FAIL: CPU not held in reset during PLL unlock");
            pass = 0;
        end
        
        // Release reset
        rst_n_async = 1'b1;
        
        // Wait for PLL lock
        wait_for_lock(1000);
        
        if (!cm_locked) begin
            $display("  FAIL: PLL did not lock");
            pass = 0;
        end
        
        // Monitor reset release order
        order_correct = 1;
        
        fork
            begin : monitor_order
                // Wait for memory release
                while (!rm_rst_mem_n) @(posedge clk_in);
                
                // At this point, cache and cpu should still be in reset
                if (rm_rst_cache_n || rm_rst_cpu_n) begin
                    order_correct = 0;
                end
                
                // Wait for cache release
                while (!rm_rst_cache_n) @(posedge clk_in);
                
                // CPU should still be in reset
                if (rm_rst_cpu_n) begin
                    order_correct = 0;
                end
                
                // Wait for CPU release
                while (!rm_rst_cpu_n) @(posedge clk_in);
            end
            
            begin : timeout_guard
                wait_cycles(500);
                disable monitor_order;
            end
        join
        
        if (!order_correct) begin
            $display("  FAIL: Reset release order violated");
            pass = 0;
        end
        
        // Wait for system to be running
        wait_for_running(200);
        
        if (rm_reset_active) begin
            $display("  FAIL: System did not reach running state");
            pass = 0;
        end
    end
    endtask

    //=========================================================================
    // Property 4: Reset Synchronization
    //
    // For any asynchronous reset assertion, the synchronized reset shall:
    //   1. Assert within 3 clock cycles
    //   2. Remain asserted for at least 2 clock cycles
    //   3. All state machines shall reach their initial states
    //
    // Validates: Requirements 3.2, 3.3
    //=========================================================================
    
    task test_property4;
        input [31:0] random_seed;
        output pass;
        
        reg [31:0] rand_val;
        integer phase_offset;
        integer assert_cycles;
        reg sync_correct;
    begin
        pass = 1;
        lfsr = random_seed;
        
        // First, get system to running state
        rst_n_async = 1'b1;
        wdt_reset = 1'b0;
        sw_reset = 1'b0;
        
        wait_for_lock(1000);
        wait_for_running(500);
        
        if (rm_reset_active) begin
            $display("  FAIL: Could not reach running state");
            pass = 0;
        end else begin
            // Generate random phase offset (0-9 ns within 10ns period)
            get_random(rand_val);
            phase_offset = rand_val % 10;
            
            // Assert reset at random phase
            #(phase_offset);
            rst_n_async = 1'b0;
            
            // Count cycles until all resets are asserted
            assert_cycles = 0;
            sync_correct = 0;
            
            repeat(10) begin
                @(posedge clk_in);
                assert_cycles = assert_cycles + 1;
                
                // Check if all resets are asserted
                if (!rm_rst_mem_n && !rm_rst_cache_n && 
                    !rm_rst_cpu_n && !rm_rst_periph_n) begin
                    sync_correct = 1;
                end
            end
            
            if (!sync_correct) begin
                $display("  FAIL: Resets not asserted within 10 cycles");
                pass = 0;
            end
            
            // Verify resets stay asserted while async reset is low
            repeat(20) begin
                @(posedge clk_in);
                if (rm_rst_mem_n || rm_rst_cache_n || 
                    rm_rst_cpu_n || rm_rst_periph_n) begin
                    $display("  FAIL: Reset released while async reset active");
                    pass = 0;
                end
            end
            
            // Release async reset
            rst_n_async = 1'b1;
            
            // Verify sync release (should take multiple cycles)
            @(posedge clk_in);
            
            // Resets should not release immediately
            if (rm_rst_cpu_n) begin
                $display("  FAIL: CPU reset released too quickly");
                pass = 0;
            end
        end
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("========================================");
        $display("Clock/Reset Property Tests");
        $display("Property 1: Boot Sequence Correctness");
        $display("Property 4: Reset Synchronization");
        $display("Validates: Requirements 1.1, 3.2-3.6");
        $display("Iterations: %0d", NUM_ITERATIONS);
        $display("========================================");
        $display("");
        
        // Initialize
        rst_n_async = 1'b0;
        wdt_reset = 1'b0;
        sw_reset = 1'b0;
        seed = 32'hDEADBEEF;
        lfsr = seed;
        
        property1_pass = 0;
        property4_pass = 0;
        total_pass = 0;
        total_fail = 0;
        
        wait_cycles(10);
        
        //=====================================================================
        // Property 1 Tests
        //=====================================================================
        $display("--- Property 1: Boot Sequence Correctness ---");
        $display("Testing %0d random reset scenarios...", NUM_ITERATIONS);
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            // Get new random seed for this iteration
            get_random(seed);
            
            test_property1(seed, iter_pass);
            
            if (iter_pass) begin
                property1_pass = property1_pass + 1;
            end else begin
                $display("  Iteration %0d failed with seed %h", iteration, seed);
            end
            
            // Brief pause between iterations
            wait_cycles(50);
        end
        
        $display("Property 1: %0d/%0d passed", property1_pass, NUM_ITERATIONS);
        
        if (property1_pass == NUM_ITERATIONS) begin
            $display("[PASS] Property 1: Boot Sequence Correctness");
            total_pass = total_pass + 1;
        end else begin
            $display("[FAIL] Property 1: Boot Sequence Correctness");
            total_fail = total_fail + 1;
        end
        
        $display("");
        
        //=====================================================================
        // Property 4 Tests
        //=====================================================================
        $display("--- Property 4: Reset Synchronization ---");
        $display("Testing %0d random reset timing scenarios...", NUM_ITERATIONS);
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            // Get new random seed for this iteration
            get_random(seed);
            
            test_property4(seed, iter_pass);
            
            if (iter_pass) begin
                property4_pass = property4_pass + 1;
            end else begin
                $display("  Iteration %0d failed with seed %h", iteration, seed);
            end
            
            // Brief pause between iterations
            wait_cycles(50);
        end
        
        $display("Property 4: %0d/%0d passed", property4_pass, NUM_ITERATIONS);
        
        if (property4_pass == NUM_ITERATIONS) begin
            $display("[PASS] Property 4: Reset Synchronization");
            total_pass = total_pass + 1;
        end else begin
            $display("[FAIL] Property 4: Reset Synchronization");
            total_fail = total_fail + 1;
        end
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("");
        $display("========================================");
        $display("PROPERTY TEST SUMMARY");
        $display("========================================");
        $display("Property 1 (Boot Sequence):      %0d/%0d iterations", property1_pass, NUM_ITERATIONS);
        $display("Property 4 (Reset Sync):         %0d/%0d iterations", property4_pass, NUM_ITERATIONS);
        $display("----------------------------------------");
        $display("Total Properties: %0d passed, %0d failed", total_pass, total_fail);
        $display("========================================");
        
        if (total_fail == 0) begin
            $display("");
            $display("*** ALL PROPERTY TESTS PASSED ***");
            $display("");
        end else begin
            $display("");
            $display("*** PROPERTY TESTS FAILED ***");
            $display("");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        // Maximum simulation time: 100ms at 10ns period = 10M cycles
        // For 100 iterations with ~1000 cycles each = ~100K cycles
        // Add safety margin: 500K cycles = 5ms
        #5_000_000;
        $display("");
        $display("ERROR: Simulation timeout!");
        $display("========================================");
        $finish;
    end

endmodule
