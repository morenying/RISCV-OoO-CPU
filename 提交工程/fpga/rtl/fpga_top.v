//=============================================================================
// Module: fpga_top
// Description: FPGA Top-level wrapper for RISC-V OoO CPU System
//              Includes clock management (MMCM/PLL), reset synchronization,
//              IOBUF for bidirectional signals, and peripheral interfaces
// Target: Xilinx Artix-7 (EGO1: xc7a35tcsg324-1)
//
// Requirements: 8.1, 9.1
//=============================================================================

`timescale 1ns/1ps

module fpga_top #(
    parameter XLEN              = 32,
    parameter RESET_VECTOR      = 32'h0000_0000,
    parameter UART_BAUD_RATE    = 115200,
    parameter CLK_FREQ_HZ       = 50_000_000,    // 50MHz system clock
    parameter INPUT_CLK_FREQ_HZ = 100_000_000,   // 100MHz input clock
    parameter NUM_IRQS          = 8,
    parameter WDT_TIMEOUT       = 50_000_000,    // 1 second at 50MHz
    parameter BOOTROM_INIT_FILE = "bootloader.hex"
)(
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire        sys_clk_i,      // External clock input (100MHz on EGO1)
    input  wire        sys_rst_n_i,    // External active-low reset (button)
    
    //=========================================================================
    // External SRAM Interface (directly to FPGA pins)
    //=========================================================================
    output wire [17:0] sram_addr_o,
    inout  wire [15:0] sram_data_io,
    output wire        sram_ce_n_o,
    output wire        sram_oe_n_o,
    output wire        sram_we_n_o,
    output wire        sram_lb_n_o,
    output wire        sram_ub_n_o,
    
    //=========================================================================
    // UART Interface
    //=========================================================================
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    
    //=========================================================================
    // SPI Interface (for Flash)
    //=========================================================================
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire        spi_cs_n_o,
    
    //=========================================================================
    // GPIO Interface (directly to LEDs and buttons)
    //=========================================================================
    output wire [7:0]  led_o,
    input  wire [7:0]  btn_i,
    
    //=========================================================================
    // External Interrupts (directly from buttons or external sources)
    //=========================================================================
    input  wire [3:0]  ext_irq_i,
    
    //=========================================================================
    // Debug UART Interface
    //=========================================================================
    input  wire        debug_uart_rx_i,
    output wire        debug_uart_tx_o
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    wire        clk_sys;           // System clock (50MHz)
    wire        rst_n_sys;         // Synchronized reset
    wire        pll_locked;
    
    // System status
    wire        cpu_halted;
    wire        wdt_timeout;
    wire [31:0] last_pc;

    //=========================================================================
    // Clock Management (MMCM)
    // Input: 100MHz, Output: 50MHz system clock
    //=========================================================================
    `ifdef SIMULATION
        // For simulation, use input clock directly
        assign clk_sys = sys_clk_i;
        assign pll_locked = 1'b1;
    `else
        // Xilinx MMCM instantiation for EGO1
        wire clk_fb;
        wire clk_50mhz;
        
        MMCME2_BASE #(
            .BANDWIDTH          ("OPTIMIZED"),
            .CLKFBOUT_MULT_F    (10.0),         // VCO = 100MHz * 10 = 1000MHz
            .CLKFBOUT_PHASE     (0.0),
            .CLKIN1_PERIOD      (10.0),         // 100MHz input = 10ns period
            .CLKOUT0_DIVIDE_F   (20.0),         // 1000MHz / 20 = 50MHz
            .CLKOUT0_DUTY_CYCLE (0.5),
            .CLKOUT0_PHASE      (0.0),
            .DIVCLK_DIVIDE      (1),
            .REF_JITTER1        (0.01),
            .STARTUP_WAIT       ("FALSE")
        ) u_mmcm (
            .CLKOUT0    (clk_50mhz),
            .CLKOUT0B   (),
            .CLKOUT1    (),
            .CLKOUT1B   (),
            .CLKOUT2    (),
            .CLKOUT2B   (),
            .CLKOUT3    (),
            .CLKOUT3B   (),
            .CLKOUT4    (),
            .CLKOUT5    (),
            .CLKOUT6    (),
            .CLKFBOUT   (clk_fb),
            .CLKFBOUTB  (),
            .LOCKED     (pll_locked),
            .CLKIN1     (sys_clk_i),
            .PWRDWN     (1'b0),
            .RST        (~sys_rst_n_i),
            .CLKFBIN    (clk_fb)
        );
        
        // Global clock buffer
        BUFG u_bufg_clk (
            .I  (clk_50mhz),
            .O  (clk_sys)
        );
    `endif

    //=========================================================================
    // Reset Synchronizer
    // Ensures clean reset release synchronized to system clock
    //=========================================================================
    reg [3:0] rst_sync_reg;
    
    always @(posedge clk_sys or negedge sys_rst_n_i) begin
        if (!sys_rst_n_i) begin
            rst_sync_reg <= 4'b0000;
        end else if (pll_locked) begin
            rst_sync_reg <= {rst_sync_reg[2:0], 1'b1};
        end else begin
            rst_sync_reg <= 4'b0000;
        end
    end
    
    assign rst_n_sys = rst_sync_reg[3];

    //=========================================================================
    // SRAM Bidirectional Data Bus
    // The system_top module handles tri-state internally via sram_controller
    // We just pass through the inout signal directly
    //=========================================================================
    // Note: For Xilinx FPGA, the synthesis tool will automatically infer
    // IOBUF primitives for inout ports. No explicit IOBUF needed here.

    //=========================================================================
    // Button Debouncing and Synchronization
    //=========================================================================
    reg [7:0] btn_sync1, btn_sync2;
    
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            btn_sync1 <= 8'h00;
            btn_sync2 <= 8'h00;
        end else begin
            btn_sync1 <= btn_i;
            btn_sync2 <= btn_sync1;
        end
    end
    
    // External interrupt synchronization
    reg [3:0] ext_irq_sync1, ext_irq_sync2;
    
    always @(posedge clk_sys or negedge rst_n_sys) begin
        if (!rst_n_sys) begin
            ext_irq_sync1 <= 4'h0;
            ext_irq_sync2 <= 4'h0;
        end else begin
            ext_irq_sync1 <= ext_irq_i;
            ext_irq_sync2 <= ext_irq_sync1;
        end
    end

    //=========================================================================
    // System Top Instance
    //=========================================================================
    
    // SRAM data bus is bidirectional in system_top
    // We need to connect it properly through the IOBUF
    wire [15:0] sram_data_to_system;
    
    system_top #(
        .XLEN               (XLEN),
        .RESET_VECTOR       (RESET_VECTOR),
        .CLK_FREQ_HZ        (CLK_FREQ_HZ),
        .UART_BAUD_RATE     (UART_BAUD_RATE),
        .NUM_IRQS           (NUM_IRQS),
        .WDT_TIMEOUT        (WDT_TIMEOUT),
        .BOOTROM_INIT_FILE  (BOOTROM_INIT_FILE)
    ) u_system_top (
        .clk                (clk_sys),
        .rst_n              (rst_n_sys),
        
        // External SRAM Interface
        .sram_addr          (sram_addr_o),
        .sram_data          (sram_data_io),  // Direct connection to IOBUF
        .sram_ce_n          (sram_ce_n_o),
        .sram_oe_n          (sram_oe_n_o),
        .sram_we_n          (sram_we_n_o),
        .sram_lb_n          (sram_lb_n_o),
        .sram_ub_n          (sram_ub_n_o),
        
        // UART Interface
        .uart_rxd           (uart_rx_i),
        .uart_txd           (uart_tx_o),
        
        // SPI Interface
        .spi_sclk           (spi_sclk_o),
        .spi_mosi           (spi_mosi_o),
        .spi_miso           (spi_miso_i),
        .spi_cs_n           (spi_cs_n_o),
        
        // GPIO Interface
        .gpio_out           (led_o),
        .gpio_in            (btn_sync2),
        
        // External Interrupts
        .ext_irq            (ext_irq_sync2),
        
        // Debug Interface
        .debug_uart_rxd     (debug_uart_rx_i),
        .debug_uart_txd     (debug_uart_tx_o),
        
        // Status Outputs
        .cpu_halted         (cpu_halted),
        .wdt_timeout        (wdt_timeout),
        .last_pc            (last_pc)
    );

endmodule
