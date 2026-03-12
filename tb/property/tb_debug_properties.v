//=============================================================================
// Property Test: Debug Interface Properties
//
// Description:
//   Property-based tests for debug interface
//   Tests Property 7 (Single-Step) and Property 8 (Memory Access)
//
// Properties Tested:
//   Property 7: Debug Single-Step
//     For any single-step command while CPU is halted, exactly one
//     instruction shall execute before the CPU halts again.
//
//   Property 8: Debug Memory Access
//     For any debug memory read/write while CPU is halted, the operation
//     shall complete correctly without affecting CPU architectural state.
//
// Requirements: 5.1, 5.2, 5.3, 5.4
//=============================================================================

`timescale 1ns/1ps

module tb_debug_properties;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter XLEN = 32;
    parameter NUM_BREAKPOINTS = 4;
    parameter TIMEOUT_CYCLES = 1000;
    parameter NUM_ITERATIONS = 50;
    
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
    integer     iteration;
    integer     pass_count;
    integer     fail_count;
    integer     seed;
    
    // Property tracking
    integer     step_count;
    reg [XLEN-1:0] saved_pc;
    reg [XLEN-1:0] saved_gpr [0:31];
    reg [31:0]  test_memory [0:1023];
    
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
    begin
        rst_n = 1'b0;
        uart_rx_data = 8'd0;
        uart_rx_valid = 1'b0;
        uart_tx_ready = 1'b1;
        cpu_halted = 1'b0;
        cpu_running = 1'b1;
        cpu_pc = 32'h8000_0000;
        cpu_instr = 32'h00000013;  // NOP
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
            repeat(3) @(posedge clk);
            gpr_rdata <= saved_gpr[gpr_addr];
            gpr_rdata_valid <= 1'b1;
            @(posedge clk);
            gpr_rdata_valid <= 1'b0;
        end
    end
    
    // CSR read response
    always @(posedge clk) begin
        if (csr_read_req) begin
            repeat(3) @(posedge clk);
            csr_rdata <= 32'hC5200000 | {20'd0, csr_addr};
            csr_rdata_valid <= 1'b1;
            @(posedge clk);
            csr_rdata_valid <= 1'b0;
        end
    end
    
    // Memory access response
    always @(posedge clk) begin
        if (dbg_mem_read) begin
            repeat(4) @(posedge clk);
            dbg_mem_rdata <= test_memory[dbg_mem_addr[11:2]];
            dbg_mem_done <= 1'b1;
            @(posedge clk);
            dbg_mem_done <= 1'b0;
        end
        if (dbg_mem_write) begin
            repeat(4) @(posedge clk);
            test_memory[dbg_mem_addr[11:2]] <= dbg_mem_wdata;
            dbg_mem_done <= 1'b1;
            @(posedge clk);
            dbg_mem_done <= 1'b0;
        end
    end
    
    //=========================================================================
    // Property 7: Debug Single-Step Test
    //=========================================================================
    task test_property_7;
        input integer iter;
        reg [31:0] initial_pc;
        reg [31:0] expected_pc;
        integer local_step_count;
        integer timeout;
    begin
        // Random initial PC
        initial_pc = 32'h8000_0000 + ($random(seed) & 32'h0000_FFFC);
        cpu_pc = initial_pc;
        step_count = 0;
        
        // First halt the CPU
        send_char("H");
        capture_response(2);
        
        if (rx_buffer[0] != "+") begin
            $display("[FAIL] Property 7 iter %0d: HALT failed", iter);
            fail_count = fail_count + 1;
        end else begin
            // Save initial state
            saved_pc = cpu_pc;
            local_step_count = step_count;
            
            // Send STEP command
            send_char("S");
            capture_response(2);
            
            // Wait for step to complete
            timeout = 0;
            while (step_count == local_step_count && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            // Verify exactly one instruction executed
            expected_pc = saved_pc + 4;
            
            if (rx_buffer[0] == "+" && 
                step_count == local_step_count + 1 &&
                cpu_pc == expected_pc) begin
                $display("[PASS] Property 7 iter %0d: Single step correct (PC: %08X -> %08X)", 
                         iter, saved_pc, cpu_pc);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Property 7 iter %0d: Step error (expected PC=%08X, got PC=%08X, steps=%0d)", 
                         iter, expected_pc, cpu_pc, step_count - local_step_count);
                fail_count = fail_count + 1;
            end
        end
        
        // Resume CPU for next iteration
        send_char("R");
        capture_response(2);
    end
    endtask
    
    //=========================================================================
    // Property 8: Debug Memory Access Test
    //=========================================================================
    task test_property_8;
        input integer iter;
        reg [31:0] test_addr;
        reg [31:0] test_data;
        reg [31:0] read_data;
        reg [31:0] saved_gpr_copy [0:31];
        integer i;
        reg state_preserved;
    begin
        // Random address and data
        test_addr = ($random(seed) & 32'h00000FFC);  // Word aligned, within test memory
        test_data = $random(seed);
        
        // Save CPU state
        for (i = 0; i < 32; i = i + 1) begin
            saved_gpr_copy[i] = saved_gpr[i];
        end
        
        // Halt CPU first
        send_char("H");
        capture_response(2);
        
        if (rx_buffer[0] != "+") begin
            $display("[FAIL] Property 8 iter %0d: HALT failed", iter);
            fail_count = fail_count + 1;
        end else begin
            // Write to memory
            send_char("W");
            send_hex_word(test_addr);
            send_hex_word(test_data);
            capture_response(2);
            
            if (rx_buffer[0] != "+") begin
                $display("[FAIL] Property 8 iter %0d: Write failed", iter);
                fail_count = fail_count + 1;
            end else begin
                // Read back from memory
                send_char("M");
                send_hex_word(test_addr);
                capture_response(10);
                
                // Parse read data from response
                if (rx_buffer[0] == "+") begin
                    read_data = 0;
                    for (i = 1; i <= 8; i = i + 1) begin
                        read_data = read_data << 4;
                        if (rx_buffer[i] >= "0" && rx_buffer[i] <= "9")
                            read_data = read_data | (rx_buffer[i] - "0");
                        else if (rx_buffer[i] >= "A" && rx_buffer[i] <= "F")
                            read_data = read_data | (rx_buffer[i] - "A" + 10);
                    end
                    
                    // Verify data integrity
                    if (read_data == test_data) begin
                        // Verify CPU state preserved
                        state_preserved = 1'b1;
                        for (i = 0; i < 32; i = i + 1) begin
                            if (saved_gpr[i] != saved_gpr_copy[i]) begin
                                state_preserved = 1'b0;
                            end
                        end
                        
                        if (state_preserved) begin
                            $display("[PASS] Property 8 iter %0d: Memory R/W correct (addr=%08X, data=%08X)", 
                                     iter, test_addr, test_data);
                            pass_count = pass_count + 1;
                        end else begin
                            $display("[FAIL] Property 8 iter %0d: CPU state corrupted", iter);
                            fail_count = fail_count + 1;
                        end
                    end else begin
                        $display("[FAIL] Property 8 iter %0d: Data mismatch (wrote=%08X, read=%08X)", 
                                 iter, test_data, read_data);
                        fail_count = fail_count + 1;
                    end
                end else begin
                    $display("[FAIL] Property 8 iter %0d: Read failed", iter);
                    fail_count = fail_count + 1;
                end
            end
        end
        
        // Resume CPU
        send_char("R");
        capture_response(2);
    end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    integer j;
    
    initial begin
        $display("=================================================");
        $display("Debug Interface Property Tests");
        $display("=================================================");
        $display("Property 7: Debug Single-Step");
        $display("Property 8: Debug Memory Access");
        $display("Iterations per property: %0d", NUM_ITERATIONS);
        $display("=================================================");
        
        pass_count = 0;
        fail_count = 0;
        seed = 12345;
        
        // Initialize test memory and GPRs
        for (j = 0; j < 1024; j = j + 1) begin
            test_memory[j] = 32'hDEAD0000 | j;
        end
        for (j = 0; j < 32; j = j + 1) begin
            saved_gpr[j] = 32'h9A200000 | j;
        end
        
        reset_dut();
        
        //=====================================================================
        // Property 7: Single-Step Tests
        //=====================================================================
        $display("\n--- Property 7: Debug Single-Step ---");
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            test_property_7(iteration);
        end
        
        //=====================================================================
        // Property 8: Memory Access Tests
        //=====================================================================
        $display("\n--- Property 8: Debug Memory Access ---");
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            test_property_8(iteration);
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
        $display("Summary: %0d passed, %0d failed (incomplete)", pass_count, fail_count);
        $finish;
    end

endmodule
