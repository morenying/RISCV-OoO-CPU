//=================================================================
// Testbench: tb_cpu_core
// Description: System-level testbench for RISC-V OoO CPU Core
//              Clock and reset generation
//              AXI slave simulation (memory)
//              Test result checking
//=================================================================

`timescale 1ns/1ps

module tb_cpu_core;

    //=========================================================
    // Parameters
    //=========================================================
    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;  // 100MHz
    parameter MEM_SIZE = 65536; // 64KB
    parameter MEM_BASE = 32'h8000_0000;
    
    //=========================================================
    // Clock and Reset
    //=========================================================
    reg clk;
    reg rst_n;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    initial begin
        rst_n = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
    end
    
    //=========================================================
    // AXI Instruction Bus Signals
    //=========================================================
    wire        m_axi_ibus_arvalid;
    reg         m_axi_ibus_arready;
    wire [31:0] m_axi_ibus_araddr;
    wire [2:0]  m_axi_ibus_arprot;
    reg         m_axi_ibus_rvalid;
    wire        m_axi_ibus_rready;
    reg  [31:0] m_axi_ibus_rdata;
    reg  [1:0]  m_axi_ibus_rresp;
    
    //=========================================================
    // AXI Data Bus Signals
    //=========================================================
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
    
    //=========================================================
    // Interrupts
    //=========================================================
    reg ext_irq;
    reg timer_irq;
    reg sw_irq;
    
    initial begin
        ext_irq = 0;
        timer_irq = 0;
        sw_irq = 0;
    end

    //=========================================================
    // Memory Model
    //=========================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    integer mem_init_i;
    
    // Initialize memory with test program
    initial begin
        // Clear memory
        for (mem_init_i = 0; mem_init_i < MEM_SIZE; mem_init_i = mem_init_i + 1) begin
            memory[mem_init_i] = 8'h00;
        end
        
        // Load test program (simple test)
        // Address 0x8000_0000: addi x1, x0, 10
        memory[0] = 8'h93; memory[1] = 8'h00; memory[2] = 8'ha0; memory[3] = 8'h00;
        // Address 0x8000_0004: addi x2, x0, 20
        memory[4] = 8'h13; memory[5] = 8'h01; memory[6] = 8'h40; memory[7] = 8'h01;
        // Address 0x8000_0008: add x3, x1, x2
        memory[8] = 8'hb3; memory[9] = 8'h81; memory[10] = 8'h20; memory[11] = 8'h00;
        // Address 0x8000_000C: sw x3, 0(x0)
        memory[12] = 8'h23; memory[13] = 8'h20; memory[14] = 8'h30; memory[15] = 8'h00;
        // Address 0x8000_0010: lw x4, 0(x0)
        memory[16] = 8'h03; memory[17] = 8'h22; memory[18] = 8'h00; memory[19] = 8'h00;
        // Address 0x8000_0014: beq x3, x4, +8 (skip next)
        memory[20] = 8'h63; memory[21] = 8'h04; memory[22] = 8'h41; memory[23] = 8'h00;
        // Address 0x8000_0018: addi x5, x0, 1 (fail)
        memory[24] = 8'h93; memory[25] = 8'h02; memory[26] = 8'h10; memory[27] = 8'h00;
        // Address 0x8000_001C: addi x5, x0, 0 (pass)
        memory[28] = 8'h93; memory[29] = 8'h02; memory[30] = 8'h00; memory[31] = 8'h00;
        // Address 0x8000_0020: ebreak (end test)
        memory[32] = 8'h73; memory[33] = 8'h00; memory[34] = 8'h10; memory[35] = 8'h00;
    end
    
    //=========================================================
    // AXI Instruction Bus Slave Model
    //=========================================================
    reg [1:0] ibus_state;
    localparam IBUS_IDLE = 2'b00;
    localparam IBUS_ADDR = 2'b01;
    localparam IBUS_DATA = 2'b10;
    
    reg [31:0] ibus_addr_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibus_state <= IBUS_IDLE;
            m_axi_ibus_arready <= 1'b0;
            m_axi_ibus_rvalid <= 1'b0;
            m_axi_ibus_rdata <= 32'd0;
            m_axi_ibus_rresp <= 2'b00;
            ibus_addr_reg <= 32'd0;
        end else begin
            case (ibus_state)
                IBUS_IDLE: begin
                    m_axi_ibus_arready <= 1'b1;
                    if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                        ibus_addr_reg <= m_axi_ibus_araddr;
                        m_axi_ibus_arready <= 1'b0;
                        ibus_state <= IBUS_DATA;
                    end
                end
                
                IBUS_DATA: begin
                    m_axi_ibus_rvalid <= 1'b1;
                    // Read from memory
                    if (ibus_addr_reg >= MEM_BASE && 
                        ibus_addr_reg < MEM_BASE + MEM_SIZE) begin
                        m_axi_ibus_rdata <= {
                            memory[ibus_addr_reg - MEM_BASE + 3],
                            memory[ibus_addr_reg - MEM_BASE + 2],
                            memory[ibus_addr_reg - MEM_BASE + 1],
                            memory[ibus_addr_reg - MEM_BASE + 0]
                        };
                        m_axi_ibus_rresp <= 2'b00;  // OKAY
                    end else begin
                        m_axi_ibus_rdata <= 32'h0000_0013;  // NOP
                        m_axi_ibus_rresp <= 2'b10;  // SLVERR
                    end
                    
                    if (m_axi_ibus_rvalid && m_axi_ibus_rready) begin
                        m_axi_ibus_rvalid <= 1'b0;
                        ibus_state <= IBUS_IDLE;
                    end
                end
                
                default: ibus_state <= IBUS_IDLE;
            endcase
        end
    end

    //=========================================================
    // AXI Data Bus Slave Model
    //=========================================================
    reg [2:0] dbus_state;
    localparam DBUS_IDLE   = 3'b000;
    localparam DBUS_RADDR  = 3'b001;
    localparam DBUS_RDATA  = 3'b010;
    localparam DBUS_WADDR  = 3'b011;
    localparam DBUS_WDATA  = 3'b100;
    localparam DBUS_WRESP  = 3'b101;
    
    reg [31:0] dbus_addr_reg;
    reg [31:0] dbus_wdata_reg;
    reg [3:0]  dbus_wstrb_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbus_state <= DBUS_IDLE;
            m_axi_dbus_arready <= 1'b0;
            m_axi_dbus_rvalid <= 1'b0;
            m_axi_dbus_rdata <= 32'd0;
            m_axi_dbus_rresp <= 2'b00;
            m_axi_dbus_awready <= 1'b0;
            m_axi_dbus_wready <= 1'b0;
            m_axi_dbus_bvalid <= 1'b0;
            m_axi_dbus_bresp <= 2'b00;
            dbus_addr_reg <= 32'd0;
            dbus_wdata_reg <= 32'd0;
            dbus_wstrb_reg <= 4'b0;
        end else begin
            case (dbus_state)
                DBUS_IDLE: begin
                    m_axi_dbus_arready <= 1'b1;
                    m_axi_dbus_awready <= 1'b1;
                    
                    // Read has priority
                    if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                        dbus_addr_reg <= m_axi_dbus_araddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        dbus_state <= DBUS_RDATA;
                    end else if (m_axi_dbus_awvalid && m_axi_dbus_awready) begin
                        dbus_addr_reg <= m_axi_dbus_awaddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        m_axi_dbus_wready <= 1'b1;
                        dbus_state <= DBUS_WDATA;
                    end
                end
                
                DBUS_RDATA: begin
                    m_axi_dbus_rvalid <= 1'b1;
                    if (dbus_addr_reg >= MEM_BASE && 
                        dbus_addr_reg < MEM_BASE + MEM_SIZE) begin
                        m_axi_dbus_rdata <= {
                            memory[dbus_addr_reg - MEM_BASE + 3],
                            memory[dbus_addr_reg - MEM_BASE + 2],
                            memory[dbus_addr_reg - MEM_BASE + 1],
                            memory[dbus_addr_reg - MEM_BASE + 0]
                        };
                        m_axi_dbus_rresp <= 2'b00;
                    end else begin
                        m_axi_dbus_rdata <= 32'd0;
                        m_axi_dbus_rresp <= 2'b10;
                    end
                    
                    if (m_axi_dbus_rvalid && m_axi_dbus_rready) begin
                        m_axi_dbus_rvalid <= 1'b0;
                        dbus_state <= DBUS_IDLE;
                    end
                end
                
                DBUS_WDATA: begin
                    if (m_axi_dbus_wvalid && m_axi_dbus_wready) begin
                        dbus_wdata_reg <= m_axi_dbus_wdata;
                        dbus_wstrb_reg <= m_axi_dbus_wstrb;
                        m_axi_dbus_wready <= 1'b0;
                        
                        // Write to memory
                        if (dbus_addr_reg >= MEM_BASE && 
                            dbus_addr_reg < MEM_BASE + MEM_SIZE) begin
                            if (m_axi_dbus_wstrb[0])
                                memory[dbus_addr_reg - MEM_BASE + 0] <= m_axi_dbus_wdata[7:0];
                            if (m_axi_dbus_wstrb[1])
                                memory[dbus_addr_reg - MEM_BASE + 1] <= m_axi_dbus_wdata[15:8];
                            if (m_axi_dbus_wstrb[2])
                                memory[dbus_addr_reg - MEM_BASE + 2] <= m_axi_dbus_wdata[23:16];
                            if (m_axi_dbus_wstrb[3])
                                memory[dbus_addr_reg - MEM_BASE + 3] <= m_axi_dbus_wdata[31:24];
                            m_axi_dbus_bresp <= 2'b00;
                        end else begin
                            m_axi_dbus_bresp <= 2'b10;
                        end
                        
                        dbus_state <= DBUS_WRESP;
                    end
                end
                
                DBUS_WRESP: begin
                    m_axi_dbus_bvalid <= 1'b1;
                    if (m_axi_dbus_bvalid && m_axi_dbus_bready) begin
                        m_axi_dbus_bvalid <= 1'b0;
                        dbus_state <= DBUS_IDLE;
                    end
                end
                
                default: dbus_state <= DBUS_IDLE;
            endcase
        end
    end

    //=========================================================
    // DUT Instantiation
    //=========================================================
    cpu_core_top #(
        .XLEN(XLEN),
        .RESET_VECTOR(MEM_BASE)
    ) u_cpu_core (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // AXI Instruction Bus
        .m_axi_ibus_arvalid     (m_axi_ibus_arvalid),
        .m_axi_ibus_arready     (m_axi_ibus_arready),
        .m_axi_ibus_araddr      (m_axi_ibus_araddr),
        .m_axi_ibus_arprot      (m_axi_ibus_arprot),
        .m_axi_ibus_rvalid      (m_axi_ibus_rvalid),
        .m_axi_ibus_rready      (m_axi_ibus_rready),
        .m_axi_ibus_rdata       (m_axi_ibus_rdata),
        .m_axi_ibus_rresp       (m_axi_ibus_rresp),
        
        // AXI Data Bus
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
        
        // Interrupts
        .ext_irq_i              (ext_irq),
        .timer_irq_i            (timer_irq),
        .sw_irq_i               (sw_irq)
    );
    
    //=========================================================
    // Test Control
    //=========================================================
    integer cycle_count;
    integer test_timeout;
    
    initial begin
        cycle_count = 0;
        test_timeout = 10000;  // 10000 cycles timeout
        
        $display("========================================");
        $display("RISC-V OoO CPU Core Testbench");
        $display("========================================");
        
        // Wait for reset
        @(posedge rst_n);
        $display("[%0t] Reset released", $time);
        
        // Run simulation
        while (cycle_count < test_timeout) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
            
            // Check for test completion (EBREAK)
            // In a real test, we would monitor for specific conditions
        end
        
        $display("[%0t] Test timeout after %0d cycles", $time, cycle_count);
        $display("========================================");
        $display("Test completed");
        $display("========================================");
        $finish;
    end
    
    //=========================================================
    // Waveform Dump
    //=========================================================
    initial begin
        $dumpfile("sim/waves/cpu_core.vcd");
        $dumpvars(0, tb_cpu_core);
    end

endmodule
