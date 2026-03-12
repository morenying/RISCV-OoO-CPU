`timescale 1ns/1ps
module tb_uart_rx_simple;
    reg clk = 0;
    reg rst_n = 0;
    reg [15:0] baud_div = 16'd26;
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
    
    always #10 clk = ~clk;
    
    integer i;
    
    initial begin
        $display("Starting test");
        #100;
        rst_n = 1;
        #100;
        $display("Reset done, state=%0d", dut.state);
        
        // One bit time = 27 * 16 * 20ns = 8640ns
        // Send start bit
        uart_rxd = 0;
        #8640;
        $display("After start bit: state=%0d, tick_cnt=%0d", dut.state, dut.tick_cnt);
        
        // Send 8 data bits for 0x55 (LSB first: 1,0,1,0,1,0,1,0)
        uart_rxd = 1; #8640;
        $display("After D0: state=%0d, bit_cnt=%0d, rx_shift=%02X", dut.state, dut.bit_cnt, dut.rx_shift);
        
        uart_rxd = 0; #8640;
        uart_rxd = 1; #8640;
        uart_rxd = 0; #8640;
        uart_rxd = 1; #8640;
        uart_rxd = 0; #8640;
        uart_rxd = 1; #8640;
        uart_rxd = 0; #8640;
        $display("After D7: state=%0d, bit_cnt=%0d, rx_shift=%02X", dut.state, dut.bit_cnt, dut.rx_shift);
        
        // Stop bit
        uart_rxd = 1;
        #8640;
        $display("After stop: state=%0d, fifo_wr=%b, wr_ptr=%0d", dut.state, dut.fifo_wr, dut.wr_ptr);
        
        #10000;
        $display("Final: rx_valid=%b, rx_data=%02X, fifo_count=%0d", rx_valid, rx_data, fifo_count);
        
        $finish;
    end
endmodule
