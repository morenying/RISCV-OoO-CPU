`timescale 1ns/1ps

module tb_bootrom_minimal;
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
    
    bootrom #(
        .DEPTH(16),
        .ADDR_WIDTH(6),
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
    
    initial clk = 0;
    always #10 clk = ~clk;
    
    initial begin
        $display("=== Minimal Boot ROM Test ===");
        
        // Init
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
        
        #200;
        rst_n = 1;
        #100;
        
        $display("After reset: arready=%b", axi_arready);
        
        // Simple read
        @(posedge clk);
        axi_arvalid = 1;
        axi_araddr = 0;
        axi_rready = 1;
        
        @(posedge clk);
        $display("Cycle 1: arready=%b, rvalid=%b", axi_arready, axi_rvalid);
        axi_arvalid = 0;
        
        @(posedge clk);
        $display("Cycle 2: arready=%b, rvalid=%b", axi_arready, axi_rvalid);
        
        @(posedge clk);
        $display("Cycle 3: arready=%b, rvalid=%b, rdata=0x%08X", axi_arready, axi_rvalid, axi_rdata);
        
        @(posedge clk);
        $display("Cycle 4: arready=%b, rvalid=%b", axi_arready, axi_rvalid);
        axi_rready = 0;
        
        #100;
        $display("=== Test Done ===");
        $finish;
    end
endmodule
