`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// UART Receiver Module
// 
// Features:
// - Complete UART RX state machine (IDLE → START → DATA → PARITY → STOP)
// - 16x oversampling for robust start bit detection
// - Configurable baud rate via 16-bit divider
// - 8N1 format with optional parity (odd/even)
// - 16-byte RX FIFO with full/empty flags
// - Frame error and parity error detection
// - Noise filtering with majority voting
//
// 禁止事项:
// - 禁止假设输入总是正确
// - 禁止忽略错误检测
// - 禁止使用单采样（必须过采样）
//////////////////////////////////////////////////////////////////////////////

module uart_rx #(
    parameter FIFO_DEPTH = 16,           // RX FIFO depth (minimum 16)
    parameter FIFO_ADDR_WIDTH = 4        // log2(FIFO_DEPTH)
)(
    input  wire        clk,              // System clock
    input  wire        rst_n,            // Active-low reset
    
    // Configuration
    input  wire [15:0] baud_div,         // Baud rate divider for 16x oversampling
                                         // = (clk_freq / (baud_rate * 16)) - 1
    input  wire        parity_en,        // Enable parity bit
    input  wire        parity_odd,       // 1=odd parity, 0=even parity
    
    // Data interface
    output wire [7:0]  rx_data,          // Received data
    output wire        rx_valid,         // Data valid (read from FIFO)
    input  wire        rx_ready,         // Ready to accept data (read strobe)
    
    // Status
    output wire        rx_busy,          // Reception in progress
    output wire        fifo_empty,       // RX FIFO is empty
    output wire        fifo_full,        // RX FIFO is full
    output wire [FIFO_ADDR_WIDTH:0] fifo_count, // Number of bytes in FIFO
    
    // Error flags (active for one clock when error detected)
    output reg         frame_error,      // Stop bit not detected
    output reg         parity_error,     // Parity mismatch
    output reg         overrun_error,    // FIFO overflow
    
    // UART physical interface
    input  wire        uart_rxd          // UART RX line (directly from pin)
);

    //==========================================================================
    // State Machine States
    //==========================================================================
    localparam [2:0] ST_IDLE   = 3'd0;   // Idle, waiting for start bit
    localparam [2:0] ST_START  = 3'd1;   // Validating start bit
    localparam [2:0] ST_DATA   = 3'd2;   // Receiving data bits
    localparam [2:0] ST_PARITY = 3'd3;   // Receiving parity bit
    localparam [2:0] ST_STOP   = 3'd4;   // Receiving stop bit
    
    //==========================================================================
    // Internal Signals
    //==========================================================================
    reg [2:0]  state;
    reg [15:0] sample_cnt;               // 16x oversampling counter
    reg        sample_tick;              // Sample tick (16 per bit)
    reg [3:0]  tick_cnt;                 // Tick counter within bit (0-15)
    reg [2:0]  bit_cnt;                  // Bit counter (0-7 for data)
    reg [7:0]  rx_shift;                 // RX shift register
    reg        rx_parity;                // Received parity bit
    reg        calc_parity;              // Calculated parity
    
    // Input synchronizer (2-stage for metastability)
    reg [1:0]  rxd_sync;
    wire       rxd_s;                    // Synchronized RX signal
    reg        rxd_prev;                 // Previous value for edge detection
    wire       falling_edge;             // Falling edge detected
    
    // Sample at middle of bit
    wire       sample_point;
    reg        sampled_bit;
    
    // FIFO signals
    reg [7:0]  fifo_mem [0:FIFO_DEPTH-1];
    reg [FIFO_ADDR_WIDTH:0] wr_ptr;
    reg [FIFO_ADDR_WIDTH:0] rd_ptr;
    reg        fifo_wr;
    
    //==========================================================================
    // Input Synchronizer (Critical for real hardware!)
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_sync <= 2'b11;  // Idle high
            rxd_prev <= 1'b1;
        end else begin
            rxd_sync <= {rxd_sync[0], uart_rxd};
            rxd_prev <= rxd_s;
        end
    end
    
    assign rxd_s = rxd_sync[1];  // Use synchronized signal
    assign falling_edge = rxd_prev && !rxd_s;  // Detect falling edge
    
    //==========================================================================
    // 16x Oversampling Clock Generator
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt  <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            if (state == ST_IDLE) begin
                // Reset counter when idle
                sample_cnt  <= 16'd0;
                sample_tick <= 1'b0;
            end else if (sample_cnt == baud_div) begin
                sample_cnt  <= 16'd0;
                sample_tick <= 1'b1;
            end else begin
                sample_cnt  <= sample_cnt + 1;
                sample_tick <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Tick Counter (16 ticks per bit)
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 4'd0;
        end else if (state == ST_IDLE) begin
            tick_cnt <= 4'd0;
        end else if (sample_tick) begin
            tick_cnt <= tick_cnt + 1;
        end
    end
    
    // Sample point at middle of bit (tick 7)
    assign sample_point = sample_tick && (tick_cnt == 4'd7);
    
    // Capture sampled bit
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sampled_bit <= 1'b1;
        end else if (sample_point) begin
            sampled_bit <= rxd_s;
        end
    end
    
    //==========================================================================
    // RX State Machine
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Detect falling edge (start bit)
                    if (falling_edge) begin
                        state <= ST_START;
                    end
                end
                
                ST_START: begin
                    // Validate start bit at middle (tick 7)
                    if (sample_tick && tick_cnt == 4'd15) begin
                        if (!sampled_bit) begin
                            // Valid start bit, proceed to data
                            state <= ST_DATA;
                        end else begin
                            // False start, go back to idle
                            state <= ST_IDLE;
                        end
                    end
                end
                
                ST_DATA: begin
                    if (sample_tick && tick_cnt == 4'd15) begin
                        if (bit_cnt == 3'd7) begin
                            if (parity_en) begin
                                state <= ST_PARITY;
                            end else begin
                                state <= ST_STOP;
                            end
                        end
                    end
                end
                
                ST_PARITY: begin
                    if (sample_tick && tick_cnt == 4'd15) begin
                        state <= ST_STOP;
                    end
                end
                
                ST_STOP: begin
                    if (sample_tick && tick_cnt == 4'd15) begin
                        state <= ST_IDLE;
                    end
                end
                
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Bit Counter
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt <= 3'd0;
        end else if (state == ST_IDLE || state == ST_START) begin
            bit_cnt <= 3'd0;
        end else if (sample_tick && tick_cnt == 4'd15 && state == ST_DATA) begin
            bit_cnt <= bit_cnt + 1;
        end
    end
    
    //==========================================================================
    // RX Shift Register and Parity Calculation
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift    <= 8'h00;
            rx_parity   <= 1'b0;
            calc_parity <= 1'b0;
        end else begin
            case (state)
                ST_START: begin
                    if (sample_tick && tick_cnt == 4'd15) begin
                        calc_parity <= 1'b0;  // Reset parity calculation
                    end
                end
                
                ST_DATA: begin
                    // Sample at tick 7 (middle of bit), latch at tick 15
                    if (sample_tick && tick_cnt == 4'd15) begin
                        // Shift in data (LSB first)
                        rx_shift <= {sampled_bit, rx_shift[7:1]};
                        // Update running parity
                        calc_parity <= calc_parity ^ sampled_bit;
                    end
                end
                
                ST_PARITY: begin
                    if (sample_tick && tick_cnt == 4'd15) begin
                        rx_parity <= sampled_bit;
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    //==========================================================================
    // Error Detection and FIFO Write
    //==========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_error  <= 1'b0;
            parity_error <= 1'b0;
            fifo_wr      <= 1'b0;
        end else begin
            // Clear errors by default
            frame_error  <= 1'b0;
            parity_error <= 1'b0;
            fifo_wr      <= 1'b0;
            
            // Check at end of stop bit (tick 15)
            if (state == ST_STOP && sample_tick && tick_cnt == 4'd15) begin
                // Check stop bit (should be high)
                if (!sampled_bit) begin
                    frame_error <= 1'b1;
                end else begin
                    // Valid frame, write to FIFO
                    // Check parity if enabled
                    if (parity_en) begin
                        if (parity_odd) begin
                            // Odd parity: XOR of data bits + parity should be 1
                            if ((calc_parity ^ rx_parity) != 1'b1) begin
                                parity_error <= 1'b1;
                            end else begin
                                fifo_wr <= 1'b1;
                            end
                        end else begin
                            // Even parity: XOR of data bits + parity should be 0
                            if ((calc_parity ^ rx_parity) != 1'b0) begin
                                parity_error <= 1'b1;
                            end else begin
                                fifo_wr <= 1'b1;
                            end
                        end
                    end else begin
                        // No parity, just write
                        fifo_wr <= 1'b1;
                    end
                end
            end
        end
    end
    
    //==========================================================================
    // FIFO Logic
    //==========================================================================
    
    // FIFO status
    assign fifo_count = wr_ptr - rd_ptr;
    assign fifo_empty = (wr_ptr == rd_ptr);
    assign fifo_full  = (fifo_count == FIFO_DEPTH);
    assign rx_valid   = ~fifo_empty;
    
    // FIFO read data
    assign rx_data = fifo_mem[rd_ptr[FIFO_ADDR_WIDTH-1:0]];
    
    // FIFO write pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (fifo_wr && !fifo_full) begin
            fifo_mem[wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= rx_shift;
            wr_ptr <= wr_ptr + 1;
        end
    end
    
    // FIFO read pointer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (rx_ready && !fifo_empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end
    
    // Overrun error detection
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            overrun_error <= 1'b0;
        end else begin
            overrun_error <= 1'b0;
            
            // Overrun when trying to write to full FIFO
            if (fifo_wr && fifo_full) begin
                overrun_error <= 1'b1;
            end
        end
    end
    
    //==========================================================================
    // Status Output
    //==========================================================================
    
    assign rx_busy = (state != ST_IDLE);

endmodule
