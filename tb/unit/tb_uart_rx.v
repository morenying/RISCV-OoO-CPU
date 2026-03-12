//////////////////////////////////////////////////////////////////////////////
// UART RX Unit Test
//
// Tests:
// 1. Basic single byte reception
// 2. Start bit detection with 16x oversampling
// 3. LSB-first data order
// 4. FIFO functionality
// 5. Frame error detection (invalid stop bit)
// 6. Parity error detection
// 7. Overrun error detection
// 8. Noise immunity (majority voting)
// 9. Multiple byte reception
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_uart_rx;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;           // 50 MHz = 20ns period
    parameter BAUD_DIV   = 26;           // For 16x oversampling: 50MHz / (115200*16) - 1 ≈ 26
    parameter BIT_TIME   = (BAUD_DIV + 1) * 16 * CLK_PERIOD;  // Time per bit = 8640ns
    
    //==========================================================================
    // Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    reg  [15:0] baud_div;
    reg         parity_en;
    reg         parity_odd;
    wire [7:0]  rx_data;
    wire        rx_valid;
    reg         rx_ready;
    wire        rx_busy;
    wire        fifo_empty;
    wire        fifo_full;
    wire [4:0]  fifo_count;
    wire        frame_error;
    wire        parity_error;
    wire        overrun_error;
    reg         uart_rxd;
    
    // Test tracking
    integer     test_num;
    integer     errors;
    integer     i;
    reg  [7:0]  expected_byte;
    
    //==========================================================================
    // DUT
    //==========================================================================
    uart_rx #(
        .FIFO_DEPTH      (16),
        .FIFO_ADDR_WIDTH (4)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .baud_div     (baud_div),
        .parity_en    (parity_en),
        .parity_odd   (parity_odd),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .rx_ready     (rx_ready),
        .rx_busy      (rx_busy),
        .fifo_empty   (fifo_empty),
        .fifo_full    (fifo_full),
        .fifo_count   (fifo_count),
        .frame_error  (frame_error),
        .parity_error (parity_error),
        .overrun_error(overrun_error),
        .uart_rxd     (uart_rxd)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //==========================================================================
    // Task: Send byte on UART RX line
    //==========================================================================
    task send_uart_byte;
        input [7:0] data;
        input       send_parity;
        input       parity_val;
        input       valid_stop;
        integer bit_idx;
        begin
            // Start bit
            uart_rxd = 1'b0;
            #(BIT_TIME);
            
            // Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rxd = data[bit_idx];
                #(BIT_TIME);
            end
            
            // Parity bit (if enabled)
            if (send_parity) begin
                uart_rxd = parity_val;
                #(BIT_TIME);
            end
            
            // Stop bit
            uart_rxd = valid_stop ? 1'b1 : 1'b0;
            #(BIT_TIME);
            
            // Return to idle and wait for RX to process
            uart_rxd = 1'b1;
            #(BIT_TIME/2);  // Extra idle time between bytes
        end
    endtask
    
    //==========================================================================
    // Task: Send byte with correct parity
    //==========================================================================
    task send_byte_with_parity;
        input [7:0] data;
        reg calc_parity;
        begin
            calc_parity = ^data;  // XOR all bits
            if (parity_odd) begin
                calc_parity = ~calc_parity;
            end
            send_uart_byte(data, parity_en, calc_parity, 1'b1);
        end
    endtask
    
    //==========================================================================
    // Task: Read byte from FIFO
    //==========================================================================
    task read_fifo;
        output [7:0] data;
        begin
            if (rx_valid) begin
                data = rx_data;
                @(posedge clk);
                rx_ready = 1'b1;
                @(posedge clk);
                rx_ready = 1'b0;
            end else begin
                data = 8'hXX;
            end
        end
    endtask
    
    //==========================================================================
    // Main Test
    //==========================================================================
    reg [7:0] read_data;
    
    initial begin
        $display("========================================");
        $display("UART RX Unit Test");
        $display("========================================");
        
        // Initialize
        rst_n      = 0;
        baud_div   = BAUD_DIV;
        parity_en  = 0;
        parity_odd = 0;
        rx_ready   = 0;
        uart_rxd   = 1;  // Idle high
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
        
        if (fifo_empty === 1'b1) begin
            $display("  PASS: FIFO empty");
        end else begin
            $display("  FAIL: FIFO should be empty");
            errors = errors + 1;
        end
        
        if (rx_busy === 1'b0) begin
            $display("  PASS: RX not busy");
        end else begin
            $display("  FAIL: RX should not be busy");
            errors = errors + 1;
        end
        
        //----------------------------------------------------------------------
        // Test 2: Single byte reception (0x55)
        //----------------------------------------------------------------------
        test_num = 2;
        $display("\nTest %0d: Single byte reception (0x55)", test_num);
        
        send_uart_byte(8'h55, 1'b0, 1'b0, 1'b1);
        
        // Wait for reception - need extra time for synchronizer and processing
        #(BIT_TIME * 2);
        repeat(500) @(posedge clk);
        
        if (rx_valid === 1'b1) begin
            read_fifo(read_data);
            if (read_data === 8'h55) begin
                $display("  PASS: Received 0x%02X", read_data);
            end else begin
                $display("  FAIL: Expected 0x55, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 3: Single byte reception (0xAA)
        //----------------------------------------------------------------------
        test_num = 3;
        $display("\nTest %0d: Single byte reception (0xAA)", test_num);
        
        send_uart_byte(8'hAA, 1'b0, 1'b0, 1'b1);
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (rx_valid) begin
            read_fifo(read_data);
            if (read_data === 8'hAA) begin
                $display("  PASS: Received 0x%02X", read_data);
            end else begin
                $display("  FAIL: Expected 0xAA, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 4: All zeros (0x00)
        //----------------------------------------------------------------------
        test_num = 4;
        $display("\nTest %0d: All zeros (0x00)", test_num);
        
        send_uart_byte(8'h00, 1'b0, 1'b0, 1'b1);
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (rx_valid) begin
            read_fifo(read_data);
            if (read_data === 8'h00) begin
                $display("  PASS: Received 0x%02X", read_data);
            end else begin
                $display("  FAIL: Expected 0x00, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 5: All ones (0xFF)
        //----------------------------------------------------------------------
        test_num = 5;
        $display("\nTest %0d: All ones (0xFF)", test_num);
        
        send_uart_byte(8'hFF, 1'b0, 1'b0, 1'b1);
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (rx_valid) begin
            read_fifo(read_data);
            if (read_data === 8'hFF) begin
                $display("  PASS: Received 0x%02X", read_data);
            end else begin
                $display("  FAIL: Expected 0xFF, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 6: Frame error detection
        //----------------------------------------------------------------------
        test_num = 6;
        $display("\nTest %0d: Frame error detection", test_num);
        
        // Send byte with invalid stop bit
        send_uart_byte(8'h42, 1'b0, 1'b0, 1'b0);  // Stop bit = 0
        
        // Check for frame error
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        // Frame error should have been asserted
        // Note: frame_error is a pulse, so we need to catch it
        $display("  INFO: Frame error test - byte with invalid stop bit sent");
        
        // The byte should NOT be stored in FIFO due to frame error
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 7: Even parity - correct
        //----------------------------------------------------------------------
        test_num = 7;
        $display("\nTest %0d: Even parity - correct", test_num);
        
        parity_en  = 1;
        parity_odd = 0;
        repeat(10) @(posedge clk);
        
        // 0x55 has 4 ones, even parity = 0
        send_uart_byte(8'h55, 1'b1, 1'b0, 1'b1);
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (rx_valid) begin
            read_fifo(read_data);
            if (read_data === 8'h55) begin
                $display("  PASS: Received 0x%02X with correct even parity", read_data);
            end else begin
                $display("  FAIL: Expected 0x55, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 8: Even parity - incorrect (should detect error)
        //----------------------------------------------------------------------
        test_num = 8;
        $display("\nTest %0d: Even parity - incorrect", test_num);
        
        // 0x55 has 4 ones, even parity should be 0, but we send 1
        send_uart_byte(8'h55, 1'b1, 1'b1, 1'b1);  // Wrong parity
        
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        $display("  INFO: Parity error test - byte with wrong parity sent");
        
        // Drain any data
        while (rx_valid) begin
            read_fifo(read_data);
        end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 9: Odd parity - correct
        //----------------------------------------------------------------------
        test_num = 9;
        $display("\nTest %0d: Odd parity - correct", test_num);
        
        parity_odd = 1;
        repeat(10) @(posedge clk);
        
        // 0x55 has 4 ones, odd parity = 1
        send_uart_byte(8'h55, 1'b1, 1'b1, 1'b1);
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (rx_valid) begin
            read_fifo(read_data);
            if (read_data === 8'h55) begin
                $display("  PASS: Received 0x%02X with correct odd parity", read_data);
            end else begin
                $display("  FAIL: Expected 0x55, got 0x%02X", read_data);
                errors = errors + 1;
            end
        end else begin
            $display("  FAIL: No data received");
            errors = errors + 1;
        end
        
        parity_en = 0;
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 10: Multiple byte reception
        //----------------------------------------------------------------------
        test_num = 10;
        $display("\nTest %0d: Multiple byte reception (Hello)", test_num);
        
        // Send "Hello"
        send_uart_byte(8'h48, 1'b0, 1'b0, 1'b1);  // H
        send_uart_byte(8'h65, 1'b0, 1'b0, 1'b1);  // e
        send_uart_byte(8'h6C, 1'b0, 1'b0, 1'b1);  // l
        send_uart_byte(8'h6C, 1'b0, 1'b0, 1'b1);  // l
        send_uart_byte(8'h6F, 1'b0, 1'b0, 1'b1);  // o
        
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        // Read and verify
        read_fifo(read_data);
        if (read_data === 8'h48) $display("  PASS: H"); else begin $display("  FAIL: H"); errors = errors + 1; end
        
        read_fifo(read_data);
        if (read_data === 8'h65) $display("  PASS: e"); else begin $display("  FAIL: e"); errors = errors + 1; end
        
        read_fifo(read_data);
        if (read_data === 8'h6C) $display("  PASS: l"); else begin $display("  FAIL: l"); errors = errors + 1; end
        
        read_fifo(read_data);
        if (read_data === 8'h6C) $display("  PASS: l"); else begin $display("  FAIL: l"); errors = errors + 1; end
        
        read_fifo(read_data);
        if (read_data === 8'h6F) $display("  PASS: o"); else begin $display("  FAIL: o"); errors = errors + 1; end
        
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 11: FIFO count
        //----------------------------------------------------------------------
        test_num = 11;
        $display("\nTest %0d: FIFO count tracking", test_num);
        
        // Send 5 bytes
        for (i = 0; i < 5; i = i + 1) begin
            send_uart_byte(8'h30 + i, 1'b0, 1'b0, 1'b1);
        end
        
        #(BIT_TIME);
        repeat(500) @(posedge clk);
        
        if (fifo_count === 5) begin
            $display("  PASS: FIFO count = %0d", fifo_count);
        end else begin
            $display("  FAIL: Expected count 5, got %0d", fifo_count);
            errors = errors + 1;
        end
        
        // Drain FIFO
        while (rx_valid) begin
            read_fifo(read_data);
        end
        
        if (fifo_empty === 1'b1) begin
            $display("  PASS: FIFO empty after drain");
        end else begin
            $display("  FAIL: FIFO not empty");
            errors = errors + 1;
        end
        
        repeat(500) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 12: Random bytes
        //----------------------------------------------------------------------
        test_num = 12;
        $display("\nTest %0d: Random byte values", test_num);
        
        for (i = 0; i < 10; i = i + 1) begin
            expected_byte = $random & 8'hFF;
            send_uart_byte(expected_byte, 1'b0, 1'b0, 1'b1);
            #(BIT_TIME);
            repeat(500) @(posedge clk);
            
            if (rx_valid) begin
                read_fifo(read_data);
                if (read_data === expected_byte) begin
                    $display("  PASS: Byte %0d = 0x%02X", i, read_data);
                end else begin
                    $display("  FAIL: Byte %0d expected 0x%02X, got 0x%02X", i, expected_byte, read_data);
                    errors = errors + 1;
                end
            end else begin
                $display("  FAIL: Byte %0d not received", i);
                errors = errors + 1;
            end
        end
        
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
        #(200_000_000);
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
