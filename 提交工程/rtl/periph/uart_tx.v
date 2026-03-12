`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// UART Transmitter Module
// 
// Features:
// - Complete UART TX state machine (IDLE → START → DATA → PARITY → STOP)
// - Configurable baud rate via 16-bit divider
// - 8N1 format with optional parity (odd/even)
// - 16-byte TX FIFO with full/empty flags
// - Proper timing with baud rate generator
//
// 禁止事项:
// - 禁止直接输出数据，必须遵循 UART 时序
// - 禁止忽略波特率时序
// - 禁止使用理想化的零延迟
//////////////////////////////////////////////////////////////////////////////

module uart_tx #(
    parameter FIFO_DEPTH = 16,           // TX FIFO depth (minimum 16)
    parameter FIFO_ADDR_WIDTH = 4        // log2(FIFO_DEPTH)
)(
    input  wire        clk,              // System clock
    input  wire        rst_n,            // Active-low reset
    
    // Configuration
    input  wire [15:0] baud_div,         // Baud rate divider (clk_freq / baud_rate - 1)
    input  wire        parity_en,        // Enable parity bit
    input  wire        parity_odd,       // 1=odd parity, 0=even parity
    
    // Data interface
    input  wire [7:0]  tx_data,          // Data to transmit
    input  wire        tx_valid,         // Data valid (write to FIFO)
    output wire        tx_ready,         // Ready to accept data (FIFO not full)
    
    // Status
    output wire        tx_busy,          // Transmission in progress
    output wire        fifo_empty,       // TX FIFO is empty
    output wire        fifo_full,        // TX FIFO is full
    output wire [FIFO_ADDR_WIDTH:0] fifo_count, // Number of bytes in FIFO
    
    // UART physical interface
    output reg         uart_txd          // UART TX line (directly to pin)
);

    //==========================================================================
    // State Machine States
    //==========================================================================
    localparam [2:0] ST_IDLE   = 3'd0;   // Idle, TX line high
    localparam [2:0] ST_LOAD   = 3'd1;   // Load data from FIFO
    localparam [2:0] ST_START  = 3'd2;   // Start bit (low)
    localparam [2:0] ST_DATA   = 3'd3;   // Data bits (LSB first)
    localparam [2:0] ST_PARITY = 3'd4;   // Parity bit (optional)
    localparam [2:0] ST_STOP   = 3'd5;   // Stop bit (high)
    
    //==========================================================================
    // Internal Signals
    //==========================================================================
    reg [2:0]  state, next_state;
    reg [15:0] baud_cnt;                 // Baud rate counter
    reg        baud_tick;                // Baud rate tick (1 per bit time)
    reg [2:0]  bit_cnt;                  // Bit counter (0-7 for data)
    reg [7:0]  tx_shift;                 // TX shift register
    reg        parity_bit;               // Calculated parity
    
    // FIFO signals
    reg [7:0]  fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_WIDTH:0] wr_ptr;
    reg [FIFO_ADDR_WIDTH:0] rd_ptr;
    wire [7:0] fifo_rdata;
    reg        fifo_rd;
    
    //==========================================================================
    // FIFO Logic
    //==========================================================================
    
    // FIFO status
    assign fifo_count = wr_ptr - rd_ptr;
    assign fifo_empty = (wr_ptr == rd_ptr);
    assign fifo_full  = (fifo_count == FIFO_DEPTH);
    assign tx_ready   = ~fifo_full;
    
    // FIFO read data
    assign fifo_rdata = fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
    
    // FIFO write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (tx_valid && !fifo_full) begin
            fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= tx_data;
            wr_ptr <= wr_ptr + 1;
        end
    end
    
    // FIFO read pointer - advance when we load data
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (fifo_rd) begin
            rd_ptr <= rd_ptr + 1;
        end
    end
    
    //==========================================================================
    // Baud Rate Generator
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == baud_div) begin
                baud_cnt  <= 16'd0;
                baud_tick <= 1'b1;
            end else begin
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // TX State Machine
    //==========================================================================
    
    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Transition immediately when data available
                    if (!fifo_empty) begin
                        state <= ST_LOAD;
                    end
                end
                
                ST_LOAD: begin
                    // Wait for baud tick to start transmission
                    if (baud_tick) begin
                        state <= ST_START;
                    end
                end
                
                default: begin
                    if (baud_tick) begin
                        state <= next_state;
                    end
                end
            endcase
        end
    end
    
    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                next_state = ST_IDLE;
            end
            
            ST_LOAD: begin
                next_state = ST_START;
            end
            
            ST_START: begin
                next_state = ST_DATA;
            end
            
            ST_DATA: begin
                if (bit_cnt == 3'd7) begin
                    if (parity_en) begin
                        next_state = ST_PARITY;
                    end else begin
                        next_state = ST_STOP;
                    end
                end else begin
                    next_state = ST_DATA;
                end
            end
            
            ST_PARITY: begin
                next_state = ST_STOP;
            end
            
            ST_STOP: begin
                if (fifo_empty) begin
                    next_state = ST_IDLE;
                end else begin
                    next_state = ST_LOAD;
                end
            end
            
            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end
    
    //==========================================================================
    // Bit Counter
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'd0;
        end else if (baud_tick) begin
            if (state == ST_DATA) begin
                bit_cnt <= bit_cnt + 1;
            end else begin
                bit_cnt <= 3'd0;
            end
        end
    end
    
    //==========================================================================
    // TX Shift Register, Parity Calculation, and FIFO Read
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift   <= 8'hFF;
            parity_bit <= 1'b0;
            fifo_rd    <= 1'b0;
        end else begin
            fifo_rd <= 1'b0;  // Default: no read
            
            case (state)
                ST_IDLE: begin
                    // When transitioning to LOAD, read FIFO
                    if (!fifo_empty) begin
                        tx_shift <= fifo_rdata;
                        // Calculate parity
                        if (parity_odd) begin
                            parity_bit <= ~(^fifo_rdata);
                        end else begin
                            parity_bit <= ^fifo_rdata;
                        end
                        fifo_rd <= 1'b1;
                    end
                end
                
                ST_DATA: begin
                    if (baud_tick) begin
                        // Shift right (LSB first)
                        tx_shift <= {1'b1, tx_shift[7:1]};
                    end
                end
                
                ST_STOP: begin
                    if (baud_tick && !fifo_empty) begin
                        // Pre-load next byte for back-to-back transmission
                        tx_shift <= fifo_rdata;
                        if (parity_odd) begin
                            parity_bit <= ~(^fifo_rdata);
                        end else begin
                            parity_bit <= ^fifo_rdata;
                        end
                        fifo_rd <= 1'b1;
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    //==========================================================================
    // UART TX Output
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_txd <= 1'b1;  // Idle high
        end else begin
            case (state)
                ST_IDLE:   uart_txd <= 1'b1;           // Idle: high
                ST_LOAD:   uart_txd <= 1'b1;           // Loading: still high
                ST_START:  uart_txd <= 1'b0;           // Start bit: low
                ST_DATA:   uart_txd <= tx_shift[0];   // Data: LSB first
                ST_PARITY: uart_txd <= parity_bit;    // Parity bit
                ST_STOP:   uart_txd <= 1'b1;           // Stop bit: high
                default:   uart_txd <= 1'b1;
            endcase
        end
    end
    
    //==========================================================================
    // Status Output
    //==========================================================================
    
    assign tx_busy = (state != ST_IDLE) || !fifo_empty;

endmodule
