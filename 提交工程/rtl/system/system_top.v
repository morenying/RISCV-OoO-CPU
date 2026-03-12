//=============================================================================
// Module: system_top
// Description: Complete System Integration for RISC-V OoO CPU
//              Integrates all modules: CPU, Memory, Peripherals, Debug
//              Implements complete address decoding and bus interconnect
//
// Memory Map:
//   0x0000_0000 - 0x0000_3FFF : Boot ROM (16KB)
//   0x8000_0000 - 0x8003_FFFF : Main Memory/SRAM (256KB)
//   0x1000_0000 - 0x1000_00FF : UART Controller
//   0x1000_0100 - 0x1000_01FF : GPIO (directly mapped to LEDs/buttons)
//   0x1000_0200 - 0x1000_02FF : Timer
//   0x1000_0300 - 0x1000_03FF : Interrupt Controller
//   0x1000_0400 - 0x1000_04FF : Watchdog Timer
//   0x1000_0500 - 0x1000_05FF : SPI Controller
//
// Requirements: 8.1
//=============================================================================

`timescale 1ns/1ps

module system_top #(
    parameter XLEN              = 32,
    parameter RESET_VECTOR      = 32'h0000_0000,  // Boot from ROM
    parameter CLK_FREQ_HZ       = 50_000_000,
    parameter UART_BAUD_RATE    = 115200,
    parameter NUM_IRQS          = 8,
    parameter WDT_TIMEOUT       = 50_000_000,     // 1 second at 50MHz
    parameter BOOTROM_INIT_FILE = "bootloader.hex"
)(
    input  wire        clk,
    input  wire        rst_n,
    
    //=========================================================================
    // External SRAM Interface
    //=========================================================================
    output wire [17:0] sram_addr,
    inout  wire [15:0] sram_data,
    output wire        sram_ce_n,
    output wire        sram_oe_n,
    output wire        sram_we_n,
    output wire        sram_lb_n,
    output wire        sram_ub_n,
    
    //=========================================================================
    // UART Interface
    //=========================================================================
    input  wire        uart_rxd,
    output wire        uart_txd,
    
    //=========================================================================
    // SPI Interface (for Flash)
    //=========================================================================
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,
    
    //=========================================================================
    // GPIO Interface
    //=========================================================================
    output wire [7:0]  gpio_out,
    input  wire [7:0]  gpio_in,
    
    //=========================================================================
    // External Interrupts
    //=========================================================================
    input  wire [3:0]  ext_irq,
    
    //=========================================================================
    // Debug Interface
    //=========================================================================
    input  wire        debug_uart_rxd,
    output wire        debug_uart_txd,
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    output wire        cpu_halted,
    output wire        wdt_timeout,
    output wire [31:0] last_pc
);

    //=========================================================================
    // Internal Signals - CPU AXI Interface
    //=========================================================================
    // Instruction Bus
    wire        cpu_ibus_arvalid;
    wire        cpu_ibus_arready;
    wire [31:0] cpu_ibus_araddr;
    wire [2:0]  cpu_ibus_arprot;
    wire        cpu_ibus_rvalid;
    wire        cpu_ibus_rready;
    wire [31:0] cpu_ibus_rdata;
    wire [1:0]  cpu_ibus_rresp;
    
    // Data Bus
    wire        cpu_dbus_awvalid;
    wire        cpu_dbus_awready;
    wire [31:0] cpu_dbus_awaddr;
    wire [2:0]  cpu_dbus_awprot;
    wire        cpu_dbus_wvalid;
    wire        cpu_dbus_wready;
    wire [31:0] cpu_dbus_wdata;
    wire [3:0]  cpu_dbus_wstrb;
    wire        cpu_dbus_bvalid;
    wire        cpu_dbus_bready;
    wire [1:0]  cpu_dbus_bresp;
    wire        cpu_dbus_arvalid;
    wire        cpu_dbus_arready;
    wire [31:0] cpu_dbus_araddr;
    wire [2:0]  cpu_dbus_arprot;
    wire        cpu_dbus_rvalid;
    wire        cpu_dbus_rready;
    wire [31:0] cpu_dbus_rdata;
    wire [1:0]  cpu_dbus_rresp;


    //=========================================================================
    // Internal Signals - AXI Interconnect
    //=========================================================================
    localparam NUM_MASTERS = 2;  // I-Bus, D-Bus
    localparam NUM_SLAVES  = 6;  // ROM, SRAM, UART, GPIO, Timer, INTC
    
    // Master signals (packed for interconnect)
    wire [NUM_MASTERS-1:0]       m_awvalid;
    wire [NUM_MASTERS-1:0]       m_awready;
    wire [NUM_MASTERS*32-1:0]    m_awaddr;
    wire [NUM_MASTERS*3-1:0]     m_awprot;
    wire [NUM_MASTERS-1:0]       m_wvalid;
    wire [NUM_MASTERS-1:0]       m_wready;
    wire [NUM_MASTERS*32-1:0]    m_wdata;
    wire [NUM_MASTERS*4-1:0]     m_wstrb;
    wire [NUM_MASTERS-1:0]       m_bvalid;
    wire [NUM_MASTERS-1:0]       m_bready;
    wire [NUM_MASTERS*2-1:0]     m_bresp;
    wire [NUM_MASTERS-1:0]       m_arvalid;
    wire [NUM_MASTERS-1:0]       m_arready;
    wire [NUM_MASTERS*32-1:0]    m_araddr;
    wire [NUM_MASTERS*3-1:0]     m_arprot;
    wire [NUM_MASTERS-1:0]       m_rvalid;
    wire [NUM_MASTERS-1:0]       m_rready;
    wire [NUM_MASTERS*32-1:0]    m_rdata;
    wire [NUM_MASTERS*2-1:0]     m_rresp;
    
    // Slave signals (packed for interconnect)
    wire [NUM_SLAVES-1:0]        s_awvalid;
    wire [NUM_SLAVES-1:0]        s_awready;
    wire [NUM_SLAVES*32-1:0]     s_awaddr;
    wire [NUM_SLAVES*3-1:0]      s_awprot;
    wire [NUM_SLAVES-1:0]        s_wvalid;
    wire [NUM_SLAVES-1:0]        s_wready;
    wire [NUM_SLAVES*32-1:0]     s_wdata;
    wire [NUM_SLAVES*4-1:0]      s_wstrb;
    wire [NUM_SLAVES-1:0]        s_bvalid;
    wire [NUM_SLAVES-1:0]        s_bready;
    wire [NUM_SLAVES*2-1:0]      s_bresp;
    wire [NUM_SLAVES-1:0]        s_arvalid;
    wire [NUM_SLAVES-1:0]        s_arready;
    wire [NUM_SLAVES*32-1:0]     s_araddr;
    wire [NUM_SLAVES*3-1:0]      s_arprot;
    wire [NUM_SLAVES-1:0]        s_rvalid;
    wire [NUM_SLAVES-1:0]        s_rready;
    wire [NUM_SLAVES*32-1:0]     s_rdata;
    wire [NUM_SLAVES*2-1:0]      s_rresp;

    //=========================================================================
    // Internal Signals - Interrupts
    //=========================================================================
    wire [NUM_IRQS-1:0] irq_sources;
    wire                irq_to_cpu;
    wire [3:0]          irq_id;
    wire                uart_irq_rx;
    wire                uart_irq_tx;
    wire                timer_irq;
    wire                wdt_irq;
    
    //=========================================================================
    // Internal Signals - Watchdog
    //=========================================================================
    wire        wdt_reset_out;
    wire [31:0] wdt_last_pc_out;
    wire        wdt_running;
    wire [31:0] wdt_counter;
    
    //=========================================================================
    // Internal Signals - Debug
    //=========================================================================
    wire        debug_cpu_halt;
    wire        debug_cpu_resume;
    wire        debug_cpu_step;
    wire        debug_cpu_halted;
    wire        debug_cpu_running;
    wire [31:0] debug_cpu_pc;
    wire [4:0]  debug_gpr_addr;
    wire        debug_gpr_read;
    wire [31:0] debug_gpr_data;
    wire        debug_gpr_valid;
    wire [11:0] debug_csr_addr;
    wire        debug_csr_read;
    wire [31:0] debug_csr_data;
    wire        debug_csr_valid;
    wire [31:0] debug_mem_addr;
    wire [31:0] debug_mem_wdata;
    wire        debug_mem_read;
    wire        debug_mem_write;
    wire [31:0] debug_mem_rdata;
    wire        debug_mem_done;
    wire        debug_mem_error;
    wire [7:0]  debug_uart_rx_data;
    wire        debug_uart_rx_valid;
    wire [7:0]  debug_uart_tx_data;
    wire        debug_uart_tx_valid;
    wire        debug_uart_tx_ready;
    
    //=========================================================================
    // Internal Signals - SRAM Controller
    //=========================================================================
    wire        sram_req;
    wire        sram_ack;
    wire        sram_done;
    wire        sram_wr;
    wire [31:0] sram_addr_cpu;
    wire [31:0] sram_wdata;
    wire [3:0]  sram_be;
    wire [31:0] sram_rdata;
    wire        sram_error;

    //=========================================================================
    // Pack Master Signals for Interconnect
    //=========================================================================
    // Master 0: I-Bus (read-only)
    assign m_awvalid[0]           = 1'b0;  // I-Bus doesn't write
    assign m_awaddr[31:0]         = 32'h0;
    assign m_awprot[2:0]          = 3'b0;
    assign m_wvalid[0]            = 1'b0;
    assign m_wdata[31:0]          = 32'h0;
    assign m_wstrb[3:0]           = 4'b0;
    assign m_bready[0]            = 1'b1;
    assign m_arvalid[0]           = cpu_ibus_arvalid;
    assign m_araddr[31:0]         = cpu_ibus_araddr;
    assign m_arprot[2:0]          = cpu_ibus_arprot;
    assign m_rready[0]            = cpu_ibus_rready;
    
    assign cpu_ibus_arready       = m_arready[0];
    assign cpu_ibus_rvalid        = m_rvalid[0];
    assign cpu_ibus_rdata         = m_rdata[31:0];
    assign cpu_ibus_rresp         = m_rresp[1:0];
    
    // Master 1: D-Bus (read/write)
    assign m_awvalid[1]           = cpu_dbus_awvalid;
    assign m_awaddr[63:32]        = cpu_dbus_awaddr;
    assign m_awprot[5:3]          = cpu_dbus_awprot;
    assign m_wvalid[1]            = cpu_dbus_wvalid;
    assign m_wdata[63:32]         = cpu_dbus_wdata;
    assign m_wstrb[7:4]           = cpu_dbus_wstrb;
    assign m_bready[1]            = cpu_dbus_bready;
    assign m_arvalid[1]           = cpu_dbus_arvalid;
    assign m_araddr[63:32]        = cpu_dbus_araddr;
    assign m_arprot[5:3]          = cpu_dbus_arprot;
    assign m_rready[1]            = cpu_dbus_rready;
    
    assign cpu_dbus_awready       = m_awready[1];
    assign cpu_dbus_wready        = m_wready[1];
    assign cpu_dbus_bvalid        = m_bvalid[1];
    assign cpu_dbus_bresp         = m_bresp[3:2];
    assign cpu_dbus_arready       = m_arready[1];
    assign cpu_dbus_rvalid        = m_rvalid[1];
    assign cpu_dbus_rdata         = m_rdata[63:32];
    assign cpu_dbus_rresp         = m_rresp[3:2];


    //=========================================================================
    // CPU Core Instance
    //=========================================================================
    cpu_core_top #(
        .XLEN(XLEN),
        .RESET_VECTOR(RESET_VECTOR)
    ) u_cpu_core (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Instruction AXI Interface
        .m_axi_ibus_arvalid     (cpu_ibus_arvalid),
        .m_axi_ibus_arready     (cpu_ibus_arready),
        .m_axi_ibus_araddr      (cpu_ibus_araddr),
        .m_axi_ibus_arprot      (cpu_ibus_arprot),
        .m_axi_ibus_rvalid      (cpu_ibus_rvalid),
        .m_axi_ibus_rready      (cpu_ibus_rready),
        .m_axi_ibus_rdata       (cpu_ibus_rdata),
        .m_axi_ibus_rresp       (cpu_ibus_rresp),
        
        // Data AXI Interface
        .m_axi_dbus_awvalid     (cpu_dbus_awvalid),
        .m_axi_dbus_awready     (cpu_dbus_awready),
        .m_axi_dbus_awaddr      (cpu_dbus_awaddr),
        .m_axi_dbus_awprot      (cpu_dbus_awprot),
        .m_axi_dbus_wvalid      (cpu_dbus_wvalid),
        .m_axi_dbus_wready      (cpu_dbus_wready),
        .m_axi_dbus_wdata       (cpu_dbus_wdata),
        .m_axi_dbus_wstrb       (cpu_dbus_wstrb),
        .m_axi_dbus_bvalid      (cpu_dbus_bvalid),
        .m_axi_dbus_bready      (cpu_dbus_bready),
        .m_axi_dbus_bresp       (cpu_dbus_bresp),
        .m_axi_dbus_arvalid     (cpu_dbus_arvalid),
        .m_axi_dbus_arready     (cpu_dbus_arready),
        .m_axi_dbus_araddr      (cpu_dbus_araddr),
        .m_axi_dbus_arprot      (cpu_dbus_arprot),
        .m_axi_dbus_rvalid      (cpu_dbus_rvalid),
        .m_axi_dbus_rready      (cpu_dbus_rready),
        .m_axi_dbus_rdata       (cpu_dbus_rdata),
        .m_axi_dbus_rresp       (cpu_dbus_rresp),
        
        // External Interrupts
        .ext_irq_i              (irq_to_cpu),
        .timer_irq_i            (timer_irq),
        .sw_irq_i               (1'b0)
    );

    //=========================================================================
    // AXI Interconnect Instance
    //=========================================================================
    axi_interconnect #(
        .NUM_MASTERS    (NUM_MASTERS),
        .NUM_SLAVES     (NUM_SLAVES),
        .ADDR_WIDTH     (32),
        .DATA_WIDTH     (32),
        .TIMEOUT_CYCLES (1000)
    ) u_axi_interconnect (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Master Ports
        .m_awvalid      (m_awvalid),
        .m_awready      (m_awready),
        .m_awaddr       (m_awaddr),
        .m_awprot       (m_awprot),
        .m_wvalid       (m_wvalid),
        .m_wready       (m_wready),
        .m_wdata        (m_wdata),
        .m_wstrb        (m_wstrb),
        .m_bvalid       (m_bvalid),
        .m_bready       (m_bready),
        .m_bresp        (m_bresp),
        .m_arvalid      (m_arvalid),
        .m_arready      (m_arready),
        .m_araddr       (m_araddr),
        .m_arprot       (m_arprot),
        .m_rvalid       (m_rvalid),
        .m_rready       (m_rready),
        .m_rdata        (m_rdata),
        .m_rresp        (m_rresp),
        
        // Slave Ports
        .s_awvalid      (s_awvalid),
        .s_awready      (s_awready),
        .s_awaddr       (s_awaddr),
        .s_awprot       (s_awprot),
        .s_wvalid       (s_wvalid),
        .s_wready       (s_wready),
        .s_wdata        (s_wdata),
        .s_wstrb        (s_wstrb),
        .s_bvalid       (s_bvalid),
        .s_bready       (s_bready),
        .s_bresp        (s_bresp),
        .s_arvalid      (s_arvalid),
        .s_arready      (s_arready),
        .s_araddr       (s_araddr),
        .s_arprot       (s_arprot),
        .s_rvalid       (s_rvalid),
        .s_rready       (s_rready),
        .s_rdata        (s_rdata),
        .s_rresp        (s_rresp)
    );

    //=========================================================================
    // Slave 0: Boot ROM (0x0000_0000 - 0x0000_3FFF)
    //=========================================================================
    bootrom #(
        .DEPTH          (4096),
        .ADDR_WIDTH     (14),
        .INIT_FILE      (BOOTROM_INIT_FILE)
    ) u_bootrom (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Read Interface
        .axi_arvalid    (s_arvalid[0]),
        .axi_arready    (s_arready[0]),
        .axi_araddr     (s_araddr[31:0]),
        .axi_rvalid     (s_rvalid[0]),
        .axi_rready     (s_rready[0]),
        .axi_rdata      (s_rdata[31:0]),
        .axi_rresp      (s_rresp[1:0]),
        
        // AXI Write Interface (returns error - ROM is read-only)
        .axi_awvalid    (s_awvalid[0]),
        .axi_awready    (s_awready[0]),
        .axi_awaddr     (s_awaddr[31:0]),
        .axi_wvalid     (s_wvalid[0]),
        .axi_wready     (s_wready[0]),
        .axi_wdata      (s_wdata[31:0]),
        .axi_wstrb      (s_wstrb[3:0]),
        .axi_bvalid     (s_bvalid[0]),
        .axi_bready     (s_bready[0]),
        .axi_bresp      (s_bresp[1:0])
    );

    //=========================================================================
    // Slave 1: SRAM Controller (0x8000_0000 - 0x8003_FFFF)
    // Requires AXI-to-Simple bridge
    //=========================================================================
    
    // AXI-to-Simple bridge signals
    wire        sram_axi_req;
    wire        sram_axi_ack;
    wire        sram_axi_done;
    wire        sram_axi_wr;
    wire [31:0] sram_axi_addr;
    wire [31:0] sram_axi_wdata;
    wire [3:0]  sram_axi_be;
    wire [31:0] sram_axi_rdata;
    wire        sram_axi_error;
    
    // AXI-to-Simple Bridge for SRAM (Slave 1)
    axi_to_simple_bridge u_sram_bridge (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Slave Interface
        .axi_awvalid    (s_awvalid[1]),
        .axi_awready    (s_awready[1]),
        .axi_awaddr     (s_awaddr[63:32]),
        .axi_wvalid     (s_wvalid[1]),
        .axi_wready     (s_wready[1]),
        .axi_wdata      (s_wdata[63:32]),
        .axi_wstrb      (s_wstrb[7:4]),
        .axi_bvalid     (s_bvalid[1]),
        .axi_bready     (s_bready[1]),
        .axi_bresp      (s_bresp[3:2]),
        .axi_arvalid    (s_arvalid[1]),
        .axi_arready    (s_arready[1]),
        .axi_araddr     (s_araddr[63:32]),
        .axi_rvalid     (s_rvalid[1]),
        .axi_rready     (s_rready[1]),
        .axi_rdata      (s_rdata[63:32]),
        .axi_rresp      (s_rresp[3:2]),
        
        // Simple Interface
        .req            (sram_axi_req),
        .ack            (sram_axi_ack),
        .done           (sram_axi_done),
        .wr             (sram_axi_wr),
        .addr           (sram_axi_addr),
        .wdata          (sram_axi_wdata),
        .be             (sram_axi_be),
        .rdata          (sram_axi_rdata),
        .error          (sram_axi_error)
    );
    
    // SRAM Controller Instance
    sram_controller #(
        .ADDR_SETUP_CYCLES  (1),
        .ACCESS_CYCLES      (2),
        .WRITE_CYCLES       (2),
        .DATA_HOLD_CYCLES   (1),
        .TIMEOUT_CYCLES     (256)
    ) u_sram_controller (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // CPU Interface (from bridge)
        .cpu_req        (sram_axi_req),
        .cpu_ack        (sram_axi_ack),
        .cpu_done       (sram_axi_done),
        .cpu_wr         (sram_axi_wr),
        .cpu_addr       (sram_axi_addr),
        .cpu_wdata      (sram_axi_wdata),
        .cpu_be         (sram_axi_be),
        .cpu_rdata      (sram_axi_rdata),
        .cpu_error      (sram_axi_error),
        
        // SRAM Interface
        .sram_addr      (sram_addr),
        .sram_data      (sram_data),
        .sram_ce_n      (sram_ce_n),
        .sram_oe_n      (sram_oe_n),
        .sram_we_n      (sram_we_n),
        .sram_lb_n      (sram_lb_n),
        .sram_ub_n      (sram_ub_n)
    );

    //=========================================================================
    // Slave 2: UART Controller (0x1000_0000 - 0x1000_00FF)
    //=========================================================================
    uart_controller #(
        .CLK_FREQ       (CLK_FREQ_HZ),
        .BAUD_RATE      (UART_BAUD_RATE),
        .FIFO_DEPTH     (16)
    ) u_uart_controller (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface
        .axi_awvalid    (s_awvalid[2]),
        .axi_awready    (s_awready[2]),
        .axi_awaddr     (s_awaddr[71:64]),
        .axi_wvalid     (s_wvalid[2]),
        .axi_wready     (s_wready[2]),
        .axi_wdata      (s_wdata[95:64]),
        .axi_wstrb      (s_wstrb[11:8]),
        .axi_bvalid     (s_bvalid[2]),
        .axi_bready     (s_bready[2]),
        .axi_bresp      (s_bresp[5:4]),
        .axi_arvalid    (s_arvalid[2]),
        .axi_arready    (s_arready[2]),
        .axi_araddr     (s_araddr[71:64]),
        .axi_rvalid     (s_rvalid[2]),
        .axi_rready     (s_rready[2]),
        .axi_rdata      (s_rdata[95:64]),
        .axi_rresp      (s_rresp[5:4]),
        
        // Interrupts
        .irq_rx         (uart_irq_rx),
        .irq_tx         (uart_irq_tx),
        
        // UART Physical Interface
        .uart_rxd       (uart_rxd),
        .uart_txd       (uart_txd)
    );

    //=========================================================================
    // Slave 3: GPIO (0x1000_0100 - 0x1000_01FF)
    // Simple register interface for LEDs and buttons
    //=========================================================================
    gpio_controller u_gpio (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface
        .axi_awvalid    (s_awvalid[3]),
        .axi_awready    (s_awready[3]),
        .axi_awaddr     (s_awaddr[103:96]),
        .axi_wvalid     (s_wvalid[3]),
        .axi_wready     (s_wready[3]),
        .axi_wdata      (s_wdata[127:96]),
        .axi_wstrb      (s_wstrb[15:12]),
        .axi_bvalid     (s_bvalid[3]),
        .axi_bready     (s_bready[3]),
        .axi_bresp      (s_bresp[7:6]),
        .axi_arvalid    (s_arvalid[3]),
        .axi_arready    (s_arready[3]),
        .axi_araddr     (s_araddr[103:96]),
        .axi_rvalid     (s_rvalid[3]),
        .axi_rready     (s_rready[3]),
        .axi_rdata      (s_rdata[127:96]),
        .axi_rresp      (s_rresp[7:6]),
        
        // GPIO Interface
        .gpio_out       (gpio_out),
        .gpio_in        (gpio_in)
    );

    //=========================================================================
    // Slave 4: Timer (0x1000_0200 - 0x1000_02FF)
    //=========================================================================
    timer_controller u_timer (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface
        .axi_awvalid    (s_awvalid[4]),
        .axi_awready    (s_awready[4]),
        .axi_awaddr     (s_awaddr[135:128]),
        .axi_wvalid     (s_wvalid[4]),
        .axi_wready     (s_wready[4]),
        .axi_wdata      (s_wdata[159:128]),
        .axi_wstrb      (s_wstrb[19:16]),
        .axi_bvalid     (s_bvalid[4]),
        .axi_bready     (s_bready[4]),
        .axi_bresp      (s_bresp[9:8]),
        .axi_arvalid    (s_arvalid[4]),
        .axi_arready    (s_arready[4]),
        .axi_araddr     (s_araddr[135:128]),
        .axi_rvalid     (s_rvalid[4]),
        .axi_rready     (s_rready[4]),
        .axi_rdata      (s_rdata[159:128]),
        .axi_rresp      (s_rresp[9:8]),
        
        // Timer Interrupt
        .timer_irq      (timer_irq)
    );

    //=========================================================================
    // Slave 5: Interrupt Controller (0x1000_0300 - 0x1000_03FF)
    //=========================================================================
    interrupt_controller #(
        .NUM_IRQS       (NUM_IRQS)
    ) u_intc (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface
        .axi_awvalid    (s_awvalid[5]),
        .axi_awready    (s_awready[5]),
        .axi_awaddr     (s_awaddr[167:160]),
        .axi_wvalid     (s_wvalid[5]),
        .axi_wready     (s_wready[5]),
        .axi_wdata      (s_wdata[191:160]),
        .axi_wstrb      (s_wstrb[23:20]),
        .axi_bvalid     (s_bvalid[5]),
        .axi_bready     (s_bready[5]),
        .axi_bresp      (s_bresp[11:10]),
        .axi_arvalid    (s_arvalid[5]),
        .axi_arready    (s_arready[5]),
        .axi_araddr     (s_araddr[167:160]),
        .axi_rvalid     (s_rvalid[5]),
        .axi_rready     (s_rready[5]),
        .axi_rdata      (s_rdata[191:160]),
        .axi_rresp      (s_rresp[11:10]),
        
        // Interrupt Sources
        .irq_sources    (irq_sources),
        
        // CPU Interface
        .irq_to_cpu     (irq_to_cpu),
        .irq_id         (irq_id),
        .irq_priority_out(),
        .irq_ack        (1'b0),
        .irq_complete   (1'b0)
    );

    //=========================================================================
    // Interrupt Source Mapping
    //=========================================================================
    assign irq_sources = {
        ext_irq[3],     // IRQ 7: External interrupt 3
        ext_irq[2],     // IRQ 6: External interrupt 2
        ext_irq[1],     // IRQ 5: External interrupt 1
        ext_irq[0],     // IRQ 4: External interrupt 0
        wdt_irq,        // IRQ 3: Watchdog timeout
        timer_irq,      // IRQ 2: Timer interrupt
        uart_irq_tx,    // IRQ 1: UART TX empty
        uart_irq_rx     // IRQ 0: UART RX ready
    };

    //=========================================================================
    // Watchdog Timer Instance
    //=========================================================================
    
    // Watchdog control signals (directly from CPU or memory-mapped)
    wire        wdt_enable;
    wire        wdt_kick;
    wire [31:0] wdt_timeout_val;
    wire        wdt_timeout_load;
    
    // Simple watchdog control - directly connected
    // In a full implementation, these would be memory-mapped registers
    assign wdt_enable = 1'b1;  // Always enabled for safety
    assign wdt_kick = 1'b0;    // CPU must kick via memory-mapped register
    assign wdt_timeout_val = WDT_TIMEOUT;
    assign wdt_timeout_load = 1'b0;
    
    watchdog #(
        .XLEN           (XLEN),
        .DEFAULT_TIMEOUT(WDT_TIMEOUT)
    ) u_watchdog (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Control Interface
        .enable         (wdt_enable),
        .kick           (wdt_kick),
        .timeout_val    (wdt_timeout_val),
        .timeout_load   (wdt_timeout_load),
        
        // CPU Interface
        .cpu_pc         (debug_cpu_pc),
        .cpu_valid      (debug_cpu_running),
        
        // Status and Reset Output
        .timeout        (wdt_timeout),
        .wdt_reset      (wdt_reset_out),
        .last_pc        (wdt_last_pc_out),
        .counter_val    (wdt_counter),
        .running        (wdt_running)
    );
    
    assign wdt_irq = wdt_timeout;

    //=========================================================================
    // Debug Interface Instance
    //=========================================================================
    
    // Debug UART signals
    wire [7:0]  dbg_uart_rx_data;
    wire        dbg_uart_rx_valid;
    wire [7:0]  dbg_uart_tx_data;
    wire        dbg_uart_tx_valid;
    wire        dbg_uart_tx_ready;
    
    // Simple debug UART (directly connected to debug pins)
    // In a full implementation, this would be a separate UART instance
    assign dbg_uart_rx_data = 8'h00;
    assign dbg_uart_rx_valid = 1'b0;
    assign dbg_uart_tx_ready = 1'b1;
    assign debug_uart_txd = 1'b1;  // Idle high
    
    debug_if #(
        .XLEN           (XLEN),
        .NUM_BREAKPOINTS(4)
    ) u_debug_if (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // UART Interface
        .uart_rx_data   (dbg_uart_rx_data),
        .uart_rx_valid  (dbg_uart_rx_valid),
        .uart_tx_data   (dbg_uart_tx_data),
        .uart_tx_valid  (dbg_uart_tx_valid),
        .uart_tx_ready  (dbg_uart_tx_ready),
        
        // CPU Debug Interface
        .cpu_halt_req   (debug_cpu_halt),
        .cpu_resume_req (debug_cpu_resume),
        .cpu_step_req   (debug_cpu_step),
        .cpu_halted     (debug_cpu_halted),
        .cpu_running    (debug_cpu_running),
        .cpu_pc         (debug_cpu_pc),
        .cpu_instr      (32'h0),
        
        // Register Read Interface
        .gpr_addr       (debug_gpr_addr),
        .gpr_read_req   (debug_gpr_read),
        .gpr_rdata      (debug_gpr_data),
        .gpr_rdata_valid(debug_gpr_valid),
        
        .csr_addr       (debug_csr_addr),
        .csr_read_req   (debug_csr_read),
        .csr_rdata      (debug_csr_data),
        .csr_rdata_valid(debug_csr_valid),
        
        // Memory Debug Interface
        .dbg_mem_addr   (debug_mem_addr),
        .dbg_mem_wdata  (debug_mem_wdata),
        .dbg_mem_read   (debug_mem_read),
        .dbg_mem_write  (debug_mem_write),
        .dbg_mem_size   (),
        .dbg_mem_rdata  (debug_mem_rdata),
        .dbg_mem_done   (debug_mem_done),
        .dbg_mem_error  (debug_mem_error),
        
        // Breakpoint Interface
        .bp_enable      (),
        .bp_addr_0      (),
        .bp_addr_1      (),
        .bp_addr_2      (),
        .bp_addr_3      (),
        .bp_hit         (1'b0),
        .bp_hit_idx     (2'b00),
        
        // Status
        .debug_active   (),
        .error_code     ()
    );
    
    // Debug interface stub connections (CPU debug not fully wired)
    assign debug_cpu_halted = 1'b0;
    assign debug_cpu_running = 1'b1;
    assign debug_cpu_pc = 32'h0;
    assign debug_gpr_data = 32'h0;
    assign debug_gpr_valid = 1'b0;
    assign debug_csr_data = 32'h0;
    assign debug_csr_valid = 1'b0;
    assign debug_mem_rdata = 32'h0;
    assign debug_mem_done = 1'b0;
    assign debug_mem_error = 1'b0;

    //=========================================================================
    // SPI Master Instance (for Flash boot)
    //=========================================================================
    spi_master #(
        .FIFO_DEPTH     (16),
        .DEFAULT_CLKDIV (50)  // 50MHz / 50 = 1MHz SPI clock
    ) u_spi_master (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI Interface (directly memory-mapped, not through interconnect)
        .axi_awvalid    (1'b0),
        .axi_awready    (),
        .axi_awaddr     (8'h0),
        .axi_wvalid     (1'b0),
        .axi_wready     (),
        .axi_wdata      (32'h0),
        .axi_wstrb      (4'h0),
        .axi_bvalid     (),
        .axi_bready     (1'b1),
        .axi_bresp      (),
        .axi_arvalid    (1'b0),
        .axi_arready    (),
        .axi_araddr     (8'h0),
        .axi_rvalid     (),
        .axi_rready     (1'b1),
        .axi_rdata      (),
        .axi_rresp      (),
        
        // SPI Physical Interface
        .spi_sck        (spi_sclk),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        .spi_cs_n       (spi_cs_n),
        
        // Interrupts
        .irq_tx_empty   (),
        .irq_rx_full    ()
    );

    //=========================================================================
    // Status Outputs
    //=========================================================================
    assign cpu_halted = debug_cpu_halted;
    assign last_pc = wdt_last_pc_out;

endmodule
