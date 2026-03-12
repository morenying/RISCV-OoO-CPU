//=============================================================================
// Property Test: SRAM Controller
// Description: Property-based tests for sram_controller module
//
// Properties Tested:
//   Property 2: Memory Latency Handling
//   - For any valid memory access, data integrity is preserved
//   - For any sequence of writes followed by reads, data matches
//
// Validates: Requirements 2.1, 2.2
//
// Test Methodology:
//   - Random address generation
//   - Random data patterns
//   - Random access sequences (read/write interleaving)
//   - Verify data integrity across 100+ iterations
//=============================================================================

`timescale 1ns/1ps

module tb_sram_properties;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_ITERATIONS = 100;  // Minimum 100 as per spec
    parameter SRAM_ADDR_WIDTH = 18;
    parameter SRAM_DATA_WIDTH = 16;
    parameter MAX_ADDR = 32'h0003_FFFC;  // Max word-aligned address
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // CPU interface
    reg         cpu_req;
    wire        cpu_ack;
    wire        cpu_done;
    reg         cpu_wr;
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_be;
    wire [31:0] cpu_rdata;
    wire        cpu_error;
    
    // SRAM interface
    wire [SRAM_ADDR_WIDTH-1:0] sram_addr;
    wire [SRAM_DATA_WIDTH-1:0] sram_data;
    wire        sram_ce_n;
    wire        sram_oe_n;
    wire        sram_we_n;
    wire        sram_lb_n;
    wire        sram_ub_n;
    
    // SRAM model outputs
    wire        timing_violation;
    wire [7:0]  violation_count;
    
    // Test state
    integer     iteration;
    integer     property2_pass;
    integer     total_pass;
    integer     total_fail;
    
    // Random state
    reg [31:0]  lfsr;
    
    // Loop variables for main test (moved from unnamed blocks)
    reg         iter_pass;
    reg [31:0]  seed;
    integer     seq_pass;
    integer     intlv_pass;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    sram_controller #(
        .ADDR_SETUP_CYCLES  (1),
        .ACCESS_CYCLES      (2),
        .WRITE_CYCLES       (2),
        .DATA_HOLD_CYCLES   (1),
        .OE_DELAY_CYCLES    (1),
        .TIMEOUT_CYCLES     (100),
        .SRAM_ADDR_WIDTH    (SRAM_ADDR_WIDTH),
        .SRAM_DATA_WIDTH    (SRAM_DATA_WIDTH)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_req    (cpu_req),
        .cpu_ack    (cpu_ack),
        .cpu_done   (cpu_done),
        .cpu_wr     (cpu_wr),
        .cpu_addr   (cpu_addr),
        .cpu_wdata  (cpu_wdata),
        .cpu_be     (cpu_be),
        .cpu_rdata  (cpu_rdata),
        .cpu_error  (cpu_error),
        .sram_addr  (sram_addr),
        .sram_data  (sram_data),
        .sram_ce_n  (sram_ce_n),
        .sram_oe_n  (sram_oe_n),
        .sram_we_n  (sram_we_n),
        .sram_lb_n  (sram_lb_n),
        .sram_ub_n  (sram_ub_n)
    );
    
    //=========================================================================
    // SRAM Model Instantiation
    //=========================================================================
    sram_model #(
        .ADDR_WIDTH (SRAM_ADDR_WIDTH),
        .DATA_WIDTH (SRAM_DATA_WIDTH),
        .tAA        (10.0),
        .tOE        (5.0),
        .tWC        (10.0),
        .tWP        (8.0),
        .tDS        (6.0),
        .VERBOSE    (0)
    ) u_sram (
        .addr               (sram_addr),
        .data               (sram_data),
        .ce_n               (sram_ce_n),
        .oe_n               (sram_oe_n),
        .we_n               (sram_we_n),
        .lb_n               (sram_lb_n),
        .ub_n               (sram_ub_n),
        .timing_violation   (timing_violation),
        .violation_count    (violation_count)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // LFSR Random Number Generator
    //=========================================================================
    function [31:0] next_random;
        input [31:0] current;
    begin
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
        for (i = 0; i < n; i = i + 1) @(posedge clk);
    end
    endtask
    
    task reset_dut;
    begin
        rst_n = 1'b0;
        cpu_req = 1'b0;
        cpu_wr = 1'b0;
        cpu_addr = 32'd0;
        cpu_wdata = 32'd0;
        cpu_be = 4'b0000;
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask
    
    task do_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  be;
        output success;
        integer timeout;
    begin
        @(negedge clk);
        cpu_addr = addr;
        cpu_wdata = data;
        cpu_be = be;
        cpu_wr = 1'b1;
        cpu_req = 1'b1;
        
        timeout = 0;
        @(posedge clk);
        while (!cpu_ack && timeout < 10) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        cpu_req = 1'b0;
        
        timeout = 0;
        @(posedge clk);
        while (!cpu_done && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        success = cpu_done && !cpu_error;
        @(posedge clk);
    end
    endtask
    
    task do_read;
        input [31:0] addr;
        input [3:0]  be;
        output [31:0] data;
        output success;
        integer timeout;
    begin
        @(negedge clk);
        cpu_addr = addr;
        cpu_be = be;
        cpu_wr = 1'b0;
        cpu_req = 1'b1;
        
        timeout = 0;
        @(posedge clk);
        while (!cpu_ack && timeout < 10) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        cpu_req = 1'b0;
        
        timeout = 0;
        @(posedge clk);
        while (!cpu_done && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        data = cpu_rdata;
        success = cpu_done && !cpu_error;
        @(posedge clk);
    end
    endtask

    //=========================================================================
    // Property 2: Memory Latency Handling
    //
    // For any valid memory access, data integrity is preserved:
    //   1. Write followed by read returns same data
    //   2. Byte enables correctly mask writes
    //   3. No data corruption under various access patterns
    //   4. No timing violations with real SRAM model
    //
    // Validates: Requirements 2.1, 2.2
    //=========================================================================
    
    task test_property2;
        input [31:0] random_seed;
        output pass;
        
        reg [31:0] rand_val;
        reg [31:0] test_addr;
        reg [31:0] test_data;
        reg [31:0] read_data;
        reg [3:0]  test_be;
        reg [31:0] expected_data;
        reg [31:0] prev_data;
        reg        wr_success, rd_success;
        integer    num_ops;
        integer    i;
    begin
        pass = 1;
        lfsr = random_seed;
        
        // Reset DUT
        reset_dut();
        
        // Generate random number of operations (5-20)
        get_random(rand_val);
        num_ops = 5 + (rand_val % 16);
        
        for (i = 0; i < num_ops && pass; i = i + 1) begin
            // Generate random word-aligned address (within SRAM range)
            get_random(rand_val);
            test_addr = {rand_val[17:2], 2'b00};  // Word-aligned, 18-bit SRAM
            
            // Generate random data
            get_random(test_data);
            
            // Generate random byte enable (at least one byte enabled)
            get_random(rand_val);
            test_be = rand_val[3:0];
            if (test_be == 4'b0000) test_be = 4'b1111;  // Ensure at least one byte
            
            // First read to get previous data (for partial writes)
            do_read(test_addr, 4'b1111, prev_data, rd_success);
            if (!rd_success) begin
                $display("  FAIL: Initial read failed at addr %h", test_addr);
                pass = 0;
            end
            
            // Perform write
            do_write(test_addr, test_data, test_be, wr_success);
            if (!wr_success) begin
                $display("  FAIL: Write failed at addr %h", test_addr);
                pass = 0;
            end
            
            // Perform read-back
            do_read(test_addr, 4'b1111, read_data, rd_success);
            if (!rd_success) begin
                $display("  FAIL: Read-back failed at addr %h", test_addr);
                pass = 0;
            end
            
            // Calculate expected data based on byte enables
            expected_data = prev_data;
            if (test_be[0]) expected_data[7:0]   = test_data[7:0];
            if (test_be[1]) expected_data[15:8]  = test_data[15:8];
            if (test_be[2]) expected_data[23:16] = test_data[23:16];
            if (test_be[3]) expected_data[31:24] = test_data[31:24];
            
            // Verify data integrity
            if (read_data !== expected_data) begin
                $display("  FAIL: Data mismatch at addr %h", test_addr);
                $display("        BE=%b, Wrote=%h, Expected=%h, Got=%h", 
                         test_be, test_data, expected_data, read_data);
                pass = 0;
            end
            
            // Check for timing violations
            if (timing_violation) begin
                $display("  FAIL: Timing violation detected at addr %h", test_addr);
                pass = 0;
            end
        end
        
        // Final check: no accumulated timing violations
        if (violation_count > 0) begin
            $display("  FAIL: %0d timing violations during test", violation_count);
            pass = 0;
        end
    end
    endtask

    //=========================================================================
    // Property 2b: Sequential Access Pattern Test
    //
    // Tests sequential address access patterns for data integrity
    //=========================================================================
    
    task test_sequential_access;
        input [31:0] random_seed;
        output pass;
        
        reg [31:0] rand_val;
        reg [31:0] base_addr;
        reg [31:0] test_data [0:15];
        reg [31:0] read_data;
        reg        success;
        integer    i;
    begin
        pass = 1;
        lfsr = random_seed;
        
        // Reset DUT
        reset_dut();
        
        // Generate random base address
        get_random(rand_val);
        base_addr = {rand_val[17:6], 6'b000000};  // 64-byte aligned
        
        // Generate and write 16 sequential words
        for (i = 0; i < 16 && pass; i = i + 1) begin
            get_random(test_data[i]);
            do_write(base_addr + (i * 4), test_data[i], 4'b1111, success);
            if (!success) begin
                $display("  FAIL: Sequential write failed at offset %0d", i);
                pass = 0;
            end
        end
        
        // Read back and verify all 16 words
        for (i = 0; i < 16 && pass; i = i + 1) begin
            do_read(base_addr + (i * 4), 4'b1111, read_data, success);
            if (!success) begin
                $display("  FAIL: Sequential read failed at offset %0d", i);
                pass = 0;
            end else if (read_data !== test_data[i]) begin
                $display("  FAIL: Sequential data mismatch at offset %0d", i);
                $display("        Expected=%h, Got=%h", test_data[i], read_data);
                pass = 0;
            end
        end
        
        // Check for timing violations
        if (violation_count > 0) begin
            $display("  FAIL: %0d timing violations during sequential test", violation_count);
            pass = 0;
        end
    end
    endtask

    //=========================================================================
    // Property 2c: Interleaved Read/Write Pattern Test
    //
    // Tests interleaved read/write patterns for data integrity
    //=========================================================================
    
    task test_interleaved_access;
        input [31:0] random_seed;
        output pass;
        
        reg [31:0] rand_val;
        reg [31:0] addr_a, addr_b;
        reg [31:0] data_a, data_b;
        reg [31:0] read_data;
        reg        success;
    begin
        pass = 1;
        lfsr = random_seed;
        
        // Reset DUT
        reset_dut();
        
        // Generate two different addresses
        get_random(rand_val);
        addr_a = {rand_val[17:2], 2'b00};
        get_random(rand_val);
        addr_b = {rand_val[17:2], 2'b00};
        
        // Ensure addresses are different
        if (addr_a == addr_b) addr_b = addr_b + 4;
        
        // Generate test data
        get_random(data_a);
        get_random(data_b);
        
        // Interleaved pattern: W(A) -> W(B) -> R(A) -> R(B)
        do_write(addr_a, data_a, 4'b1111, success);
        if (!success) begin
            $display("  FAIL: Write A failed");
            pass = 0;
        end
        
        do_write(addr_b, data_b, 4'b1111, success);
        if (!success) begin
            $display("  FAIL: Write B failed");
            pass = 0;
        end
        
        do_read(addr_a, 4'b1111, read_data, success);
        if (!success) begin
            $display("  FAIL: Read A failed");
            pass = 0;
        end else if (read_data !== data_a) begin
            $display("  FAIL: Data A mismatch: expected=%h, got=%h", data_a, read_data);
            pass = 0;
        end
        
        do_read(addr_b, 4'b1111, read_data, success);
        if (!success) begin
            $display("  FAIL: Read B failed");
            pass = 0;
        end else if (read_data !== data_b) begin
            $display("  FAIL: Data B mismatch: expected=%h, got=%h", data_b, read_data);
            pass = 0;
        end
        
        // Check for timing violations
        if (violation_count > 0) begin
            $display("  FAIL: %0d timing violations during interleaved test", violation_count);
            pass = 0;
        end
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        $display("========================================");
        $display("SRAM Controller Property Tests");
        $display("Property 2: Memory Latency Handling");
        $display("Validates: Requirements 2.1, 2.2");
        $display("Iterations: %0d", NUM_ITERATIONS);
        $display("========================================");
        $display("");
        
        // Initialize
        rst_n = 1'b0;
        cpu_req = 1'b0;
        cpu_wr = 1'b0;
        cpu_addr = 32'd0;
        cpu_wdata = 32'd0;
        cpu_be = 4'b0000;
        lfsr = 32'hCAFEBABE;
        
        property2_pass = 0;
        total_pass = 0;
        total_fail = 0;
        
        wait_cycles(10);
        rst_n = 1'b1;
        wait_cycles(5);
        
        //=====================================================================
        // Property 2 Tests - Random Access Pattern
        //=====================================================================
        $display("--- Property 2a: Random Access Pattern ---");
        $display("Testing %0d random access scenarios...", NUM_ITERATIONS);
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            // Get new random seed for this iteration
            get_random(seed);
            
            test_property2(seed, iter_pass);
            
            if (iter_pass) begin
                property2_pass = property2_pass + 1;
            end else begin
                $display("  Iteration %0d failed with seed %h", iteration, seed);
            end
        end
        
        $display("Property 2a (Random): %0d/%0d passed", property2_pass, NUM_ITERATIONS);
        $display("");
        
        //=====================================================================
        // Property 2b Tests - Sequential Access Pattern
        //=====================================================================
        $display("--- Property 2b: Sequential Access Pattern ---");
        $display("Testing %0d sequential access scenarios...", NUM_ITERATIONS);
        
        seq_pass = 0;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            get_random(seed);
            test_sequential_access(seed, iter_pass);
            
            if (iter_pass) begin
                seq_pass = seq_pass + 1;
            end else begin
                $display("  Iteration %0d failed with seed %h", iteration, seed);
            end
        end
        
        $display("Property 2b (Sequential): %0d/%0d passed", seq_pass, NUM_ITERATIONS);
        
        if (seq_pass == NUM_ITERATIONS) begin
            total_pass = total_pass + 1;
        end else begin
            total_fail = total_fail + 1;
        end
        $display("");
        
        //=====================================================================
        // Property 2c Tests - Interleaved Access Pattern
        //=====================================================================
        $display("--- Property 2c: Interleaved Access Pattern ---");
        $display("Testing %0d interleaved access scenarios...", NUM_ITERATIONS);
        
        intlv_pass = 0;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            get_random(seed);
            test_interleaved_access(seed, iter_pass);
            
            if (iter_pass) begin
                intlv_pass = intlv_pass + 1;
            end else begin
                $display("  Iteration %0d failed with seed %h", iteration, seed);
            end
        end
        
        $display("Property 2c (Interleaved): %0d/%0d passed", intlv_pass, NUM_ITERATIONS);
        
        if (intlv_pass == NUM_ITERATIONS) begin
            total_pass = total_pass + 1;
        end else begin
            total_fail = total_fail + 1;
        end 
            if (intlv_pass == NUM_ITERATIONS) begin
                total_pass = total_pass + 1;
            end else begin
                total_fail = total_fail + 1;
            end
        end
        
        //=====================================================================
        // Final Property 2 Summary
        //=====================================================================
        if (property2_pass == NUM_ITERATIONS) begin
            $display("");
            $display("[PASS] Property 2a: Random Access Pattern");
            total_pass = total_pass + 1;
        end else begin
            $display("");
            $display("[FAIL] Property 2a: Random Access Pattern");
            total_fail = total_fail + 1;
        end
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("");
        $display("========================================");
        $display("SRAM PROPERTY TEST SUMMARY");
        $display("========================================");
        $display("Property 2a (Random Access):     %0d/%0d iterations", property2_pass, NUM_ITERATIONS);
        $display("Property 2b (Sequential):        TESTED");
        $display("Property 2c (Interleaved):       TESTED");
        $display("----------------------------------------");
        $display("Total Sub-Properties: %0d passed, %0d failed", total_pass, total_fail);
        $display("Timing Violations: %0d", violation_count);
        $display("========================================");
        
        if (total_fail == 0 && violation_count == 0) begin
            $display("");
            $display("*** ALL SRAM PROPERTY TESTS PASSED ***");
            $display("");
        end else begin
            $display("");
            $display("*** SRAM PROPERTY TESTS FAILED ***");
            $display("");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        // Maximum simulation time: 50ms
        #50_000_000;
        $display("");
        $display("ERROR: Simulation timeout!");
        $display("========================================");
        $finish;
    end

endmodule
