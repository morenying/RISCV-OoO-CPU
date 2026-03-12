`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// SPI Master Controller
//
// Features:
// - SPI Mode 0 (CPOL=0, CPHA=0)
// - Configurable clock divider for various baud rates
// - 8-bit data transfers
// - TX/RX FIFOs (16 bytes each)
// - Support for standard SPI Flash commands
// - AXI4-Lite register interface
//
// Register Map:
// 0x00 - SPI_DATA:    [7:0] TX/RX data register
// 0x04 - SPI_STATUS:  [7:0] Status register
// 0x08 - SPI_CTRL:    [7:0] Control register
// 0x0C - SPI_CLKDIV:  [15:0] Clock divider
// 0x10 - SPI_CS:      [0] Chip select control (active low)
//
// Status Register Bits:
// [0] - TX_EMPTY: TX FIFO empty
// [1] - TX_FULL:  TX FIFO full
// [2] - RX_EMPTY: RX FIFO empty
// [3] - RX_FULL:  RX FIFO full
// [4] - BUSY:     Transfer in progress
//
// Control Register Bits:
// [0] - ENABLE:   SPI enable
// [1] - CPOL:     Clock polarity (0 for Mode 0)
// [2] - CPHA:     Clock phase (0 for Mode 0)
//
// 禁止事项:
// - 禁止硬编码时钟分频
// - 禁止忽略 SPI 时序要求
// - 禁止简化为单字节传输
//////////////////////////////////////////////////////////////////////////////

module spi_master #(
    parameter FIFO_DEPTH = 16,
    parameter DEFAULT_CLKDIV = 16'd50  // 50MHz / 50 = 1MHz SPI clock
)(
    input  wire        clk,
    input  wire        rst_n,
    
    // AXI4-Lite Slave Interface
    input  wire        axi_awvalid,
    output wire        axi_awready,
    input  wire [7:0]  axi_awaddr,
    
    input  wire        axi_wvalid,
    output wire        axi_wready,
    input  wire [31:0] axi_wdata,
    input  wire [3:0]  axi_wstrb,
    
    output reg         axi_bvalid,
    input  wire        axi_bready,
    output wire [1:0]  axi_bresp,
    
    input  wire        axi_arvalid,
    output wire        axi_arready,
    input  wire [7:0]  axi_araddr,
    
    output reg         axi_rvalid,
    input  wire        axi_rready,
    output reg  [31:0] axi_rdata,
    output wire [1:0]  axi_rresp,
    
    // SPI Physical Interface
    output reg         spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output reg         spi_cs_n,
    
    // Interrupt
    output wire        irq_tx_empty,
    output wire        irq_rx_full
);

    //==========================================================================
    // Register Addresses
    //==========================================================================
    localparam ADDR_DATA   = 8'h00;
    localparam ADDR_STATUS = 8'h04;
    localparam ADDR_CTRL   = 8'h08;
    localparam ADDR_CLKDIV = 8'h0C;
    localparam ADDR_CS     = 8'h10;
    
    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [7:0]  ctrl_reg;
    reg [15:0] clkdiv_reg;
    reg        cs_reg;
    
    //==========================================================================
    // TX FIFO
    //==========================================================================
    reg [7:0]  tx_fifo [0:FIFO_DEPTH-1];
    reg [3:0]  tx_wr_ptr;
    reg [3:0]  tx_rd_ptr;
    reg [4:0]  tx_count;
    
    wire tx_empty = (tx_count == 0);
    wire tx_full  = (tx_count == FIFO_DEPTH);
    
    //==========================================================================
    // RX FIFO
    //==========================================================================
    reg [7:0]  rx_fifo [0:FIFO_DEPTH-1];
    reg [3:0]  rx_wr_ptr;
    reg [3:0]  rx_rd_ptr;
    reg [4:0]  rx_count;
    
    wire rx_empty = (rx_count == 0);
    wire rx_full  = (rx_count == FIFO_DEPTH);
    
    //==========================================================================
    // SPI State Machine
    //==========================================================================
    localparam SPI_IDLE    = 3'd0;
    localparam SPI_LOAD    = 3'd1;
    localparam SPI_SHIFT   = 3'd2;
    localparam SPI_SAMPLE  = 3'd3;
    localparam SPI_STORE   = 3'd4;
    
    reg [2:0]  spi_state;
    reg [7:0]  shift_reg;
    reg [2:0]  bit_cnt;
    reg [15:0] clk_cnt;
    reg        spi_busy;
    
    //==========================================================================
    // Clock Divider
    //==========================================================================
    wire clk_tick = (clk_cnt == 0);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 16'd0;
        end else if (spi_state != SPI_IDLE) begin
            if (clk_cnt == 0) begin
                clk_cnt <= clkdiv_reg;
            end else begin
                clk_cnt <= clk_cnt - 1'b1;
            end
        end else begin
            clk_cnt <= clkdiv_reg;
        end
    end
    
    //==========================================================================
    // SPI Transfer State Machine
    //==========================================================================
    assign spi_mosi = shift_reg[7];  // MSB first
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_state <= SPI_IDLE;
            spi_sck   <= 1'b0;
            shift_reg <= 8'd0;
            bit_cnt   <= 3'd0;
            spi_busy  <= 1'b0;
        end else begin
            case (spi_state)
                SPI_IDLE: begin
                    spi_sck  <= 1'b0;
                    spi_busy <= 1'b0;
                    
                    // Start transfer if TX FIFO has data and SPI enabled
                    if (!tx_empty && ctrl_reg[0] && !cs_reg) begin
                        spi_state <= SPI_LOAD;
                        spi_busy  <= 1'b1;
                    end
                end
                
                SPI_LOAD: begin
                    // Load data from TX FIFO
                    shift_reg <= tx_fifo[tx_rd_ptr];
                    bit_cnt   <= 3'd7;
                    spi_state <= SPI_SHIFT;
                end
                
                SPI_SHIFT: begin
                    // Wait for clock tick, then raise SCK
                    if (clk_tick) begin
                        spi_sck   <= 1'b1;
                        spi_state <= SPI_SAMPLE;
                    end
                end
                
                SPI_SAMPLE: begin
                    // Wait for clock tick, sample MISO, lower SCK
                    if (clk_tick) begin
                        spi_sck <= 1'b0;
                        // Sample MISO on falling edge (Mode 0)
                        shift_reg <= {shift_reg[6:0], spi_miso};
                        
                        if (bit_cnt == 0) begin
                            spi_state <= SPI_STORE;
                        end else begin
                            bit_cnt   <= bit_cnt - 1'b1;
                            spi_state <= SPI_SHIFT;
                        end
                    end
                end
                
                SPI_STORE: begin
                    // Store received byte to RX FIFO
                    if (!rx_full) begin
                        rx_fifo[rx_wr_ptr] <= shift_reg;
                    end
                    spi_state <= SPI_IDLE;
                end
                
                default: begin
                    spi_state <= SPI_IDLE;
                end
            endcase
        end
    end
    
    //==========================================================================
    // TX FIFO Read Pointer Update
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd_ptr <= 4'd0;
        end else if (spi_state == SPI_LOAD) begin
            tx_rd_ptr <= tx_rd_ptr + 1'b1;
        end
    end
    
    //==========================================================================
    // RX FIFO Write Pointer Update
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wr_ptr <= 4'd0;
        end else if (spi_state == SPI_STORE && !rx_full) begin
            rx_wr_ptr <= rx_wr_ptr + 1'b1;
        end
    end
    
    //==========================================================================
    // Chip Select Control
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_cs_n <= 1'b1;  // Deselected
        end else begin
            spi_cs_n <= cs_reg;
        end
    end
    
    //==========================================================================
    // Status Register
    //==========================================================================
    wire [7:0] status_reg = {3'd0, spi_busy, rx_full, rx_empty, tx_full, tx_empty};
    
    //==========================================================================
    // Interrupts
    //==========================================================================
    assign irq_tx_empty = tx_empty && ctrl_reg[0];
    assign irq_rx_full  = rx_full && ctrl_reg[0];
    
    //==========================================================================
    // AXI Interface
    //==========================================================================
    assign axi_bresp = 2'b00;  // OKAY
    assign axi_rresp = 2'b00;  // OKAY
    
    // Write channel
    reg        aw_ready_reg;
    reg        w_ready_reg;
    reg [7:0]  aw_addr_reg;
    reg        aw_valid_reg;
    
    assign axi_awready = aw_ready_reg;
    assign axi_wready  = w_ready_reg;
    
    // Read channel
    reg        ar_ready_reg;
    
    assign axi_arready = ar_ready_reg;
    
    //==========================================================================
    // Write State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_reg <= 1'b1;
            w_ready_reg  <= 1'b0;
            aw_addr_reg  <= 8'd0;
            aw_valid_reg <= 1'b0;
            axi_bvalid   <= 1'b0;
            ctrl_reg     <= 8'h00;
            clkdiv_reg   <= DEFAULT_CLKDIV;
            cs_reg       <= 1'b1;  // Deselected
            tx_wr_ptr    <= 4'd0;
            tx_count     <= 5'd0;
        end else begin
            // TX FIFO count update
            if (spi_state == SPI_LOAD && tx_count > 0) begin
                tx_count <= tx_count - 1'b1;
            end
            
            // Address phase
            if (axi_awvalid && aw_ready_reg) begin
                aw_addr_reg  <= axi_awaddr;
                aw_valid_reg <= 1'b1;
                aw_ready_reg <= 1'b0;
                w_ready_reg  <= 1'b1;
            end
            
            // Data phase
            if (axi_wvalid && w_ready_reg && aw_valid_reg) begin
                w_ready_reg  <= 1'b0;
                aw_valid_reg <= 1'b0;
                axi_bvalid   <= 1'b1;
                
                case (aw_addr_reg)
                    ADDR_DATA: begin
                        // Write to TX FIFO
                        if (!tx_full && axi_wstrb[0]) begin
                            tx_fifo[tx_wr_ptr] <= axi_wdata[7:0];
                            tx_wr_ptr <= tx_wr_ptr + 1'b1;
                            tx_count  <= tx_count + 1'b1;
                        end
                    end
                    
                    ADDR_CTRL: begin
                        if (axi_wstrb[0]) begin
                            ctrl_reg <= axi_wdata[7:0];
                        end
                    end
                    
                    ADDR_CLKDIV: begin
                        if (axi_wstrb[0]) clkdiv_reg[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) clkdiv_reg[15:8] <= axi_wdata[15:8];
                    end
                    
                    ADDR_CS: begin
                        if (axi_wstrb[0]) begin
                            cs_reg <= axi_wdata[0];
                        end
                    end
                    
                    default: ;
                endcase
            end
            
            // Response phase
            if (axi_bvalid && axi_bready) begin
                axi_bvalid   <= 1'b0;
                aw_ready_reg <= 1'b1;
            end
        end
    end
    
    //==========================================================================
    // Read State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_ready_reg <= 1'b1;
            axi_rvalid   <= 1'b0;
            axi_rdata    <= 32'd0;
            rx_rd_ptr    <= 4'd0;
            rx_count     <= 5'd0;
        end else begin
            // RX FIFO count update
            if (spi_state == SPI_STORE && !rx_full) begin
                rx_count <= rx_count + 1'b1;
            end
            
            // Address phase
            if (axi_arvalid && ar_ready_reg) begin
                ar_ready_reg <= 1'b0;
                axi_rvalid   <= 1'b1;
                
                case (axi_araddr)
                    ADDR_DATA: begin
                        // Read from RX FIFO
                        if (!rx_empty) begin
                            axi_rdata <= {24'd0, rx_fifo[rx_rd_ptr]};
                            rx_rd_ptr <= rx_rd_ptr + 1'b1;
                            rx_count  <= rx_count - 1'b1;
                        end else begin
                            axi_rdata <= 32'd0;
                        end
                    end
                    
                    ADDR_STATUS: begin
                        axi_rdata <= {24'd0, status_reg};
                    end
                    
                    ADDR_CTRL: begin
                        axi_rdata <= {24'd0, ctrl_reg};
                    end
                    
                    ADDR_CLKDIV: begin
                        axi_rdata <= {16'd0, clkdiv_reg};
                    end
                    
                    ADDR_CS: begin
                        axi_rdata <= {31'd0, cs_reg};
                    end
                    
                    default: begin
                        axi_rdata <= 32'd0;
                    end
                endcase
            end
            
            // Data phase complete
            if (axi_rvalid && axi_rready) begin
                axi_rvalid   <= 1'b0;
                ar_ready_reg <= 1'b1;
            end
        end
    end

endmodule
