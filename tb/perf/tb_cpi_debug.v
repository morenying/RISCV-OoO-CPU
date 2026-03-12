//==============================================================================
// Debug CPI Benchmark - 简化版本用于调试
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_debug;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter MEM_SIZE = 65536;
    parameter MEM_BASE = 32'h8000_0000;
    
    reg clk;
    reg rst_n;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
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
    reg [7:0] memory [0:MEM_SIZE-1];
    integer i;
    
    // Simple AXI I-Bus responder
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_ibus_arready <= 1'b1;
            m_axi_ibus_rvalid <= 1'b0;
            m_axi_ibus_rdata <= 32'd0;
            m_axi_ibus_rresp <= 2'b00;
        end else begin
            // Default: ready to accept
            m_axi_ibus_arready <= 1'b1;
            
            // If we accepted a request, provide response next cycle
            if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                m_axi_ibus_rvalid <= 1'b1;
                if (m_axi_ibus_araddr >= MEM_BASE && m_axi_ibus_araddr < MEM_BASE + MEM_SIZE) begin
                    m_axi_ibus_rdata <= {
                        memory[m_axi_ibus_araddr - MEM_BASE + 3],
                        memory[m_axi_ibus_araddr - MEM_BASE + 2],
                        memory[m_axi_ibus_araddr - MEM_BASE + 1],
                        memory[m_axi_ibus_araddr - MEM_BASE + 0]
                    };
                end else begin
                    m_axi_ibus_rdata <= 32'h00000013; // NOP
                end
                m_axi_ibus_rresp <= 2'b00;
            end else if (m_axi_ibus_rvalid && m_axi_ibus_rready) begin
                m_axi_ibus_rvalid <= 1'b0;
            end
        end
    end
    
    // Simple AXI D-Bus responder
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
            m_axi_dbus_arready <= 1'b1;
            m_axi_dbus_awready <= 1'b1;
            m_axi_dbus_wready <= 1'b1;
            
            // Read response
            if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                m_axi_dbus_rvalid <= 1'b1;
                m_axi_dbus_rdata <= 32'd0;
                m_axi_dbus_rresp <= 2'b00;
            end else if (m_axi_dbus_rvalid && m_axi_dbus_rready) begin
                m_axi_dbus_rvalid <= 1'b0;
            end
            
            // Write response
            if (m_axi_dbus_wvalid && m_axi_dbus_wready) begin
                m_axi_dbus_bvalid <= 1'b1;
                m_axi_dbus_bresp <= 2'b00;
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
        .clk                    (clk),
        .rst_n                  (rst_n),
        .m_axi_ibus_arvalid     (m_axi_ibus_arvalid),
        .m_axi_ibus_arready     (m_axi_ibus_arready),
        .m_axi_ibus_araddr      (m_axi_ibus_araddr),
        .m_axi_ibus_arprot      (m_axi_ibus_arprot),
        .m_axi_ibus_rvalid      (m_axi_ibus_rvalid),
        .m_axi_ibus_rready      (m_axi_ibus_rready),
        .m_axi_ibus_rdata       (m_axi_ibus_rdata),
        .m_axi_ibus_rresp       (m_axi_ibus_rresp),
        .m_axi_dbus_awvalid     (m_axi_dbus_awvalid),
        .m_axi_dbus_awready     (m_axi_dbus_awready),
        .m_axi_dbus_awaddr      (m_axi_dbus_awaddr),
        .m_axi_dbus_awprot      (m_axi_dbus_awprot),
        .m_axi_dbus_wvalid      (m_axi_dbus_wvalid),
        .m_axi_dbus_wready      (m_axi_dbus_wready),
        .m_axi_dbus_wdata       (m_axi_dbus_wdata),
        .m_axi_dbus_wstrb       (m_axi_dbus_wstrb),
        .m_axi_dbus_bvalid      (m_axi_dbus_bvalid),
        .m_axi_dbus_bready      (m_axi_dbus_bready),
        .m_axi_dbus_bresp       (m_axi_dbus_bresp),
        .m_axi_dbus_arvalid     (m_axi_dbus_arvalid),
        .m_axi_dbus_arready     (m_axi_dbus_arready),
        .m_axi_dbus_araddr      (m_axi_dbus_araddr),
        .m_axi_dbus_arprot      (m_axi_dbus_arprot),
        .m_axi_dbus_rvalid      (m_axi_dbus_rvalid),
        .m_axi_dbus_rready      (m_axi_dbus_rready),
        .m_axi_dbus_rdata       (m_axi_dbus_rdata),
        .m_axi_dbus_rresp       (m_axi_dbus_rresp),
        .ext_irq_i              (ext_irq),
        .timer_irq_i            (timer_irq),
        .sw_irq_i               (sw_irq)
    );
    
    // Monitor internal signals
    wire stall_if = u_cpu_core.stall_if;
    wire stall_id = u_cpu_core.stall_id;
    wire stall_rn = u_cpu_core.stall_rn;
    wire rob_alloc_ready = u_cpu_core.rob_alloc_ready;
    wire fl_alloc_valid = u_cpu_core.fl_alloc_valid;
    wire is_stall_out = u_cpu_core.is_stall_out;
    wire icache_req_valid = u_cpu_core.if_icache_req_valid;
    wire icache_req_ready = u_cpu_core.if_icache_req_ready;
    wire icache_resp_valid = u_cpu_core.if_icache_resp_valid;
    wire [1:0] icache_state = u_cpu_core.u_icache.state;
    wire [1:0] if_state = u_cpu_core.u_if_stage.state;
    wire [31:0] if_pc = u_cpu_core.u_if_stage.pc_reg;
    wire if_id_valid = u_cpu_core.if_id_valid;
    
    initial begin
        $display("=== CPI Debug Test ===");
        
        // Initialize
        rst_n = 0;
        ext_irq = 0;
        timer_irq = 0;
        sw_irq = 0;
        
        // Clear memory and load simple program
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 8'h00;
        
        // Simple program: addi x1, x0, 1; addi x2, x0, 2; ebreak
        // 0x80000000: addi x1, x0, 1  -> 0x00100093
        memory[0] = 8'h93; memory[1] = 8'h00; memory[2] = 8'h10; memory[3] = 8'h00;
        // 0x80000004: addi x2, x0, 2  -> 0x00200113
        memory[4] = 8'h13; memory[5] = 8'h01; memory[6] = 8'h20; memory[7] = 8'h00;
        // 0x80000008: ebreak          -> 0x00100073
        memory[8] = 8'h73; memory[9] = 8'h00; memory[10] = 8'h10; memory[11] = 8'h00;
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        
        // Run for 20 cycles then exit
        repeat(20) @(posedge clk);
        
        $display("=== Test Complete ===");
        $display("Final PC: %h", if_pc);
        $display("IF valid: %b", if_id_valid);
        $finish;
    end
    
    // Disable VCD for faster simulation
    // initial begin
    //     $dumpfile("sim/cpi_debug.vcd");
    //     $dumpvars(0, tb_cpi_debug);
    // end

endmodule
