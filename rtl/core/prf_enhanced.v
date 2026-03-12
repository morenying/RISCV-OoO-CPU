//=================================================================
// Module: prf_enhanced
// Description: Enhanced Physical Register File (PRF)
//              128 physical registers (doubled from 64)
//              8 read ports, 2 write ports
//              Register bypass network for zero-latency forwarding
// Requirements: 4.5, 4.6
//=================================================================

`timescale 1ns/1ps

module prf_enhanced #(
    parameter NUM_PHYS_REGS  = 128,
    parameter PHYS_REG_BITS  = 7,       // log2(128)
    parameter DATA_WIDTH     = 32,
    parameter NUM_READ_PORTS = 4,
    parameter NUM_WRITE_PORTS = 2
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Read Ports (8 ports for superscalar 4-way issue)
    //=========================================================
    // Port 0
    input  wire [PHYS_REG_BITS-1:0] rd0_addr_i,
    input  wire                     rd0_en_i,
    output wire [DATA_WIDTH-1:0]    rd0_data_o,
    output wire                     rd0_ready_o,
    
    // Port 1
    input  wire [PHYS_REG_BITS-1:0] rd1_addr_i,
    input  wire                     rd1_en_i,
    output wire [DATA_WIDTH-1:0]    rd1_data_o,
    output wire                     rd1_ready_o,
    
    // Port 2
    input  wire [PHYS_REG_BITS-1:0] rd2_addr_i,
    input  wire                     rd2_en_i,
    output wire [DATA_WIDTH-1:0]    rd2_data_o,
    output wire                     rd2_ready_o,
    
    // Port 3
    input  wire [PHYS_REG_BITS-1:0] rd3_addr_i,
    input  wire                     rd3_en_i,
    output wire [DATA_WIDTH-1:0]    rd3_data_o,
    output wire                     rd3_ready_o,
    
    // Port 4
    input  wire [PHYS_REG_BITS-1:0] rd4_addr_i,
    input  wire                     rd4_en_i,
    output wire [DATA_WIDTH-1:0]    rd4_data_o,
    output wire                     rd4_ready_o,
    
    // Port 5
    input  wire [PHYS_REG_BITS-1:0] rd5_addr_i,
    input  wire                     rd5_en_i,
    output wire [DATA_WIDTH-1:0]    rd5_data_o,
    output wire                     rd5_ready_o,
    
    // Port 6
    input  wire [PHYS_REG_BITS-1:0] rd6_addr_i,
    input  wire                     rd6_en_i,
    output wire [DATA_WIDTH-1:0]    rd6_data_o,
    output wire                     rd6_ready_o,
    
    // Port 7
    input  wire [PHYS_REG_BITS-1:0] rd7_addr_i,
    input  wire                     rd7_en_i,
    output wire [DATA_WIDTH-1:0]    rd7_data_o,
    output wire                     rd7_ready_o,
    
    //=========================================================
    // Write Ports (2 ports for dual commit)
    //=========================================================
    // Port 0
    input  wire [PHYS_REG_BITS-1:0] wr0_addr_i,
    input  wire [DATA_WIDTH-1:0]    wr0_data_i,
    input  wire                     wr0_en_i,
    
    // Port 1
    input  wire [PHYS_REG_BITS-1:0] wr1_addr_i,
    input  wire [DATA_WIDTH-1:0]    wr1_data_i,
    input  wire                     wr1_en_i,
    
    //=========================================================
    // Ready Bit Management
    //=========================================================
    // Set ready bit when instruction is allocated
    input  wire [PHYS_REG_BITS-1:0] set_unready_addr_i,
    input  wire                     set_unready_en_i,
    
    input  wire [PHYS_REG_BITS-1:0] set_unready_addr2_i,
    input  wire                     set_unready_en2_i,
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire [NUM_PHYS_REGS-1:0] flush_ready_mask_i
);

    //=========================================================
    // Register Storage
    //=========================================================
    reg [DATA_WIDTH-1:0] regs [0:NUM_PHYS_REGS-1];
    reg [NUM_PHYS_REGS-1:0] ready;  // Scoreboard - 1 means data is ready
    
    integer i;
    
    //=========================================================
    // Read Logic with Bypass
    //=========================================================
    // Bypass network: forward data from write ports if addresses match
    
    // Port 0 bypass
    wire wr0_bypass_rd0 = wr0_en_i && (wr0_addr_i == rd0_addr_i);
    wire wr1_bypass_rd0 = wr1_en_i && (wr1_addr_i == rd0_addr_i);
    
    wire [DATA_WIDTH-1:0] rd0_data_raw = regs[rd0_addr_i];
    wire [DATA_WIDTH-1:0] rd0_data_bypassed = wr0_bypass_rd0 ? wr0_data_i :
                                               wr1_bypass_rd0 ? wr1_data_i :
                                               rd0_data_raw;
    
    wire rd0_ready_raw = ready[rd0_addr_i];
    wire rd0_ready_bypassed = wr0_bypass_rd0 || wr1_bypass_rd0 || rd0_ready_raw;
    
    // Physical register 0 is always 0 and ready (for RISC-V x0)
    assign rd0_data_o = (rd0_addr_i == 0) ? 32'b0 : rd0_data_bypassed;
    assign rd0_ready_o = (rd0_addr_i == 0) ? 1'b1 : rd0_ready_bypassed;
    
    // Port 1 bypass
    wire wr0_bypass_rd1 = wr0_en_i && (wr0_addr_i == rd1_addr_i);
    wire wr1_bypass_rd1 = wr1_en_i && (wr1_addr_i == rd1_addr_i);
    
    wire [DATA_WIDTH-1:0] rd1_data_raw = regs[rd1_addr_i];
    wire [DATA_WIDTH-1:0] rd1_data_bypassed = wr0_bypass_rd1 ? wr0_data_i :
                                               wr1_bypass_rd1 ? wr1_data_i :
                                               rd1_data_raw;
    
    wire rd1_ready_raw = ready[rd1_addr_i];
    wire rd1_ready_bypassed = wr0_bypass_rd1 || wr1_bypass_rd1 || rd1_ready_raw;
    
    assign rd1_data_o = (rd1_addr_i == 0) ? 32'b0 : rd1_data_bypassed;
    assign rd1_ready_o = (rd1_addr_i == 0) ? 1'b1 : rd1_ready_bypassed;
    
    // Port 2 bypass
    wire wr0_bypass_rd2 = wr0_en_i && (wr0_addr_i == rd2_addr_i);
    wire wr1_bypass_rd2 = wr1_en_i && (wr1_addr_i == rd2_addr_i);
    
    wire [DATA_WIDTH-1:0] rd2_data_raw = regs[rd2_addr_i];
    wire [DATA_WIDTH-1:0] rd2_data_bypassed = wr0_bypass_rd2 ? wr0_data_i :
                                               wr1_bypass_rd2 ? wr1_data_i :
                                               rd2_data_raw;
    
    wire rd2_ready_raw = ready[rd2_addr_i];
    wire rd2_ready_bypassed = wr0_bypass_rd2 || wr1_bypass_rd2 || rd2_ready_raw;
    
    assign rd2_data_o = (rd2_addr_i == 0) ? 32'b0 : rd2_data_bypassed;
    assign rd2_ready_o = (rd2_addr_i == 0) ? 1'b1 : rd2_ready_bypassed;
    
    // Port 3 bypass
    wire wr0_bypass_rd3 = wr0_en_i && (wr0_addr_i == rd3_addr_i);
    wire wr1_bypass_rd3 = wr1_en_i && (wr1_addr_i == rd3_addr_i);
    
    wire [DATA_WIDTH-1:0] rd3_data_raw = regs[rd3_addr_i];
    wire [DATA_WIDTH-1:0] rd3_data_bypassed = wr0_bypass_rd3 ? wr0_data_i :
                                               wr1_bypass_rd3 ? wr1_data_i :
                                               rd3_data_raw;
    
    wire rd3_ready_raw = ready[rd3_addr_i];
    wire rd3_ready_bypassed = wr0_bypass_rd3 || wr1_bypass_rd3 || rd3_ready_raw;
    
    assign rd3_data_o = (rd3_addr_i == 0) ? 32'b0 : rd3_data_bypassed;
    assign rd3_ready_o = (rd3_addr_i == 0) ? 1'b1 : rd3_ready_bypassed;

    // Port 4 bypass
    wire wr0_bypass_rd4 = wr0_en_i && (wr0_addr_i == rd4_addr_i);
    wire wr1_bypass_rd4 = wr1_en_i && (wr1_addr_i == rd4_addr_i);
    wire [DATA_WIDTH-1:0] rd4_data_raw = regs[rd4_addr_i];
    wire [DATA_WIDTH-1:0] rd4_data_bypassed = wr0_bypass_rd4 ? wr0_data_i :
                                               wr1_bypass_rd4 ? wr1_data_i :
                                               rd4_data_raw;
    wire rd4_ready_raw = ready[rd4_addr_i];
    wire rd4_ready_bypassed = wr0_bypass_rd4 || wr1_bypass_rd4 || rd4_ready_raw;
    assign rd4_data_o = (rd4_addr_i == 0) ? 32'b0 : rd4_data_bypassed;
    assign rd4_ready_o = (rd4_addr_i == 0) ? 1'b1 : rd4_ready_bypassed;

    // Port 5 bypass
    wire wr0_bypass_rd5 = wr0_en_i && (wr0_addr_i == rd5_addr_i);
    wire wr1_bypass_rd5 = wr1_en_i && (wr1_addr_i == rd5_addr_i);
    wire [DATA_WIDTH-1:0] rd5_data_raw = regs[rd5_addr_i];
    wire [DATA_WIDTH-1:0] rd5_data_bypassed = wr0_bypass_rd5 ? wr0_data_i :
                                               wr1_bypass_rd5 ? wr1_data_i :
                                               rd5_data_raw;
    wire rd5_ready_raw = ready[rd5_addr_i];
    wire rd5_ready_bypassed = wr0_bypass_rd5 || wr1_bypass_rd5 || rd5_ready_raw;
    assign rd5_data_o = (rd5_addr_i == 0) ? 32'b0 : rd5_data_bypassed;
    assign rd5_ready_o = (rd5_addr_i == 0) ? 1'b1 : rd5_ready_bypassed;

    // Port 6 bypass
    wire wr0_bypass_rd6 = wr0_en_i && (wr0_addr_i == rd6_addr_i);
    wire wr1_bypass_rd6 = wr1_en_i && (wr1_addr_i == rd6_addr_i);
    wire [DATA_WIDTH-1:0] rd6_data_raw = regs[rd6_addr_i];
    wire [DATA_WIDTH-1:0] rd6_data_bypassed = wr0_bypass_rd6 ? wr0_data_i :
                                               wr1_bypass_rd6 ? wr1_data_i :
                                               rd6_data_raw;
    wire rd6_ready_raw = ready[rd6_addr_i];
    wire rd6_ready_bypassed = wr0_bypass_rd6 || wr1_bypass_rd6 || rd6_ready_raw;
    assign rd6_data_o = (rd6_addr_i == 0) ? 32'b0 : rd6_data_bypassed;
    assign rd6_ready_o = (rd6_addr_i == 0) ? 1'b1 : rd6_ready_bypassed;

    // Port 7 bypass
    wire wr0_bypass_rd7 = wr0_en_i && (wr0_addr_i == rd7_addr_i);
    wire wr1_bypass_rd7 = wr1_en_i && (wr1_addr_i == rd7_addr_i);
    wire [DATA_WIDTH-1:0] rd7_data_raw = regs[rd7_addr_i];
    wire [DATA_WIDTH-1:0] rd7_data_bypassed = wr0_bypass_rd7 ? wr0_data_i :
                                               wr1_bypass_rd7 ? wr1_data_i :
                                               rd7_data_raw;
    wire rd7_ready_raw = ready[rd7_addr_i];
    wire rd7_ready_bypassed = wr0_bypass_rd7 || wr1_bypass_rd7 || rd7_ready_raw;
    assign rd7_data_o = (rd7_addr_i == 0) ? 32'b0 : rd7_data_bypassed;
    assign rd7_ready_o = (rd7_addr_i == 0) ? 1'b1 : rd7_ready_bypassed;
    
    //=========================================================
    // Write Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all registers to 0
            for (i = 0; i < NUM_PHYS_REGS; i = i + 1) begin
                regs[i] <= 0;
            end
            // First 32 registers (arch regs initial mapping) are ready
            ready <= {{(NUM_PHYS_REGS-32){1'b0}}, {32{1'b1}}};
        end else if (flush_i) begin
            // On flush, restore ready bits from checkpoint mask
            ready <= flush_ready_mask_i;
        end else begin
            // Write port 0
            if (wr0_en_i && (wr0_addr_i != 0)) begin
                regs[wr0_addr_i] <= wr0_data_i;
                ready[wr0_addr_i] <= 1'b1;
            end
            
            // Write port 1
            if (wr1_en_i && (wr1_addr_i != 0)) begin
                regs[wr1_addr_i] <= wr1_data_i;
                ready[wr1_addr_i] <= 1'b1;
            end
            
            // Mark registers as not ready (when instruction is allocated)
            if (set_unready_en_i && (set_unready_addr_i != 0)) begin
                ready[set_unready_addr_i] <= 1'b0;
            end
            
            if (set_unready_en2_i && (set_unready_addr2_i != 0)) begin
                ready[set_unready_addr2_i] <= 1'b0;
            end
        end
    end

endmodule
