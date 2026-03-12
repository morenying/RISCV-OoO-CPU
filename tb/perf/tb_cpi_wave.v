//==============================================================================
// CPI Wave Test - Generate VCD for debugging
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_wave;
    parameter CLK_PERIOD = 10;
    parameter MEM_BASE = 32'h8000_0000;
    
    reg clk, rst_n;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    reg [31:0] memory [0:255];
    
    // AXI I-Bus
    wire arvalid;
    reg  arready;
    wire [31:0] araddr;
    reg  rvalid;
    wire rready;
    reg  [31:0] rdata;
    
    // AXI D-Bus (minimal)
    wire dbus_awvalid, dbus_wvalid, dbus_arvalid;
    reg  dbus_awready = 1, dbus_wready = 1, dbus_arready = 1;
    reg  dbus_bvalid = 0, dbus_rvalid = 0;
    wire dbus_bready, dbus_rready;
    
    // I-Bus response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready <= 1;
            rvalid <= 0;
            rdata <= 32'h13;
        end else begin
            if (arvalid && arready) begin
                rvalid <= 1;
                if (araddr >= MEM_BASE)
                    rdata <= memory[(araddr - MEM_BASE) >> 2];
                else
                    rdata <= 32'h13;
            end else if (rvalid && rready) begin
                rvalid <= 0;
            end
        end
    end

    
    // DUT
    cpu_core_top #(.XLEN(32), .RESET_VECTOR(MEM_BASE)) u_cpu (
        .clk(clk), .rst_n(rst_n),
        .m_axi_ibus_arvalid(arvalid), .m_axi_ibus_arready(arready),
        .m_axi_ibus_araddr(araddr), .m_axi_ibus_arprot(),
        .m_axi_ibus_rvalid(rvalid), .m_axi_ibus_rready(rready),
        .m_axi_ibus_rdata(rdata), .m_axi_ibus_rresp(2'b00),
        .m_axi_dbus_awvalid(dbus_awvalid), .m_axi_dbus_awready(dbus_awready),
        .m_axi_dbus_awaddr(), .m_axi_dbus_awprot(),
        .m_axi_dbus_wvalid(dbus_wvalid), .m_axi_dbus_wready(dbus_wready),
        .m_axi_dbus_wdata(), .m_axi_dbus_wstrb(),
        .m_axi_dbus_bvalid(dbus_bvalid), .m_axi_dbus_bready(dbus_bready),
        .m_axi_dbus_bresp(2'b00),
        .m_axi_dbus_arvalid(dbus_arvalid), .m_axi_dbus_arready(dbus_arready),
        .m_axi_dbus_araddr(), .m_axi_dbus_arprot(),
        .m_axi_dbus_rvalid(dbus_rvalid), .m_axi_dbus_rready(dbus_rready),
        .m_axi_dbus_rdata(32'd0), .m_axi_dbus_rresp(2'b00),
        .ext_irq_i(1'b0), .timer_irq_i(1'b0), .sw_irq_i(1'b0)
    );
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cycle_count <= 0;
        else cycle_count <= cycle_count + 1;
    end
    
    integer i;
    initial begin
        $dumpfile("sim/cpi_wave.vcd");
        $dumpvars(0, tb_cpi_wave);
        
        $display("=== CPI Wave Test ===");
        rst_n = 0;
        for (i = 0; i < 256; i = i + 1) memory[i] = 32'h13;
        memory[0] = 32'h00100093; // addi x1, x0, 1
        memory[1] = 32'h00200113; // addi x2, x0, 2
        memory[2] = 32'h00300193; // addi x3, x0, 3
        
        #(CLK_PERIOD * 3);
        rst_n = 1;
        
        // Run for 50 cycles
        #(CLK_PERIOD * 50);
        
        $display("=== Done ===");
        $finish;
    end
endmodule