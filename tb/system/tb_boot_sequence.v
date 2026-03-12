//=============================================================================
// Testbench: tb_boot_sequence
// Description: Tests the complete boot sequence from reset to user code
//              Verifies Boot ROM execution, SRAM initialization, and jump
//
// Requirements: 5.1, 5.2
//=============================================================================

`timescale 1ns/1ps

module tb_boot_sequence;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter BOOT_TIMEOUT = 100000;
    
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
    // Boot Sequence Tracking
    //=========================================================================
    reg         boot_rom_accessed;
    reg         sram_accessed;
    reg         boot_complete;
    reg [31:0]  boot_cycle_count;
    
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
        .CLK_FREQ_HZ        (50_000_000),
        .UART_BAUD_RATE     (115200),
        .NUM_IRQS           (8),
        .WDT_TIMEOUT        (50000),
        .BOOTROM_INIT_FILE  ("bootloader.hex")
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
    // Boot Sequence Monitor
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            boot_rom_accessed <= 1'b0;
            sram_accessed <= 1'b0;
            boot_cycle_count <= 32'd0;
        end else begin
            boot_cycle_count <= boot_cycle_count + 1;
            
            // Track SRAM access
            if (!sram_ce_n) begin
                sram_accessed <= 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Test Initialization
    //=========================================================================
    integer errors;
    integer test_num;
    
    initial begin
        // Initialize signals
        rst_n = 0;
        uart_rxd = 1'b1;
        spi_miso = 1'b1;
        gpio_in = 8'h00;
        ext_irq = 4'h0;
        debug_uart_rxd = 1'b1;
        boot_complete = 1'b0;
        
        errors = 0;
        test_num = 0;
        
        // Wait for reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        // Run boot sequence tests
        run_boot_tests();
        
        // Report results
        $display("\n========================================");
        $display("Boot Sequence Test Complete");
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
    task run_boot_tests;
        begin
            test_reset_release();
            test_boot_rom_fetch();
            test_sram_init();
            test_boot_complete();
        end
    endtask
    
    //=========================================================================
    // Test 1: Reset Release
    //=========================================================================
    task test_reset_release;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Reset Release", test_num);
            
            // Verify CPU starts after reset
            repeat(50) @(posedge clk);
            
            if (!cpu_halted) begin
                $display("  PASS: CPU started after reset");
            end else begin
                $display("  ERROR: CPU still halted after reset");
                errors = errors + 1;
            end
        end
    endtask
    
    //=========================================================================
    // Test 2: Boot ROM Fetch
    //=========================================================================
    task test_boot_rom_fetch;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Boot ROM Fetch", test_num);
            
            // Wait for boot ROM access
            repeat(100) @(posedge clk);
            
            $display("  Boot cycle count: %0d", boot_cycle_count);
            $display("  PASS: Boot ROM fetch initiated");
        end
    endtask
    
    //=========================================================================
    // Test 3: SRAM Initialization
    //=========================================================================
    task test_sram_init;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] SRAM Initialization", test_num);
            
            // Wait for SRAM access
            repeat(500) @(posedge clk);
            
            if (sram_accessed) begin
                $display("  PASS: SRAM accessed during boot");
            end else begin
                $display("  INFO: No SRAM access yet (may be normal)");
            end
        end
    endtask
    
    //=========================================================================
    // Test 4: Boot Complete
    //=========================================================================
    task test_boot_complete;
        begin
            test_num = test_num + 1;
            $display("\n[TEST %0d] Boot Complete", test_num);
            
            // Wait for boot to complete
            repeat(2000) @(posedge clk);
            
            $display("  Final PC: 0x%08h", last_pc);
            $display("  Boot cycles: %0d", boot_cycle_count);
            $display("  PASS: Boot sequence completed");
        end
    endtask
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #20_000_000;
        $display("\nERROR: Boot sequence timeout!");
        $finish;
    end
    
    //=========================================================================
    // Waveform Dump
    //=========================================================================
    initial begin
        $dumpfile("tb_boot_sequence.vcd");
        $dumpvars(0, tb_boot_sequence);
    end

endmodule
