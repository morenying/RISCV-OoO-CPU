//==============================================================================
// Real CPI Performance Benchmark
// 使用真实 CPU 核心执行指令，测量实际 CPI
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_real;

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
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================
    // Performance Counters (Testbench side)
    //=========================================================
    integer cycle_count;
    integer instr_count;
    integer branch_count;
    integer branch_miss_count;
    integer load_count;
    integer store_count;
    integer stall_count;
    real cpi;
    
    //=========================================================
    // Test Control
    //=========================================================
    reg [31:0] test_start_cycle;
    reg [31:0] test_end_cycle;
    reg [31:0] test_start_instr;
    reg [31:0] test_end_instr;
    reg        test_running;
    reg [3:0]  current_test;
    
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
    integer mem_i;
    
    //=========================================================
    // Memory Latency Simulation
    //=========================================================
    reg [3:0] icache_latency;
    reg [3:0] dcache_latency;
    reg [3:0] icache_delay_cnt;
    reg [3:0] dcache_delay_cnt;
    
    //=========================================================
    // AXI Instruction Bus Slave Model (with configurable latency)
    //=========================================================
    reg [1:0] ibus_state;
    localparam IBUS_IDLE = 2'b00;
    localparam IBUS_WAIT = 2'b01;
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
            icache_delay_cnt <= 0;
        end else begin
            case (ibus_state)
                IBUS_IDLE: begin
                    m_axi_ibus_arready <= 1'b1;
                    if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                        ibus_addr_reg <= m_axi_ibus_araddr;
                        m_axi_ibus_arready <= 1'b0;
                        icache_delay_cnt <= icache_latency;
                        ibus_state <= (icache_latency > 0) ? IBUS_WAIT : IBUS_DATA;
                    end
                end
                
                IBUS_WAIT: begin
                    if (icache_delay_cnt > 0)
                        icache_delay_cnt <= icache_delay_cnt - 1;
                    else
                        ibus_state <= IBUS_DATA;
                end
                
                IBUS_DATA: begin
                    m_axi_ibus_rvalid <= 1'b1;
                    if (ibus_addr_reg >= MEM_BASE && 
                        ibus_addr_reg < MEM_BASE + MEM_SIZE) begin
                        m_axi_ibus_rdata <= {
                            memory[ibus_addr_reg - MEM_BASE + 3],
                            memory[ibus_addr_reg - MEM_BASE + 2],
                            memory[ibus_addr_reg - MEM_BASE + 1],
                            memory[ibus_addr_reg - MEM_BASE + 0]
                        };
                        m_axi_ibus_rresp <= 2'b00;
                    end else begin
                        m_axi_ibus_rdata <= 32'h0000_0013;  // NOP
                        m_axi_ibus_rresp <= 2'b10;
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
    // AXI Data Bus Slave Model (with configurable latency)
    //=========================================================
    reg [2:0] dbus_state;
    localparam DBUS_IDLE   = 3'b000;
    localparam DBUS_RWAIT  = 3'b001;
    localparam DBUS_RDATA  = 3'b010;
    localparam DBUS_WDATA  = 3'b011;
    localparam DBUS_WWAIT  = 3'b100;
    localparam DBUS_WRESP  = 3'b101;
    
    reg [31:0] dbus_addr_reg;
    
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
            dcache_delay_cnt <= 0;
        end else begin
            case (dbus_state)
                DBUS_IDLE: begin
                    m_axi_dbus_arready <= 1'b1;
                    m_axi_dbus_awready <= 1'b1;
                    
                    if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                        dbus_addr_reg <= m_axi_dbus_araddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        dcache_delay_cnt <= dcache_latency;
                        dbus_state <= (dcache_latency > 0) ? DBUS_RWAIT : DBUS_RDATA;
                    end else if (m_axi_dbus_awvalid && m_axi_dbus_awready) begin
                        dbus_addr_reg <= m_axi_dbus_awaddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        m_axi_dbus_wready <= 1'b1;
                        dbus_state <= DBUS_WDATA;
                    end
                end
                
                DBUS_RWAIT: begin
                    if (dcache_delay_cnt > 0)
                        dcache_delay_cnt <= dcache_delay_cnt - 1;
                    else
                        dbus_state <= DBUS_RDATA;
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
                        m_axi_dbus_wready <= 1'b0;
                        
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
                        
                        dcache_delay_cnt <= dcache_latency;
                        dbus_state <= (dcache_latency > 0) ? DBUS_WWAIT : DBUS_WRESP;
                    end
                end
                
                DBUS_WWAIT: begin
                    if (dcache_delay_cnt > 0)
                        dcache_delay_cnt <= dcache_delay_cnt - 1;
                    else
                        dbus_state <= DBUS_WRESP;
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
    // Monitor ROB Commit for Instruction Count
    //=========================================================
    // Access internal ROB signals for monitoring
    wire rob_commit_valid = u_cpu_core.rob_commit_valid;
    wire rob_commit_ready = u_cpu_core.rob_commit_ready;
    wire [31:0] rob_commit_pc = u_cpu_core.rob_commit_pc;
    
    // Track instruction retirement
    always @(posedge clk) begin
        if (rst_n && test_running) begin
            cycle_count <= cycle_count + 1;
            if (rob_commit_valid && rob_commit_ready) begin
                instr_count <= instr_count + 1;
            end
        end
    end

    //=========================================================
    // Test Programs
    //=========================================================
    
    // Task: Load test program into memory
    task load_test_program;
        input [3:0] test_id;
        begin
            // Clear memory first
            for (mem_i = 0; mem_i < MEM_SIZE; mem_i = mem_i + 1) begin
                memory[mem_i] = 8'h00;
            end
            
            case (test_id)
                4'd1: load_alu_test();
                4'd2: load_branch_test();
                4'd3: load_memory_test();
                4'd4: load_loop_test();
                4'd5: load_dependency_test();
                default: load_alu_test();
            endcase
        end
    endtask
    
    // Test 1: Pure ALU operations (no hazards)
    task load_alu_test;
        integer addr;
        begin
            addr = 0;
            // 20 independent ALU instructions
            // addi x1, x0, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100093; addr = addr + 4;
            // addi x2, x0, 2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00200113; addr = addr + 4;
            // addi x3, x0, 3
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00300193; addr = addr + 4;
            // addi x4, x0, 4
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00400213; addr = addr + 4;
            // addi x5, x0, 5
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00500293; addr = addr + 4;
            // addi x6, x0, 6
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00600313; addr = addr + 4;
            // addi x7, x0, 7
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00700393; addr = addr + 4;
            // addi x8, x0, 8
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00800413; addr = addr + 4;
            // addi x9, x0, 9
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00900493; addr = addr + 4;
            // addi x10, x0, 10
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00a00513; addr = addr + 4;
            // add x11, x1, x2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h002085b3; addr = addr + 4;
            // add x12, x3, x4
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00418633; addr = addr + 4;
            // add x13, x5, x6
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h006286b3; addr = addr + 4;
            // add x14, x7, x8
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00838733; addr = addr + 4;
            // add x15, x9, x10
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00a487b3; addr = addr + 4;
            // xor x16, x11, x12
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00c5c833; addr = addr + 4;
            // or x17, x13, x14
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00e6e8b3; addr = addr + 4;
            // and x18, x15, x16
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0107f933; addr = addr + 4;
            // sll x19, x17, x1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h001899b3; addr = addr + 4;
            // srl x20, x18, x2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00295a33; addr = addr + 4;
            // ebreak (end)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask
    
    // Test 2: Branch-heavy test
    task load_branch_test;
        integer addr;
        begin
            addr = 0;
            // Initialize counter
            // addi x1, x0, 10  (loop count)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00a00093; addr = addr + 4;
            // addi x2, x0, 0   (counter)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00000113; addr = addr + 4;
            // Loop start (addr = 8):
            // addi x2, x2, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00110113; addr = addr + 4;
            // bne x2, x1, -4 (loop back)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'hfe111ee3; addr = addr + 4;
            // ebreak
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask
    
    // Test 3: Memory access test
    task load_memory_test;
        integer addr;
        begin
            addr = 0;
            // Store and load sequence
            // addi x1, x0, 0x100
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h10000093; addr = addr + 4;
            // addi x2, x0, 0xAB
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0ab00113; addr = addr + 4;
            // sw x2, 0(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0020a023; addr = addr + 4;
            // lw x3, 0(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0000a183; addr = addr + 4;
            // addi x4, x0, 0xCD
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0cd00213; addr = addr + 4;
            // sw x4, 4(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0040a223; addr = addr + 4;
            // lw x5, 4(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0040a283; addr = addr + 4;
            // add x6, x3, x5
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00518333; addr = addr + 4;
            // sw x6, 8(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0060a423; addr = addr + 4;
            // lw x7, 8(x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h0080a383; addr = addr + 4;
            // ebreak
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask
    
    // Test 4: Loop with computation
    task load_loop_test;
        integer addr;
        begin
            addr = 0;
            // Sum 1 to N
            // addi x1, x0, 20  (N)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h01400093; addr = addr + 4;
            // addi x2, x0, 0   (sum)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00000113; addr = addr + 4;
            // addi x3, x0, 1   (i)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100193; addr = addr + 4;
            // Loop (addr = 12):
            // add x2, x2, x3
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00310133; addr = addr + 4;
            // addi x3, x3, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00118193; addr = addr + 4;
            // ble x3, x1, -8 (bge x1, x3, -8)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'hfe30dce3; addr = addr + 4;
            // ebreak
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask
    
    // Test 5: Data dependency chain (RAW hazards)
    task load_dependency_test;
        integer addr;
        begin
            addr = 0;
            // Chain of dependent instructions
            // addi x1, x0, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100093; addr = addr + 4;
            // addi x2, x1, 1  (depends on x1)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00108113; addr = addr + 4;
            // addi x3, x2, 1  (depends on x2)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00110193; addr = addr + 4;
            // addi x4, x3, 1  (depends on x3)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00118213; addr = addr + 4;
            // addi x5, x4, 1  (depends on x4)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00120293; addr = addr + 4;
            // addi x6, x5, 1  (depends on x5)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00128313; addr = addr + 4;
            // addi x7, x6, 1  (depends on x6)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00130393; addr = addr + 4;
            // addi x8, x7, 1  (depends on x7)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00138413; addr = addr + 4;
            // addi x9, x8, 1  (depends on x8)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00140493; addr = addr + 4;
            // addi x10, x9, 1 (depends on x9)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00148513; addr = addr + 4;
            // ebreak
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask

    //=========================================================
    // CPI Calculation Task
    //=========================================================
    task calculate_and_report_cpi;
        input [127:0] test_name;
        begin
            if (instr_count > 0) begin
                cpi = cycle_count * 1.0 / instr_count;
                $display("  Test: %0s", test_name);
                $display("    Cycles:       %0d", cycle_count);
                $display("    Instructions: %0d", instr_count);
                $display("    CPI:          %0.3f", cpi);
                $display("");
            end else begin
                $display("  Test: %0s - No instructions retired!", test_name);
            end
        end
    endtask

    //=========================================================
    // Run Single Test
    //=========================================================
    task run_test;
        input [3:0] test_id;
        input [127:0] test_name;
        input [31:0] timeout;
        integer wait_cycles;
        begin
            $display("\n--- Running: %0s ---", test_name);
            
            // Load program
            load_test_program(test_id);
            
            // Reset CPU
            rst_n = 0;
            cycle_count = 0;
            instr_count = 0;
            test_running = 0;
            #(CLK_PERIOD * 10);
            rst_n = 1;
            #(CLK_PERIOD * 5);
            
            // Start counting
            test_running = 1;
            
            // Wait for completion or timeout
            wait_cycles = 0;
            while (wait_cycles < timeout) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
                
                // Check for EBREAK (instruction fetch of 0x00100073)
                if (m_axi_ibus_rvalid && m_axi_ibus_rdata == 32'h00100073) begin
                    // Wait a few more cycles for pipeline to drain
                    repeat(20) @(posedge clk);
                    wait_cycles = timeout; // Exit loop
                end
            end
            
            test_running = 0;
            
            // Report results
            calculate_and_report_cpi(test_name);
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $dumpfile("sim/waves/cpi_real.vcd");
        $dumpvars(0, tb_cpi_real);
        
        $display("============================================================");
        $display("       Real CPI Performance Benchmark");
        $display("       Using actual CPU core execution");
        $display("============================================================");
        
        // Initialize
        rst_n = 0;
        cycle_count = 0;
        instr_count = 0;
        test_running = 0;
        icache_latency = 0;  // No extra latency initially
        dcache_latency = 0;
        
        #(CLK_PERIOD * 20);
        
        $display("\n=== Test Suite 1: Zero Memory Latency ===");
        icache_latency = 0;
        dcache_latency = 0;
        
        run_test(4'd1, "ALU Operations (no hazards)", 500);
        run_test(4'd5, "Dependency Chain (RAW hazards)", 500);
        run_test(4'd2, "Branch Loop (10 iterations)", 500);
        run_test(4'd3, "Memory Access (SW/LW)", 500);
        run_test(4'd4, "Compute Loop (sum 1-20)", 1000);
        
        $display("\n=== Test Suite 2: With Memory Latency (5 cycles) ===");
        icache_latency = 5;
        dcache_latency = 5;
        
        run_test(4'd1, "ALU + 5-cycle I$ latency", 2000);
        run_test(4'd3, "Memory + 5-cycle D$ latency", 2000);
        
        $display("\n=== Test Suite 3: High Memory Latency (10 cycles) ===");
        icache_latency = 10;
        dcache_latency = 10;
        
        run_test(4'd1, "ALU + 10-cycle I$ latency", 5000);
        run_test(4'd3, "Memory + 10-cycle D$ latency", 5000);
        
        $display("============================================================");
        $display("       Real CPI Benchmark Complete");
        $display("============================================================");
        
        #100;
        $finish;
    end

endmodule
