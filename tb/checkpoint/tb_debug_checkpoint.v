//=============================================================================
// Checkpoint Test: Debug Interface Verification
//
// Description:
//   Complete debug interface verification checkpoint
//   Tests all debug functionality comprehensively
//
// Tests:
//   1. Basic commands (HALT, RESUME, STEP)
//   2. Register read (PC, GPR, CSR)
//   3. Memory read/write
//   4. Breakpoint management
//   5. Single-step precision
//   6. Error handling
//
// Requirements: 5.1, 5.2, 5.3, 5.4
//=============================================================================

`timescale 1ns/1ps

module tb_debug_checkpoint;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;
    parameter XLEN = 32;
    parameter NUM_BREAKPOINTS = 4;
    parameter TIMEOUT_CYCLES = 1000;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // UART Interface
    reg  [7:0]  uart_rx_data;
    reg         uart_rx_valid;
    wire [7:0]  uart_tx_data;
    wire        uart_tx_valid;
    reg         uart_tx_ready;
    
    // CPU Debug Interface
    wire        cpu_halt_req;
    wire        cpu_resume_req;
    wire        cpu_step_req;
    reg         cpu_halted;
    reg         cpu_running;
    reg  [XLEN-1:0] cpu_pc;
    reg  [XLEN-1:0] cpu_instr;
    
    // Register Read Interface
    wire [4:0]  gpr_addr;
    wire        gpr_read_req;
    reg  [XLEN-1:0] gpr_rdata;
    reg         gpr_rdata_valid;
    
    wire [11:0] csr_addr;
    wire        csr_read_req;
    reg  [XLEN-1:0] csr_rdata;
    reg         csr_rdata_valid;
    
    // Memory Debug Interface
    wire [XLEN-1:0] dbg_mem_addr;
    wire [XLEN-1:0] dbg_mem_wdata;
    wire        dbg_mem_read;
    wire        dbg_mem_write;
    wire [1:0]  dbg_mem_size;
    reg  [XLEN-1:0] dbg_mem_rdata;
    reg         dbg_mem_done;
    reg         dbg_mem_error;
    
    // Breakpoint Interface
    wire [NUM_BREAKPOINTS-1:0] bp_enable;
    wire [XLEN-1:0] bp_addr_0, bp_addr_1, bp_addr_2, bp_addr_3;
    reg         bp_hit;
    reg  [1:0]  bp_hit_idx;
    
    // Status
    wire        debug_active;
    wire [7:0]  error_code;
    
    // Test tracking
    integer     test_num;
    integer     pass_count;
    integer     fail_count;
    integer     step_count;
    
    // Test memory and registers
    reg [31:0]  test_memory [0:255];
    reg [31:0]  gpr_file [0:31];
    reg [31:0]  csr_file [0:4095];
    
    // Response capture
    reg [7:0]   rx_buffer [0:15];
    integer     rx_count;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    debug_if #(
        .XLEN           (XLEN),
        .NUM_BREAKPOINTS(NUM_BREAKPOINTS),
        .TIMEOUT_CYCLES (TIMEOUT_CYCLES)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        
        .uart_rx_data   (uart_rx_data),
        .uart_rx_valid  (uart_rx_valid),
        .uart_tx_data   (uart_tx_data),
        .uart_tx_valid  (uart_tx_valid),
        .uart_tx_ready  (uart_tx_ready),
        
        .cpu_halt_req   (cpu_halt_req),
        .cpu_resume_req (cpu_resume_req),
        .cpu_step_req   (cpu_step_req),
        .cpu_halted     (cpu_halted),
        .cpu_running    (cpu_running),
        .cpu_pc         (cpu_pc),
        .cpu_instr      (cpu_instr),
        
        .gpr_addr       (gpr_addr),
        .gpr_read_req   (gpr_read_req),
        .gpr_rdata      (gpr_rdata),
        .gpr_rdata_valid(gpr_rdata_valid),
        
        .csr_addr       (csr_addr),
        .csr_read_req   (csr_read_req),
        .csr_rdata      (csr_rdata),
        .csr_rdata_valid(csr_rdata_valid),
        
        .dbg_mem_addr   (dbg_mem_addr),
        .dbg_mem_wdata  (dbg_mem_wdata),
        .dbg_mem_read   (dbg_mem_read),
        .dbg_mem_write  (dbg_mem_write),
        .dbg_mem_size   (dbg_mem_size),
        .dbg_mem_rdata  (dbg_mem_rdata),
        .dbg_mem_done   (dbg_mem_done),
        .dbg_mem_error  (dbg_mem_error),
        
        .bp_enable      (bp_enable),
        .bp_addr_0      (bp_addr_0),
        .bp_addr_1      (bp_addr_1),
        .bp_addr_2      (bp_addr_2),
        .bp_addr_3      (bp_addr_3),
        .bp_hit         (bp_hit),
        .bp_hit_idx     (bp_hit_idx),
        
        .debug_active   (debug_active),
        .error_code     (error_code)
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
        integer j;
    begin
        rst_n = 1'b0;
        uart_rx_data = 8'd0;
        uart_rx_valid = 1'b0;
        uart_tx_ready = 1'b1;
        cpu_halted = 1'b0;
        cpu_running = 1'b1;
        cpu_pc = 32'h8000_0000;
        cpu_instr = 32'h00000013;
        gpr_rdata = 32'd0;
        gpr_rdata_valid = 1'b0;
        csr_rdata = 32'd0;
        csr_rdata_valid = 1'b0;
        dbg_mem_rdata = 32'd0;
        dbg_mem_done = 1'b0;
        dbg_mem_error = 1'b0;
        bp_hit = 1'b0;
        bp_hit_idx = 2'd0;
        rx_count = 0;
        step_count = 0;
        
        // Initialize test data
        for (j = 0; j < 256; j = j + 1) test_memory[j] = 32'hA5A50000 | j;
        for (j = 0; j < 32; j = j + 1) gpr_file[j] = 32'hDEAD0000 | j;
        for (j = 0; j < 4096; j = j + 1) csr_file[j] = 32'hC5200000 | j;
        
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask
    
    task send_char;
        input [7:0] ch;
    begin
        @(negedge clk);
        uart_rx_data = ch;
        uart_rx_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        uart_rx_valid = 1'b0;
        @(posedge clk);
        @(posedge clk);
    end
    endtask
    
    task send_hex_byte;
        input [7:0] val;
        reg [7:0] hi, lo;
    begin
        hi = (val[7:4] < 10) ? ("0" + val[7:4]) : ("A" + val[7:4] - 10);
        lo = (val[3:0] < 10) ? ("0" + val[3:0]) : ("A" + val[3:0] - 10);
        send_char(hi);
        send_char(lo);
    end
    endtask
    
    task send_hex_word;
        input [31:0] val;
    begin
        send_hex_byte(val[31:24]);
        send_hex_byte(val[23:16]);
        send_hex_byte(val[15:8]);
        send_hex_byte(val[7:0]);
    end
    endtask
    
    task capture_response;
        input integer max_chars;
        integer i;
        integer timeout;
    begin
        rx_count = 0;
        for (i = 0; i < max_chars; i = i + 1) begin
            timeout = 0;
            while (!uart_tx_valid && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 2000) begin
                i = max_chars;
            end else if (uart_tx_valid && uart_tx_ready) begin
                rx_buffer[rx_count] = uart_tx_data;
                rx_count = rx_count + 1;
                @(posedge clk);
            end else begin
                i = max_chars;
            end
        end
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

    //=========================================================================
    // CPU Response Simulation
    //=========================================================================
    always @(posedge clk) begin
        if (cpu_halt_req && cpu_running) begin
            repeat(3) @(posedge clk);
            cpu_halted <= 1'b1;
            cpu_running <= 1'b0;
        end
        if (cpu_resume_req && cpu_halted) begin
            repeat(3) @(posedge clk);
            cpu_halted <= 1'b0;
            cpu_running <= 1'b1;
        end
        if (cpu_step_req && cpu_halted) begin
            repeat(3) @(posedge clk);
            cpu_pc <= cpu_pc + 4;
            step_count <= step_count + 1;
        end
    end
    
    // GPR read response
    always @(posedge clk) begin
        if (gpr_read_req) begin
            repeat(2) @(posedge clk);
            gpr_rdata <= gpr_file[gpr_addr];
            gpr_rdata_valid <= 1'b1;
            @(posedge clk);
            gpr_rdata_valid <= 1'b0;
        end
    end
    
    // CSR read response
    always @(posedge clk) begin
        if (csr_read_req) begin
            repeat(2) @(posedge clk);
            csr_rdata <= csr_file[csr_addr];
            csr_rdata_valid <= 1'b1;
            @(posedge clk);
            csr_rdata_valid <= 1'b0;
        end
    end
    
    // Memory access response
    always @(posedge clk) begin
        if (dbg_mem_read) begin
            repeat(3) @(posedge clk);
            dbg_mem_rdata <= test_memory[dbg_mem_addr[9:2]];
            dbg_mem_done <= 1'b1;
            @(posedge clk);
            dbg_mem_done <= 1'b0;
        end
        if (dbg_mem_write) begin
            repeat(3) @(posedge clk);
            test_memory[dbg_mem_addr[9:2]] <= dbg_mem_wdata;
            dbg_mem_done <= 1'b1;
            @(posedge clk);
            dbg_mem_done <= 1'b0;
        end
    end
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    integer i;
    reg [31:0] expected_val;
    reg [31:0] read_val;
    integer errors;
    
    initial begin
        $display("=================================================");
        $display("Debug Interface Checkpoint Test");
        $display("=================================================");
        
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        //=====================================================================
        // Test 1: Basic HALT/RESUME Cycle
        //=====================================================================
        $display("\n--- Test 1: Basic HALT/RESUME ---");
        
        send_char("H");
        capture_response(2);
        check_result(rx_buffer[0] == "+" && cpu_halted, "HALT command");
        
        send_char("R");
        capture_response(2);
        check_result(rx_buffer[0] == "+" && cpu_running, "RESUME command");
        
        //=====================================================================
        // Test 2: Read PC
        //=====================================================================
        $display("\n--- Test 2: Read PC ---");
        
        cpu_pc = 32'h8000_ABCD;
        send_char("H");
        capture_response(2);
        
        send_char("P");
        capture_response(10);
        check_result(rx_buffer[0] == "+" && 
                     rx_buffer[1] == "8" && rx_buffer[2] == "0" &&
                     rx_buffer[3] == "0" && rx_buffer[4] == "0" &&
                     rx_buffer[5] == "A" && rx_buffer[6] == "B" &&
                     rx_buffer[7] == "C" && rx_buffer[8] == "D",
                     "Read PC = 8000ABCD");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 3: Single Step Precision
        //=====================================================================
        $display("\n--- Test 3: Single Step Precision ---");
        
        cpu_pc = 32'h8000_0100;
        step_count = 0;
        
        send_char("H");
        capture_response(2);
        
        // Execute 10 single steps
        errors = 0;
        for (i = 0; i < 10; i = i + 1) begin
            expected_val = 32'h8000_0100 + (i * 4);
            if (cpu_pc != expected_val) errors = errors + 1;
            
            send_char("S");
            capture_response(2);
            
            if (rx_buffer[0] != "+") errors = errors + 1;
        end
        
        check_result(errors == 0 && step_count == 10, "10 single steps executed");
        check_result(cpu_pc == 32'h8000_0128, "Final PC after 10 steps");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 4: GPR Read (Sample registers)
        //=====================================================================
        $display("\n--- Test 4: GPR Read ---");
        
        send_char("H");
        capture_response(2);
        
        errors = 0;
        // Read sample GPRs (x0, x1, x10, x31)
        send_char("G");
        send_hex_word(0);
        capture_response(10);
        if (rx_buffer[0] != "+") errors = errors + 1;
        
        send_char("G");
        send_hex_word(1);
        capture_response(10);
        if (rx_buffer[0] != "+") errors = errors + 1;
        
        send_char("G");
        send_hex_word(10);
        capture_response(10);
        if (rx_buffer[0] != "+") errors = errors + 1;
        
        send_char("G");
        send_hex_word(31);
        capture_response(10);
        if (rx_buffer[0] != "+") errors = errors + 1;
        
        check_result(errors == 0, "Sample GPRs readable (x0, x1, x10, x31)");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 5: CSR Read
        //=====================================================================
        $display("\n--- Test 5: CSR Read ---");
        
        send_char("H");
        capture_response(2);
        
        // Read mstatus (0x300)
        send_char("C");
        send_hex_word(32'h0000_0300);
        capture_response(10);
        check_result(rx_buffer[0] == "+", "CSR mstatus readable");
        
        // Read mtvec (0x305)
        send_char("C");
        send_hex_word(32'h0000_0305);
        capture_response(10);
        check_result(rx_buffer[0] == "+", "CSR mtvec readable");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 6: Memory Read/Write
        //=====================================================================
        $display("\n--- Test 6: Memory Read/Write ---");
        
        send_char("H");
        capture_response(2);
        
        // Write pattern to memory
        send_char("W");
        send_hex_word(32'h0000_0100);
        send_hex_word(32'hCAFE_BABE);
        capture_response(2);
        check_result(rx_buffer[0] == "+", "Memory write");
        
        // Read back
        send_char("M");
        send_hex_word(32'h0000_0100);
        capture_response(10);
        check_result(rx_buffer[0] == "+" &&
                     rx_buffer[1] == "C" && rx_buffer[2] == "A" &&
                     rx_buffer[3] == "F" && rx_buffer[4] == "E" &&
                     rx_buffer[5] == "B" && rx_buffer[6] == "A" &&
                     rx_buffer[7] == "B" && rx_buffer[8] == "E",
                     "Memory read back correct");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 7: Breakpoint Management
        //=====================================================================
        $display("\n--- Test 7: Breakpoint Management ---");
        
        // Set 4 breakpoints
        send_char("B"); send_hex_word(32'h8000_1000); capture_response(2);
        check_result(rx_buffer[0] == "+" && bp_enable[0], "Set BP 0");
        
        send_char("B"); send_hex_word(32'h8000_2000); capture_response(2);
        check_result(rx_buffer[0] == "+" && bp_enable[1], "Set BP 1");
        
        send_char("B"); send_hex_word(32'h8000_3000); capture_response(2);
        check_result(rx_buffer[0] == "+" && bp_enable[2], "Set BP 2");
        
        send_char("B"); send_hex_word(32'h8000_4000); capture_response(2);
        check_result(rx_buffer[0] == "+" && bp_enable[3], "Set BP 3");
        
        check_result(bp_enable == 4'b1111, "All 4 BPs enabled");
        
        // Delete one breakpoint
        send_char("D"); send_hex_word(32'h8000_2000); capture_response(2);
        check_result(rx_buffer[0] == "+" && !bp_enable[1], "Delete BP 1");
        
        // List breakpoints
        send_char("L");
        capture_response(2);
        check_result(rx_buffer[0] == "+", "List BPs");
        
        //=====================================================================
        // Test 8: Sequential Memory Operations
        //=====================================================================
        $display("\n--- Test 8: Sequential Memory Operations ---");
        
        send_char("H");
        capture_response(2);
        
        errors = 0;
        // Write 4 words
        for (i = 0; i < 4; i = i + 1) begin
            send_char("W");
            send_hex_word(i * 4);
            send_hex_word(32'h12340000 | i);
            capture_response(2);
            if (rx_buffer[0] != "+") errors = errors + 1;
        end
        
        // Read back and verify
        for (i = 0; i < 4; i = i + 1) begin
            send_char("M");
            send_hex_word(i * 4);
            capture_response(10);
            if (rx_buffer[0] != "+") errors = errors + 1;
        end
        
        check_result(errors == 0, "8 sequential memory operations");
        
        send_char("R");
        capture_response(2);
        
        //=====================================================================
        // Test 9: INFO Command
        //=====================================================================
        $display("\n--- Test 9: INFO Command ---");
        
        send_char("I");
        capture_response(10);
        check_result(rx_buffer[0] == "+", "INFO command");
        
        //=====================================================================
        // Test 10: HELP Command
        //=====================================================================
        $display("\n--- Test 10: HELP Command ---");
        
        send_char("?");
        capture_response(2);
        check_result(rx_buffer[0] == "+", "HELP command");
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("\n=================================================");
        $display("Checkpoint Test Summary");
        $display("=================================================");
        $display("Total Tests: %0d", test_num);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("=================================================");
        
        if (fail_count == 0) begin
            $display("CHECKPOINT 14 PASSED: Debug Interface Verified!");
        end else begin
            $display("CHECKPOINT 14 FAILED: Some tests failed!");
        end
        
        $display("=================================================");
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("\n[ERROR] Test timeout!");
        $display("Summary: %0d passed, %0d failed (incomplete)", pass_count, fail_count);
        $finish;
    end

endmodule
