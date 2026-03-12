`timescale 1ns/1ps

module tb_bootrom_simple;
    reg clk;
    reg rst_n;
    
    initial begin
        $display("Test starting...");
        clk = 0;
        rst_n = 0;
        #100;
        rst_n = 1;
        #100;
        $display("Test complete!");
        $finish;
    end
    
    always #10 clk = ~clk;
endmodule
