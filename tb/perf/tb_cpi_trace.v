//==============================================================================
// CPI Trace Test - Debug version with detailed pipeline tracing
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_trace;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter MEM_SIZE = 4096;
    parameter MEM_BASE = 32'h8000_0000;
    
    reg clk;
    reg rst_n;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    integer cycle_count;
    
    // AXI I-Bus
    wire        m_axi_ibus_arvalid;
    reg         m_axi_ibus_arready;
    wire [31:0] m_axi_ibus_araddr;
    wire [2:0]  m_axi_ibus_arprot;
    reg         m_axi_ibus_rvalid;
    wire        m_axi_ibus_rready;
    reg  [31:0] m_axi_ibus_rdata;
    reg  [1:0]  m_axi_ibus_rresp;
    
    // AXI D-Bus
    wire        m_axi_dbus_awvalid;
    reg         m_axi_dbus_awready;
    wire [31:0] m_axi_dbus_awaddr;
    wire [2:0]  m_axi_dbus_awprot;
    wire        m_axi_dbus_wvalid;
    reg         m_axi_dbus_wready;
    wire [31:0] m_axi_dbus_wdata;
    wire [3:0]  m_axi_dbus_wstrb;
    reg         m_axi_dbus_bvalid;
    wire        m_axi_dbus_bready;
    reg  [1:0]  m_axi_dbus_bresp;
    wire        m_axi_dbus_arvalid;
    reg         m_axi_dbus_arready;
    wire [31:0] m_axi_dbus_araddr;
    wire [2:0]  m_axi_dbus_arprot;
    reg         m_axi_dbus_rvalid;
    wire        m_axi_dbus_rready;
    reg  [31:0] m_axi_dbus_rdata;
    reg  [1:0]  m_axi_dbus_rresp;
    
    reg ext_irq, timer_irq, sw_irq;
    
    // Memory
    reg [31:0] memory [0:MEM_SIZE/4-1];
    
    // AXI I-Bus - immediate response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_ibus_arready <= 1'b1;
            m_axi_ibus_rvalid <= 1'b0;
            m_axi_ibus_rdata <= 32'h00000013;
            m_axi_ibus_rresp <= 2'b00;
        end else begin
            if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                m_axi_ibus_rvalid <= 1'b1;
                if (m_axi_ibus_araddr >= MEM_BASE && m_axi_ibus_araddr < MEM_BASE + MEM_SIZE)
                    m_axi_ibus_rdata <= memory[(m_axi_ibus_araddr - MEM_BASE) >> 2];
                else
                    m_axi_ibus_rdata <= 32'h00000013;
            end else if (m_axi_ibus_rvalid && m_axi_ibus_rready) begin
                m_axi_ibus_rvalid <= 1'b0;
            end
        end
    end
    
    // AXI D-Bus
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_dbus_arready <= 1'b1;
            m_axi_dbus_awready <= 1'b1;
            m_axi_dbus_wready <= 1'b1;
            m_axi_dbus_rvalid <= 1'b0;
            m_axi_dbus_bvalid <= 1'b0;
            m_axi_dbus_rdata <= 32'd0;
            m_axi_dbus_rresp <= 2'b00;
            m_axi_dbus_bresp <= 2'b00;
        end else begin
            if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                m_axi_dbus_rvalid <= 1'b1;
                m_axi_dbus_rdata <= 32'd0;
            end else if (m_axi_dbus_rvalid && m_axi_dbus_rready) begin
                m_axi_dbus_rvalid <= 1'b0;
            end
            
            if (m_axi_dbus_wvalid && m_axi_dbus_wready) begin
                m_axi_dbus_bvalid <= 1'b1;
            end else if (m_axi_dbus_bvalid && m_axi_dbus_bready) begin
                m_axi_dbus_bvalid <= 1'b0;
            end
        end
    end
    
    // DUT
    cpu_core_top #(
        .XLEN(XLEN),
        .RESET_VECTOR(MEM_BASE)
    ) u_cpu_core (
        .clk(clk), .rst_n(rst_n),
        .m_axi_ibus_arvalid(m_axi_ibus_arvalid), .m_axi_ibus_arready(m_axi_ibus_arready),
        .m_axi_ibus_araddr(m_axi_ibus_araddr), .m_axi_ibus_arprot(m_axi_ibus_arprot),
        .m_axi_ibus_rvalid(m_axi_ibus_rvalid), .m_axi_ibus_rready(m_axi_ibus_rready),
        .m_axi_ibus_rdata(m_axi_ibus_rdata), .m_axi_ibus_rresp(m_axi_ibus_rresp),
        .m_axi_dbus_awvalid(m_axi_dbus_awvalid), .m_axi_dbus_awready(m_axi_dbus_awready),
        .m_axi_dbus_awaddr(m_axi_dbus_awaddr), .m_axi_dbus_awprot(m_axi_dbus_awprot),
        .m_axi_dbus_wvalid(m_axi_dbus_wvalid), .m_axi_dbus_wready(m_axi_dbus_wready),
        .m_axi_dbus_wdata(m_axi_dbus_wdata), .m_axi_dbus_wstrb(m_axi_dbus_wstrb),
        .m_axi_dbus_bvalid(m_axi_dbus_bvalid), .m_axi_dbus_bready(m_axi_dbus_bready),
        .m_axi_dbus_bresp(m_axi_dbus_bresp),
        .m_axi_dbus_arvalid(m_axi_dbus_arvalid), .m_axi_dbus_arready(m_axi_dbus_arready),
        .m_axi_dbus_araddr(m_axi_dbus_araddr), .m_axi_dbus_arprot(m_axi_dbus_arprot),
        .m_axi_dbus_rvalid(m_axi_dbus_rvalid), .m_axi_dbus_rready(m_axi_dbus_rready),
        .m_axi_dbus_rdata(m_axi_dbus_rdata), .m_axi_dbus_rresp(m_axi_dbus_rresp),
        .ext_irq_i(ext_irq), .timer_irq_i(timer_irq), .sw_irq_i(sw_irq)
    );
    
    // Cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // Trace pipeline every cycle
    always @(posedge clk) begin
        if (rst_n && cycle_count <= 30) begin
            $display("[%0d] IF->ID: v=%b pc=%h instr=%h | ID->RN: v=%b | RN->IS: v=%b",
                cycle_count,
                u_cpu_core.if_id_valid, u_cpu_core.if_id_pc, u_cpu_core.if_id_instr,
                u_cpu_core.id_rn_valid,
                u_cpu_core.rn_is_valid);
            $display("     Stalls: if=%b id=%b rn=%b | rob_rdy=%b fl_empty=%b is_stall=%b",
                u_cpu_core.stall_if, u_cpu_core.stall_id, u_cpu_core.stall_rn,
                u_cpu_core.rob_alloc_ready, u_cpu_core.fl_empty, u_cpu_core.is_stall_out);
            $display("     ICache: req_v=%b resp_v=%b state=%b | flush_id=%b flush_rn=%b",
                u_cpu_core.if_icache_req_valid,
                u_cpu_core.if_icache_resp_valid,
                u_cpu_core.u_icache.state,
                u_cpu_core.flush_id, u_cpu_core.flush_rn);
        end
    end
    
    integer i;
    initial begin
        $display("=== CPI Trace Test ===");
        
        rst_n = 0;
        ext_irq = 0; timer_irq = 0; sw_irq = 0;
        
        // Clear memory
        for (i = 0; i < MEM_SIZE/4; i = i + 1)
            memory[i] = 32'h00000013; // NOP
        
        // Simple program: 3 ADDIs
        memory[0] = 32'h00100093; // addi x1, x0, 1
        memory[1] = 32'h00200113; // addi x2, x0, 2
        memory[2] = 32'h00300193; // addi x3, x0, 3
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        
        // Run for 20 cycles
        #(CLK_PERIOD * 20);
        
        $display("=== Test Complete ===");
        $finish;
    end

endmodule
