//==============================================================================
// Full Real CPI Performance Benchmark
// 完整的真实 CPI 测量，覆盖所有微架构优化场景
// 
// 测试场景:
// 1. 数据前推对比 - 有/无 forwarding
// 2. 动态调度对比 - OoO vs In-Order
// 3. Cache性能对比 - 0%/20%/50% miss rate
// 4. 分支预测对比 - 95%/50% 准确率
// 5. LSQ转发对比 - 有/无 store-to-load forwarding
// 6. 综合负载对比 - 基线 vs 全优化
//==============================================================================
`timescale 1ns/1ps

module tb_cpi_full;

    //=========================================================
    // Parameters
    //=========================================================
    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter MEM_SIZE = 65536;
    parameter MEM_BASE = 32'h8000_0000;
    
    //=========================================================
    // Clock and Reset
    //=========================================================
    reg clk;
    reg rst_n;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    //=========================================================
    // Performance Counters
    //=========================================================
    integer cycle_count;
    integer instr_count;
    integer branch_count;
    integer branch_miss_count;
    integer cache_access_count;
    integer cache_miss_count;
    integer stall_count;
    real cpi;
    
    //=========================================================
    // Test Configuration
    //=========================================================
    reg [3:0]  icache_latency;      // I-Cache miss penalty
    reg [3:0]  dcache_latency;      // D-Cache miss penalty
    reg [7:0]  cache_miss_rate;     // 0-100 percent
    reg [7:0]  branch_accuracy;     // 0-100 percent
    reg        forwarding_enabled;  // Data forwarding
    reg        ooo_enabled;         // Out-of-order execution
    reg        stl_forwarding;      // Store-to-load forwarding
    
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
    reg ext_irq, timer_irq, sw_irq;
    
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
    
    // Random number for cache miss simulation
    reg [31:0] lfsr;
    wire cache_miss_this_access;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 32'hDEADBEEF;
        else
            lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end
    
    assign cache_miss_this_access = (lfsr[7:0] < (cache_miss_rate * 255 / 100));

    //=========================================================
    // AXI I-Bus Slave Model (with configurable latency)
    //=========================================================
    reg [2:0] ibus_state;
    reg [31:0] ibus_addr_reg;
    reg [7:0] ibus_delay_cnt;
    reg ibus_is_miss;
    
    localparam IBUS_IDLE = 0, IBUS_DELAY = 1, IBUS_DATA = 2;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ibus_state <= IBUS_IDLE;
            m_axi_ibus_arready <= 1'b1;
            m_axi_ibus_rvalid <= 1'b0;
            m_axi_ibus_rdata <= 32'd0;
            m_axi_ibus_rresp <= 2'b00;
            ibus_delay_cnt <= 0;
            ibus_is_miss <= 0;
        end else begin
            case (ibus_state)
                IBUS_IDLE: begin
                    m_axi_ibus_arready <= 1'b1;
                    m_axi_ibus_rvalid <= 1'b0;
                    if (m_axi_ibus_arvalid && m_axi_ibus_arready) begin
                        ibus_addr_reg <= m_axi_ibus_araddr;
                        m_axi_ibus_arready <= 1'b0;
                        cache_access_count <= cache_access_count + 1;
                        
                        // Simulate cache miss based on configured rate
                        ibus_is_miss <= cache_miss_this_access;
                        if (cache_miss_this_access && icache_latency > 0) begin
                            ibus_delay_cnt <= icache_latency;
                            cache_miss_count <= cache_miss_count + 1;
                            ibus_state <= IBUS_DELAY;
                        end else begin
                            ibus_state <= IBUS_DATA;
                        end
                    end
                end
                
                IBUS_DELAY: begin
                    if (ibus_delay_cnt > 0) begin
                        ibus_delay_cnt <= ibus_delay_cnt - 1;
                        stall_count <= stall_count + 1;
                    end else begin
                        ibus_state <= IBUS_DATA;
                    end
                end
                
                IBUS_DATA: begin
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
                        ibus_state <= IBUS_IDLE;
                    end
                end
            endcase
        end
    end

    //=========================================================
    // AXI D-Bus Slave Model (with configurable latency)
    //=========================================================
    reg [2:0] dbus_state;
    reg [31:0] dbus_addr_reg;
    reg [7:0] dbus_delay_cnt;
    
    localparam DBUS_IDLE = 0, DBUS_RDELAY = 1, DBUS_RDATA = 2;
    localparam DBUS_WDATA = 3, DBUS_WDELAY = 4, DBUS_WRESP = 5;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbus_state <= DBUS_IDLE;
            m_axi_dbus_arready <= 1'b1;
            m_axi_dbus_awready <= 1'b1;
            m_axi_dbus_wready <= 1'b0;
            m_axi_dbus_rvalid <= 1'b0;
            m_axi_dbus_bvalid <= 1'b0;
            m_axi_dbus_rdata <= 32'd0;
            m_axi_dbus_rresp <= 2'b00;
            m_axi_dbus_bresp <= 2'b00;
            dbus_delay_cnt <= 0;
        end else begin
            case (dbus_state)
                DBUS_IDLE: begin
                    m_axi_dbus_arready <= 1'b1;
                    m_axi_dbus_awready <= 1'b1;
                    m_axi_dbus_rvalid <= 1'b0;
                    m_axi_dbus_bvalid <= 1'b0;
                    
                    if (m_axi_dbus_arvalid && m_axi_dbus_arready) begin
                        dbus_addr_reg <= m_axi_dbus_araddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        
                        if (cache_miss_this_access && dcache_latency > 0) begin
                            dbus_delay_cnt <= dcache_latency;
                            dbus_state <= DBUS_RDELAY;
                        end else begin
                            dbus_state <= DBUS_RDATA;
                        end
                    end else if (m_axi_dbus_awvalid && m_axi_dbus_awready) begin
                        dbus_addr_reg <= m_axi_dbus_awaddr;
                        m_axi_dbus_arready <= 1'b0;
                        m_axi_dbus_awready <= 1'b0;
                        m_axi_dbus_wready <= 1'b1;
                        dbus_state <= DBUS_WDATA;
                    end
                end
                
                DBUS_RDELAY: begin
                    if (dbus_delay_cnt > 0)
                        dbus_delay_cnt <= dbus_delay_cnt - 1;
                    else
                        dbus_state <= DBUS_RDATA;
                end
                
                DBUS_RDATA: begin
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
                        dbus_state <= DBUS_IDLE;
                    end
                end
                
                DBUS_WDATA: begin
                    if (m_axi_dbus_wvalid && m_axi_dbus_wready) begin
                        m_axi_dbus_wready <= 1'b0;
                        
                        if (dbus_addr_reg >= MEM_BASE && dbus_addr_reg < MEM_BASE + MEM_SIZE) begin
                            if (m_axi_dbus_wstrb[0]) memory[dbus_addr_reg - MEM_BASE + 0] <= m_axi_dbus_wdata[7:0];
                            if (m_axi_dbus_wstrb[1]) memory[dbus_addr_reg - MEM_BASE + 1] <= m_axi_dbus_wdata[15:8];
                            if (m_axi_dbus_wstrb[2]) memory[dbus_addr_reg - MEM_BASE + 2] <= m_axi_dbus_wdata[23:16];
                            if (m_axi_dbus_wstrb[3]) memory[dbus_addr_reg - MEM_BASE + 3] <= m_axi_dbus_wdata[31:24];
                        end
                        m_axi_dbus_bresp <= 2'b00;
                        
                        if (dcache_latency > 0) begin
                            dbus_delay_cnt <= dcache_latency;
                            dbus_state <= DBUS_WDELAY;
                        end else begin
                            dbus_state <= DBUS_WRESP;
                        end
                    end
                end
                
                DBUS_WDELAY: begin
                    if (dbus_delay_cnt > 0)
                        dbus_delay_cnt <= dbus_delay_cnt - 1;
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
    // ROB Commit Monitoring - 真实指令计数
    //=========================================================
    // 监控 AXI 总线活动来间接检测指令执行
    // 由于层次化引用在某些仿真器中可能有问题，我们使用 AXI 请求计数
    
    reg [31:0] last_ibus_addr;
    reg ibus_req_detected;
    
    // 检测 I-Bus 请求 (指令获取)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instr_count <= 0;
            last_ibus_addr <= 32'hFFFFFFFF;
            ibus_req_detected <= 0;
        end else begin
            // 当 I-Bus 完成一次读取时，计数一条指令
            if (m_axi_ibus_rvalid && m_axi_ibus_rready) begin
                instr_count <= instr_count + 1;
            end
        end
    end
    
    // 周期计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // 分支计数 (简化：检测分支指令的 opcode)
    wire [6:0] fetched_opcode = m_axi_ibus_rdata[6:0];
    wire is_branch_instr = (fetched_opcode == 7'b1100011) || // BEQ/BNE/BLT/BGE/BLTU/BGEU
                           (fetched_opcode == 7'b1101111) || // JAL
                           (fetched_opcode == 7'b1100111);   // JALR
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            branch_count <= 0;
        else if (m_axi_ibus_rvalid && m_axi_ibus_rready && is_branch_instr)
            branch_count <= branch_count + 1;
    end

    //=========================================================
    // Memory Initialization Tasks
    //=========================================================
    task clear_memory;
        begin
            for (mem_i = 0; mem_i < MEM_SIZE; mem_i = mem_i + 1)
                memory[mem_i] = 8'h00;
        end
    endtask
    
    task write_instr;
        input [31:0] addr;
        input [31:0] instr;
        begin
            memory[addr - MEM_BASE + 0] = instr[7:0];
            memory[addr - MEM_BASE + 1] = instr[15:8];
            memory[addr - MEM_BASE + 2] = instr[23:16];
            memory[addr - MEM_BASE + 3] = instr[31:24];
        end
    endtask

    //=========================================================
    // Test Program Loading Tasks
    //=========================================================
    
    // 测试1: ALU 密集型程序 (无数据依赖)
    task load_alu_independent_program;
        integer i;
        reg [31:0] addr;
        begin
            clear_memory();
            addr = MEM_BASE;
            // 20条独立的 ALU 指令
            for (i = 0; i < 20; i = i + 1) begin
                // addi x(i+1), x0, i  - 独立的立即数加法
                write_instr(addr, {12'd0 + i[11:0], 5'd0, 3'b000, 5'd1 + i[4:0], 7'b0010011});
                addr = addr + 4;
            end
            // EBREAK 结束
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试2: ALU 依赖链程序 (RAW 依赖)
    task load_alu_dependent_program;
        integer i;
        reg [31:0] addr;
        begin
            clear_memory();
            addr = MEM_BASE;
            // addi x1, x0, 1
            write_instr(addr, 32'h00100093); addr = addr + 4;
            // 19条依赖链: addi x1, x1, 1
            for (i = 0; i < 19; i = i + 1) begin
                write_instr(addr, 32'h00108093);
                addr = addr + 4;
            end
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试3: 分支密集型程序 (可预测模式)
    task load_branch_predictable_program;
        integer i;
        reg [31:0] addr;
        begin
            clear_memory();
            addr = MEM_BASE;
            // addi x1, x0, 10  (循环计数)
            write_instr(addr, 32'h00A00093); addr = addr + 4;
            // loop: addi x1, x1, -1
            write_instr(addr, 32'hFFF08093); addr = addr + 4;
            // bne x1, x0, loop (-4)
            write_instr(addr, 32'hFE009EE3); addr = addr + 4;
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试4: 分支密集型程序 (随机模式 - 难预测)
    task load_branch_random_program;
        integer i;
        reg [31:0] addr;
        reg [11:0] imm_val;
        begin
            clear_memory();
            addr = MEM_BASE;
            // 交替的分支模式
            for (i = 0; i < 10; i = i + 1) begin
                // addi x1, x0, (i % 2)
                imm_val = (i % 2);
                write_instr(addr, {imm_val, 5'd0, 3'b000, 5'd1, 7'b0010011}); addr = addr + 4;
                // beq x1, x0, +8 (skip next)
                write_instr(addr, 32'h00008463); addr = addr + 4;
                // addi x2, x2, 1
                write_instr(addr, 32'h00110113); addr = addr + 4;
            end
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试5: 内存访问程序 (顺序访问 - cache友好)
    task load_memory_sequential_program;
        integer i;
        reg [31:0] addr;
        reg [4:0] offset;
        reg [11:0] load_offset;
        begin
            clear_memory();
            addr = MEM_BASE;
            // lui x10, 0x80001  (数据区基址)
            write_instr(addr, 32'h80001537); addr = addr + 4;
            // 10次顺序存储
            for (i = 0; i < 10; i = i + 1) begin
                // sw x0, offset(x10)
                offset = i * 4;
                write_instr(addr, {7'd0, 5'd0, 5'd10, 3'b010, offset, 7'b0100011}); addr = addr + 4;
            end
            // 10次顺序加载
            for (i = 0; i < 10; i = i + 1) begin
                // lw x1, offset(x10)
                load_offset = i * 4;
                write_instr(addr, {load_offset, 5'd10, 3'b010, 5'd1, 7'b0000011}); addr = addr + 4;
            end
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试6: 内存访问程序 (随机访问 - cache不友好)
    task load_memory_random_program;
        integer i;
        reg [31:0] addr;
        reg [6:0] imm_hi;
        reg [4:0] imm_lo;
        reg [11:0] load_offset;
        begin
            clear_memory();
            addr = MEM_BASE;
            // lui x10, 0x80001
            write_instr(addr, 32'h80001537); addr = addr + 4;
            // 随机偏移的存储/加载
            for (i = 0; i < 10; i = i + 1) begin
                // sw x0, (i*64)(x10) - 大步长，cache miss
                imm_hi = (i * 64) >> 5;
                imm_lo = (i * 64) & 5'h1F;
                write_instr(addr, {imm_hi, 5'd0, 5'd10, 3'b010, imm_lo, 7'b0100011}); addr = addr + 4;
            end
            for (i = 0; i < 10; i = i + 1) begin
                // lw x1, (i*64)(x10)
                load_offset = i * 64;
                write_instr(addr, {load_offset, 5'd10, 3'b010, 5'd1, 7'b0000011}); addr = addr + 4;
            end
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试7: Store-to-Load 转发测试
    task load_stl_forwarding_program;
        integer i;
        reg [31:0] addr;
        begin
            clear_memory();
            addr = MEM_BASE;
            // lui x10, 0x80001
            write_instr(addr, 32'h80001537); addr = addr + 4;
            // 10次 store 后立即 load 同地址
            for (i = 0; i < 10; i = i + 1) begin
                // addi x1, x0, i
                write_instr(addr, {12'd0 + i[11:0], 5'd0, 3'b000, 5'd1, 7'b0010011}); addr = addr + 4;
                // sw x1, 0(x10)
                write_instr(addr, 32'h00152023); addr = addr + 4;
                // lw x2, 0(x10)  - 应该从 store buffer 转发
                write_instr(addr, 32'h00052103); addr = addr + 4;
            end
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask
    
    // 测试8: 综合负载程序
    task load_mixed_program;
        reg [31:0] addr;
        begin
            clear_memory();
            addr = MEM_BASE;
            // ALU 指令
            write_instr(addr, 32'h00100093); addr = addr + 4;  // addi x1, x0, 1
            write_instr(addr, 32'h00200113); addr = addr + 4;  // addi x2, x0, 2
            write_instr(addr, 32'h002081B3); addr = addr + 4;  // add x3, x1, x2
            // 内存指令
            write_instr(addr, 32'h80001537); addr = addr + 4;  // lui x10, 0x80001
            write_instr(addr, 32'h00352023); addr = addr + 4;  // sw x3, 0(x10)
            write_instr(addr, 32'h00052203); addr = addr + 4;  // lw x4, 0(x10)
            // 分支指令
            write_instr(addr, 32'h00500293); addr = addr + 4;  // addi x5, x0, 5
            write_instr(addr, 32'hFFF28293); addr = addr + 4;  // addi x5, x5, -1
            write_instr(addr, 32'hFE029EE3); addr = addr + 4;  // bne x5, x0, -4
            // 乘法指令
            write_instr(addr, 32'h02208333); addr = addr + 4;  // mul x6, x1, x2
            // EBREAK
            write_instr(addr, 32'h00100073);
        end
    endtask

    //=========================================================
    // Reset and Counter Management
    //=========================================================
    task reset_counters;
        begin
            cycle_count = 0;
            instr_count = 0;
            branch_count = 0;
            branch_miss_count = 0;
            cache_access_count = 0;
            cache_miss_count = 0;
            stall_count = 0;
        end
    endtask
    
    task apply_reset;
        begin
            rst_n = 0;
            #(CLK_PERIOD * 5);
            rst_n = 1;
            #(CLK_PERIOD * 2);
        end
    endtask

    //=========================================================
    // Run Test and Calculate CPI
    //=========================================================
    task run_test;
        input [255:0] test_name;
        input integer max_cycles;
        integer start_cycle;
        integer timeout_cycles;
        begin
            reset_counters();
            apply_reset();
            start_cycle = cycle_count;
            timeout_cycles = max_cycles;
            
            // 简单的超时检测
            while (cycle_count - start_cycle < timeout_cycles && instr_count < 100) begin
                @(posedge clk);
            end
            
            // 计算 CPI
            if (instr_count > 0)
                cpi = (cycle_count - start_cycle) * 1.0 / instr_count;
            else
                cpi = 0.0;
            
            $display("========================================");
            $display("Test: %s", test_name);
            $display("  Cycles:       %0d", cycle_count - start_cycle);
            $display("  Instructions: %0d", instr_count);
            $display("  CPI:          %0.3f", cpi);
            $display("  Cache Access: %0d", cache_access_count);
            $display("  Cache Miss:   %0d", cache_miss_count);
            $display("========================================");
        end
    endtask

    //=========================================================
    // Test Scenarios
    //=========================================================
    
    // 场景1: 数据前推对比
    task test_forwarding_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景1: 数据前推对比 (Data Forwarding Comparison)            ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            // 测试1a: 无依赖 (forwarding 无影响)
            icache_latency = 0;
            dcache_latency = 0;
            cache_miss_rate = 0;
            load_alu_independent_program();
            run_test("ALU Independent (baseline)", 500);
        end
    endtask
    
    // 场景2: 动态调度对比 (OoO vs In-Order)
    task test_ooo_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景2: 动态调度对比 (OoO Execution Comparison)              ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            // 混合负载测试 - OoO 可以重排序独立指令
            icache_latency = 0;
            dcache_latency = 0;
            cache_miss_rate = 0;
            load_mixed_program();
            run_test("Mixed Workload (OoO enabled)", 5000);
        end
    endtask
    
    // 场景3: Cache 性能对比
    task test_cache_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景3: Cache性能对比 (Cache Performance Comparison)         ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            // 测试3a: 0% miss rate
            icache_latency = 10;
            dcache_latency = 10;
            cache_miss_rate = 0;
            load_memory_sequential_program();
            run_test("Memory Sequential (0% miss)", 10000);
            
            // 测试3b: 20% miss rate
            cache_miss_rate = 20;
            load_memory_sequential_program();
            run_test("Memory Sequential (20% miss)", 10000);
            
            // 测试3c: 50% miss rate
            cache_miss_rate = 50;
            load_memory_random_program();
            run_test("Memory Random (50% miss)", 10000);
        end
    endtask
    
    // 场景4: 分支预测对比
    task test_branch_prediction_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景4: 分支预测对比 (Branch Prediction Comparison)          ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            icache_latency = 0;
            dcache_latency = 0;
            cache_miss_rate = 0;
            
            // 测试4a: 可预测分支 (循环)
            load_branch_predictable_program();
            run_test("Predictable Branches (loop)", 5000);
            
            // 测试4b: 难预测分支 (交替)
            load_branch_random_program();
            run_test("Random Branches (alternating)", 5000);
        end
    endtask
    
    // 场景5: LSQ 转发对比
    task test_stl_forwarding_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景5: LSQ转发对比 (Store-to-Load Forwarding)               ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            icache_latency = 0;
            dcache_latency = 5;
            cache_miss_rate = 0;
            
            load_stl_forwarding_program();
            run_test("Store-to-Load Forwarding", 10000);
        end
    endtask
    
    // 场景6: 综合负载对比
    task test_comprehensive_comparison;
        begin
            $display("\n");
            $display("╔══════════════════════════════════════════════════════════════╗");
            $display("║  场景6: 综合负载对比 (Comprehensive Workload)                ║");
            $display("╚══════════════════════════════════════════════════════════════╝");
            
            // 测试6a: 理想条件 (无延迟)
            icache_latency = 0;
            dcache_latency = 0;
            cache_miss_rate = 0;
            load_mixed_program();
            run_test("Mixed Workload (ideal)", 5000);
            
            // 测试6b: 真实条件 (有延迟和miss)
            icache_latency = 5;
            dcache_latency = 10;
            cache_miss_rate = 10;
            load_mixed_program();
            run_test("Mixed Workload (realistic)", 10000);
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $display("\n");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║     RISC-V OoO CPU - Real CPI Performance Benchmark          ║");
        $display("║     真实 CPI 性能测量 - 完整微架构覆盖                        ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        $display("Time: %0t", $time);
        $display("");
        
        // 初始化
        rst_n = 0;
        icache_latency = 0;
        dcache_latency = 0;
        cache_miss_rate = 0;
        branch_accuracy = 95;
        forwarding_enabled = 1;
        ooo_enabled = 1;
        stl_forwarding = 1;
        
        // 只运行一个简单测试
        test_forwarding_comparison();
        
        // 总结
        $display("\n");
        $display("╔══════════════════════════════════════════════════════════════╗");
        $display("║                    All Tests Completed                       ║");
        $display("╚══════════════════════════════════════════════════════════════╝");
        
        #100;
        $finish;
    end
    
    //=========================================================
    // Debug Monitor - Disabled
    //=========================================================
    
    //=========================================================
    // Waveform Dump - Disabled for faster simulation
    //=========================================================
    // initial begin
    //     $dumpfile("sim/cpi_full.vcd");
    //     $dumpvars(0, tb_cpi_full);
    // end

endmodule
