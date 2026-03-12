//==============================================================================
// Real CPI Pipeline Benchmark
// 测量 IF + ID 流水线的真实性能
//==============================================================================
`timescale 1ns/1ps
`include "cpu_defines.vh"

module tb_cpi_pipeline;

    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;
    parameter MEM_SIZE = 65536;
    parameter MEM_BASE = 32'h8000_0000;
    parameter GHR_WIDTH = 64;
    
    reg clk;
    reg rst_n;
    
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Performance counters
    integer cycle_count;
    integer fetch_count;
    integer decode_count;
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
    
    reg         bpu_pred_taken;
    reg  [31:0] bpu_pred_target;
    reg  [1:0]  bpu_pred_type;
    
    wire        if_id_valid;
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;
    wire        if_id_pred_taken;
    wire [31:0] if_id_pred_target;
    wire [1:0]  if_id_pred_type;
    wire [GHR_WIDTH-1:0] if_id_ghr;
    
    reg         stall_if;
    reg         flush_if;
    reg         redirect_valid;
    reg  [31:0] redirect_pc;
    reg  [GHR_WIDTH-1:0] ghr;
    
    //=========================================================
    // ID Stage Signals
    //=========================================================
    wire        id_rn_valid;
    wire [31:0] id_rn_pc;
    wire [31:0] id_rn_instr;
    wire [4:0]  id_rn_rd;
    wire [4:0]  id_rn_rs1;
    wire [4:0]  id_rn_rs2;
    wire [31:0] id_rn_imm;
    wire [3:0]  id_rn_alu_op;
    wire [1:0]  id_rn_alu_src1;
    wire [1:0]  id_rn_alu_src2;
    wire        id_rn_reg_write;
    wire        id_rn_mem_read;
    wire        id_rn_mem_write;
    wire        id_rn_branch;
    wire        id_rn_jump;
    wire [2:0]  id_rn_fu_type;
    wire [1:0]  id_rn_mem_size;
    wire        id_rn_mem_sign_ext;
    wire        id_rn_csr_op;
    wire [2:0]  id_rn_csr_type;
    wire        id_rn_pred_taken;
    wire [31:0] id_rn_pred_target;
    wire [GHR_WIDTH-1:0] id_rn_ghr;
    wire        id_rn_illegal;
    
    reg         stall_id;
    reg         flush_id;
    
    //=========================================================
    // IF Stage Instance
    //=========================================================
    if_stage #(
        .XLEN(XLEN),
        .GHR_WIDTH(GHR_WIDTH)
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
        .bpu_req_o          (),
        .bpu_pc_o           (),
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
    // ID Stage Instance
    //=========================================================
    id_stage #(
        .XLEN(XLEN),
        .GHR_WIDTH(GHR_WIDTH)
    ) u_id_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .stall_i            (stall_id),
        .flush_i            (flush_id),
        .if_valid_i         (if_id_valid),
        .if_pc_i            (if_id_pc),
        .if_instr_i         (if_id_instr),
        .if_pred_taken_i    (if_id_pred_taken),
        .if_pred_target_i   (if_id_pred_target),
        .if_pred_type_i     (if_id_pred_type),
        .if_ghr_i           (if_id_ghr),
        .rn_valid_o         (id_rn_valid),
        .rn_pc_o            (id_rn_pc),
        .rn_instr_o         (id_rn_instr),
        .rn_rd_o            (id_rn_rd),
        .rn_rs1_o           (id_rn_rs1),
        .rn_rs2_o           (id_rn_rs2),
        .rn_imm_o           (id_rn_imm),
        .rn_alu_op_o        (id_rn_alu_op),
        .rn_alu_src1_o      (id_rn_alu_src1),
        .rn_alu_src2_o      (id_rn_alu_src2),
        .rn_reg_write_o     (id_rn_reg_write),
        .rn_mem_read_o      (id_rn_mem_read),
        .rn_mem_write_o     (id_rn_mem_write),
        .rn_branch_o        (id_rn_branch),
        .rn_jump_o          (id_rn_jump),
        .rn_fu_type_o       (id_rn_fu_type),
        .rn_mem_size_o      (id_rn_mem_size),
        .rn_mem_sign_ext_o  (id_rn_mem_sign_ext),
        .rn_csr_op_o        (id_rn_csr_op),
        .rn_csr_type_o      (id_rn_csr_type),
        .rn_pred_taken_o    (id_rn_pred_taken),
        .rn_pred_target_o   (id_rn_pred_target),
        .rn_ghr_o           (id_rn_ghr),
        .rn_illegal_o       (id_rn_illegal)
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
        end else begin
            case (mem_state)
                0: begin
                    icache_req_ready <= 1'b1;
                    icache_resp_valid <= 1'b0;
                    if (icache_req_valid && icache_req_ready) begin
                        mem_addr_reg <= icache_req_addr;
                        icache_req_ready <= 1'b0;
                        mem_state <= 1;
                    end
                end
                1: begin
                    icache_resp_valid <= 1'b1;
                    if (mem_addr_reg >= MEM_BASE && mem_addr_reg < MEM_BASE + MEM_SIZE) begin
                        icache_resp_data <= {
                            memory[mem_addr_reg - MEM_BASE + 3],
                            memory[mem_addr_reg - MEM_BASE + 2],
                            memory[mem_addr_reg - MEM_BASE + 1],
                            memory[mem_addr_reg - MEM_BASE + 0]
                        };
                    end else begin
                        icache_resp_data <= 32'h00000013;
                    end
                    mem_state <= 0;
                end
            endcase
        end
    end
    
    //=========================================================
    // BPU (always not taken)
    //=========================================================
    always @(*) begin
        bpu_pred_taken = 1'b0;
        bpu_pred_target = 32'd0;
        bpu_pred_type = 2'b00;
    end
    
    //=========================================================
    // Counters
    //=========================================================
    reg [31:0] last_fetch_pc;
    reg [31:0] last_decode_pc;
    reg        ebreak_seen;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            fetch_count <= 0;
            decode_count <= 0;
            last_fetch_pc <= 32'hFFFFFFFF;
            last_decode_pc <= 32'hFFFFFFFF;
            ebreak_seen <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            
            // Count fetches
            if (if_id_valid && !stall_if && (if_id_pc != last_fetch_pc)) begin
                last_fetch_pc <= if_id_pc;
                fetch_count <= fetch_count + 1;
            end
            
            // Count decodes
            if (id_rn_valid && !stall_id && (id_rn_pc != last_decode_pc)) begin
                last_decode_pc <= id_rn_pc;
                decode_count <= decode_count + 1;
                
                // Check for EBREAK
                if (id_rn_instr == 32'h00100073) begin
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
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100093; addr = addr + 4; // addi x1, x0, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00200113; addr = addr + 4; // addi x2, x0, 2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00300193; addr = addr + 4; // addi x3, x0, 3
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00400213; addr = addr + 4; // addi x4, x0, 4
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00500293; addr = addr + 4; // addi x5, x0, 5
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00208333; addr = addr + 4; // add x6, x1, x2
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h004183b3; addr = addr + 4; // add x7, x3, x4
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00628433; addr = addr + 4; // add x8, x5, x6
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h008384b3; addr = addr + 4; // add x9, x7, x8
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00148533; addr = addr + 4; // add x10, x9, x1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4; // ebreak
        end
    endtask
    
    task load_dependency_test;
        integer addr;
        begin
            addr = 0;
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100093; addr = addr + 4; // addi x1, x0, 1
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00108113; addr = addr + 4; // addi x2, x1, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00110193; addr = addr + 4; // addi x3, x2, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00118213; addr = addr + 4; // addi x4, x3, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00120293; addr = addr + 4; // addi x5, x4, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00128313; addr = addr + 4; // addi x6, x5, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00130393; addr = addr + 4; // addi x7, x6, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00138413; addr = addr + 4; // addi x8, x7, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00140493; addr = addr + 4; // addi x9, x8, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00148513; addr = addr + 4; // addi x10, x9, 1 (RAW)
            {memory[addr+3], memory[addr+2], memory[addr+1], memory[addr]} = 32'h00100073; addr = addr + 4; // ebreak
        end
    endtask

    //=========================================================
    // Main Test
    //=========================================================
    task run_test;
        input [255:0] test_name;
        input integer max_cycles;
        integer test_cycles;
        begin
            $display("\n--- %0s ---", test_name);
            
            rst_n = 0;
            cycle_count = 0;
            fetch_count = 0;
            decode_count = 0;
            last_fetch_pc = 32'hFFFFFFFF;
            last_decode_pc = 32'hFFFFFFFF;
            ebreak_seen = 0;
            
            #(CLK_PERIOD * 5);
            rst_n = 1;
            
            test_cycles = 0;
            while (!ebreak_seen && test_cycles < max_cycles) begin
                @(posedge clk);
                test_cycles = test_cycles + 1;
            end
            
            repeat(10) @(posedge clk);
            
            if (decode_count > 0) begin
                cpi = cycle_count * 1.0 / decode_count;
                $display("  Cycles: %0d, Fetched: %0d, Decoded: %0d", 
                         cycle_count, fetch_count, decode_count);
                $display("  Fetch CPI: %0.3f, Decode CPI: %0.3f", 
                         cycle_count * 1.0 / fetch_count, cpi);
            end else begin
                $display("  No instructions decoded!");
            end
        end
    endtask
    
    initial begin
        $dumpfile("sim/waves/cpi_pipeline.vcd");
        $dumpvars(0, tb_cpi_pipeline);
        
        $display("============================================================");
        $display("       IF+ID Pipeline CPI Benchmark");
        $display("============================================================");
        
        for (i = 0; i < MEM_SIZE; i = i + 1)
            memory[i] = 8'h00;
        
        rst_n = 0;
        stall_if = 0;
        stall_id = 0;
        flush_if = 0;
        flush_id = 0;
        redirect_valid = 0;
        redirect_pc = 0;
        ghr = 0;
        
        // Test 1: Independent ALU
        load_alu_test();
        run_test("Test 1: Independent ALU (11 instr)", 500);
        
        // Test 2: Dependency chain
        for (i = 0; i < MEM_SIZE; i = i + 1) memory[i] = 8'h00;
        load_dependency_test();
        run_test("Test 2: RAW Dependency Chain (11 instr)", 500);
        
        $display("");
        $display("============================================================");
        $display("       Pipeline Benchmark Complete");
        $display("============================================================");
        
        #100;
        $finish;
    end

endmodule
