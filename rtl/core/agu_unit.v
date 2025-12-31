//=================================================================
// Module: agu_unit
// Description: Address Generation Unit for Load/Store operations
//              Calculates effective address: base + offset
//              Detects address misalignment exceptions
// Requirements: 11.5, 1.1
//=================================================================

`timescale 1ns/1ps

module agu_unit (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input interface
    input  wire        valid_i,
    input  wire        is_store_i,     // 1: store, 0: load
    input  wire [31:0] base_i,         // Base address (rs1)
    input  wire [31:0] offset_i,       // Offset (immediate)
    input  wire [31:0] store_data_i,   // Store data (rs2)
    input  wire [1:0]  size_i,         // 00:byte, 01:half, 10:word
    input  wire        sign_ext_i,     // Sign extend for loads
    input  wire [5:0]  prd_i,
    input  wire [4:0]  rob_idx_i,
    
    // Output interface
    output reg         done_o,
    output reg  [31:0] addr_o,         // Effective address
    output reg  [31:0] data_o,         // Store data (passed through)
    output reg         misaligned_o,   // Misalignment exception
    output reg  [1:0]  size_o,         // Size (passed through)
    output reg         sign_ext_o,     // Sign extend (passed through)
    output reg         is_store_o,     // Store flag (passed through)
    output reg  [5:0]  result_prd_o,
    output reg  [4:0]  result_rob_idx_o
);

    //=========================================================
    // Local Parameters
    //=========================================================
    localparam SIZE_BYTE = 2'b00;
    localparam SIZE_HALF = 2'b01;
    localparam SIZE_WORD = 2'b10;
    
    //=========================================================
    // Internal Signals
    //=========================================================
    wire [31:0] effective_addr;
    wire        half_misaligned;
    wire        word_misaligned;
    wire        addr_misaligned;
    
    //=========================================================
    // Address Calculation
    //=========================================================
    assign effective_addr = base_i + offset_i;
    
    //=========================================================
    // Misalignment Detection
    //=========================================================
    // Halfword access must be 2-byte aligned (addr[0] = 0)
    assign half_misaligned = (size_i == SIZE_HALF) && effective_addr[0];
    
    // Word access must be 4-byte aligned (addr[1:0] = 0)
    assign word_misaligned = (size_i == SIZE_WORD) && (effective_addr[1:0] != 2'b00);
    
    // Combined misalignment check
    assign addr_misaligned = half_misaligned || word_misaligned;

    //=========================================================
    // Output Logic (Single Cycle)
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_o <= 1'b0;
            addr_o <= 32'b0;
            data_o <= 32'b0;
            misaligned_o <= 1'b0;
            size_o <= 2'b0;
            sign_ext_o <= 1'b0;
            is_store_o <= 1'b0;
            result_prd_o <= 6'b0;
            result_rob_idx_o <= 5'b0;
        end else begin
            done_o <= valid_i;
            
            if (valid_i) begin
                addr_o <= effective_addr;
                data_o <= store_data_i;
                misaligned_o <= addr_misaligned;
                size_o <= size_i;
                sign_ext_o <= sign_ext_i;
                is_store_o <= is_store_i;
                result_prd_o <= prd_i;
                result_rob_idx_o <= rob_idx_i;
            end
        end
    end

endmodule
