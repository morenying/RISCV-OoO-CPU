//////////////////////////////////////////////////////////////////////////////
// UART TX Unit Test
//
// Tests:
// 1. Basic single byte transmission
// 2. Correct start/data/stop bit timing
// 3. LSB-first data order
// 4. FIFO functionality (multiple bytes)
// 5. FIFO full handling
// 6. Parity generation (odd and even)
// 7. Continuous transmission
// 8. Baud rate accuracy
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_uart_tx;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;           // 50 MHz
    parameter BAUD_DIV   = 433;          // 50MHz / 115200 - 1 = 433
    parameter BIT_TIME   = (BAUD_DIV + 1) * CLK_PERIOD;  // Time per bit
    
    //==========================================================================
    // Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg  [15:0] baud_div;
    reg         parity_en;
    reg         parity_odd;
    reg  [7:0]  tx_data;
    reg         tx_valid;
    wire        tx_ready;
    wire        tx_busy;
    wire        fifo_empty;
    wire        fifo_full;
    wire [4:0]  fifo_count;
    wire        uart_txd;
    
    // Test tracking
    integer     test_num;
    integer     errors;
    integer     i, j;
    reg  [7:0]  captured_byte;
    reg         captured_parity;
    
    //==========================================================================
    // DUT
    //==========================================================================
    uart_tx #(
        .FIFO_DEPTH      (16),
        .FIFO_ADDR_WIDTH (4)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .baud_div   (baud_div),
        .parity_en  (parity_en),
        .parity_odd (parity_odd),
        .tx_data    (tx_data),
        .tx_valid   (tx_valid),
        .tx_ready   (tx_ready),
        .tx_busy    (tx_busy),
        .fifo_empty (fifo_empty),
        .fifo_full  (fifo_full),
        .fifo_count (fifo_count),
        .uart_txd   (uart_txd)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //==========================================================================
    // Task: Send byte to TX FIFO
    //==========================================================================
    task send_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            tx_data  <= data;
            tx_valid <= 1'b1;
            @(posedge clk);
            tx_valid <= 1'b0;
        end
    endtask
    
    //==========================================================================
    // Task: Capture transmitted byte from UART line
    //==========================================================================
    task capture_uart_byte;
        output [7:0] data;
        output       parity;
        integer bit_idx;
        begin
            // Wait for start bit (falling edge)
            @(negedge uart_txd);
            
            // Wait to middle of start bit
            #(BIT_TIME/2);
            
            // Verify start bit is low
            if (uart_txd !== 1'b0) begin
                $display("ERROR: Start bit not low");
                errors = errors + 1;
            end
            
            // Sample 8 data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #(BIT_TIME);
                data[bit_idx] = uart_txd;
            end
            
            // Sample parity if enabled
            if (parity_en) begin
                #(BIT_TIME);
                parity = uart_txd;
            end else begin
                parity = 1'b0;
            end
            
            // Sample stop bit
            #(BIT_TIME);
            if (uart_txd !== 1'b1) begin
                $display("ERROR: Stop bit not high");
                errors = errors + 1;
            end
        end
    endtask
    
    //==========================================================================
    // Main Test
    //==========================================================================
    initial begin
        $display("========================================");
        $display("UART TX Unit Test");
        $display("========================================");
        
        // Initialize
        rst_n      = 0;
        baud_div   = BAUD_DIV;
        parity_en  = 0;
        parity_odd = 0;
        tx_data    = 0;
        tx_valid   = 0;
        test_num   = 0;
        errors     = 0;
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 1: Initial state
        //----------------------------------------------------------------------
        test_num = 1;
        $display("\nTest %0d: Initial state", test_num);
        
        if (uart_txd !== 1'b1) begin
            $display("  FAIL: TX line should be idle high");
            errors = errors + 1;
        end else begin
            $display("  PASS: TX line idle high");
        end
        
        if (fifo_empty !== 1'b1) begin
            $display("  FAIL: FIFO should be empty");
            errors = errors + 1;
        end else begin
            $display("  PASS: FIFO empty");
        end
        
        if (tx_busy !== 1'b0) begin
            $display("  FAIL: TX should not be busy");
            errors = errors + 1;
        end else begin
            $display("  PASS: TX not busy");
        end
        
        //----------------------------------------------------------------------
        // Test 2: Single byte transmission (0x55 = 01010101)
        //----------------------------------------------------------------------
        test_num = 2;
        $display("\nTest %0d: Single byte transmission (0x55)", test_num);
        
        send_byte(8'h55);
        
        // Capture and verify
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h55) begin
            $display("  PASS: Received 0x%02X", captured_byte);
        end else begin
            $display("  FAIL: Expected 0x55, got 0x%02X", captured_byte);
            errors = errors + 1;
        end
        
        // Wait for idle
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 3: Single byte transmission (0xAA = 10101010)
        //----------------------------------------------------------------------
        test_num = 3;
        $display("\nTest %0d: Single byte transmission (0xAA)", test_num);
        
        send_byte(8'hAA);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'hAA) begin
            $display("  PASS: Received 0x%02X", captured_byte);
        end else begin
            $display("  FAIL: Expected 0xAA, got 0x%02X", captured_byte);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 4: All zeros (0x00)
        //----------------------------------------------------------------------
        test_num = 4;
        $display("\nTest %0d: All zeros (0x00)", test_num);
        
        send_byte(8'h00);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h00) begin
            $display("  PASS: Received 0x%02X", captured_byte);
        end else begin
            $display("  FAIL: Expected 0x00, got 0x%02X", captured_byte);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 5: All ones (0xFF)
        //----------------------------------------------------------------------
        test_num = 5;
        $display("\nTest %0d: All ones (0xFF)", test_num);
        
        send_byte(8'hFF);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'hFF) begin
            $display("  PASS: Received 0x%02X", captured_byte);
        end else begin
            $display("  FAIL: Expected 0xFF, got 0x%02X", captured_byte);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 6: FIFO multiple bytes
        //----------------------------------------------------------------------
        test_num = 6;
        $display("\nTest %0d: FIFO multiple bytes", test_num);
        
        // Send 4 bytes quickly
        for (i = 0; i < 4; i = i + 1) begin
            send_byte(8'h41 + i);  // 'A', 'B', 'C', 'D'
        end
        
        // Verify FIFO count
        if (fifo_count >= 3) begin
            $display("  PASS: FIFO count = %0d", fifo_count);
        end else begin
            $display("  FAIL: FIFO count should be >= 3, got %0d", fifo_count);
            errors = errors + 1;
        end
        
        // Capture all 4 bytes
        for (i = 0; i < 4; i = i + 1) begin
            capture_uart_byte(captured_byte, captured_parity);
            if (captured_byte === (8'h41 + i)) begin
                $display("  PASS: Byte %0d = 0x%02X ('%c')", i, captured_byte, captured_byte);
            end else begin
                $display("  FAIL: Byte %0d expected 0x%02X, got 0x%02X", i, 8'h41+i, captured_byte);
                errors = errors + 1;
            end
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 7: FIFO full handling
        //----------------------------------------------------------------------
        test_num = 7;
        $display("\nTest %0d: FIFO full handling", test_num);
        
        // Fill FIFO (16 bytes)
        for (i = 0; i < 16; i = i + 1) begin
            send_byte(8'h30 + i);  // '0' to '?'
        end
        
        // Wait a bit for FIFO to register
        repeat(5) @(posedge clk);
        
        if (fifo_full === 1'b1) begin
            $display("  PASS: FIFO full flag set");
        end else begin
            $display("  FAIL: FIFO full flag not set (count=%0d)", fifo_count);
            errors = errors + 1;
        end
        
        if (tx_ready === 1'b0) begin
            $display("  PASS: tx_ready deasserted when full");
        end else begin
            $display("  FAIL: tx_ready should be 0 when full");
            errors = errors + 1;
        end
        
        // Drain FIFO
        for (i = 0; i < 16; i = i + 1) begin
            capture_uart_byte(captured_byte, captured_parity);
        end
        
        repeat(100) @(posedge clk);
        
        if (fifo_empty === 1'b1) begin
            $display("  PASS: FIFO empty after drain");
        end else begin
            $display("  FAIL: FIFO not empty after drain");
            errors = errors + 1;
        end
        
        //----------------------------------------------------------------------
        // Test 8: Even parity
        //----------------------------------------------------------------------
        test_num = 8;
        $display("\nTest %0d: Even parity", test_num);
        
        parity_en  = 1;
        parity_odd = 0;
        repeat(10) @(posedge clk);
        
        // 0x55 has 4 ones, even parity bit should be 0
        send_byte(8'h55);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h55 && captured_parity === 1'b0) begin
            $display("  PASS: 0x55 with even parity = %b", captured_parity);
        end else begin
            $display("  FAIL: Expected parity 0, got %b", captured_parity);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        // 0x57 has 5 ones, even parity bit should be 1
        send_byte(8'h57);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h57 && captured_parity === 1'b1) begin
            $display("  PASS: 0x57 with even parity = %b", captured_parity);
        end else begin
            $display("  FAIL: Expected parity 1, got %b", captured_parity);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 9: Odd parity
        //----------------------------------------------------------------------
        test_num = 9;
        $display("\nTest %0d: Odd parity", test_num);
        
        parity_odd = 1;
        repeat(10) @(posedge clk);
        
        // 0x55 has 4 ones, odd parity bit should be 1
        send_byte(8'h55);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h55 && captured_parity === 1'b1) begin
            $display("  PASS: 0x55 with odd parity = %b", captured_parity);
        end else begin
            $display("  FAIL: Expected parity 1, got %b", captured_parity);
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        // 0x57 has 5 ones, odd parity bit should be 0
        send_byte(8'h57);
        capture_uart_byte(captured_byte, captured_parity);
        
        if (captured_byte === 8'h57 && captured_parity === 1'b0) begin
            $display("  PASS: 0x57 with odd parity = %b", captured_parity);
        end else begin
            $display("  FAIL: Expected parity 0, got %b", captured_parity);
            errors = errors + 1;
        end
        
        parity_en = 0;
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 10: Continuous transmission
        //----------------------------------------------------------------------
        test_num = 10;
        $display("\nTest %0d: Continuous transmission (Hello)", test_num);
        
        // Send "Hello"
        send_byte(8'h48);  // H
        send_byte(8'h65);  // e
        send_byte(8'h6C);  // l
        send_byte(8'h6C);  // l
        send_byte(8'h6F);  // o
        
        // Capture and verify
        capture_uart_byte(captured_byte, captured_parity);
        if (captured_byte !== 8'h48) begin errors = errors + 1; $display("  FAIL: H"); end
        else $display("  PASS: H");
        
        capture_uart_byte(captured_byte, captured_parity);
        if (captured_byte !== 8'h65) begin errors = errors + 1; $display("  FAIL: e"); end
        else $display("  PASS: e");
        
        capture_uart_byte(captured_byte, captured_parity);
        if (captured_byte !== 8'h6C) begin errors = errors + 1; $display("  FAIL: l"); end
        else $display("  PASS: l");
        
        capture_uart_byte(captured_byte, captured_parity);
        if (captured_byte !== 8'h6C) begin errors = errors + 1; $display("  FAIL: l"); end
        else $display("  PASS: l");
        
        capture_uart_byte(captured_byte, captured_parity);
        if (captured_byte !== 8'h6F) begin errors = errors + 1; $display("  FAIL: o"); end
        else $display("  PASS: o");
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("\n========================================");
        $display("Test Summary: %0d tests, %0d errors", test_num, errors);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #(100_000_000);
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
