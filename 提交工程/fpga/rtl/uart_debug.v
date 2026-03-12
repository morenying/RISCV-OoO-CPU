//=================================================================
// Module: uart_debug
// Description: UART Debug Interface for CPU
//              Provides serial communication for debug access
//              Supports memory read/write and register access
// Requirements: 9.3
//=================================================================

`timescale 1ns/1ps

module uart_debug #(
    parameter CLK_FREQ   = 100_000_000,  // 100MHz
    parameter BAUD_RATE  = 115200,
    parameter XLEN       = 32
) (
    input  wire                 clk,
    input  wire                 rst_n,
    
    // UART Interface
    input  wire                 uart_rx_i,
    output wire                 uart_tx_o,
    
    // Debug Memory Interface
    output reg  [XLEN-1:0]      dbg_addr_o,
    output reg  [XLEN-1:0]      dbg_wdata_o,
    output reg                  dbg_we_o,
    output reg                  dbg_req_o,
    input  wire [XLEN-1:0]      dbg_rdata_i,
    input  wire                 dbg_ack_i,
    
    // CPU Control
    output reg                  dbg_halt_req_o,
    output reg                  dbg_resume_req_o,
    output reg                  dbg_reset_req_o,
    input  wire                 dbg_halted_i
);

    //=========================================================
    // UART Parameters
    //=========================================================
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam BIT_CNT_WIDTH = $clog2(CLKS_PER_BIT);

    //=========================================================
    // UART RX State Machine
    //=========================================================
    localparam RX_IDLE  = 3'd0;
    localparam RX_START = 3'd1;
    localparam RX_DATA  = 3'd2;
    localparam RX_STOP  = 3'd3;
    localparam RX_DONE  = 3'd4;

    reg [2:0]               rx_state;
    reg [BIT_CNT_WIDTH-1:0] rx_clk_cnt;
    reg [2:0]               rx_bit_idx;
    reg [7:0]               rx_byte;
    reg                     rx_done;
    reg [1:0]               rx_sync;

    // Synchronize RX input
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_sync <= 2'b11;
        else
            rx_sync <= {rx_sync[0], uart_rx_i};
    end

    wire rx_bit = rx_sync[1];

    // RX State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= 0;
            rx_bit_idx <= 0;
            rx_byte    <= 8'h00;
            rx_done    <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            
            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 0;
                    rx_bit_idx <= 0;
                    if (rx_bit == 1'b0) begin  // Start bit detected
                        rx_state <= RX_START;
                    end
                end
                
                RX_START: begin
                    if (rx_clk_cnt == (CLKS_PER_BIT - 1) / 2) begin
                        if (rx_bit == 1'b0) begin
                            rx_clk_cnt <= 0;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;  // False start
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                
                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 0;
                        rx_byte[rx_bit_idx] <= rx_bit;
                        if (rx_bit_idx == 7) begin
                            rx_bit_idx <= 0;
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 1;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                
                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_done <= 1'b1;
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1;
                    end
                end
                
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    //=========================================================
    // UART TX State Machine
    //=========================================================
    localparam TX_IDLE  = 3'd0;
    localparam TX_START = 3'd1;
    localparam TX_DATA  = 3'd2;
    localparam TX_STOP  = 3'd3;

    reg [2:0]               tx_state;
    reg [BIT_CNT_WIDTH-1:0] tx_clk_cnt;
    reg [2:0]               tx_bit_idx;
    reg [7:0]               tx_byte;
    reg                     tx_bit;
    reg                     tx_busy;
    reg                     tx_start;
    reg [7:0]               tx_data;

    assign uart_tx_o = tx_bit;

    // TX State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_clk_cnt <= 0;
            tx_bit_idx <= 0;
            tx_byte    <= 8'h00;
            tx_bit     <= 1'b1;  // Idle high
            tx_busy    <= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_bit <= 1'b1;
                    tx_clk_cnt <= 0;
                    tx_bit_idx <= 0;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_byte <= tx_data;
                        tx_busy <= 1'b1;
                        tx_state <= TX_START;
                    end
                end
                
                TX_START: begin
                    tx_bit <= 1'b0;  // Start bit
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        tx_state <= TX_DATA;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                
                TX_DATA: begin
                    tx_bit <= tx_byte[tx_bit_idx];
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_clk_cnt <= 0;
                        if (tx_bit_idx == 7) begin
                            tx_bit_idx <= 0;
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1;
                        end
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                
                TX_STOP: begin
                    tx_bit <= 1'b1;  // Stop bit
                    if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_clk_cnt <= tx_clk_cnt + 1;
                    end
                end
                
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    //=========================================================
    // Debug Command Parser
    //=========================================================
    // Commands:
    // 'R' addr[4] -> Read memory, returns 4 bytes
    // 'W' addr[4] data[4] -> Write memory
    // 'H' -> Halt CPU
    // 'G' -> Go (resume) CPU
    // 'X' -> Reset CPU
    // 'S' -> Status query
    
    localparam CMD_IDLE     = 4'd0;
    localparam CMD_READ_ADDR = 4'd1;
    localparam CMD_READ_EXEC = 4'd2;
    localparam CMD_READ_RESP = 4'd3;
    localparam CMD_WRITE_ADDR = 4'd4;
    localparam CMD_WRITE_DATA = 4'd5;
    localparam CMD_WRITE_EXEC = 4'd6;
    localparam CMD_STATUS    = 4'd7;

    reg [3:0]  cmd_state;
    reg [7:0]  cmd_byte;
    reg [1:0]  byte_cnt;
    reg [31:0] cmd_addr;
    reg [31:0] cmd_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_state <= CMD_IDLE;
            byte_cnt <= 0;
            cmd_addr <= 32'h0;
            cmd_data <= 32'h0;
            dbg_addr_o <= 32'h0;
            dbg_wdata_o <= 32'h0;
            dbg_we_o <= 1'b0;
            dbg_req_o <= 1'b0;
            dbg_halt_req_o <= 1'b0;
            dbg_resume_req_o <= 1'b0;
            dbg_reset_req_o <= 1'b0;
            tx_start <= 1'b0;
            tx_data <= 8'h00;
        end else begin
            tx_start <= 1'b0;
            dbg_halt_req_o <= 1'b0;
            dbg_resume_req_o <= 1'b0;
            dbg_reset_req_o <= 1'b0;
            
            case (cmd_state)
                CMD_IDLE: begin
                    dbg_req_o <= 1'b0;
                    dbg_we_o <= 1'b0;
                    byte_cnt <= 0;
                    
                    if (rx_done) begin
                        case (rx_byte)
                            "R": cmd_state <= CMD_READ_ADDR;
                            "W": cmd_state <= CMD_WRITE_ADDR;
                            "H": begin
                                dbg_halt_req_o <= 1'b1;
                                tx_data <= "K";  // ACK
                                tx_start <= 1'b1;
                            end
                            "G": begin
                                dbg_resume_req_o <= 1'b1;
                                tx_data <= "K";
                                tx_start <= 1'b1;
                            end
                            "X": begin
                                dbg_reset_req_o <= 1'b1;
                                tx_data <= "K";
                                tx_start <= 1'b1;
                            end
                            "S": cmd_state <= CMD_STATUS;
                            default: begin
                                tx_data <= "?";  // Unknown command
                                tx_start <= 1'b1;
                            end
                        endcase
                    end
                end
                
                CMD_READ_ADDR: begin
                    if (rx_done) begin
                        cmd_addr <= {cmd_addr[23:0], rx_byte};
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 3) begin
                            cmd_state <= CMD_READ_EXEC;
                        end
                    end
                end
                
                CMD_READ_EXEC: begin
                    dbg_addr_o <= cmd_addr;
                    dbg_we_o <= 1'b0;
                    dbg_req_o <= 1'b1;
                    if (dbg_ack_i) begin
                        cmd_data <= dbg_rdata_i;
                        dbg_req_o <= 1'b0;
                        byte_cnt <= 0;
                        cmd_state <= CMD_READ_RESP;
                    end
                end
                
                CMD_READ_RESP: begin
                    if (!tx_busy) begin
                        case (byte_cnt)
                            0: tx_data <= cmd_data[31:24];
                            1: tx_data <= cmd_data[23:16];
                            2: tx_data <= cmd_data[15:8];
                            3: tx_data <= cmd_data[7:0];
                        endcase
                        tx_start <= 1'b1;
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 3) begin
                            cmd_state <= CMD_IDLE;
                        end
                    end
                end
                
                CMD_WRITE_ADDR: begin
                    if (rx_done) begin
                        cmd_addr <= {cmd_addr[23:0], rx_byte};
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 3) begin
                            byte_cnt <= 0;
                            cmd_state <= CMD_WRITE_DATA;
                        end
                    end
                end
                
                CMD_WRITE_DATA: begin
                    if (rx_done) begin
                        cmd_data <= {cmd_data[23:0], rx_byte};
                        byte_cnt <= byte_cnt + 1;
                        if (byte_cnt == 3) begin
                            cmd_state <= CMD_WRITE_EXEC;
                        end
                    end
                end
                
                CMD_WRITE_EXEC: begin
                    dbg_addr_o <= cmd_addr;
                    dbg_wdata_o <= cmd_data;
                    dbg_we_o <= 1'b1;
                    dbg_req_o <= 1'b1;
                    if (dbg_ack_i) begin
                        dbg_req_o <= 1'b0;
                        dbg_we_o <= 1'b0;
                        tx_data <= "K";  // ACK
                        tx_start <= 1'b1;
                        cmd_state <= CMD_IDLE;
                    end
                end
                
                CMD_STATUS: begin
                    if (!tx_busy) begin
                        tx_data <= dbg_halted_i ? "H" : "R";  // Halted or Running
                        tx_start <= 1'b1;
                        cmd_state <= CMD_IDLE;
                    end
                end
                
                default: cmd_state <= CMD_IDLE;
            endcase
        end
    end

endmodule
