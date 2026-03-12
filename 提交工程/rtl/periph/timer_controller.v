//=============================================================================
// Module: timer_controller
// Description: Simple Timer Controller with AXI4-Lite Interface
//              Provides basic timer/counter functionality
//
// Register Map:
//   0x00 - TIMER_CTRL:   [7:0] Control register
//   0x04 - TIMER_STATUS: [7:0] Status register
//   0x08 - TIMER_COUNT:  [31:0] Current counter value
//   0x0C - TIMER_CMP:    [31:0] Compare value (for interrupt)
//   0x10 - TIMER_PRESCALE: [15:0] Prescaler value
//
// Control Register Bits:
//   [0] - ENABLE: Timer enable
//   [1] - AUTO_RELOAD: Auto-reload on compare match
//   [2] - IRQ_EN: Interrupt enable
//   [3] - COUNT_DOWN: Count down mode (0=up, 1=down)
//
// Status Register Bits:
//   [0] - MATCH: Compare match occurred (write-1-clear)
//   [1] - OVERFLOW: Counter overflow occurred (write-1-clear)
//
// Requirements: 8.1
//=============================================================================

`timescale 1ns/1ps

module timer_controller (
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
    // Timer Interrupt
    //=========================================================================
    output wire        timer_irq
);

    //=========================================================================
    // Register Addresses
    //=========================================================================
    localparam ADDR_CTRL     = 8'h00;
    localparam ADDR_STATUS   = 8'h04;
    localparam ADDR_COUNT    = 8'h08;
    localparam ADDR_CMP      = 8'h0C;
    localparam ADDR_PRESCALE = 8'h10;
    
    //=========================================================================
    // Control Register Bits
    //=========================================================================
    localparam CTRL_ENABLE      = 0;
    localparam CTRL_AUTO_RELOAD = 1;
    localparam CTRL_IRQ_EN      = 2;
    localparam CTRL_COUNT_DOWN  = 3;
    
    //=========================================================================
    // Status Register Bits
    //=========================================================================
    localparam STATUS_MATCH    = 0;
    localparam STATUS_OVERFLOW = 1;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0]  ctrl_reg;
    reg [7:0]  status_reg;
    reg [31:0] count_reg;
    reg [31:0] cmp_reg;
    reg [15:0] prescale_reg;
    reg [15:0] prescale_cnt;
    
    //=========================================================================
    // Timer Logic
    //=========================================================================
    wire timer_enable = ctrl_reg[CTRL_ENABLE];
    wire auto_reload  = ctrl_reg[CTRL_AUTO_RELOAD];
    wire irq_enable   = ctrl_reg[CTRL_IRQ_EN];
    wire count_down   = ctrl_reg[CTRL_COUNT_DOWN];
    
    // Prescaler tick
    wire prescale_tick = (prescale_cnt == 0);
    
    // Compare match
    wire compare_match = (count_reg == cmp_reg);
    
    // Interrupt output
    assign timer_irq = irq_enable && status_reg[STATUS_MATCH];
    
    //=========================================================================
    // Prescaler Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale_cnt <= 16'd0;
        end else if (timer_enable) begin
            if (prescale_cnt == 0) begin
                prescale_cnt <= prescale_reg;
            end else begin
                prescale_cnt <= prescale_cnt - 1'b1;
            end
        end else begin
            prescale_cnt <= prescale_reg;
        end
    end
    
    //=========================================================================
    // Main Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_reg <= 32'd0;
        end else if (timer_enable && prescale_tick) begin
            if (compare_match && auto_reload) begin
                // Auto-reload on match
                count_reg <= 32'd0;
            end else if (count_down) begin
                // Count down
                if (count_reg == 0) begin
                    count_reg <= 32'hFFFFFFFF;
                end else begin
                    count_reg <= count_reg - 1'b1;
                end
            end else begin
                // Count up
                count_reg <= count_reg + 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Status Register Update
    //=========================================================================
    reg match_event;
    reg overflow_event;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            match_event    <= 1'b0;
            overflow_event <= 1'b0;
        end else begin
            match_event    <= 1'b0;
            overflow_event <= 1'b0;
            
            if (timer_enable && prescale_tick) begin
                if (compare_match) begin
                    match_event <= 1'b1;
                end
                if (!count_down && count_reg == 32'hFFFFFFFF) begin
                    overflow_event <= 1'b1;
                end
                if (count_down && count_reg == 0) begin
                    overflow_event <= 1'b1;
                end
            end
        end
    end
    
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
    reg [7:0] status_clear;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_ready_reg <= 1'b1;
            w_ready_reg  <= 1'b0;
            aw_addr_reg  <= 8'd0;
            aw_valid_reg <= 1'b0;
            axi_bvalid   <= 1'b0;
            ctrl_reg     <= 8'h00;
            status_reg   <= 8'h00;
            cmp_reg      <= 32'hFFFFFFFF;
            prescale_reg <= 16'd0;
            status_clear <= 8'h00;
        end else begin
            // Update status on events
            if (match_event)    status_reg[STATUS_MATCH]    <= 1'b1;
            if (overflow_event) status_reg[STATUS_OVERFLOW] <= 1'b1;
            
            // Clear status bits
            status_reg <= status_reg & ~status_clear;
            status_clear <= 8'h00;
            
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
                    ADDR_CTRL: begin
                        if (axi_wstrb[0]) ctrl_reg <= axi_wdata[7:0];
                    end
                    
                    ADDR_STATUS: begin
                        // Write-1-clear
                        if (axi_wstrb[0]) status_clear <= axi_wdata[7:0];
                    end
                    
                    ADDR_COUNT: begin
                        // Direct write to counter (for initialization)
                        if (axi_wstrb[0]) count_reg[7:0]   <= axi_wdata[7:0];
                        if (axi_wstrb[1]) count_reg[15:8]  <= axi_wdata[15:8];
                        if (axi_wstrb[2]) count_reg[23:16] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) count_reg[31:24] <= axi_wdata[31:24];
                    end
                    
                    ADDR_CMP: begin
                        if (axi_wstrb[0]) cmp_reg[7:0]   <= axi_wdata[7:0];
                        if (axi_wstrb[1]) cmp_reg[15:8]  <= axi_wdata[15:8];
                        if (axi_wstrb[2]) cmp_reg[23:16] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) cmp_reg[31:24] <= axi_wdata[31:24];
                    end
                    
                    ADDR_PRESCALE: begin
                        if (axi_wstrb[0]) prescale_reg[7:0]  <= axi_wdata[7:0];
                        if (axi_wstrb[1]) prescale_reg[15:8] <= axi_wdata[15:8];
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
                    ADDR_CTRL:     axi_rdata <= {24'd0, ctrl_reg};
                    ADDR_STATUS:   axi_rdata <= {24'd0, status_reg};
                    ADDR_COUNT:    axi_rdata <= count_reg;
                    ADDR_CMP:      axi_rdata <= cmp_reg;
                    ADDR_PRESCALE: axi_rdata <= {16'd0, prescale_reg};
                    default:       axi_rdata <= 32'd0;
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
