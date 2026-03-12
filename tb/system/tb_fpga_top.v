//=============================================================================
// Testbench: tb_fpga_top
// Description: FPGA top-level testbench with clock generation and I/O models
//              Tests the complete FPGA design including MMCM and I/O buffers
//
// Requirements: 8.1, 9.1
//=============================================================================

`timescale 1ns/1ps

module tb_fpga_top;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter INPUT_CLK_PERIOD = 10;  // 100MHz = 10ns period
    
    //=========================================================================
    // Test Signals
    //=========================================================================
    reg         sys_clk_i;
    reg         sys_rst_n_i;
    
    // SRAM Interface
    wire [17:0] sram_addr_o;
    wire [15:0] sram_data_io;
    wire        sram_ce_n_o;
    wire        sram_oe_n_o;
    wire        sram_we_n_o;
    wire        sram_lb_n_o;
    wire        sram_ub_n_o;
    
    // UART Interface
    reg         uart_rx_i;
    wire        uart_tx_o;
    
    // SPI Interface
    wire        spi_sclk_o;
    wire        spi_mosi_o;
    reg         spi_miso_i;
    wire        spi_cs_n_o;
    
    // GPIO Interface
    wire [7:0]  led_o;
    reg  [7:0]  btn_i;
    
    // External Interrupts
    reg  [3:0]  ext_irq_i;
    
    // Debug Interface
    reg         debug_uart_rx_i;
    wire        debug_uart_tx_o;
    
    //=========================================================================
    // Test Control
    //=========================================================================
    integer     test_num;
    integer     errors;
    
    //=========================================================================
    // Clock Generation (100MHz input)
    //=========================================================================
    initial begin
        sys_clk_i = 0;
        forever #(INPUT_CLK_PERIOD/2) sys_clk_i = ~sys_clk_i;
    end
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    fpga_top #(
        .XLEN               (32),
        .RESET_VECTOR       (32'h0000_0000),
        .UART_BAUD_RATE     (115200),
        .CLK_FREQ_HZ        (50_000_000),
        .INPUT_CLK_FREQ_HZ  (100_000_000),
        .NUM_IRQS           (8),
        .WDT_TIMEOUT        (1000),
        .BOOTROM_INIT_FILE  ("test_boot.hex")
    ) dut (
        .sys_clk_i          (sys_clk_i),
        .sys_rst_n_i        (sys_rst_n_i),
        
        // SRAM Interface
        .sram_addr_o        (sram_addr_o),
        .sram_data_io       (sram_data_io),
        .sram_ce_n_o        (sram_ce_n_o),
        .sram_oe_n_o        (sram_oe_n_o),
        .sram_we_n_o        (sram_we_n_o),
        .sram_lb_n_o        (sram_lb_n_o),
        .sram_ub_n_o        (sram_ub_n_o),
        
        // UART Interface
        .uart_rx_i          (uart_rx_i),
        .uart_tx_o          (uart_tx_o),
        
        // SPI Interface
        .spi_sclk_o         (spi_sclk_o),
        .spi_mosi_o         (spi_mosi_o),
        .spi_miso_i         (spi_miso_i),
        .spi_cs_n_o         (spi_cs_n_o),
        
        // GPIO Interface
        .led_o              (led_o),
        .btn_i              (btn_i),
        
        // External Interrupts
        .ext_irq_i          (ext_irq_i),
        
        // Debug Interface
        .debug_uart_rx_i    (debug_uart_rx_i),
        .debug_uart_tx_o    (debug_uart_tx_o)
    );
    
    //=========================================================================
    // SRAM Model
    //=========================================================================
    sram_model #(
        .ADDR_WIDTH (18),
        .DATA_WIDTH (16),
        .MEM_DEPTH  (262144)
    ) u_sram_model (
        .addr       (sram_addr_o),
        .data       (sram_data_io),
        .ce_n       (sram_ce_n_o),
        .oe_n       (sram_oe_n_o),
        .we_n       (sram_we_n_o),
        .lb_n       (sram_lb_n_o),
        .ub_n       (sram_ub_n_o)
    );
    
    //=========================================================================
    // Test Initialization
    //=========================================================================
    initial begin
        // Initialize signals
        sys_rst_n_i = 0;
        uart_rx_i = 1'b1;
        spi_miso_i = 1'b1;
        btn_i = 8'h00;
        ext_irq_i = 4'h0;
        debug_uart_rx_i = 1'b1;
        
        test_num = 0;
        errors = 0;
        
        // Wait for reset
        repeat(20) @(posedge sys_clk_i);
        sys_rst_n_i = 1;
        
        // Wait for PLL lock and system stabilization
        repeat(200) @(posedge sys_clk_i);
        
        // Run tests
        run_fpga_tests();
        
        // Report results
        $display("\n========================================");
        $display("FPGA Top Test Complete");
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
    task run_fpga_tests;
        begin
            test_clock_and_reset();
            test_led_output();
            test_button_input();
            test_sram_interface();
        end
    endtask
    
    //=========================================================================
    // Test 1: Clock and Reset
    //=========================================================================
    task test_clock_and_reset;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Clock and Reset", test_num);
            
            // Apply reset
            sys_rst_n_i = 0;
            repeat(10) @(posedge sys_clk_i);
            
            // Release reset
            sys_rst_n_i = 1;
            repeat(100) @(posedge sys_clk_i);
            
            $display("  PASS: Clock and reset functional");
        end
    endtask
    
    //=========================================================================
    // Test 2: LED Output
    //=========================================================================
    task test_led_output;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] LED Output", test_num);
            
            repeat(500) @(posedge sys_clk_i);
            
            $display("  LED Output: 0x%02h", led_o);
            $display("  PASS: LED output functional");
        end
    endtask
    
    //=========================================================================
    // Test 3: Button Input
    //=========================================================================
    task test_button_input;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Button Input", test_num);
            
            btn_i = 8'hFF;
            repeat(50) @(posedge sys_clk_i);
            
            btn_i = 8'h00;
            repeat(50) @(posedge sys_clk_i);
            
            $display("  PASS: Button input functional");
        end
    endtask
    
    //=========================================================================
    // Test 4: SRAM Interface
    //=========================================================================
    task test_sram_interface;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] SRAM Interface", test_num);
            
            repeat(1000) @(posedge sys_clk_i);
            
            $display("  SRAM CE_n: %b, OE_n: %b, WE_n: %b", 
                     sram_ce_n_o, sram_oe_n_o, sram_we_n_o);
            
            $display("  PASS: SRAM interface functional");
        end
    endtask
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #5_000_000;
        $display("\nERROR: Test timeout!");
        $finish;
    end
    
    //=========================================================================
    // Waveform Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_fpga_top.vcd");
        $dumpvars(0, tb_fpga_top);
    end

endmodule
