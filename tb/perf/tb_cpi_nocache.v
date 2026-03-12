//==============================================================================
// Real CPI Benchmark - No Cache Version
// 直接连接 IF stage 到内存，绕过 cache
// 用于测量真实的 CPU 流水线性能
//==============================================================================
`timescale 1ns/1ps
`include "cpu_defines.vh"

module tb_cpi_nocache;

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
    integer fetch_count;
    real cpi;
    
    //=========================================================
    // Memory
    //=========================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    integer i;
    
    //=========================================================
    // IF Stage Signals
    //=========================================================
    wire        icache_req_valid;
    wire [31:0] icache_req_addr;
    reg         icache_req_ready;
    reg         icache_resp_valid;
    reg  [31:0] icache_resp_data;
    
    wire        bpu_req;
    wire [31:0] bpu_pc;
    reg         bpu_pred_taken;
    reg  [31:0] bpu_pred_target;
    reg  [1:0]  bpu_pred_type;
    
    wire        if_id_valid;
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;
    wire        if_id_pred_taken;
    wire [31:0] if_id_pred_target;
    wire [1:0]  if_id_pred_type;
    wire [63:0] if_id_ghr;
    
    // Control signals
    reg         stall_if;
    reg         flush_if;
    reg         redirect_valid;
    reg  [31:0] redirect_pc;
    reg  [63:0] ghr;
    
    //=========================================================
    // IF Stage Instance
    //=========================================================
    if_stage #(
        .XLEN(XLEN),
        .GHR_WIDTH(64)
    ) u_if_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .stall_i            (stall_if),
        .flush_i            (flush_if),
        .redirect_valid_i   (redirect_valid),
        .redirect_pc_i      (redirect_pc),
        .icache_req_valid_o (icache_req_valid),
        .icache_req_addr_o  (icache_req_addr),
        .icache_req_ready_i (icache_req_ready),
        .icache_resp_valid_i(icache_resp_valid),
        .icache_resp_data_i (icache_resp_data),
        .bpu_req_o          (bpu_req),
        .bpu_pc_o           (bpu_pc),
        .bpu_pred_taken_i   (bpu_pred_taken),
        .bpu_pred_target_i  (bpu_pred_target),
        .bpu_pred_type_i    (bpu_pred_type),
        .id_valid_o         (if_id_valid),
        .id_pc_o            (if_id_pc),
        .id_instr_o         (if_id_instr),
        .id_pred_taken_o    (if_id_pred_taken),
        .id_pred_target_o   (if_id_pred_target),
        .id_pred_type_o     (if_id_pred_type),
        .id_ghr_o           (if_id_ghr),
        .ghr_i              (ghr)
    );
    
    //=========================================================
    // Simple Memory Model (1-cycle latency)
    //=========================================================
    reg [1:0] mem_state;
    reg [31:0] mem_addr_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state <= 0;
            icache_req_ready <= 1'b1;
            icache_resp_valid <= 1'b0;
            icache_resp_data <= 32'd0;
            mem_addr_reg <= 32'd0;
        end else begin
            case (mem_state)
                0: begin // IDLE
                    icache_req_ready <= 1'b1;
                    icache_resp_valid <= 1'b0;
                    if (icache_req_valid && icache_req_ready) begin
                        mem_addr_reg <= icache_req_addr;
                        icache_req_ready <= 1'b0;
                        mem_state <= 1;
                        fetch_count <= fetch_count + 1;
                    end
                end
                1: begin // RESPOND
                    icache_resp_valid <= 1'b1;
                    if (mem_addr_reg >= MEM_BASE && mem_addr_reg < MEM_BASE + MEM_SIZE) begin
                        icache_resp_data <= {
                            memory[mem_addr_reg - MEM_BASE + 3],
                            memory[mem_addr_reg - MEM_BASE + 2],
                            memory[mem_addr_reg - MEM_BASE + 1],
                            memory[mem_addr_reg - MEM_BASE + 0]
                        };
                    end else begin
                        icache_resp_data <= 32'h00000013; // NOP
                    end
                    mem_state <= 0;
                end
            endcase
        end
    end
    
    //=========================================================
    // Simple BPU (always not taken)
    //=========================================================
    always @(*) begin
        bpu_pred_taken = 1'b0;
        bpu_pred_target = 32'd0;
        bpu_pred_type = 2'b00;
    end
    
    //=========================================================
    // Instruction Counter (count unique fetches)
    //=========================================================
    reg [31:0] last_pc;
    reg        ebreak_seen;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_pc <= 32'hFFFFFFFF;
            ebreak_seen <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            
            // Count only when PC changes (new instruction)
            if (if_id_valid && !stall_if && (if_id_pc != last_pc)) begin
                last_pc <= if_id_pc;
                instr_count <= instr_count + 1;
                
                $display("[%0t] FETCH #%0d: PC=%h INSTR=%h", $time, instr_count + 1, if_id_pc, if_id_instr);
                
                // Check for EBREAK
                if (if_id_instr == 32'h00100073) begin
                    $display("[%0t] EBREAK detected!", $time);
                    ebreak_seen <= 1;
                end
            end
        end
    end

    //=========================================================
    // Test Programs
    //=========================================================
    task load_alu_test;
        integer addr;
        begin
            addr = 0;
            // 10 independent ALU instructions
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
            // add x6, x1, x2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00208333; addr = addr + 4;
            // add x7, x3, x4
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h004183b3; addr = addr + 4;
            // add x8, x5, x6
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00628433; addr = addr + 4;
            // add x9, x7, x8
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h008384b3; addr = addr + 4;
            // add x10, x9, x1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00148533; addr = addr + 4;
            // ebreak
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4;
        end
    endtask

    //=========================================================
    // Main Test
    //=========================================================
    integer test_cycles;
    integer test_instrs;
    
    task run_test;
        input [255:0] test_name;
        input integer max_cycles;
        begin
            $display("\n--- %0s ---", test_name);
            
            // Reset
            rst_n = 0;
            cycle_count = 0;
            instr_count = 0;
            fetch_count = 0;
            last_pc = 32'hFFFFFFFF;
            ebreak_seen = 0;
            
            #(CLK_PERIOD * 5);
            rst_n = 1;
            
            // Run until EBREAK or timeout
            test_cycles = 0;
            while (!ebreak_seen && test_cycles < max_cycles) begin
                @(posedge clk);
                test_cycles = test_cycles + 1;
            end
            
            // Wait a bit for final instruction
            repeat(10) @(posedge clk);
            
            // Report
            test_instrs = instr_count;
            if (test_instrs > 0) begin
                cpi = cycle_count * 1.0 / test_instrs;
                $display("  Cycles: %0d, Instructions: %0d, CPI: %0.3f", 
                         cycle_count, test_instrs, cpi);
            end else begin
                $display("  No instructions completed!");
            end
        end
    endtask
    
    initial begin
        $dumpfile("sim/waves/cpi_nocache.vcd");
        $dumpvars(0, tb_cpi_nocache);
        
        $display("============================================================");
        $display("       IF Stage CPI Benchmark (No Cache)");
        $display("       Measures fetch-only performance");
        $display("============================================================");
        
        // Initialize
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 8'h00;
        
        rst_n = 0;
        cycle_count = 0;
        instr_count = 0;
        fetch_count = 0;
        stall_if = 0;
        flush_if = 0;
        redirect_valid = 0;
        redirect_pc = 0;
        ghr = 0;
        
        // Test 1: ALU sequence
        load_alu_test();
        run_test("Test 1: ALU Sequence (11 instructions)", 500);
        
        $display("");
        $display("============================================================");
        $display("       IF Stage Benchmark Complete");
        $display("       Note: CPI ~4 is expected for IF stage alone");
        $display("       (IDLE->FETCH->WAIT->complete = 4 cycles/instr)");
        $display("============================================================");
        
        #100;
        $finish;
    end

endmodule
