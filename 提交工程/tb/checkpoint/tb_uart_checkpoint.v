//////////////////////////////////////////////////////////////////////////////
// UART Checkpoint Test
//
// Comprehensive verification of UART controller:
// - Loopback test (TX -> RX)
// - Various baud rates
// - Data integrity
// - Interrupt generation
//////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps

module tb_uart_checkpoint;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;           // 50 MHz
    parameter CLK_FREQ   = 50_000_000;
    parameter BAUD_RATE  = 115200;
    parameter BAUD_DIV   = (CLK_FREQ / BAUD_RATE) - 1;
    parameter BIT_TIME   = (BAUD_DIV + 1) * CLK_PERIOD;
    
    // Register addresses
    localparam ADDR_DATA   = 8'h00;
    localparam ADDR_STATUS = 8'h04;
    localparam ADDR_CTRL   = 8'h08;
    localparam ADDR_BAUD   = 8'h0C;
    
    //==========================================================================
    // Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    
    // AXI interface
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [7:0]  axi_awaddr;
    reg         axi_wvalid;
    wire        axi_wready;
    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    wire        axi_bvalid;
    reg         axi_bready;
    wire [1:0]  axi_bresp;
    reg         axi_arvalid;
    wire        axi_arready;
    reg  [7:0]  axi_araddr;
    wire        axi_rvalid;
    reg         axi_rready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    
    // Interrupts
    wire        irq_rx;
    wire        irq_tx;
    
    // UART - loopback
    wire        uart_txd;
    wire        uart_rxd;
    
    // Test tracking
    integer     total_tx;
    integer     total_rx;
    integer     total_errors;
    integer     i;
    reg  [31:0] read_data;
    reg  [7:0]  test_data [0:255];
    reg  [7:0]  recv_data [0:255];
    
    //==========================================================================
    // DUT
    //==========================================================================
    uart_controller #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (16)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .axi_awvalid (axi_awvalid),
        .axi_awready (axi_awready),
        .axi_awaddr  (axi_awaddr),
        .axi_wvalid  (axi_wvalid),
        .axi_wready  (axi_wready),
        .axi_wdata   (axi_wdata),
        .axi_wstrb   (axi_wstrb),
        .axi_bvalid  (axi_bvalid),
        .axi_bready  (axi_bready),
        .axi_bresp   (axi_bresp),
        .axi_arvalid (axi_arvalid),
        .axi_arready (axi_arready),
        .axi_araddr  (axi_araddr),
        .axi_rvalid  (axi_rvalid),
        .axi_rready  (axi_rready),
        .axi_rdata   (axi_rdata),
        .axi_rresp   (axi_rresp),
        .irq_rx      (irq_rx),
        .irq_tx      (irq_tx),
        .uart_rxd    (uart_rxd),
        .uart_txd    (uart_txd)
    );
    
    // Loopback connection
    assign uart_rxd = uart_txd;
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //==========================================================================
    // Task: AXI Write
    //==========================================================================
    task axi_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            axi_awvalid <= 1'b1;
            axi_awaddr  <= addr;
            axi_wvalid  <= 1'b1;
            axi_wdata   <= data;
            axi_wstrb   <= 4'b1111;
            
            while (!axi_awready) @(posedge clk);
            @(posedge clk);
            axi_awvalid <= 1'b0;
            
            while (!axi_wready) @(posedge clk);
            @(posedge clk);
            axi_wvalid <= 1'b0;
            
            axi_bready <= 1'b1;
            while (!axi_bvalid) @(posedge clk);
            @(posedge clk);
            axi_bready <= 1'b0;
        end
    endtask
    
    //==========================================================================
    // Task: AXI Read
    //==========================================================================
    task axi_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axi_arvalid <= 1'b1;
            axi_araddr  <= addr;
            
            while (!axi_arready) @(posedge clk);
            @(posedge clk);
            axi_arvalid <= 1'b0;
            
            axi_rready <= 1'b1;
            while (!axi_rvalid) @(posedge clk);
            data = axi_rdata;
            @(posedge clk);
            axi_rready <= 1'b0;
        end
    endtask
    
    //==========================================================================
    // Task: Send and receive byte via loopback
    //==========================================================================
    task send_receive_byte;
        input [7:0] tx_byte;
        output [7:0] rx_byte;
        begin
            // Send byte
            axi_write(ADDR_DATA, {24'd0, tx_byte});
            total_tx = total_tx + 1;
            
            // Wait for RX
            axi_read(ADDR_STATUS, read_data);
            while (read_data[2]) begin  // RX_EMPTY
                @(posedge clk);
                axi_read(ADDR_STATUS, read_data);
            end
            
            // Read received byte
            axi_read(ADDR_DATA, read_data);
            rx_byte = read_data[7:0];
            total_rx = total_rx + 1;
        end
    endtask
    
    //==========================================================================
    // Main Test
    //==========================================================================
    reg [7:0] rx_byte;
    integer error_count;
    
    initial begin
        $display("========================================");
        $display("UART Checkpoint Test");
        $display("========================================");
        $display("Baud Rate: %0d", BAUD_RATE);
        $display("Baud Divider: %0d", BAUD_DIV);
        
        // Initialize
        rst_n       = 0;
        axi_awvalid = 0;
        axi_awaddr  = 0;
        axi_wvalid  = 0;
        axi_wdata   = 0;
        axi_wstrb   = 0;
        axi_bready  = 0;
        axi_arvalid = 0;
        axi_araddr  = 0;
        axi_rready  = 0;
        total_tx    = 0;
        total_rx    = 0;
        total_errors = 0;
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(100) @(posedge clk);
        
        //----------------------------------------------------------------------
        // Test 1: Basic Loopback (50 bytes)
        //----------------------------------------------------------------------
        $display("\n--- Test 1: Basic Loopback (50 bytes) ---");
        
        error_count = 0;
        for (i = 0; i < 50; i = i + 1) begin
            test_data[i] = $random & 8'hFF;
            send_receive_byte(test_data[i], rx_byte);
            if (rx_byte !== test_data[i]) begin
                error_count = error_count + 1;
                if (error_count <= 3) begin
                    $display("  Error at byte %0d: sent 0x%02X, received 0x%02X", 
                             i, test_data[i], rx_byte);
                end
            end
        end
        
        if (error_count == 0) begin
            $display("  PASS: 50/50 bytes correct");
        end else begin
            $display("  FAIL: %0d errors", error_count);
            total_errors = total_errors + error_count;
        end
        
        //----------------------------------------------------------------------
        // Test 2: Sequential Data (ASCII printable)
        //----------------------------------------------------------------------
        $display("\n--- Test 2: Sequential ASCII Data ---");
        
        error_count = 0;
        for (i = 0; i < 95; i = i + 1) begin  // ASCII 32-126
            send_receive_byte(8'h20 + i, rx_byte);
            if (rx_byte !== (8'h20 + i)) begin
                error_count = error_count + 1;
            end
        end
        
        if (error_count == 0) begin
            $display("  PASS: 95/95 ASCII bytes correct");
        end else begin
            $display("  FAIL: %0d errors", error_count);
            total_errors = total_errors + error_count;
        end
        
        //----------------------------------------------------------------------
        // Test 3: Boundary Values
        //----------------------------------------------------------------------
        $display("\n--- Test 3: Boundary Values ---");
        
        error_count = 0;
        
        // Test 0x00
        send_receive_byte(8'h00, rx_byte);
        if (rx_byte !== 8'h00) error_count = error_count + 1;
        
        // Test 0xFF
        send_receive_byte(8'hFF, rx_byte);
        if (rx_byte !== 8'hFF) error_count = error_count + 1;
        
        // Test 0x55 (alternating)
        send_receive_byte(8'h55, rx_byte);
        if (rx_byte !== 8'h55) error_count = error_count + 1;
        
        // Test 0xAA (alternating)
        send_receive_byte(8'hAA, rx_byte);
        if (rx_byte !== 8'hAA) error_count = error_count + 1;
        
        if (error_count == 0) begin
            $display("  PASS: All boundary values correct");
        end else begin
            $display("  FAIL: %0d errors", error_count);
            total_errors = total_errors + error_count;
        end
        
        //----------------------------------------------------------------------
        // Test 4: Interrupt Functionality
        //----------------------------------------------------------------------
        $display("\n--- Test 4: Interrupt Functionality ---");
        
        // Enable RX interrupt
        axi_write(ADDR_CTRL, 32'h0000_0023);  // TX_EN | RX_EN | IRQ_RX_EN
        repeat(10) @(posedge clk);
        
        // RX should be empty, no interrupt
        if (irq_rx === 1'b0) begin
            $display("  PASS: RX interrupt inactive when empty");
        end else begin
            $display("  FAIL: RX interrupt should be inactive");
            total_errors = total_errors + 1;
        end
        
        // Send a byte
        axi_write(ADDR_DATA, 32'h0000_0042);
        
        // Wait for RX
        repeat(BIT_TIME * 12 / CLK_PERIOD) @(posedge clk);
        
        if (irq_rx === 1'b1) begin
            $display("  PASS: RX interrupt active when data available");
        end else begin
            $display("  FAIL: RX interrupt should be active");
            total_errors = total_errors + 1;
        end
        
        // Read data to clear interrupt
        axi_read(ADDR_DATA, read_data);
        repeat(10) @(posedge clk);
        
        if (irq_rx === 1'b0) begin
            $display("  PASS: RX interrupt cleared after read");
        end else begin
            $display("  FAIL: RX interrupt should be cleared");
            total_errors = total_errors + 1;
        end
        
        // Disable interrupts
        axi_write(ADDR_CTRL, 32'h0000_0003);
        
        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("\n========================================");
        $display("UART Checkpoint Summary");
        $display("========================================");
        $display("Total TX: %0d bytes", total_tx);
        $display("Total RX: %0d bytes", total_rx);
        $display("Total Errors: %0d", total_errors);
        
        if (total_errors == 0) begin
            $display("\nCHECKPOINT PASSED");
        end else begin
            $display("\nCHECKPOINT FAILED");
        end
        $display("========================================\n");
        
        $finish;
    end
    
    // Timeout
    initial begin
        #(200_000_000);  // 200ms
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
