//=============================================================================
// Unit Test: Watchdog Timer
//
// Description:
//   Comprehensive tests for watchdog module
//   Tests timeout detection, kick operation, PC capture
//
// Test Categories:
//   1. Basic enable/disable
//   2. Kick operation (counter reset)
//   3. Timeout detection
//   4. Last PC capture
//   5. Reset pulse generation
//   6. Configurable timeout
//
// Requirements: 5.5, 7.4
//=============================================================================

`timescale 1ns/1ps

module tb_watchdog;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter XLEN = 32;
    parameter COUNTER_WIDTH = 32;
    parameter TEST_TIMEOUT = 100;  // Short timeout for testing
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // Control Interface
    reg         enable;
    reg         kick;
    reg  [COUNTER_WIDTH-1:0] timeout_val;
    reg         timeout_load;
    
    // CPU Interface
    reg  [XLEN-1:0] cpu_pc;
    reg         cpu_valid;
    
    // Status and Reset Output
    wire        timeout;
    wire        wdt_reset;
    wire [XLEN-1:0] last_pc;
    wire [COUNTER_WIDTH-1:0] counter_val;
    wire        running;
    
    // Test tracking
    integer     test_num;
    integer     pass_count;
    integer     fail_count;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    watchdog #(
        .XLEN           (XLEN),
        .DEFAULT_TIMEOUT(TEST_TIMEOUT),
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
        timeout_val = TEST_TIMEOUT;
        timeout_load = 1'b0;
        cpu_pc = 32'h8000_0000;
        cpu_valid = 1'b0;
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask
    
    task check_result;
        input pass;
        input [255:0] name;
    begin
        test_num = test_num + 1;
        if (pass) begin
            pass_count = pass_count + 1;
            $display("[PASS] %3d: %0s", test_num, name);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] %3d: %0s", test_num, name);
        end
    end
    endtask
    
    task simulate_cpu_activity;
        input [31:0] pc_start;
        input integer num_instrs;
        integer i;
    begin
        for (i = 0; i < num_instrs; i = i + 1) begin
            cpu_pc = pc_start + (i * 4);
            cpu_valid = 1'b1;
            @(posedge clk);
            cpu_valid = 1'b0;
            @(posedge clk);
        end
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("=================================================");
        $display("Watchdog Timer Unit Test");
        $display("=================================================");
        
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        //=====================================================================
        // Test 1: Initial State
        //=====================================================================
        $display("\n--- Test 1: Initial State ---");
        check_result(!running, "Watchdog not running after reset");
        check_result(!timeout, "No timeout after reset");
        check_result(!wdt_reset, "No reset signal after reset");
        check_result(counter_val == 0, "Counter is zero");
        
        //=====================================================================
        // Test 2: Enable Watchdog
        //=====================================================================
        $display("\n--- Test 2: Enable Watchdog ---");
        enable = 1'b1;
        wait_cycles(5);
        check_result(running, "Watchdog running after enable");
        check_result(counter_val > 0, "Counter incrementing");
        
        //=====================================================================
        // Test 3: Kick Operation
        //=====================================================================
        $display("\n--- Test 3: Kick Operation ---");
        wait_cycles(50);  // Let counter run
        kick = 1'b1;
        @(posedge clk);
        kick = 1'b0;
        wait_cycles(2);
        check_result(counter_val < 10, "Counter reset by kick");
        
        //=====================================================================
        // Test 4: Disable Watchdog
        //=====================================================================
        $display("\n--- Test 4: Disable Watchdog ---");
        enable = 1'b0;
        wait_cycles(5);
        check_result(!running, "Watchdog stopped after disable");
        
        //=====================================================================
        // Test 5: Timeout Detection
        //=====================================================================
        $display("\n--- Test 5: Timeout Detection ---");
        reset_dut();
        
        // Set short timeout
        timeout_val = 50;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        // Enable and wait for timeout
        enable = 1'b1;
        wait_cycles(60);
        
        check_result(timeout, "Timeout detected");
        
        //=====================================================================
        // Test 6: Reset Pulse Generation
        //=====================================================================
        $display("\n--- Test 6: Reset Pulse Generation ---");
        // State machine: ST_TIMEOUT -> ST_RESET (next cycle)
        // wdt_reset is set in ST_RESET state
        wait_cycles(2);  // Wait for ST_RESET state
        check_result(wdt_reset, "Reset pulse generated");
        
        // Wait for reset pulse to complete
        wait_cycles(20);
        check_result(!wdt_reset, "Reset pulse completed");
        
        //=====================================================================
        // Test 7: Last PC Capture
        //=====================================================================
        $display("\n--- Test 7: Last PC Capture ---");
        reset_dut();
        
        // Simulate CPU activity
        cpu_pc = 32'h8000_1234;
        cpu_valid = 1'b1;
        @(posedge clk);
        cpu_valid = 1'b0;
        
        cpu_pc = 32'h8000_5678;
        cpu_valid = 1'b1;
        @(posedge clk);
        cpu_valid = 1'b0;
        
        // Set short timeout and enable
        timeout_val = 30;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        enable = 1'b1;
        wait_cycles(40);
        
        check_result(last_pc == 32'h8000_5678, "Last PC captured correctly");
        
        //=====================================================================
        // Test 8: Continuous Kick Prevents Timeout
        //=====================================================================
        $display("\n--- Test 8: Continuous Kick Prevents Timeout ---");
        reset_dut();
        
        timeout_val = 50;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        enable = 1'b1;
        
        // Kick every 20 cycles (before timeout)
        begin : kick_loop
            integer i;
            for (i = 0; i < 5; i = i + 1) begin
                wait_cycles(20);
                kick = 1'b1;
                @(posedge clk);
                kick = 1'b0;
            end
        end
        
        check_result(!timeout, "No timeout with regular kicks");
        check_result(running, "Watchdog still running");
        
        //=====================================================================
        // Test 9: Configurable Timeout
        //=====================================================================
        $display("\n--- Test 9: Configurable Timeout ---");
        reset_dut();
        
        // Set longer timeout
        timeout_val = 200;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        enable = 1'b1;
        wait_cycles(100);
        check_result(!timeout, "No timeout before configured value");
        
        wait_cycles(110);
        check_result(timeout, "Timeout at configured value");
        
        //=====================================================================
        // Test 10: Multiple Timeout Cycles
        //=====================================================================
        $display("\n--- Test 10: Multiple Timeout Cycles ---");
        reset_dut();
        
        timeout_val = 30;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        // First timeout
        enable = 1'b1;
        wait_cycles(40);  // Wait longer for timeout
        check_result(timeout, "First timeout");
        
        // Wait for reset to complete and state to return to idle
        wait_cycles(30);
        enable = 1'b0;
        wait_cycles(5);
        
        // Re-enable for second timeout
        reset_dut();
        timeout_val = 30;
        timeout_load = 1'b1;
        @(posedge clk);
        timeout_load = 1'b0;
        
        enable = 1'b1;
        wait_cycles(40);  // Wait longer for timeout
        check_result(timeout, "Second timeout");
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("\n=================================================");
        $display("Test Summary");
        $display("=================================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("=================================================");
        
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        
        $display("=================================================");
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(CLK_PERIOD * 50000);
        $display("\n[ERROR] Test timeout!");
        $finish;
    end

endmodule
