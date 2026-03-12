//=================================================================
// Module: bram_imem
// Description: BRAM-based Instruction Memory with AXI-like interface
//              Single-port read-only memory for FPGA
//=================================================================

`timescale 1ns/1ps

module bram_imem #(
    parameter ADDR_WIDTH = 14,      // 16KB addressable
    parameter DATA_WIDTH = 32
) (
    input  wire                     clk,
    
    // AXI-like Read Interface
    input  wire [ADDR_WIDTH-1:0]    axi_araddr,
    input  wire                     axi_arvalid,
    output reg                      axi_arready,
    output reg  [DATA_WIDTH-1:0]    axi_rdata,
    output reg                      axi_rvalid,
    input  wire                     axi_rready,
    output wire [1:0]               axi_rresp,
    output wire                     axi_rlast
);

    //=========================================================
    // Memory Array
    //=========================================================
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    
    // Initialize memory (for simulation and FPGA)
    initial begin
        $readmemh("program.hex", mem);
    end

    //=========================================================
    // Read State Machine
    //=========================================================
    localparam IDLE = 1'b0;
    localparam READ = 1'b1;
    
    reg state;
    reg [ADDR_WIDTH-1:0] addr_reg;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                axi_arready <= 1'b1;
                axi_rvalid <= 1'b0;
                
                if (axi_arvalid && axi_arready) begin
                    addr_reg <= axi_araddr;
                    axi_arready <= 1'b0;
                    state <= READ;
                end
            end
            
            READ: begin
                axi_rdata <= mem[addr_reg];
                axi_rvalid <= 1'b1;
                
                if (axi_rvalid && axi_rready) begin
                    axi_rvalid <= 1'b0;
                    axi_arready <= 1'b1;
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end

    // Fixed responses
    assign axi_rresp = 2'b00;  // OKAY
    assign axi_rlast = 1'b1;   // Single beat

endmodule
