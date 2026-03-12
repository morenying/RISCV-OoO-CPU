//=================================================================
// Module: debug_csr
// Description: Debug CSR Registers
//              dcsr, dpc, dscratch registers
//              Single-step execution support
// Requirements: 14.1, 14.3
//=================================================================

`timescale 1ns/1ps

module debug_csr #(
    parameter XLEN = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================
    // CSR Read/Write Interface
    //=========================================================
    input  wire                    csr_read_i,
    input  wire                    csr_write_i,
    input  wire [11:0]             csr_addr_i,
    input  wire [XLEN-1:0]         csr_wdata_i,
    output reg  [XLEN-1:0]         csr_rdata_o,
    output wire                    csr_valid_o,
    
    //=========================================================
    // Debug Control Interface
    //=========================================================
    input  wire                    debug_mode_i,
    input  wire                    debug_entry_i,
    input  wire [2:0]              debug_cause_i,
    input  wire [XLEN-1:0]         debug_pc_i,
    
    output wire                    step_o,
    output wire                    ebreakm_o,
    output wire [XLEN-1:0]         dpc_o
);

    // Debug CSR addresses
    localparam DCSR_ADDR      = 12'h7B0;
    localparam DPC_ADDR       = 12'h7B1;
    localparam DSCRATCH0_ADDR = 12'h7B2;
    localparam DSCRATCH1_ADDR = 12'h7B3;
    
    //=========================================================
    // Debug CSR Registers
    //=========================================================
    
    // DCSR - Debug Control and Status Register
    // [31:28] xdebugver = 4 (external debug support)
    // [15]    ebreakm - EBREAK in M-mode enters debug mode
    // [11]    stopcount - Stop counters in debug mode
    // [10]    stoptime - Stop timers in debug mode
    // [8:6]   cause - Cause of debug mode entry
    // [2]     step - Single step
    // [1:0]   prv - Privilege level before debug mode
    reg [XLEN-1:0] dcsr;
    
    // DPC - Debug PC
    reg [XLEN-1:0] dpc;
    
    // DSCRATCH0/1 - Debug scratch registers
    reg [XLEN-1:0] dscratch0;
    reg [XLEN-1:0] dscratch1;
    
    //=========================================================
    // CSR Address Decode
    //=========================================================
    wire sel_dcsr      = (csr_addr_i == DCSR_ADDR);
    wire sel_dpc       = (csr_addr_i == DPC_ADDR);
    wire sel_dscratch0 = (csr_addr_i == DSCRATCH0_ADDR);
    wire sel_dscratch1 = (csr_addr_i == DSCRATCH1_ADDR);
    
    assign csr_valid_o = sel_dcsr || sel_dpc || sel_dscratch0 || sel_dscratch1;
    
    //=========================================================
    // CSR Read
    //=========================================================
    always @(*) begin
        csr_rdata_o = 32'd0;
        if (csr_read_i) begin
            case (1'b1)
                sel_dcsr:      csr_rdata_o = dcsr;
                sel_dpc:       csr_rdata_o = dpc;
                sel_dscratch0: csr_rdata_o = dscratch0;
                sel_dscratch1: csr_rdata_o = dscratch1;
                default:       csr_rdata_o = 32'd0;
            endcase
        end
    end
    
    //=========================================================
    // CSR Write
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset values
            dcsr <= {4'd4, 12'd0, 1'b0, 3'd0, 1'b0, 1'b0, 2'd0, 3'd0, 1'b0, 2'b11};
            dpc <= 32'd0;
            dscratch0 <= 32'd0;
            dscratch1 <= 32'd0;
        end else begin
            // Debug mode entry
            if (debug_entry_i) begin
                dpc <= debug_pc_i;
                dcsr[8:6] <= debug_cause_i;  // Update cause
                dcsr[1:0] <= 2'b11;          // Save M-mode privilege
            end
            
            // CSR writes (only in debug mode)
            if (csr_write_i && debug_mode_i) begin
                if (sel_dcsr) begin
                    // Only certain fields are writable
                    dcsr[15] <= csr_wdata_i[15];    // ebreakm
                    dcsr[11] <= csr_wdata_i[11];    // stopcount
                    dcsr[10] <= csr_wdata_i[10];    // stoptime
                    dcsr[2]  <= csr_wdata_i[2];     // step
                end
                if (sel_dpc) begin
                    dpc <= {csr_wdata_i[XLEN-1:1], 1'b0};  // Align to 2 bytes
                end
                if (sel_dscratch0) begin
                    dscratch0 <= csr_wdata_i;
                end
                if (sel_dscratch1) begin
                    dscratch1 <= csr_wdata_i;
                end
            end
        end
    end
    
    //=========================================================
    // Output Signals
    //=========================================================
    assign step_o = dcsr[2];
    assign ebreakm_o = dcsr[15];
    assign dpc_o = dpc;

endmodule
