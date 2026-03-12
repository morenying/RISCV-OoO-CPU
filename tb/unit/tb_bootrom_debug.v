`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Boot ROM Debug Test - Minimal AXI4-Lite Read Test
//////////////////////////////////////////////////////////////////////////////

module tb_bootrom_debug;
    parameter DEPTH = 16;
    parameter ADDR_WIDTH = 6;
    
    reg clk;
    reg rst_n;
    
    reg         axi_arvalid;
    wire        axi_arready;
    reg  [31:0] axi_araddr;
    
    wire        axi_rvalid;
    reg         axi_rready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [31:0] axi_awaddr;
    
    reg         axi_wvalid;
    wire        axi_wready;
    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    
    wire        axi_bvalid;
    reg         axi_bready;
    wire [1:0]  axi_bresp;
    
    // Timeout counter
    integer timeout_cnt;
    
    bootrom #(
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE("none")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_araddr(axi_araddr),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_awaddr(axi_awaddr),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_bresp(axi_bresp)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    initial begin
        $display("=== Boot ROM Debug Test ===");
        $display("Testing AXI4-Lite read protocol");
        
        // Initialize all signals
        rst_n = 0;
        axi_arvalid = 0;
        axi_rready = 0;
        axi_awvalid = 0;
        axi_wvalid = 0;
        axi_bready = 0;
        axi_araddr = 0;
        axi_awaddr = 0;
        axi_wdata = 0;
        axi_wstrb = 0;
        timeout_cnt = 0;
        
        // Reset sequence
        repeat(10) @(posedge clk);
        $display("[%0t] Releasing reset...", $time);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // Check initial state
        $display("[%0t] Initial state: arready=%b, rvalid=%b", $time, axi_arready, axi_rvalid);
        
        if (!axi_arready) begin
            $display("[ERROR] arready should be 1 after reset!");
            $finish;
        end
        
        //======================================================================
        // AXI4-Lite Read Transaction
        //======================================================================
        $display("\n[%0t] Starting AXI read transaction to address 0x0000", $time);
        
        // Phase 1: Address phase
        @(posedge clk);
        axi_arvalid = 1;
        axi_araddr = 32'h00000000;
        axi_rready = 1;  // Ready to accept data immediately
        
        // Wait for address handshake (arvalid && arready)
        @(posedge clk);
        timeout_cnt = 0;
        while (!(axi_arvalid && axi_arready)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("[ERROR] Timeout waiting for address handshake!");
                $finish;
            end
        end
        $display("[%0t] Address handshake complete", $time);
        
        // Deassert arvalid after handshake
        @(posedge clk);
        axi_arvalid = 0;
        
        // Phase 2: Data phase - wait for rvalid
        $display("[%0t] Waiting for data (rvalid)...", $time);
        timeout_cnt = 0;
        while (!axi_rvalid) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
            $display("[%0t] Cycle %0d: rvalid=%b", $time, timeout_cnt, axi_rvalid);
            if (timeout_cnt > 20) begin
                $display("[ERROR] Timeout waiting for rvalid!");
                $finish;
            end
        end
        
        // Data handshake (rvalid && rready)
        $display("[%0t] Data handshake: data=0x%08X, resp=%b", $time, axi_rdata, axi_rresp);
        
        // Verify data - should be NOP instruction (0x00000013)
        if (axi_rdata == 32'h00000013) begin
            $display("[PASS] Read correct NOP instruction");
        end else begin
            $display("[FAIL] Expected 0x00000013, got 0x%08X", axi_rdata);
        end
        
        if (axi_rresp == 2'b00) begin
            $display("[PASS] Response is OKAY");
        end else begin
            $display("[FAIL] Expected OKAY (00), got %b", axi_rresp);
        end
        
        @(posedge clk);
        axi_rready = 0;
        
        // Wait a few cycles
        repeat(5) @(posedge clk);
        
        // Check that arready is back to 1
        if (axi_arready) begin
            $display("[PASS] arready returned to 1 after transaction");
        end else begin
            $display("[FAIL] arready should be 1 after transaction complete");
        end
        
        $display("\n=== Debug Test Complete ===");
        $finish;
    end
    
    // Watchdog timer
    initial begin
        #10000;
        $display("[ERROR] Global timeout - test took too long!");
        $finish;
    end
endmodule
