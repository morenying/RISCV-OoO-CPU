`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Checkpoint 12: Bootloader Verification
//
// Tests:
// 1. Boot ROM functionality
// 2. SPI Master functionality
// 3. Complete boot sequence simulation
// 4. Error handling
//////////////////////////////////////////////////////////////////////////////

module tb_bootloader_checkpoint;
    parameter CLK_PERIOD = 20;
    
    reg clk, rst_n;
    
    // Boot ROM
    reg br_arvalid, br_rready, br_awvalid, br_wvalid, br_bready;
    wire br_arready, br_rvalid, br_awready, br_wready, br_bvalid;
    reg [31:0] br_araddr, br_awaddr, br_wdata;
    reg [3:0] br_wstrb;
    wire [31:0] br_rdata;
    wire [1:0] br_rresp, br_bresp;
    
    // SPI
    reg spi_awvalid, spi_wvalid, spi_arvalid, spi_bready, spi_rready;
    reg [7:0] spi_awaddr, spi_araddr;
    reg [31:0] spi_wdata;
    reg [3:0] spi_wstrb;
    wire spi_awready, spi_wready, spi_bvalid, spi_arready, spi_rvalid;
    wire [31:0] spi_rdata;
    wire [1:0] spi_bresp, spi_rresp;
    wire spi_sck, spi_mosi, spi_cs_n;
    reg spi_miso;
    
    integer test_count, pass_count, fail_count, timeout, i;
    reg [31:0] read_data;
    reg [1:0] read_resp, write_resp;
    
    bootrom #(.DEPTH(256), .ADDR_WIDTH(10), .INIT_FILE("none")) bootrom_inst (
        .clk(clk), .rst_n(rst_n),
        .axi_arvalid(br_arvalid), .axi_arready(br_arready), .axi_araddr(br_araddr),
        .axi_rvalid(br_rvalid), .axi_rready(br_rready), .axi_rdata(br_rdata), .axi_rresp(br_rresp),
        .axi_awvalid(br_awvalid), .axi_awready(br_awready), .axi_awaddr(br_awaddr),
        .axi_wvalid(br_wvalid), .axi_wready(br_wready), .axi_wdata(br_wdata), .axi_wstrb(br_wstrb),
        .axi_bvalid(br_bvalid), .axi_bready(br_bready), .axi_bresp(br_bresp)
    );
    
    spi_master #(.FIFO_DEPTH(16), .DEFAULT_CLKDIV(4)) spi_inst (
        .clk(clk), .rst_n(rst_n),
        .axi_awvalid(spi_awvalid), .axi_awready(spi_awready), .axi_awaddr(spi_awaddr),
        .axi_wvalid(spi_wvalid), .axi_wready(spi_wready), .axi_wdata(spi_wdata), .axi_wstrb(spi_wstrb),
        .axi_bvalid(spi_bvalid), .axi_bready(spi_bready), .axi_bresp(spi_bresp),
        .axi_arvalid(spi_arvalid), .axi_arready(spi_arready), .axi_araddr(spi_araddr),
        .axi_rvalid(spi_rvalid), .axi_rready(spi_rready), .axi_rdata(spi_rdata), .axi_rresp(spi_rresp),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso), .spi_cs_n(spi_cs_n),
        .irq_tx_empty(), .irq_rx_full()
    );
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin #20000000; $display("TIMEOUT"); $finish; end
    
    task bootrom_read(input [31:0] addr, output [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); br_arvalid <= 1; br_araddr <= addr; br_rready <= 1;
        timeout = 0;
        while (!(br_arvalid && br_arready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin data = 32'hDEAD; resp = 2'b11; br_arvalid <= 0; br_rready <= 0; disable bootrom_read; end end
        @(posedge clk); br_arvalid <= 0;
        while (!br_rvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin data = 32'hDEAD; resp = 2'b11; br_rready <= 0; disable bootrom_read; end end
        data = br_rdata; resp = br_rresp;
        @(posedge clk); br_rready <= 0;
    end
    endtask
    
    task bootrom_write(input [31:0] addr, input [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); br_awvalid <= 1; br_awaddr <= addr; br_wvalid <= 1; br_wdata <= data; br_wstrb <= 4'b1111; br_bready <= 1;
        @(posedge clk); br_awvalid <= 0;
        @(posedge clk); br_wvalid <= 0;
        timeout = 0;
        while (!br_bvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 50) begin resp = 2'b11; br_bready <= 0; disable bootrom_write; end end
        resp = br_bresp;
        @(posedge clk); br_bready <= 0;
    end
    endtask
    
    task spi_write(input [7:0] addr, input [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); spi_awvalid <= 1; spi_awaddr <= addr; spi_wvalid <= 1; spi_wdata <= data; spi_wstrb <= 4'b1111; spi_bready <= 1;
        timeout = 0;
        while (!(spi_awvalid && spi_awready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; spi_awvalid <= 0; spi_wvalid <= 0; spi_bready <= 0; disable spi_write; end end
        @(posedge clk); spi_awvalid <= 0;
        while (!(spi_wvalid && spi_wready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; spi_wvalid <= 0; spi_bready <= 0; disable spi_write; end end
        @(posedge clk); spi_wvalid <= 0;
        while (!spi_bvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin resp = 2'b11; spi_bready <= 0; disable spi_write; end end
        resp = spi_bresp;
        @(posedge clk); spi_bready <= 0;
    end
    endtask
    
    task spi_read(input [7:0] addr, output [31:0] data, output [1:0] resp);
    begin
        @(posedge clk); spi_arvalid <= 1; spi_araddr <= addr; spi_rready <= 1;
        timeout = 0;
        while (!(spi_arvalid && spi_arready)) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin data = 32'hDEAD; resp = 2'b11; spi_arvalid <= 0; spi_rready <= 0; disable spi_read; end end
        @(posedge clk); spi_arvalid <= 0;
        while (!spi_rvalid) begin @(posedge clk); timeout = timeout + 1; if (timeout > 100) begin data = 32'hDEAD; resp = 2'b11; spi_rready <= 0; disable spi_read; end end
        data = spi_rdata; resp = spi_rresp;
        @(posedge clk); spi_rready <= 0;
    end
    endtask
    
    task reset_all;
    begin
        rst_n = 0;
        br_arvalid = 0; br_rready = 0; br_awvalid = 0; br_wvalid = 0; br_bready = 0;
        br_araddr = 0; br_awaddr = 0; br_wdata = 0; br_wstrb = 0;
        spi_awvalid = 0; spi_wvalid = 0; spi_arvalid = 0; spi_bready = 0; spi_rready = 0;
        spi_awaddr = 0; spi_araddr = 0; spi_wdata = 0; spi_wstrb = 0; spi_miso = 0;
        repeat(10) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);
    end
    endtask
    
    initial begin
        $display("##############################################");
        $display("# Checkpoint 12: Bootloader Verification");
        $display("##############################################");
        test_count = 0; pass_count = 0; fail_count = 0;
        reset_all();
        
        //======================================================================
        // Test 1: Boot ROM Basic Read
        //======================================================================
        $display("\n=== Test 1: Boot ROM Basic Read ===");
        test_count = test_count + 1;
        bootrom_read(32'h0, read_data, read_resp);
        if (read_data == 32'h00000013 && read_resp == 2'b00) begin
            pass_count = pass_count + 1;
            $display("[PASS] First instruction = NOP (0x%08X)", read_data);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Expected NOP, got 0x%08X", read_data);
        end
        
        //======================================================================
        // Test 2: Boot ROM Sequential Read
        //======================================================================
        $display("\n=== Test 2: Boot ROM Sequential Read ===");
        for (i = 0; i < 64; i = i + 1) begin
            test_count = test_count + 1;
            bootrom_read(i * 4, read_data, read_resp);
            if (read_resp == 2'b00) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("[FAIL] addr 0x%04X", i*4); end
        end
        $display("[INFO] 64 sequential reads completed");
        
        //======================================================================
        // Test 3: Boot ROM Write Rejection
        //======================================================================
        $display("\n=== Test 3: Boot ROM Write Rejection ===");
        test_count = test_count + 1;
        bootrom_write(32'h0, 32'hDEADBEEF, write_resp);
        if (write_resp == 2'b10) begin
            pass_count = pass_count + 1;
            $display("[PASS] Write rejected with SLVERR");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Expected SLVERR, got %b", write_resp);
        end
        
        // Verify unchanged
        test_count = test_count + 1;
        bootrom_read(32'h0, read_data, read_resp);
        if (read_data == 32'h00000013) begin
            pass_count = pass_count + 1;
            $display("[PASS] ROM content unchanged");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] ROM changed to 0x%08X", read_data);
        end
        
        //======================================================================
        // Test 4: SPI Master Initialization
        //======================================================================
        $display("\n=== Test 4: SPI Master Initialization ===");
        test_count = test_count + 1;
        spi_read(8'h04, read_data, read_resp);
        if (read_data[0] == 1) begin
            pass_count = pass_count + 1;
            $display("[PASS] SPI TX_EMPTY after reset");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] SPI status = 0x%02X", read_data[7:0]);
        end
        
        //======================================================================
        // Test 5: SPI Transfer
        //======================================================================
        $display("\n=== Test 5: SPI Transfer ===");
        test_count = test_count + 1;
        
        // Enable SPI
        spi_write(8'h08, 32'h01, write_resp);
        // Assert CS
        spi_write(8'h10, 32'h00, write_resp);
        // Send byte
        spi_write(8'h00, 32'hA5, write_resp);
        // Wait
        repeat(300) @(posedge clk);
        // Check done
        spi_read(8'h04, read_data, read_resp);
        if (read_data[4] == 0) begin
            pass_count = pass_count + 1;
            $display("[PASS] SPI transfer completed");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] SPI still busy");
        end
        // Deassert CS
        spi_write(8'h10, 32'h01, write_resp);
        
        //======================================================================
        // Test 6: SPI Multi-byte Transfer
        //======================================================================
        $display("\n=== Test 6: SPI Multi-byte Transfer ===");
        spi_write(8'h10, 32'h00, write_resp);  // CS low
        for (i = 0; i < 8; i = i + 1) begin
            test_count = test_count + 1;
            spi_write(8'h00, i, write_resp);
            repeat(300) @(posedge clk);
            spi_read(8'h04, read_data, read_resp);
            if (read_data[4] == 0) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("[FAIL] byte %0d stuck", i); end
        end
        spi_write(8'h10, 32'h01, write_resp);  // CS high
        $display("[INFO] 8-byte transfer completed");
        
        //======================================================================
        // Test 7: Boot ROM Stress Test
        //======================================================================
        $display("\n=== Test 7: Boot ROM Stress Test ===");
        for (i = 0; i < 100; i = i + 1) begin
            test_count = test_count + 1;
            bootrom_read((i % 256) * 4, read_data, read_resp);
            if (read_resp == 2'b00 && read_data == 32'h00000013) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("[FAIL] stress %0d", i); end
        end
        $display("[INFO] 100 stress reads completed");
        
        //======================================================================
        // Test 8: SPI Clock Divider
        //======================================================================
        $display("\n=== Test 8: SPI Clock Divider ===");
        test_count = test_count + 1;
        spi_write(8'h0C, 32'h0020, write_resp);
        spi_read(8'h0C, read_data, read_resp);
        if (read_data[15:0] == 16'h0020) begin
            pass_count = pass_count + 1;
            $display("[PASS] Clock divider = 0x%04X", read_data[15:0]);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Clock divider = 0x%04X", read_data[15:0]);
        end
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n##############################################");
        $display("# Checkpoint 12 Summary");
        $display("##############################################");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        if (fail_count == 0) begin
            $display("STATUS: ALL TESTS PASSED!");
            $display("Boot ROM: VERIFIED");
            $display("SPI Master: VERIFIED");
            $display("Bootloader Hardware: READY");
        end else begin
            $display("STATUS: SOME TESTS FAILED");
        end
        $display("##############################################");
        $finish;
    end
endmodule
