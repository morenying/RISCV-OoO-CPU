//=================================================================
// Module: ecc_unit
// Description: Error Correction Code (ECC) Unit
//              Implements SEC-DED (Single Error Correct,
//              Double Error Detect) for memory protection
// Requirements: 10.5
//=================================================================

`timescale 1ns/1ps

module ecc_unit #(
    parameter DATA_WIDTH = 32,
    parameter ECC_WIDTH  = 7      // For 32-bit data: 7 check bits
) (
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Encode Interface
    input  wire [DATA_WIDTH-1:0]    data_in_i,
    output wire [DATA_WIDTH+ECC_WIDTH-1:0] encoded_o,
    
    // Decode Interface
    input  wire [DATA_WIDTH+ECC_WIDTH-1:0] encoded_i,
    output wire [DATA_WIDTH-1:0]    data_out_o,
    output wire                     single_error_o,   // Correctable error
    output wire                     double_error_o,   // Uncorrectable error
    output wire [5:0]               error_pos_o       // Error bit position
);

    //=========================================================
    // Hamming Code Generator Matrix (for 32-bit data)
    //=========================================================
    // Check bit positions: 1, 2, 4, 8, 16, 32 (plus overall parity)
    // Data bit positions: 3, 5-7, 9-15, 17-31, 33-38
    
    //=========================================================
    // Encode: Generate Check Bits
    //=========================================================
    wire [6:0] check_bits;
    
    // P1 covers bits: 1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35,37
    assign check_bits[0] = data_in_i[0]  ^ data_in_i[1]  ^ data_in_i[3]  ^ data_in_i[4]  ^
                           data_in_i[6]  ^ data_in_i[8]  ^ data_in_i[10] ^ data_in_i[11] ^
                           data_in_i[13] ^ data_in_i[15] ^ data_in_i[17] ^ data_in_i[19] ^
                           data_in_i[21] ^ data_in_i[23] ^ data_in_i[25] ^ data_in_i[26] ^
                           data_in_i[28] ^ data_in_i[30];
    
    // P2 covers bits: 2,3,6,7,10,11,14,15,18,19,22,23,26,27,30,31,34,35,38
    assign check_bits[1] = data_in_i[0]  ^ data_in_i[2]  ^ data_in_i[3]  ^ data_in_i[5]  ^
                           data_in_i[6]  ^ data_in_i[9]  ^ data_in_i[10] ^ data_in_i[12] ^
                           data_in_i[13] ^ data_in_i[16] ^ data_in_i[17] ^ data_in_i[20] ^
                           data_in_i[21] ^ data_in_i[24] ^ data_in_i[25] ^ data_in_i[27] ^
                           data_in_i[28] ^ data_in_i[31];
    
    // P4 covers bits: 4-7,12-15,20-23,28-31,36-38
    assign check_bits[2] = data_in_i[1]  ^ data_in_i[2]  ^ data_in_i[3]  ^ data_in_i[7]  ^
                           data_in_i[8]  ^ data_in_i[9]  ^ data_in_i[10] ^ data_in_i[14] ^
                           data_in_i[15] ^ data_in_i[16] ^ data_in_i[17] ^ data_in_i[22] ^
                           data_in_i[23] ^ data_in_i[24] ^ data_in_i[25] ^ data_in_i[29] ^
                           data_in_i[30] ^ data_in_i[31];
    
    // P8 covers bits: 8-15,24-31
    assign check_bits[3] = data_in_i[4]  ^ data_in_i[5]  ^ data_in_i[6]  ^ data_in_i[7]  ^
                           data_in_i[8]  ^ data_in_i[9]  ^ data_in_i[10] ^ data_in_i[18] ^
                           data_in_i[19] ^ data_in_i[20] ^ data_in_i[21] ^ data_in_i[22] ^
                           data_in_i[23] ^ data_in_i[24] ^ data_in_i[25];
    
    // P16 covers bits: 16-31
    assign check_bits[4] = data_in_i[11] ^ data_in_i[12] ^ data_in_i[13] ^ data_in_i[14] ^
                           data_in_i[15] ^ data_in_i[16] ^ data_in_i[17] ^ data_in_i[18] ^
                           data_in_i[19] ^ data_in_i[20] ^ data_in_i[21] ^ data_in_i[22] ^
                           data_in_i[23] ^ data_in_i[24] ^ data_in_i[25];
    
    // P32 covers bits: 32-38
    assign check_bits[5] = data_in_i[26] ^ data_in_i[27] ^ data_in_i[28] ^ data_in_i[29] ^
                           data_in_i[30] ^ data_in_i[31];
    
    // Overall parity (for double error detection)
    assign check_bits[6] = ^data_in_i ^ ^check_bits[5:0];
    
    // Encoded output: interleave check bits with data
    assign encoded_o = {check_bits[6], data_in_i[31:26], check_bits[5],
                        data_in_i[25:11], check_bits[4],
                        data_in_i[10:4], check_bits[3],
                        data_in_i[3:1], check_bits[2],
                        data_in_i[0], check_bits[1], check_bits[0]};

    //=========================================================
    // Decode: Check and Correct
    //=========================================================
    wire [6:0] syndrome;
    wire       overall_parity;
    
    // Extract check bits from encoded data
    wire [6:0] recv_check;
    wire [31:0] recv_data;
    
    assign recv_check[0] = encoded_i[0];
    assign recv_check[1] = encoded_i[1];
    assign recv_check[2] = encoded_i[3];
    assign recv_check[3] = encoded_i[7];
    assign recv_check[4] = encoded_i[15];
    assign recv_check[5] = encoded_i[31];
    assign recv_check[6] = encoded_i[38];
    
    // Extract data bits
    assign recv_data[0]  = encoded_i[2];
    assign recv_data[3:1] = encoded_i[6:4];
    assign recv_data[10:4] = encoded_i[14:8];
    assign recv_data[25:11] = encoded_i[30:16];
    assign recv_data[31:26] = encoded_i[37:32];
    
    // Recalculate check bits
    wire [5:0] calc_check;
    
    assign calc_check[0] = recv_data[0]  ^ recv_data[1]  ^ recv_data[3]  ^ recv_data[4]  ^
                           recv_data[6]  ^ recv_data[8]  ^ recv_data[10] ^ recv_data[11] ^
                           recv_data[13] ^ recv_data[15] ^ recv_data[17] ^ recv_data[19] ^
                           recv_data[21] ^ recv_data[23] ^ recv_data[25] ^ recv_data[26] ^
                           recv_data[28] ^ recv_data[30];
    
    assign calc_check[1] = recv_data[0]  ^ recv_data[2]  ^ recv_data[3]  ^ recv_data[5]  ^
                           recv_data[6]  ^ recv_data[9]  ^ recv_data[10] ^ recv_data[12] ^
                           recv_data[13] ^ recv_data[16] ^ recv_data[17] ^ recv_data[20] ^
                           recv_data[21] ^ recv_data[24] ^ recv_data[25] ^ recv_data[27] ^
                           recv_data[28] ^ recv_data[31];
    
    assign calc_check[2] = recv_data[1]  ^ recv_data[2]  ^ recv_data[3]  ^ recv_data[7]  ^
                           recv_data[8]  ^ recv_data[9]  ^ recv_data[10] ^ recv_data[14] ^
                           recv_data[15] ^ recv_data[16] ^ recv_data[17] ^ recv_data[22] ^
                           recv_data[23] ^ recv_data[24] ^ recv_data[25] ^ recv_data[29] ^
                           recv_data[30] ^ recv_data[31];
    
    assign calc_check[3] = recv_data[4]  ^ recv_data[5]  ^ recv_data[6]  ^ recv_data[7]  ^
                           recv_data[8]  ^ recv_data[9]  ^ recv_data[10] ^ recv_data[18] ^
                           recv_data[19] ^ recv_data[20] ^ recv_data[21] ^ recv_data[22] ^
                           recv_data[23] ^ recv_data[24] ^ recv_data[25];
    
    assign calc_check[4] = recv_data[11] ^ recv_data[12] ^ recv_data[13] ^ recv_data[14] ^
                           recv_data[15] ^ recv_data[16] ^ recv_data[17] ^ recv_data[18] ^
                           recv_data[19] ^ recv_data[20] ^ recv_data[21] ^ recv_data[22] ^
                           recv_data[23] ^ recv_data[24] ^ recv_data[25];
    
    assign calc_check[5] = recv_data[26] ^ recv_data[27] ^ recv_data[28] ^ recv_data[29] ^
                           recv_data[30] ^ recv_data[31];
    
    // Syndrome calculation
    assign syndrome[5:0] = recv_check[5:0] ^ calc_check[5:0];
    assign overall_parity = ^encoded_i;
    assign syndrome[6] = overall_parity;
    
    // Error detection and correction
    assign single_error_o = (syndrome[5:0] != 0) && overall_parity;
    assign double_error_o = (syndrome[5:0] != 0) && !overall_parity;
    assign error_pos_o = syndrome[5:0];
    
    // Correct single-bit error
    wire [31:0] corrected_data;
    
    // Map syndrome to data bit position and correct
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : correct_loop
            // Calculate the encoded position for each data bit
            // and compare with syndrome to determine if correction needed
            wire [5:0] bit_pos;
            
            // Data bit position mapping (simplified)
            if (i == 0)       assign bit_pos = 6'd3;
            else if (i <= 3)  assign bit_pos = 6'd4 + i - 1;
            else if (i <= 10) assign bit_pos = 6'd8 + i - 4;
            else if (i <= 25) assign bit_pos = 6'd16 + i - 11;
            else              assign bit_pos = 6'd32 + i - 26;
            
            assign corrected_data[i] = (single_error_o && (syndrome[5:0] == bit_pos)) ?
                                       ~recv_data[i] : recv_data[i];
        end
    endgenerate
    
    assign data_out_o = corrected_data;

endmodule

//=================================================================
// Module: parity_gen
// Description: Simple Parity Generator/Checker
//              For less critical memories
//=================================================================

module parity_gen #(
    parameter DATA_WIDTH = 32
) (
    // Generate parity
    input  wire [DATA_WIDTH-1:0] data_i,
    output wire                  parity_o,
    
    // Check parity
    input  wire [DATA_WIDTH-1:0] check_data_i,
    input  wire                  check_parity_i,
    output wire                  error_o
);

    // Even parity generation
    assign parity_o = ^data_i;
    
    // Parity check
    assign error_o = (^check_data_i) != check_parity_i;

endmodule
