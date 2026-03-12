`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// UART Controller with AXI4-Lite Interface
// 
// Features:
// - Complete register interface (DATA, STATUS, CTRL, BAUD)
// - Interrupt generation (RX_FULL, TX_EMPTY, RX_READY, errors)
// - FIFO status flags
// - Configurable baud rate
// - 8N1 with optional parity
//
// Register Map:
// 0x00 - DATA:   [7:0] TX/RX data (write=TX, read=RX)
// 0x04 - STATUS: [7:0] Status flags (read-only)
// 0x08 - CTRL:   [7:0] Control register
// 0x0C - BAUD:   [15:0] Baud rate divider
// 0x10 - TXCNT:  [4:0] TX FIFO count (read-only)
// 0x14 - RXCNT:  [4:0] RX FIFO count (read-only)
//
// 禁止事项:
// - 禁止硬编码波特率
// - 禁止缺少状态寄存器
// - 禁止忽略中断生成
//////////////////////////////////////////////////////////////////////////////

module uart_controller #(
    parameter CLK_FREQ   = 50_000_000,   // System clock frequency
    parameter BAUD_RATE  = 115200,       // Default baud rate
    parameter FIFO_DEPTH = 16            // FIFO depth
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
    
    // Interrupts
    output wire        irq_rx,           // RX data available interrupt
    output wire        irq_tx,           // TX FIFO empty interrupt
    
    // UART Physical Interface
    input  wire        uart_rxd,
    output wire        uart_txd
);

    //==========================================================================
    // Register Addresses
    //==========================================================================
    localparam ADDR_DATA   = 8'h00;
    localparam ADDR_STATUS = 8'h04;
    localparam ADDR_CTRL   = 8'h08;
    localparam ADDR_BAUD   = 8'h0C;
    localparam ADDR_TXCNT  = 8'h10;
    localparam ADDR_RXCNT  = 8'h14;
    
    //==========================================================================
    // Status Register Bits
    //==========================================================================
    localparam STATUS_TX_EMPTY    = 0;   // TX FIFO empty
    localparam STATUS_TX_FULL     = 1;   // TX FIFO full
    localparam STATUS_RX_EMPTY    = 2;   // RX FIFO empty
    localparam STATUS_RX_FULL     = 3;   // RX FIFO full
    localparam STATUS_TX_BUSY     = 4;   // TX in progress
    localparam STATUS_RX_BUSY     = 5;   // RX in progress
    localparam STATUS_FRAME_ERR   = 6;   // Frame error (latched)
    localparam STATUS_PARITY_ERR  = 7;   // Parity error (latched)
    
    //==========================================================================
    // Control Register Bits
    //==========================================================================
    localparam CTRL_TX_EN         = 0;   // TX enable
    localparam CTRL_RX_EN         = 1;   // RX enable
    localparam CTRL_PARITY_EN     = 2;   // Parity enable
    localparam CTRL_PARITY_ODD    = 3;   // Odd parity (0=even)
    localparam CTRL_IRQ_TX_EN     = 4;   // TX empty interrupt enable
    localparam CTRL_IRQ_RX_EN     = 5;   // RX ready interrupt enable
    localparam CTRL_ERR_CLR       = 6;   // Clear error flags (write 1)
    localparam CTRL_FIFO_RST      = 7;   // Reset FIFOs (write 1)
    
    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [7:0]  ctrl_reg;
    reg [15:0] baud_reg;
    reg        frame_err_latch;
    reg        parity_err_latch;
    reg        overrun_err_latch;
    
    // Calculate default baud divider
    // For TX: divider = CLK_FREQ / BAUD_RATE - 1
    // For RX (16x oversampling): divider = CLK_FREQ / (BAUD_RATE * 16) - 1
    localparam DEFAULT_BAUD_DIV = (CLK_FREQ / BAUD_RATE) - 1;
    
    //==========================================================================
    // TX Module Signals
    //==========================================================================
    wire [15:0] tx_baud_div;
    wire        tx_parity_en;
    wire        tx_parity_odd;
    wire [7:0]  tx_data;
    wire        tx_valid;
    wire        tx_ready;
    wire        tx_busy;
    wire        tx_fifo_empty;
    wire        tx_fifo_full;
    wire [4:0]  tx_fifo_count;
    
    //==========================================================================
    // RX Module Signals
    //==========================================================================
    wire [15:0] rx_baud_div;
    wire        rx_parity_en;
    wire        rx_parity_odd;
    wire [7:0]  rx_data;
    wire        rx_valid;
    wire        rx_ready;
    wire        rx_busy;
    wire        rx_fifo_empty;
    wire        rx_fifo_full;
    wire [4:0]  rx_fifo_count;
    wire        frame_error;
    wire        parity_error;
    wire        overrun_error;
    
    //==========================================================================
    // AXI Interface Logic
    //==========================================================================
    
    // Write channel
    reg        aw_ready_reg;
    reg        w_ready_reg;
    reg [7:0]  aw_addr_reg;
    reg        aw_valid_reg;
    
    assign axi_awready = aw_ready_reg;
    assign axi_wready  = w_ready_reg;
    assign axi_bresp   = 2'b00;  // OKAY
    
    // Read channel
    reg        ar_ready_reg;
    reg [7:0]  ar_addr_reg;
    
    assign axi_arready = ar_ready_reg;
    assign axi_rresp   = 2'b00;  // OKAY
    
    // TX data write
    reg        tx_wr_pending;
    reg [7:0]  tx_wr_data;
    
    assign tx_data  = tx_wr_data;
    assign tx_valid = tx_wr_pending && tx_ready;
    
    // RX data read
    reg        rx_rd_pending;
    assign rx_ready = rx_rd_pending && rx_valid;
    
    //==========================================================================
    // Write State Machine
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_reg  <= 1'b1;
            w_ready_reg   <= 1'b0;
            aw_addr_reg   <= 8'd0;
            aw_valid_reg  <= 1'b0;
            axi_bvalid    <= 1'b0;
            tx_wr_pending <= 1'b0;
            tx_wr_data    <= 8'd0;
            ctrl_reg      <= 8'h03;  // TX_EN and RX_EN by default
            baud_reg      <= DEFAULT_BAUD_DIV[15:0];
        end else begin
            // Clear pending write after accepted
            if (tx_wr_pending && tx_ready) begin
                tx_wr_pending <= 1'b0;
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
                
                // Register writes
                case (aw_addr_reg)
                    ADDR_DATA: begin
                        if (axi_wstrb[0]) begin
                            tx_wr_data    <= axi_wdata[7:0];
                            tx_wr_pending <= 1'b1;
                        end
                    end
                    
                    ADDR_CTRL: begin
                        if (axi_wstrb[0]) begin
                            ctrl_reg <= axi_wdata[7:0];
                        end
                    end
                    
                    ADDR_BAUD: begin
                        if (axi_wstrb[0]) baud_reg[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) baud_reg[15:8] <= axi_wdata[15:8];
                    end
                    
                    default: ;
                endcase
            end
            
            // Response phase
            if (axi_bvalid && axi_bready) begin
                axi_bvalid   <= 1'b0;
                aw_ready_reg <= 1'b1;
            end
            
            // Clear error flags if requested
            if (ctrl_reg[CTRL_ERR_CLR]) begin
                ctrl_reg[CTRL_ERR_CLR] <= 1'b0;
            end
            
            // Clear FIFO reset after one cycle
            if (ctrl_reg[CTRL_FIFO_RST]) begin
                ctrl_reg[CTRL_FIFO_RST] <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Read State Machine
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_ready_reg  <= 1'b1;
            ar_addr_reg   <= 8'd0;
            axi_rvalid    <= 1'b0;
            axi_rdata     <= 32'd0;
            rx_rd_pending <= 1'b0;
        end else begin
            // Clear pending read after accepted
            if (rx_rd_pending && rx_valid) begin
                rx_rd_pending <= 1'b0;
            end
            
            // Address phase
            if (axi_arvalid && ar_ready_reg) begin
                ar_addr_reg  <= axi_araddr;
                ar_ready_reg <= 1'b0;
                axi_rvalid   <= 1'b1;
                
                // Register reads
                case (axi_araddr)
                    ADDR_DATA: begin
                        axi_rdata     <= {24'd0, rx_data};
                        rx_rd_pending <= 1'b1;
                    end
                    
                    ADDR_STATUS: begin
                        axi_rdata <= {24'd0,
                            parity_err_latch,           // [7]
                            frame_err_latch,            // [6]
                            rx_busy,                    // [5]
                            tx_busy,                    // [4]
                            rx_fifo_full,               // [3]
                            rx_fifo_empty,              // [2]
                            tx_fifo_full,               // [1]
                            tx_fifo_empty               // [0]
                        };
                    end
                    
                    ADDR_CTRL: begin
                        axi_rdata <= {24'd0, ctrl_reg};
                    end
                    
                    ADDR_BAUD: begin
                        axi_rdata <= {16'd0, baud_reg};
                    end
                    
                    ADDR_TXCNT: begin
                        axi_rdata <= {27'd0, tx_fifo_count};
                    end
                    
                    ADDR_RXCNT: begin
                        axi_rdata <= {27'd0, rx_fifo_count};
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
    
    //==========================================================================
    // Error Latching
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_err_latch   <= 1'b0;
            parity_err_latch  <= 1'b0;
            overrun_err_latch <= 1'b0;
        end else begin
            // Latch errors
            if (frame_error)   frame_err_latch   <= 1'b1;
            if (parity_error)  parity_err_latch  <= 1'b1;
            if (overrun_error) overrun_err_latch <= 1'b1;
            
            // Clear on write to CTRL with ERR_CLR bit
            if (ctrl_reg[CTRL_ERR_CLR]) begin
                frame_err_latch   <= 1'b0;
                parity_err_latch  <= 1'b0;
                overrun_err_latch <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Interrupt Generation
    //==========================================================================
    
    assign irq_tx = ctrl_reg[CTRL_IRQ_TX_EN] && tx_fifo_empty;
    assign irq_rx = ctrl_reg[CTRL_IRQ_RX_EN] && !rx_fifo_empty;
    
    //==========================================================================
    // Configuration Signals
    //==========================================================================
    
    assign tx_baud_div  = baud_reg;
    // RX needs 16x oversampling, so divide the baud divider by 16
    // baud_reg = CLK_FREQ / BAUD_RATE - 1
    // rx_baud_div = CLK_FREQ / (BAUD_RATE * 16) - 1 = (baud_reg + 1) / 16 - 1
    assign rx_baud_div  = ((baud_reg + 1) >> 4) - 1;
    assign tx_parity_en = ctrl_reg[CTRL_PARITY_EN];
    assign rx_parity_en = ctrl_reg[CTRL_PARITY_EN];
    assign tx_parity_odd = ctrl_reg[CTRL_PARITY_ODD];
    assign rx_parity_odd = ctrl_reg[CTRL_PARITY_ODD];
    
    //==========================================================================
    // FIFO Reset Logic
    //==========================================================================
    
    wire fifo_rst_n = rst_n && !ctrl_reg[CTRL_FIFO_RST];
    
    //==========================================================================
    // TX Module Instance
    //==========================================================================
    
    uart_tx #(
        .FIFO_DEPTH      (FIFO_DEPTH),
        .FIFO_ADDR_WIDTH (4)
    ) u_uart_tx (
        .clk         (clk),
        .rst_n       (fifo_rst_n),
        .baud_div    (tx_baud_div),
        .parity_en   (tx_parity_en),
        .parity_odd  (tx_parity_odd),
        .tx_data     (tx_data),
        .tx_valid    (tx_valid),
        .tx_ready    (tx_ready),
        .tx_busy     (tx_busy),
        .fifo_empty  (tx_fifo_empty),
        .fifo_full   (tx_fifo_full),
        .fifo_count  (tx_fifo_count),
        .uart_txd    (uart_txd)
    );
    
    //==========================================================================
    // RX Module Instance
    //==========================================================================
    
    uart_rx #(
        .FIFO_DEPTH      (FIFO_DEPTH),
        .FIFO_ADDR_WIDTH (4)
    ) u_uart_rx (
        .clk          (clk),
        .rst_n        (fifo_rst_n),
        .baud_div     (rx_baud_div),
        .parity_en    (rx_parity_en),
        .parity_odd   (rx_parity_odd),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .rx_ready     (rx_ready),
        .rx_busy      (rx_busy),
        .fifo_empty   (rx_fifo_empty),
        .fifo_full    (rx_fifo_full),
        .fifo_count   (rx_fifo_count),
        .frame_error  (frame_error),
        .parity_error (parity_error),
        .overrun_error(overrun_error),
        .uart_rxd     (uart_rxd)
    );

endmodule
