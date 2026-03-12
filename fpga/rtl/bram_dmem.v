//=================================================================
// Module: bram_dmem
// Description: BRAM-based Data Memory with AXI-like interface
//              Dual-port read/write memory for FPGA
//=================================================================

`timescale 1ns/1ps

module bram_dmem #(
    parameter ADDR_WIDTH = 14,      // 16KB addressable
    parameter DATA_WIDTH = 32
) (
    input  wire                     clk,
    input  wire                     rst_n,
    
    // AXI-like Read Interface
    input  wire [ADDR_WIDTH-1:0]    axi_araddr,
    input  wire                     axi_arvalid,
    output reg                      axi_arready,
    output reg  [DATA_WIDTH-1:0]    axi_rdata,
    output reg                      axi_rvalid,
    input  wire                     axi_rready,
    output wire [1:0]               axi_rresp,
    output wire                     axi_rlast,
    
    // AXI-like Write Interface
    input  wire [ADDR_WIDTH-1:0]    axi_awaddr,
    input  wire                     axi_awvalid,
    output reg                      axi_awready,
    input  wire [DATA_WIDTH-1:0]    axi_wdata,
    input  wire [3:0]               axi_wstrb,
    input  wire                     axi_wvalid,
    output reg                      axi_wready,
    output reg                      axi_bvalid,
    input  wire                     axi_bready,
    output wire [1:0]               axi_bresp
);

    //=========================================================
    // Memory Array
    //=========================================================
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    
    // Initialize memory
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            mem[i] = 32'h0;
        end
    end

    //=========================================================
    // Read Channel State Machine
    //=========================================================
    localparam R_IDLE = 1'b0;
    localparam R_READ = 1'b1;
    
    reg r_state;
    reg [ADDR_WIDTH-1:0] r_addr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= R_IDLE;
            axi_arready <= 1'b1;
            axi_rvalid <= 1'b0;
            axi_rdata <= 32'h0;
            r_addr_reg <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (r_state)
                R_IDLE: begin
                    axi_arready <= 1'b1;
                    
                    if (axi_arvalid && axi_arready) begin
                        r_addr_reg <= axi_araddr;
                        axi_arready <= 1'b0;
                        r_state <= R_READ;
                    end
                end
                
                R_READ: begin
                    axi_rdata <= mem[r_addr_reg];
                    axi_rvalid <= 1'b1;
                    
                    if (axi_rvalid && axi_rready) begin
                        axi_rvalid <= 1'b0;
                        axi_arready <= 1'b1;
                        r_state <= R_IDLE;
                    end
                end
                
                default: r_state <= R_IDLE;
            endcase
        end
    end

    //=========================================================
    // Write Channel State Machine
    //=========================================================
    localparam W_IDLE  = 2'b00;
    localparam W_ADDR  = 2'b01;
    localparam W_DATA  = 2'b10;
    localparam W_RESP  = 2'b11;
    
    reg [1:0] w_state;
    reg [ADDR_WIDTH-1:0] w_addr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            axi_awready <= 1'b1;
            axi_wready <= 1'b0;
            axi_bvalid <= 1'b0;
            w_addr_reg <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (w_state)
                W_IDLE: begin
                    axi_awready <= 1'b1;
                    axi_wready <= 1'b1;
                    
                    if (axi_awvalid && axi_awready) begin
                        w_addr_reg <= axi_awaddr;
                        axi_awready <= 1'b0;
                        
                        if (axi_wvalid && axi_wready) begin
                            // Write data
                            if (axi_wstrb[0]) mem[axi_awaddr][7:0]   <= axi_wdata[7:0];
                            if (axi_wstrb[1]) mem[axi_awaddr][15:8]  <= axi_wdata[15:8];
                            if (axi_wstrb[2]) mem[axi_awaddr][23:16] <= axi_wdata[23:16];
                            if (axi_wstrb[3]) mem[axi_awaddr][31:24] <= axi_wdata[31:24];
                            axi_wready <= 1'b0;
                            w_state <= W_RESP;
                        end else begin
                            w_state <= W_DATA;
                        end
                    end else if (axi_wvalid && axi_wready) begin
                        w_state <= W_ADDR;
                    end
                end
                
                W_ADDR: begin
                    if (axi_awvalid && axi_awready) begin
                        // Write data with stored address
                        if (axi_wstrb[0]) mem[axi_awaddr][7:0]   <= axi_wdata[7:0];
                        if (axi_wstrb[1]) mem[axi_awaddr][15:8]  <= axi_wdata[15:8];
                        if (axi_wstrb[2]) mem[axi_awaddr][23:16] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) mem[axi_awaddr][31:24] <= axi_wdata[31:24];
                        axi_awready <= 1'b0;
                        axi_wready <= 1'b0;
                        w_state <= W_RESP;
                    end
                end
                
                W_DATA: begin
                    if (axi_wvalid && axi_wready) begin
                        // Write data with stored address
                        if (axi_wstrb[0]) mem[w_addr_reg][7:0]   <= axi_wdata[7:0];
                        if (axi_wstrb[1]) mem[w_addr_reg][15:8]  <= axi_wdata[15:8];
                        if (axi_wstrb[2]) mem[w_addr_reg][23:16] <= axi_wdata[23:16];
                        if (axi_wstrb[3]) mem[w_addr_reg][31:24] <= axi_wdata[31:24];
                        axi_wready <= 1'b0;
                        w_state <= W_RESP;
                    end
                end
                
                W_RESP: begin
                    axi_bvalid <= 1'b1;
                    
                    if (axi_bvalid && axi_bready) begin
                        axi_bvalid <= 1'b0;
                        axi_awready <= 1'b1;
                        axi_wready <= 1'b1;
                        w_state <= W_IDLE;
                    end
                end
                
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // Fixed responses
    assign axi_rresp = 2'b00;  // OKAY
    assign axi_rlast = 1'b1;   // Single beat
    assign axi_bresp = 2'b00;  // OKAY

endmodule
