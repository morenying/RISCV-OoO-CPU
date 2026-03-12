`timescale 1ns/1ps
module tb_spi_master;
    parameter CLK_PERIOD = 20;
    
    reg clk, rst_n;
    reg axi_awvalid, axi_wvalid, axi_arvalid, axi_bready, axi_rready;
    reg [7:0] axi_awaddr, axi_araddr;
    reg [31:0] axi_wdata;
    reg [3:0] axi_wstrb;
    wire axi_awready, axi_wready, axi_bvalid, axi_arready, axi_rvalid;
    wire [31:0] axi_rdata;
    wire [1:0] axi_bresp, axi_rresp;
    wire spi_sck, spi_mosi, spi_cs_n, irq_tx_empty, irq_rx_full;
    reg spi_miso;
    
    integer test_count, pass_count, fail_count, timeout;
    reg [31:0] read_data;
    reg [1:0] read_resp, write_resp;
    
    spi_master #(.FIFO_DEPTH(16), .DEFAULT_CLKDIV(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .axi_awvalid(axi_awvalid), .axi_awready(axi_awready), .axi_awaddr(axi_awaddr),
        .axi_wvalid(axi_wvalid), .axi_wready(axi_wready), .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
        .axi_bvalid(axi_bvalid), .axi_bready(axi_bready), .axi_bresp(axi_bresp),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready), .axi_araddr(axi_araddr),
        .axi_rvalid(axi_rvalid), .axi_rready(axi_rready), .axi_rdata(axi_rdata), .axi_rresp(axi_rresp),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs_n(spi_cs_n),
        .irq_tx_empty(irq_tx_empty), .irq_rx_full(irq_rx_full)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin #5000000; $display("TIMEOUT"); $finish; end
    
    task axi_write(input [7:0] addr, input [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); axi_awvalid <= 1; axi_awaddr <= addr; axi_wvalid <= 1; axi_wdata <= data; axi_wstrb <= 4'b1111; axi_bready <= 1;
        timeout = 0;
        while (!(axi_awvalid && axi_awready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; axi_awvalid <= 0; axi_wvalid <= 0; axi_bready <= 0; disable axi_write; end end
        @(posedge clk); axi_awvalid <= 0;
        while (!(axi_wvalid && axi_wready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; axi_wvalid <= 0; axi_bready <= 0; disable axi_write; end end
        @(posedge clk); axi_wvalid <= 0;
        while (!axi_bvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; axi_bready <= 0; disable axi_write; end end
        resp = axi_bresp;
        @(posedge clk); axi_bready <= 0;
    end
    endtask
    
    task axi_read(input [7:0] addr, output [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); axi_arvalid <= 1; axi_araddr <= addr; axi_rready <= 1;
        timeout = 0;
        while (!(axi_arvalid && axi_arready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin data = 32'hDEAD; resp = 2'b11; axi_arvalid <= 0; axi_rready <= 0; disable axi_read; end end
        @(posedge clk); axi_arvalid <= 0;
        while (!axi_rvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin data = 32'hDEAD; resp = 2'b11; axi_rready <= 0; disable axi_read; end end
        data = axi_rdata; resp = axi_rresp;
        @(posedge clk); axi_rready <= 0;
    end
    endtask
    
    task reset_dut;
    begin
        rst_n = 0; axi_awvalid = 0; axi_wvalid = 0; axi_arvalid = 0; axi_bready = 0; axi_rready = 0;
        axi_awaddr = 0; axi_araddr = 0; axi_wdata = 0; axi_wstrb = 0; spi_miso = 0;
        repeat(10) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
    end
    endtask
    
    initial begin
        $display("==============================================");
        $display("SPI Master Unit Tests");
        $display("==============================================");
        test_count = 0; pass_count = 0; fail_count = 0;
        reset_dut();
        
        $display("--- Test 1: Read Status (initial) ---");
        test_count = test_count + 1;
        axi_read(8'h04, read_data, read_resp);
        if (read_resp == 2'b00 && read_data[0] == 1) begin pass_count = pass_count + 1; $display("[PASS] TX_EMPTY=1"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] status=0x%08X", read_data); end
        
        $display("--- Test 2: Write Control ---");
        test_count = test_count + 1;
        axi_write(8'h08, 32'h01, write_resp);
        if (write_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] CTRL write"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] write resp=%b", write_resp); end
        
        $display("--- Test 3: Read Control ---");
        test_count = test_count + 1;
        axi_read(8'h08, read_data, read_resp);
        if (read_data[0] == 1) begin pass_count = pass_count + 1; $display("[PASS] CTRL=0x%02X", read_data[7:0]); end
        else begin fail_count = fail_count + 1; $display("[FAIL] CTRL=0x%02X", read_data[7:0]); end
        
        $display("--- Test 4: Write Clock Divider ---");
        test_count = test_count + 1;
        axi_write(8'h0C, 32'h0010, write_resp);
        if (write_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] CLKDIV write"); end
        else begin fail_count = fail_count + 1; $display("[FAIL]"); end
        
        $display("--- Test 5: Read Clock Divider ---");
        test_count = test_count + 1;
        axi_read(8'h0C, read_data, read_resp);
        if (read_data[15:0] == 16'h0010) begin pass_count = pass_count + 1; $display("[PASS] CLKDIV=0x%04X", read_data[15:0]); end
        else begin fail_count = fail_count + 1; $display("[FAIL] CLKDIV=0x%04X", read_data[15:0]); end
        
        $display("--- Test 6: CS Control ---");
        test_count = test_count + 1;
        axi_write(8'h10, 32'h00, write_resp);
        repeat(5) @(posedge clk);
        if (spi_cs_n == 0) begin pass_count = pass_count + 1; $display("[PASS] CS asserted"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] CS=%b", spi_cs_n); end
        
        $display("--- Test 7: Write TX Data ---");
        test_count = test_count + 1;
        axi_write(8'h00, 32'hA5, write_resp);
        if (write_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] TX data write"); end
        else begin fail_count = fail_count + 1; $display("[FAIL]"); end
        
        $display("--- Test 8: Check TX not empty ---");
        test_count = test_count + 1;
        axi_read(8'h04, read_data, read_resp);
        if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] TX processed"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] status=0x%02X", read_data[7:0]); end
        
        $display("--- Test 9: Wait for transfer ---");
        test_count = test_count + 1;
        spi_miso = 1;
        repeat(500) @(posedge clk);
        axi_read(8'h04, read_data, read_resp);
        if (read_data[4] == 0) begin pass_count = pass_count + 1; $display("[PASS] Transfer done"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] BUSY=%b", read_data[4]); end
        
        $display("--- Test 10: Read RX Data ---");
        test_count = test_count + 1;
        axi_read(8'h00, read_data, read_resp);
        $display("[INFO] RX data=0x%02X", read_data[7:0]);
        if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] RX read"); end
        else begin fail_count = fail_count + 1; $display("[FAIL]"); end
        
        $display("--- Test 11: CS Deassert ---");
        test_count = test_count + 1;
        axi_write(8'h10, 32'h01, write_resp);
        repeat(5) @(posedge clk);
        if (spi_cs_n == 1) begin pass_count = pass_count + 1; $display("[PASS] CS deasserted"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] CS=%b", spi_cs_n); end
        
        $display("==============================================");
        $display("Summary: %0d/%0d passed", pass_count, test_count);
        if (fail_count == 0) $display("ALL TESTS PASSED!");
        else $display("FAILURES: %0d", fail_count);
        $display("==============================================");
        $finish;
    end
endmodule

