`timescale 1ns/1ps
module tb_uart_rx_debug;
    parameter CLK_PERIOD = 20;
    parameter BAUD_DIV = 26;
    parameter BIT_TIME = (BAUD_DIV + 1) * 16 * CLK_PERIOD;
    
    reg clk = 0;
    reg rst_n = 0;
    reg [15:0] baud_div = BAUD_DIV;
    reg parity_en = 0;
    reg parity_odd = 0;
    wire [7:0] rx_data;
    wire rx_valid;
    reg rx_ready = 0;
    wire rx_busy;
    wire fifo_empty;
    wire fifo_full;
    wire [4:0] fifo_count;
    wire frame_error;
    wire parity_error;
    wire overrun_error;
    reg uart_rxd = 1;
    
    uart_rx #(.FIFO_DEPTH(16), .FIFO_ADDR_WIDTH(4)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .baud_div(baud_div),
        .parity_en(parity_en),
        .parity_odd(parity_odd),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_ready(rx_ready),
        .rx_busy(rx_busy),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full),
        .fifo_count(fifo_count),
        .frame_error(frame_error),
        .parity_error(parity_error),
        .overrun_error(overrun_error),
        .uart_rxd(uart_rxd)
    );
    
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        $display("BIT_TIME = %0d ns", BIT_TIME);
        #100 rst_n = 1;
        #100;
        
        // Send 0x55 (01010101)
        $display("Sending start bit at %0t", $time);
        uart_rxd = 0; #(BIT_TIME);  // Start
        $display("State after start: %0d, rx_busy=%b", dut.state, rx_busy);
        
        $display("Sending bit 0 (1) at %0t", $time);
        uart_rxd = 1; #(BIT_TIME);  // D0
        $display("State: %0d, bit_cnt=%0d, rx_shift=0x%02X", dut.state, dut.bit_cnt, dut.rx_shift);
        
        uart_rxd = 0; #(BIT_TIME);  // D1
        $display("State: %0d, bit_cnt=%0d, rx_shift=0x%02X", dut.state, dut.bit_cnt, dut.rx_shift);
        
        uart_rxd = 1; #(BIT_TIME);  // D2
        uart_rxd = 0; #(BIT_TIME);  // D3
        uart_rxd = 1; #(BIT_TIME);  // D4
        uart_rxd = 0; #(BIT_TIME);  // D5
        uart_rxd = 1; #(BIT_TIME);  // D6
        uart_rxd = 0; #(BIT_TIME);  // D7
        $display("After all data bits: state=%0d, bit_cnt=%0d, rx_shift=0x%02X", dut.state, dut.bit_cnt, dut.rx_shift);
        
        $display("Sending stop bit at %0t", $time);
        uart_rxd = 1; #(BIT_TIME);  // Stop
        $display("After stop: state=%0d, fifo_wr=%b", dut.state, dut.fifo_wr);
        
        #(BIT_TIME * 2);
        $display("Final: rx_valid=%b fifo_empty=%b rx_data=0x%02X fifo_count=%0d", rx_valid, fifo_empty, rx_data, fifo_count);
        $display("wr_ptr=%0d rd_ptr=%0d", dut.wr_ptr, dut.rd_ptr);
        $finish;
    end
endmodule
