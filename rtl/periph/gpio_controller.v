//=============================================================================
// Module: gpio_controller
// Description: Simple GPIO Controller with AXI4-Lite Interface
//              Provides basic input/output functionality for LEDs and buttons
//
// Register Map:
//   0x00 - GPIO_OUT:    [7:0] Output data register
//   0x04 - GPIO_IN:     [7:0] Input data register (read-only)
//   0x08 - GPIO_DIR:    [7:0] Direction register (1=output, 0=input)
//   0x0C - GPIO_IRQ_EN: [7:0] Interrupt enable (for input change)
//   0x10 - GPIO_IRQ_ST: [7:0] Interrupt status (write-1-clear)
//
// Requirements: 8.1
//=============================================================================

`timescale 1ns/1ps

module gpio_controller (
    input  wire        clk,
    input  wire        rst_n,
    
    //=========================================================================
    // AXI4-Lite Slave Interface
    //=========================================================================
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
    
    //=========================================================================
    // GPIO Interface
    //=========================================================================
    output wire [7:0]  gpio_out,
    input  wire [7:0]  gpio_in
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam ADDR_OUT    = 8'h00;
    localparam ADDR_IN     = 8'h04;
    localparam ADDR_DIR    = 8'h08;
    localparam ADDR_IRQ_EN = 8'h0C;
    localparam ADDR_IRQ_ST = 8'h10;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0] out_reg;
    reg [7:0] dir_reg;
    reg [7:0] irq_en_reg;
    reg [7:0] irq_st_reg;
    
    // Input synchronizer
    reg [7:0] gpio_in_sync1;
    reg [7:0] gpio_in_sync2;
    reg [7:0] gpio_in_prev;
    
    //=========================================================================
    // Output Assignment
    //=========================================================================
    assign gpio_out = out_reg;
    
    //=========================================================================
    // Input Synchronization
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_in_sync1 <= 8'h00;
            gpio_in_sync2 <= 8'h00;
            gpio_in_prev  <= 8'h00;
        end else begin
            gpio_in_sync1 <= gpio_in;
            gpio_in_sync2 <= gpio_in_sync1;
            gpio_in_prev  <= gpio_in_sync2;
        end
    end
    
    // Edge detection for interrupts
    wire [7:0] gpio_change = gpio_in_sync2 ^ gpio_in_prev;
    
    //=========================================================================
    // AXI Interface
    //=========================================================================
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
    
    //=========================================================================
    // Write State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_reg <= 1'b1;
            w_ready_reg  <= 1'b0;
            aw_addr_reg  <= 8'd0;
            aw_valid_reg <= 1'b0;
            axi_bvalid   <= 1'b0;
            out_reg      <= 8'h00;
            dir_reg      <= 8'h00;
            irq_en_reg   <= 8'h00;
            irq_st_reg   <= 8'h00;
        end else begin
            // Update interrupt status on input change
            irq_st_reg <= irq_st_reg | (gpio_change & irq_en_reg);
            
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
                    ADDR_OUT: begin
                        if (axi_wstrb[0]) out_reg <= axi_wdata[7:0];
                    end
                    
                    ADDR_DIR: begin
                        if (axi_wstrb[0]) dir_reg <= axi_wdata[7:0];
                    end
                    
                    ADDR_IRQ_EN: begin
                        if (axi_wstrb[0]) irq_en_reg <= axi_wdata[7:0];
                    end
                    
                    ADDR_IRQ_ST: begin
                        // Write-1-clear
                        if (axi_wstrb[0]) irq_st_reg <= irq_st_reg & ~axi_wdata[7:0];
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
    
    //=========================================================================
    // Read State Machine
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ar_ready_reg <= 1'b1;
            axi_rvalid   <= 1'b0;
            axi_rdata    <= 32'd0;
        end else begin
            // Address phase
            if (axi_arvalid && ar_ready_reg) begin
                ar_ready_reg <= 1'b0;
                axi_rvalid   <= 1'b1;
                
                case (axi_araddr)
                    ADDR_OUT:    axi_rdata <= {24'd0, out_reg};
                    ADDR_IN:     axi_rdata <= {24'd0, gpio_in_sync2};
                    ADDR_DIR:    axi_rdata <= {24'd0, dir_reg};
                    ADDR_IRQ_EN: axi_rdata <= {24'd0, irq_en_reg};
                    ADDR_IRQ_ST: axi_rdata <= {24'd0, irq_st_reg};
                    default:     axi_rdata <= 32'd0;
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
