//==============================================================================
// Simple Real CPI Benchmark - Debug Version
// 简化版本，用于调试 CPU 核心执行
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_simple;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter MEM_SIZE = 65536;
    parameter MEM_BASE = 32'h8000_0000;
    
    reg clk;
    reg rst_n;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Performance counters
    integer cycle_count;
    integer instr_count;
    real cpi;
    
    //=========================================================
    // AXI Signals
    //=========================================================
    wire        m_axi_ibus_arvalid;
    reg         m_axi_ibus_arready;
    wire [31:0] m_axi_ibus_araddr;
    wire [2:0]  m_axi_ibus_arprot;
    reg         m_axi_ibus_rvalid;
    wire        m_axi_ibus_rready;
    reg  [31:0] m_axi_ibus_rdata;
    reg  [1:0]  m_axi_ibus_rresp;
    
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
    
    initial begin
        ext_irq = 0;
        timer_irq = 0;
        sw_irq = 0;
    end

    //=========================================================
    // Memory
    //=========================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    integer i;
    
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 8'h00;
        
        // Simple test program at 0x8000_0000
        // addi x1, x0, 10
        memory[0] = 8'h93; memory[1] = 8'h00; memory[2] = 8'ha0; memory[3] = 8'h00;
        // addi x2, x0, 20
        memory[4] = 8'h13; memory[5] = 8'h01; memory[6] = 8'h40; memory[7] = 8'h01;
        // add x3, x1, x2
        memory[8] = 8'hb3; memory[9] = 8'h81; memory[10] = 8'h20; memory[11] = 8'h00;
        // addi x4, x0, 30
        memory[12] = 8'h13; memory[13] = 8'h02; memory[14] = 8'he0; memory[15] = 8'h01;
        // add x5, x3, x4
        memory[16] = 8'hb3; memory[17] = 8'h82; memory[18] = 8'h41; memory[19] = 8'h00;
        // NOP (addi x0, x0, 0)
        memory[20] = 8'h13; memory[21] = 8'h00; memory[22] = 8'h00; memory[23] = 8'h00;
        // NOP
        memory[24] = 8'h13; memory[25] = 8'h00; memory[26] = 8'h00; memory[27] = 8'h00;
        // NOP
        memory[28] = 8'h13; memory[29] = 8'h00; memory[30] = 8'h00; memory[31] = 8'h00;
        // NOP
        memory[32] = 8'h13; memory[33] = 8'h00; memory[34] = 8'h00; memory[35] = 8'h00;
        // NOP
        memory[36] = 8'h13; memory[37] = 8'h00; memory[38] = 8'h00; memory[39] = 8'h00;
    end

    //=========================================================
    // Simple AXI I-Bus Slave (1-cycle response)
    //=========================================================
    reg [1:0] ibus_state;
    reg [31:0] ibus_addr_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibus_state <= 0;
            m_axi_ibus_arready <= 1'b1;
            m_axi_ibus_rvalid <= 1'b0;
            m_axi_ibus_rdata <= 32'd0;
            m_axi_ibus_rresp <= 2'b00;
        end else begin
            case (ibus_state)
                0: begin
                    m_axi_ibus_arready <= 1'b1;
                    if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                        ibus_addr_reg <= m_axi_ibus_araddr;
                        m_axi_ibus_arready <= 1'b0;
                        ibus_state <= 1;
                    end
                end
                1: begin
                    m_axi_ibus_rvalid <= 1'b1;
                    if (ibus_addr_reg >= MEM_BASE && ibus_addr_reg < MEM_BASE + MEM_SIZE) begin
                        m_axi_ibus_rdata <= {
                            memory[ibus_addr_reg - MEM_BASE + 3],
                            memory[ibus_addr_reg - MEM_BASE + 2],
                            memory[ibus_addr_reg - MEM_BASE + 1],
                            memory[ibus_addr_reg - MEM_BASE + 0]
                        };
                        m_axi_ibus_rresp <= 2'b00;
                    end else begin
                        m_axi_ibus_rdata <= 32'h00000013; // NOP
                        m_axi_ibus_rresp <= 2'b00;
                    end
                    
                    if (m_axi_ibus_rvalid && m_axi_ibus_rready) begin
                        m_axi_ibus_rvalid <= 1'b0;
                        ibus_state <= 0;
                    end
                end
            endcase
        end
    end

    //=========================================================
    // Simple AXI D-Bus Slave
    //=========================================================
    reg [2:0] dbus_state;
    reg [31:0] dbus_addr_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbus_state <= 0;
            m_axi_dbus_arready <= 1'b1;
            m_axi_dbus_awready <= 1'b1;
            m_axi_dbus_wready <= 1'b0;
            m_axi_dbus_rvalid <= 1'b0;
            m_axi_dbus_bvalid <= 1'b0;
            m_axi_dbus_rdata <= 32'd0;
            m_axi_dbus_rresp <= 2'b00;
            m_axi_dbus_bresp <= 2'b00;
        end else begin
            case (dbus_state)
                0: begin // IDLE
                    m_axi_dbus_arready <= 1'b1;
                    m_axi_dbus_awready <= 1'b1;
                    
                    if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                        dbus_addr_reg <= m_axi_dbus_araddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        dbus_state <= 1; // READ
                    end else if (m_axi_dbus_awvalid && m_axi_dbus_awready) begin
                        dbus_addr_reg <= m_axi_dbus_awaddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        m_axi_dbus_wready <= 1'b1;
                        dbus_state <= 2; // WRITE DATA
                    end
                end
                
                1: begin // READ DATA
                    m_axi_dbus_rvalid <= 1'b1;
                    if (dbus_addr_reg >= MEM_BASE && dbus_addr_reg < MEM_BASE + MEM_SIZE) begin
                        m_axi_dbus_rdata <= {
                            memory[dbus_addr_reg - MEM_BASE + 3],
                            memory[dbus_addr_reg - MEM_BASE + 2],
                            memory[dbus_addr_reg - MEM_BASE + 1],
                            memory[dbus_addr_reg - MEM_BASE + 0]
                        };
                        m_axi_dbus_rresp <= 2'b00;
                    end else begin
                        m_axi_dbus_rdata <= 32'd0;
                        m_axi_dbus_rresp <= 2'b00;
                    end
                    
                    if (m_axi_dbus_rvalid && m_axi_dbus_rready) begin
                        m_axi_dbus_rvalid <= 1'b0;
                        dbus_state <= 0;
                    end
                end
                
                2: begin // WRITE DATA
                    if (m_axi_dbus_wvalid && m_axi_dbus_wready) begin
                        m_axi_dbus_wready <= 1'b0;
                        
                        if (dbus_addr_reg >= MEM_BASE && dbus_addr_reg < MEM_BASE + MEM_SIZE) begin
                            if (m_axi_dbus_wstrb[0]) memory[dbus_addr_reg - MEM_BASE + 0] <= m_axi_dbus_wdata[7:0];
                            if (m_axi_dbus_wstrb[1]) memory[dbus_addr_reg - MEM_BASE + 1] <= m_axi_dbus_wdata[15:8];
                            if (m_axi_dbus_wstrb[2]) memory[dbus_addr_reg - MEM_BASE + 2] <= m_axi_dbus_wdata[23:16];
                            if (m_axi_dbus_wstrb[3]) memory[dbus_addr_reg - MEM_BASE + 3] <= m_axi_dbus_wdata[31:24];
                        end
                        m_axi_dbus_bresp <= 2'b00;
                        dbus_state <= 3; // WRITE RESP
                    end
                end
                
                3: begin // WRITE RESP
                    m_axi_dbus_bvalid <= 1'b1;
                    if (m_axi_dbus_bvalid && m_axi_dbus_bready) begin
                        m_axi_dbus_bvalid <= 1'b0;
                        dbus_state <= 0;
                    end
                end
            endcase
        end
    end

    //=========================================================
    // DUT
    //=========================================================
    cpu_core_top #(
        .XLEN(XLEN),
        .RESET_VECTOR(MEM_BASE)
    ) u_cpu (
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

    //=========================================================
    // Monitor ROB Commit
    //=========================================================
    wire rob_commit_valid = u_cpu.rob_commit_valid;
    wire rob_commit_ready = u_cpu.rob_commit_ready;
    wire [31:0] rob_commit_pc = u_cpu.rob_commit_pc;
    
    // Debug: monitor IF stage
    wire if_valid = u_cpu.if_id_valid;
    wire [31:0] if_pc = u_cpu.if_id_pc;
    wire [31:0] if_instr = u_cpu.if_id_instr;
    
    // Debug: monitor ID stage
    wire id_valid = u_cpu.id_rn_valid;
    
    // Count instructions
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;
            if (rob_commit_valid && rob_commit_ready) begin
                instr_count <= instr_count + 1;
                $display("[%0t] COMMIT: PC=%h, instr_count=%0d", $time, rob_commit_pc, instr_count + 1);
            end
        end
    end
    
    // Debug: print fetch activity
    always @(posedge clk) begin
        if (rst_n && m_axi_ibus_arvalid && m_axi_ibus_arready) begin
            $display("[%0t] FETCH REQ: addr=%h", $time, m_axi_ibus_araddr);
        end
        if (rst_n && m_axi_ibus_rvalid && m_axi_ibus_rready) begin
            $display("[%0t] FETCH RSP: data=%h", $time, m_axi_ibus_rdata);
        end
    end

    //=========================================================
    // Main Test
    //=========================================================
    initial begin
        $dumpfile("sim/waves/cpi_simple.vcd");
        $dumpvars(0, tb_cpi_simple);
        
        $display("============================================================");
        $display("       Simple CPI Benchmark - Debug Version");
        $display("============================================================");
        
        rst_n = 0;
        cycle_count = 0;
        instr_count = 0;
        
        #(CLK_PERIOD * 10);
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        
        // Run for 500 cycles
        repeat(500) @(posedge clk);
        
        $display("");
        $display("============================================================");
        $display("Results:");
        $display("  Cycles:       %0d", cycle_count);
        $display("  Instructions: %0d", instr_count);
        if (instr_count > 0) begin
            cpi = cycle_count * 1.0 / instr_count;
            $display("  CPI:          %0.3f", cpi);
        end else begin
            $display("  CPI:          N/A (no instructions retired)");
        end
        $display("============================================================");
        
        #100;
        $finish;
    end

endmodule
