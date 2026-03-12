//=============================================================================
// Property Test: Watchdog Properties
//
// Description:
//   Property-based tests for watchdog timer
//   Tests Property 13: Watchdog Reset
//
// Property 13: Watchdog Reset
//   For any period where the CPU does not kick the watchdog within the
//   timeout period, the watchdog shall:
//   1. Assert reset
//   2. Log the last known PC
//   3. System shall restart from bootloader
//
// Requirements: 5.5, 7.4
//=============================================================================

`timescale 1ns/1ps

module tb_watchdog_properties;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;
    parameter XLEN = 32;
    parameter COUNTER_WIDTH = 32;
    parameter NUM_ITERATIONS = 50;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    reg         enable;
    reg         kick;
    reg  [COUNTER_WIDTH-1:0] timeout_val;
    reg         timeout_load;
    reg  [XLEN-1:0] cpu_pc;
    reg         cpu_valid;
    
    wire        timeout;
    wire        wdt_reset;
    wire [XLEN-1:0] last_pc;
    wire [COUNTER_WIDTH-1:0] counter_val;
    wire        running;
    
    // Test tracking
    integer     iteration;
    integer     pass_count;
    integer     fail_count;
    integer     seed;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    watchdog #(
        .XLEN           (XLEN),
        .DEFAULT_TIMEOUT(100),
        .COUNTER_WIDTH  (COUNTER_WIDTH)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .kick           (kick),
        .timeout_val    (timeout_val),
        .timeout_load   (timeout_load),
        .cpu_pc         (cpu_pc),
        .cpu_valid      (cpu_valid),
        .timeout        (timeout),
        .wdt_reset      (wdt_reset),
        .last_pc        (last_pc),
        .counter_val    (counter_val),
        .running        (running)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    task wait_cycles;
        input integer n;
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) @(posedge clk);
    end
    endtask
    
    task reset_dut;
    begin
        rst_n = 1'b0;
        enable = 1'b0;
        kick = 1'b0;
        timeout_val = 100;
        timeout_load = 1'b0;
        cpu_pc = 32'h8000_0000;
        cpu_valid = 1'b0;
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask
    
    //=========================================================================
    // Property 13: Watchdog Reset Test
    //=========================================================================
    task test_property_13;
        input integer iter;
        reg [31:0] random_timeout;
        reg [31:0] random_pc;
        reg [31:0] expected_last_pc;
        integer wait_time;
        reg reset_asserted;
        reg pc_captured;
        reg [31:0] rand_val;
    begin
        // Random timeout value (30-100 cycles) - use unsigned math
        rand_val = $random(seed);
        random_timeout = 30 + (rand_val[6:0] % 70);
        rand_val = $random(seed);
        random_pc = 32'h8000_0000 + {16'd0, rand_val[15:0]};
        
        // Configure timeout
        timeout_val = random_timeout;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        // Simulate some CPU activity
        cpu_pc = random_pc;
        cpu_valid = 1'b1;
        @(posedge clk);
        cpu_valid = 1'b0;
        expected_last_pc = random_pc;
        
        // Enable watchdog
        enable = 1'b1;
        
        // Wait for timeout (don't kick) - add extra cycles for state machine
        wait_time = random_timeout + 10;
        wait_cycles(wait_time);
        
        // Check property conditions
        reset_asserted = wdt_reset;
        pc_captured = (last_pc == expected_last_pc);
        
        if (timeout && reset_asserted && pc_captured) begin
            $display("[PASS] Property 13 iter %0d: timeout=%0d, PC=%08X captured", 
                     iter, random_timeout, expected_last_pc);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Property 13 iter %0d: timeout=%0d, reset=%b, pc_match=%b (last_pc=%08X, expected=%08X)", 
                     iter, random_timeout, reset_asserted, pc_captured, last_pc, expected_last_pc);
            fail_count = fail_count + 1;
        end
        
        // Wait for reset to complete
        wait_cycles(20);
        enable = 1'b0;
    end
    endtask
    
    //=========================================================================
    // Property: Kick Prevents Timeout
    //=========================================================================
    task test_kick_prevents_timeout;
        input integer iter;
        reg [31:0] random_timeout;
        integer kick_interval;
        integer i;
        reg timeout_occurred;
        reg [31:0] rand_val;
    begin
        // Random timeout (50-100 cycles)
        rand_val = $random(seed);
        random_timeout = 50 + (rand_val[5:0] % 50);
        kick_interval = random_timeout / 3;  // Kick well before timeout
        
        // Configure timeout
        timeout_val = random_timeout;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        // Enable watchdog
        enable = 1'b1;
        
        // Kick regularly for 5 intervals
        timeout_occurred = 1'b0;
        for (i = 0; i < 5; i = i + 1) begin
            wait_cycles(kick_interval);
            if (timeout) timeout_occurred = 1'b1;
            kick = 1'b1;
            @(posedge clk);
            kick = 1'b0;
        end
        
        if (!timeout_occurred) begin
            $display("[PASS] Kick prevents timeout iter %0d: interval=%0d, timeout=%0d", 
                     iter, kick_interval, random_timeout);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Kick prevents timeout iter %0d: unexpected timeout", iter);
            fail_count = fail_count + 1;
        end
        
        enable = 1'b0;
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("=================================================");
        $display("Watchdog Property Tests");
        $display("=================================================");
        $display("Property 13: Watchdog Reset");
        $display("Iterations: %0d", NUM_ITERATIONS);
        $display("=================================================");
        
        pass_count = 0;
        fail_count = 0;
        seed = 54321;
        
        reset_dut();
        
        //=====================================================================
        // Property 13: Watchdog Reset
        //=====================================================================
        $display("\n--- Property 13: Watchdog Reset ---");
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            test_property_13(iteration);
        end
        
        //=====================================================================
        // Additional: Kick Prevents Timeout
        //=====================================================================
        $display("\n--- Kick Prevents Timeout ---");
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            test_kick_prevents_timeout(iteration);
        end
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("\n=================================================");
        $display("Property Test Summary");
        $display("=================================================");
        $display("Total Tests: %0d", pass_count + fail_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("=================================================");
        
        if (fail_count == 0) begin
            $display("ALL PROPERTY TESTS PASSED!");
        end else begin
            $display("SOME PROPERTY TESTS FAILED!");
        end
        
        $display("=================================================");
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(CLK_PERIOD * 500000);
        $display("\n[ERROR] Test timeout!");
        $finish;
    end

endmodule
