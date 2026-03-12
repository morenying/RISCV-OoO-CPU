//=============================================================================
// Checkpoint 4: SRAM Controller Verification
// Description: Comprehensive verification with 1000+ random memory operations
//
// Requirements:
//   - 1000+ random memory operations
//   - No data corruption
//   - No deadlocks
//   - No timing violations
//
// Validates: Requirements 2.1, 2.2, 2.6
//=============================================================================

`timescale 1ns/1ps

module tb_sram_checkpoint;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_OPERATIONS = 1000;  // Minimum 1000 as per checkpoint
    parameter SRAM_ADDR_WIDTH = 18;
    parameter SRAM_DATA_WIDTH = 16;
    
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
    
    // Test statistics
    integer     total_writes;
    integer     total_reads;
    integer     write_errors;
    integer     read_errors;
    integer     data_mismatches;
    integer     timeouts;
    
    // Reference memory for verification
    reg [31:0]  ref_mem [0:65535];  // 256KB reference
    reg         ref_valid [0:65535]; // Track which addresses have been written
    
    // Random state
    reg [31:0]  lfsr;
    
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
        if (timeout >= 200) timeouts = timeouts + 1;
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
        if (timeout >= 200) timeouts = timeouts + 1;
        @(posedge clk);
    end
    endtask

    //=========================================================================
    // Reference Memory Update Task
    //=========================================================================
    task update_ref_mem;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  be;
        
        reg [15:0] idx;
        reg [31:0] current;
    begin
        idx = addr[17:2];  // Word index
        
        // For partial writes, we need to read the current value first
        // If not yet written, assume 0 (SRAM model returns X but we'll write full word first)
        current = ref_valid[idx] ? ref_mem[idx] : 32'h0;
        
        if (be[0]) current[7:0]   = data[7:0];
        if (be[1]) current[15:8]  = data[15:8];
        if (be[2]) current[23:16] = data[23:16];
        if (be[3]) current[31:24] = data[31:24];
        
        ref_mem[idx] = current;
        ref_valid[idx] = 1'b1;  // Mark as written
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    integer i;
    reg [31:0] rand_val;
    reg [31:0] test_addr;
    reg [31:0] test_data;
    reg [31:0] read_data;
    reg [31:0] expected_data;
    reg [3:0]  test_be;
    reg        is_write;
    reg        success;
    
    // Verification phase variables (moved from unnamed block)
    integer    verify_errors;
    integer    verified_count;
    
    initial begin
        $display("========================================");
        $display("CHECKPOINT 4: SRAM Controller Verification");
        $display("========================================");
        $display("Operations: %0d", NUM_OPERATIONS);
        $display("Requirements: 2.1, 2.2, 2.6");
        $display("========================================");
        $display("");
        
        // Initialize
        lfsr = 32'hDEAD_BEEF;
        total_writes = 0;
        total_reads = 0;
        write_errors = 0;
        read_errors = 0;
        data_mismatches = 0;
        timeouts = 0;
        
        // Initialize reference memory to 0
        for (i = 0; i < 65536; i = i + 1) begin
            ref_mem[i] = 32'h0;
            ref_valid[i] = 1'b0;  // Mark all as unwritten
        end
        
        // Reset DUT
        reset_dut();
        
        $display("Phase 1: Initial Write Pass (populate memory)");
        $display("-------------------------------------------");
        
        // First, write to 256 random locations to populate memory
        for (i = 0; i < 256; i = i + 1) begin
            get_random(rand_val);
            test_addr = {rand_val[17:2], 2'b00};
            get_random(test_data);
            test_be = 4'b1111;
            
            do_write(test_addr, test_data, test_be, success);
            total_writes = total_writes + 1;
            
            if (success) begin
                update_ref_mem(test_addr, test_data, test_be);
            end else begin
                write_errors = write_errors + 1;
                $display("  ERROR: Write failed at addr %h", test_addr);
            end
        end
        
        $display("Initial writes complete: %0d writes, %0d errors", 256, write_errors);
        $display("");
        
        $display("Phase 2: Random Read/Write Operations");
        $display("-------------------------------------------");
        
        // Main test loop: random mix of reads and writes
        for (i = 0; i < NUM_OPERATIONS; i = i + 1) begin
            // Progress indicator every 100 operations
            if (i % 100 == 0) begin
                $display("  Progress: %0d/%0d operations...", i, NUM_OPERATIONS);
            end
            
            // Random operation type (60% read, 40% write)
            get_random(rand_val);
            is_write = (rand_val[7:0] < 102);  // ~40% writes
            
            // Random address (word-aligned)
            get_random(rand_val);
            test_addr = {rand_val[17:2], 2'b00};
            
            // Random byte enable
            get_random(rand_val);
            test_be = rand_val[3:0];
            if (test_be == 4'b0000) test_be = 4'b1111;
            
            if (is_write) begin
                // Write operation
                get_random(test_data);
                
                // For partial writes, only write to addresses that have been written before
                // This avoids X propagation from uninitialized SRAM locations
                if (test_be != 4'b1111 && !ref_valid[test_addr[17:2]]) begin
                    test_be = 4'b1111;  // Force full word write for new addresses
                end
                
                do_write(test_addr, test_data, test_be, success);
                total_writes = total_writes + 1;
                
                if (success) begin
                    update_ref_mem(test_addr, test_data, test_be);
                end else begin
                    write_errors = write_errors + 1;
                end
            end else begin
                // Read operation - only verify if address was written
                do_read(test_addr, 4'b1111, read_data, success);
                total_reads = total_reads + 1;
                
                if (success) begin
                    if (ref_valid[test_addr[17:2]]) begin
                        expected_data = ref_mem[test_addr[17:2]];
                        if (read_data !== expected_data) begin
                            data_mismatches = data_mismatches + 1;
                            if (data_mismatches <= 10) begin
                                $display("  MISMATCH at addr %h: expected=%h, got=%h", 
                                         test_addr, expected_data, read_data);
                            end
                        end
                    end
                    // Skip verification for unwritten addresses (they return X which is expected)
                end else begin
                    read_errors = read_errors + 1;
                end
            end
        end
        
        $display("  Progress: %0d/%0d operations... DONE", NUM_OPERATIONS, NUM_OPERATIONS);
        $display("");
        
        $display("Phase 3: Verification Read Pass");
        $display("-------------------------------------------");
        
        // Final verification: read back 256 random locations that were written
        verify_errors = 0;
        verified_count = 0;
        
        for (i = 0; i < 256; i = i + 1) begin
            get_random(rand_val);
            test_addr = {rand_val[17:2], 2'b00};
            
            // Only verify addresses that were written
            if (ref_valid[test_addr[17:2]]) begin
                do_read(test_addr, 4'b1111, read_data, success);
                total_reads = total_reads + 1;
                verified_count = verified_count + 1;
                
                if (success) begin
                    expected_data = ref_mem[test_addr[17:2]];
                    if (read_data !== expected_data) begin
                        verify_errors = verify_errors + 1;
                        data_mismatches = data_mismatches + 1;
                    end
                end else begin
                    read_errors = read_errors + 1;
                end
            end
        end
        
        $display("Verification reads complete: %0d verified, %0d errors", verified_count, verify_errors);
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("");
        $display("========================================");
        $display("CHECKPOINT 4 SUMMARY");
        $display("========================================");
        $display("Total Operations:    %0d", total_writes + total_reads);
        $display("  - Writes:          %0d", total_writes);
        $display("  - Reads:           %0d", total_reads);
        $display("----------------------------------------");
        $display("Write Errors:        %0d", write_errors);
        $display("Read Errors:         %0d", read_errors);
        $display("Data Mismatches:     %0d", data_mismatches);
        $display("Timeouts:            %0d", timeouts);
        $display("Timing Violations:   %0d", violation_count);
        $display("========================================");
        
        if (write_errors == 0 && read_errors == 0 && 
            data_mismatches == 0 && timeouts == 0 && violation_count == 0) begin
            $display("");
            $display("*** CHECKPOINT 4 PASSED ***");
            $display("  - No data corruption");
            $display("  - No deadlocks");
            $display("  - No timing violations");
            $display("");
        end else begin
            $display("");
            $display("*** CHECKPOINT 4 FAILED ***");
            $display("");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        // Maximum simulation time: 100ms
        #100_000_000;
        $display("");
        $display("ERROR: Simulation timeout!");
        $display("========================================");
        $finish;
    end

endmodule
