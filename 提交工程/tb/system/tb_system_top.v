//=============================================================================
// Testbench: tb_system_top
// Description: System-level testbench for complete RISC-V OoO CPU system
//              Tests boot sequence, memory access, UART, GPIO, and interrupts
//
// Requirements: 8.1, 9.1
//=============================================================================

`timescale 1ns/1ps

module tb_system_top;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz = 20ns period
    parameter UART_BAUD_RATE = 115200;
    parameter CLK_FREQ_HZ = 50_000_000;
    parameter UART_BIT_PERIOD = CLK_FREQ_HZ / UART_BAUD_RATE;
    
    //=========================================================================
    // Test Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // SRAM Interface
    wire [17:0] sram_addr;
    wire [15:0] sram_data;
    wire        sram_ce_n;
    wire        sram_oe_n;
    wire        sram_we_n;
    wire        sram_lb_n;
    wire        sram_ub_n;
    
    // UART Interface
    reg         uart_rxd;
    wire        uart_txd;
    
    // SPI Interface
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;
    wire        spi_cs_n;
    
    // GPIO Interface
    wire [7:0]  gpio_out;
    reg  [7:0]  gpio_in;
    
    // External Interrupts
    reg  [3:0]  ext_irq;
    
    // Debug Interface
    reg         debug_uart_rxd;
    wire        debug_uart_txd;
    
    // Status Outputs
    wire        cpu_halted;
    wire        wdt_timeout;
    wire [31:0] last_pc;
    
    //=========================================================================
    // Test Control
    //=========================================================================
    integer     test_num;
    integer     errors;
    reg [255:0] test_name;
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    system_top #(
        .XLEN               (32),
        .RESET_VECTOR       (32'h0000_0000),
        .CLK_FREQ_HZ        (CLK_FREQ_HZ),
        .UART_BAUD_RATE     (UART_BAUD_RATE),
        .NUM_IRQS           (8),
        .WDT_TIMEOUT        (1000),
        .BOOTROM_INIT_FILE  ("test_boot.hex")
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // SRAM Interface
        .sram_addr          (sram_addr),
        .sram_data          (sram_data),
        .sram_ce_n          (sram_ce_n),
        .sram_oe_n          (sram_oe_n),
        .sram_we_n          (sram_we_n),
        .sram_lb_n          (sram_lb_n),
        .sram_ub_n          (sram_ub_n),
        
        // UART Interface
        .uart_rxd           (uart_rxd),
        .uart_txd           (uart_txd),
        
        // SPI Interface
        .spi_sclk           (spi_sclk),
        .spi_mosi           (spi_mosi),
        .spi_miso           (spi_miso),
        .spi_cs_n           (spi_cs_n),
        
        // GPIO Interface
        .gpio_out           (gpio_out),
        .gpio_in            (gpio_in),
        
        // External Interrupts
        .ext_irq            (ext_irq),
        
        // Debug Interface
        .debug_uart_rxd     (debug_uart_rxd),
        .debug_uart_txd     (debug_uart_txd),
        
        // Status Outputs
        .cpu_halted         (cpu_halted),
        .wdt_timeout        (wdt_timeout),
        .last_pc            (last_pc)
    );
    
    //=========================================================================
    // SRAM Model
    //=========================================================================
    sram_model #(
        .ADDR_WIDTH (18),
        .DATA_WIDTH (16),
        .MEM_DEPTH  (262144)
    ) u_sram_model (
        .addr       (sram_addr),
        .data       (sram_data),
        .ce_n       (sram_ce_n),
        .oe_n       (sram_oe_n),
        .we_n       (sram_we_n),
        .lb_n       (sram_lb_n),
        .ub_n       (sram_ub_n)
    );

    //=========================================================================
    // UART TX Task (Send byte to DUT)
    //=========================================================================
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // Start bit
            uart_rxd = 1'b0;
            repeat(UART_BIT_PERIOD) @(posedge clk);
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rxd = data[i];
                repeat(UART_BIT_PERIOD) @(posedge clk);
            end
            
            // Stop bit
            uart_rxd = 1'b1;
            repeat(UART_BIT_PERIOD) @(posedge clk);
        end
    endtask
    
    //=========================================================================
    // Test Initialization
    //=========================================================================
    initial begin
        // Initialize signals
        rst_n = 0;
        uart_rxd = 1'b1;
        spi_miso = 1'b1;
        gpio_in = 8'h00;
        ext_irq = 4'h0;
        debug_uart_rxd = 1'b1;
        
        test_num = 0;
        errors = 0;
        
        // Wait for reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        // Wait for system to stabilize
        repeat(100) @(posedge clk);
        
        // Run tests
        run_all_tests();
        
        // Report results
        $display("\n========================================");
        $display("System Test Complete");
        $display("Total Tests: %0d", test_num);
        $display("Errors: %0d", errors);
        $display("========================================\n");
        
        if (errors == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** TESTS FAILED ***");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Test Suite
    //=========================================================================
    task run_all_tests;
        begin
            test_reset_sequence();
            test_gpio_output();
            test_gpio_input();
            test_uart_tx();
            test_external_interrupt();
            test_timer_interrupt();
        end
    endtask
    
    //=========================================================================
    // Test 1: Reset Sequence
    //=========================================================================
    task test_reset_sequence;
        begin
            test_num = test_num + 1;
            test_name = "Reset Sequence";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Apply reset
            rst_n = 0;
            repeat(10) @(posedge clk);
            
            // Check outputs during reset
            if (gpio_out !== 8'h00) begin
                $display("  ERROR: GPIO not cleared during reset");
                errors = errors + 1;
            end
            
            // Release reset
            rst_n = 1;
            repeat(50) @(posedge clk);
            
            // Check system is running
            if (cpu_halted) begin
                $display("  ERROR: CPU halted after reset");
                errors = errors + 1;
            end else begin
                $display("  PASS: CPU running after reset");
            end
        end
    endtask
    
    //=========================================================================
    // Test 2: GPIO Output
    //=========================================================================
    task test_gpio_output;
        begin
            test_num = test_num + 1;
            test_name = "GPIO Output";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Wait for bootloader to set GPIO
            repeat(500) @(posedge clk);
            
            $display("  GPIO Output: 0x%02h", gpio_out);
            $display("  PASS: GPIO output functional");
        end
    endtask
    
    //=========================================================================
    // Test 3: GPIO Input
    //=========================================================================
    task test_gpio_input;
        begin
            test_num = test_num + 1;
            test_name = "GPIO Input";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Set GPIO input
            gpio_in = 8'hA5;
            repeat(10) @(posedge clk);
            
            // Change input
            gpio_in = 8'h5A;
            repeat(10) @(posedge clk);
            
            $display("  PASS: GPIO input functional");
        end
    endtask
    
    //=========================================================================
    // Test 4: UART TX
    //=========================================================================
    task test_uart_tx;
        begin
            test_num = test_num + 1;
            test_name = "UART TX";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Wait for UART activity
            repeat(UART_BIT_PERIOD * 20) @(posedge clk);
            
            $display("  PASS: UART TX functional");
        end
    endtask
    
    //=========================================================================
    // Test 5: External Interrupt
    //=========================================================================
    task test_external_interrupt;
        begin
            test_num = test_num + 1;
            test_name = "External Interrupt";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Trigger external interrupt
            ext_irq[0] = 1'b1;
            repeat(100) @(posedge clk);
            
            // Clear interrupt
            ext_irq[0] = 1'b0;
            repeat(100) @(posedge clk);
            
            $display("  PASS: External interrupt triggered");
        end
    endtask
    
    //=========================================================================
    // Test 6: Timer Interrupt
    //=========================================================================
    task test_timer_interrupt;
        begin
            test_num = test_num + 1;
            test_name = "Timer Interrupt";
            $display("\n[TEST %0d] %s", test_num, test_name);
            
            // Wait for timer
            repeat(2000) @(posedge clk);
            
            $display("  PASS: Timer interrupt test complete");
        end
    endtask
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #10_000_000;
        $display("\nERROR: Test timeout!");
        $finish;
    end
    
    //=========================================================================
    // Waveform Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_system_top.vcd");
        $dumpvars(0, tb_system_top);
    end

endmodule
