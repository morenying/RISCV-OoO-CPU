`timescale 1ns/1ps
module tb_bootrom;
    parameter CLK_PERIOD = 20;
    parameter DEPTH = 256;
    parameter ADDR_WIDTH = 10;
    
    reg clk;
    reg rst_n;
    reg axi_arvalid;
    wire axi_arready;
    reg [31:0] axi_araddr;
    wire axi_rvalid;
    reg axi_rready;
    wire [31:0] axi_rdata;
    wire [1:0] axi_rresp;
    reg axi_awvalid;
    wire axi_awready;
    reg [31:0] axi_awaddr;
    reg axi_wvalid;
    wire axi_wready;
    reg [31:0] axi_wdata;
    reg [3:0] axi_wstrb;
    wire axi_bvalid;
    reg axi_bready;
    wire [1:0] axi_bresp;
    
    integer test_count, pass_count, fail_count, i, seed, timeout;
    reg [31:0] read_data, test_addr;
    reg [1:0] read_resp, write_resp;
    
    bootrom #(.DEPTH(DEPTH), .ADDR_WIDTH(ADDR_WIDTH), .INIT_FILE("none")) dut (
        .clk(clk), .rst_n(rst_n),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready), .axi_araddr(axi_araddr),
        .axi_rvalid(axi_rvalid), .axi_rready(axi_rready), .axi_rdata(axi_rdata), .axi_rresp(axi_rresp),
        .axi_awvalid(axi_awvalid), .axi_awready(axi_awready), .axi_awaddr(axi_awaddr),
        .axi_wvalid(axi_wvalid), .axi_wready(axi_wready), .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
        .axi_bvalid(axi_bvalid), .axi_bready(axi_bready), .axi_bresp(axi_bresp)
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    initial begin #2000000; $display("TIMEOUT"); $finish; end
    
    task axi_read(input [31:0] addr, output [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); axi_arvalid <= 1; axi_araddr <= addr; axi_rready <= 1;
        timeout = 0;
        while (!(axi_arvalid && axi_arready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin data = 32'hDEAD; resp = 2'b11; axi_arvalid <= 0; axi_rready <= 0; disable axi_read; end end
        @(posedge clk); axi_arvalid <= 0;
        timeout = 0;
        while (!axi_rvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin data = 32'hDEAD; resp = 2'b11; axi_rready <= 0; disable axi_read; end end
        data = axi_rdata; resp = axi_rresp;
        @(posedge clk); axi_rready <= 0;
    end
    endtask

    task axi_write(input [31:0] addr, input [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); axi_awvalid <= 1; axi_awaddr <= addr; axi_wvalid <= 1; axi_wdata <= data; axi_wstrb <= 4'b1111; axi_bready <= 1;
        @(posedge clk); axi_awvalid <= 0;
        @(posedge clk); axi_wvalid <= 0;
        timeout = 0;
        while (!axi_bvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin resp = 2'b11; axi_bready <= 0; disable axi_write; end end
        resp = axi_bresp;
        @(posedge clk); axi_bready <= 0;
    end
    endtask
    
    task reset_dut;
    begin
        rst_n = 0; axi_arvalid = 0; axi_rready = 0; axi_awvalid = 0; axi_wvalid = 0; axi_bready = 0;
        axi_araddr = 0; axi_awaddr = 0; axi_wdata = 0; axi_wstrb = 0;
        repeat(10) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
    end
    endtask
    
    initial begin
        $display("==============================================");
        $display("Boot ROM Unit Tests");
        $display("==============================================");
        test_count = 0; pass_count = 0; fail_count = 0; seed = 12345;
        reset_dut();
        
        $display("--- Test 1: Basic Read ---");
        test_count = test_count + 1;
        axi_read(32'h0, read_data, read_resp);
        if (read_data == 32'h00000013 && read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] data=0x%08X", read_data); end
        else begin fail_count = fail_count + 1; $display("[FAIL] got 0x%08X", read_data); end
        
        $display("--- Test 2: Sequential Reads ---");
        for (i = 0; i < 16; i = i + 1) begin
            test_count = test_count + 1;
            axi_read(i * 4, read_data, read_resp);
            if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] addr 0x%04X: 0x%08X", i*4, read_data); end
            else begin fail_count = fail_count + 1; $display("[FAIL] addr 0x%04X", i*4); end
        end
        
        $display("--- Test 3: Random Reads ---");
        for (i = 0; i < 20; i = i + 1) begin
            test_count = test_count + 1;
            test_addr = (($random(seed) & 32'h7FFFFFFF) % DEPTH) * 4;
            axi_read(test_addr, read_data, read_resp);
            if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] addr 0x%04X: 0x%08X", test_addr, read_data); end
            else begin fail_count = fail_count + 1; $display("[FAIL] addr 0x%04X", test_addr); end
        end
        
        $display("--- Test 4: Write Rejection ---");
        test_count = test_count + 1;
        axi_write(32'h0, 32'hDEADBEEF, write_resp);
        if (write_resp == 2'b10) begin pass_count = pass_count + 1; $display("[PASS] SLVERR"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] resp=%b", write_resp); end
        
        test_count = test_count + 1;
        axi_read(32'h0, read_data, read_resp);
        if (read_data == 32'h00000013) begin pass_count = pass_count + 1; $display("[PASS] unchanged"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] changed to 0x%08X", read_data); end
        
        $display("--- Test 5: Back-to-Back ---");
        for (i = 0; i < 10; i = i + 1) begin
            test_count = test_count + 1;
            axi_read(i * 4, read_data, read_resp);
            if (read_resp == 2'b00) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("[FAIL] b2b %0d", i); end
        end
        $display("[INFO] 10 back-to-back done");
        
        $display("--- Test 6: Alignment ---");
        test_count = test_count + 1;
        axi_read(32'h100, read_data, read_resp);
        if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] aligned"); end
        else fail_count = fail_count + 1;
        
        test_count = test_count + 1;
        axi_read(32'h101, read_data, read_resp);
        if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] unaligned"); end
        else fail_count = fail_count + 1;
        
        $display("--- Test 7: Max Address ---");
        test_count = test_count + 1;
        axi_read((DEPTH - 1) * 4, read_data, read_resp);
        if (read_resp == 2'b00) begin pass_count = pass_count + 1; $display("[PASS] max addr"); end
        else begin fail_count = fail_count + 1; $display("[FAIL] max addr"); end
        
        $display("--- Test 8: Multi Write ---");
        for (i = 0; i < 5; i = i + 1) begin
            test_count = test_count + 1;
            axi_write(i * 4, 32'hCAFEBABE, write_resp);
            if (write_resp == 2'b10) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("[FAIL] write %0d", i); end
        end
        $display("[INFO] writes rejected");
        
        $display("==============================================");
        $display("Summary: %0d/%0d passed", pass_count, test_count);
        if (fail_count == 0) $display("ALL TESTS PASSED!");
        else $display("FAILURES: %0d", fail_count);
        $display("==============================================");
        $finish;
    end
endmodule
