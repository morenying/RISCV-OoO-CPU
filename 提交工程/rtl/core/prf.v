//=================================================================
// Module: prf
// Description: Physical Register File
//              64 x 32-bit registers
//              4 read ports, 2 write ports
//              P0 is hardwired to zero
// Requirements: 3.2
//=================================================================

`timescale 1ns/1ps

module prf #(
    parameter NUM_PHYS_REGS = 64,
    parameter PHYS_REG_BITS = 6,
    parameter DATA_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Read port 0
    input  wire [PHYS_REG_BITS-1:0] rd_addr0_i,
    output wire [DATA_WIDTH-1:0]    rd_data0_o,
    
    // Read port 1
    input  wire [PHYS_REG_BITS-1:0] rd_addr1_i,
    output wire [DATA_WIDTH-1:0]    rd_data1_o,
    
    // Read port 2
    input  wire [PHYS_REG_BITS-1:0] rd_addr2_i,
    output wire [DATA_WIDTH-1:0]    rd_data2_o,
    
    // Read port 3
    input  wire [PHYS_REG_BITS-1:0] rd_addr3_i,
    output wire [DATA_WIDTH-1:0]    rd_data3_o,
    
    // Write port 0
    input  wire                     wr_en0_i,
    input  wire [PHYS_REG_BITS-1:0] wr_addr0_i,
    input  wire [DATA_WIDTH-1:0]    wr_data0_i,
    
    // Write port 1
    input  wire                     wr_en1_i,
    input  wire [PHYS_REG_BITS-1:0] wr_addr1_i,
    input  wire [DATA_WIDTH-1:0]    wr_data1_i
);

    //=========================================================
    // Register File Storage
    //=========================================================
    reg [DATA_WIDTH-1:0] regs [0:NUM_PHYS_REGS-1];
    
    integer i;
    
    //=========================================================
    // Read Logic (combinational with bypass)
    //=========================================================
    // Read port 0 with write bypass
    assign rd_data0_o = (rd_addr0_i == 6'd0) ? 32'd0 :
                        (wr_en0_i && wr_addr0_i == rd_addr0_i) ? wr_data0_i :
                        (wr_en1_i && wr_addr1_i == rd_addr0_i) ? wr_data1_i :
                        regs[rd_addr0_i];
    
    // Read port 1 with write bypass
    assign rd_data1_o = (rd_addr1_i == 6'd0) ? 32'd0 :
                        (wr_en0_i && wr_addr0_i == rd_addr1_i) ? wr_data0_i :
                        (wr_en1_i && wr_addr1_i == rd_addr1_i) ? wr_data1_i :
                        regs[rd_addr1_i];
    
    // Read port 2 with write bypass
    assign rd_data2_o = (rd_addr2_i == 6'd0) ? 32'd0 :
                        (wr_en0_i && wr_addr0_i == rd_addr2_i) ? wr_data0_i :
                        (wr_en1_i && wr_addr1_i == rd_addr2_i) ? wr_data1_i :
                        regs[rd_addr2_i];
    
    // Read port 3 with write bypass
    assign rd_data3_o = (rd_addr3_i == 6'd0) ? 32'd0 :
                        (wr_en0_i && wr_addr0_i == rd_addr3_i) ? wr_data0_i :
                        (wr_en1_i && wr_addr1_i == rd_addr3_i) ? wr_data1_i :
                        regs[rd_addr3_i];
    
    //=========================================================
    // Write Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all registers to zero
            for (i = 0; i < NUM_PHYS_REGS; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else begin
            // Write port 0 (P0 is read-only zero)
            if (wr_en0_i && wr_addr0_i != 6'd0) begin
                regs[wr_addr0_i] <= wr_data0_i;
            end
            
            // Write port 1 (P0 is read-only zero)
            if (wr_en1_i && wr_addr1_i != 6'd0) begin
                regs[wr_addr1_i] <= wr_data1_i;
            end
        end
    end

endmodule
