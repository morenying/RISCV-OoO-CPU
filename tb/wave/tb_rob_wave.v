//==============================================================================
// ROB 精简波形测试 - 覆盖分配/完成/提交流程，约30周期
//==============================================================================
`timescale 1ns/1ps

module tb_rob_wave;
    reg clk, rst_n, flush_i;
    // Allocation
    reg alloc_req_i;
    reg [4:0] alloc_rd_arch_i;
    reg [5:0] alloc_rd_phys_i, alloc_rd_phys_old_i;
    reg [31:0] alloc_pc_i;
    reg [3:0] alloc_instr_type_i;
    reg alloc_is_branch_i, alloc_is_store_i;
    wire alloc_ready_o;
    wire [4:0] alloc_idx_o;
    // Completion
    reg complete_valid_i;
    reg [4:0] complete_idx_i;
    reg [31:0] complete_result_i, complete_branch_target_i;
    reg complete_exception_i, complete_branch_taken_i;
    reg [3:0] complete_exc_code_i;
    // Commit
    wire commit_valid_o;
    reg commit_ready_i;
    wire [4:0] commit_idx_o, commit_rd_arch_o;
    wire [5:0] commit_rd_phys_o, commit_rd_phys_old_o;
    wire [31:0] commit_result_o, commit_pc_o, commit_branch_target_o;
    wire commit_is_branch_o, commit_branch_taken_o, commit_is_store_o;
    wire commit_exception_o;
    wire [3:0] commit_exc_code_o;
    wire empty_o, full_o;
    wire [5:0] count_o;

    rob dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/rob_wave.vcd");
        $dumpvars(0, tb_rob_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== ROB Wave Test ===");
        rst_n = 0; flush_i = 0; alloc_req_i = 0; complete_valid_i = 0; commit_ready_i = 1;
        alloc_rd_arch_i = 0; alloc_rd_phys_i = 0; alloc_rd_phys_old_i = 0;
        alloc_pc_i = 0; alloc_instr_type_i = 0; alloc_is_branch_i = 0; alloc_is_store_i = 0;
        complete_idx_i = 0; complete_result_i = 0; complete_exception_i = 0;
        complete_exc_code_i = 0; complete_branch_taken_i = 0; complete_branch_target_i = 0;
        #25; // 等待复位完成（在时钟沿之间）
        rst_n = 1;
        #10; // 等待一个时钟周期
        
        // 分配阶段禁用 commit
        commit_ready_i = 0;

        // Allocate entry 0
        alloc_req_i = 1; alloc_rd_arch_i = 1; alloc_rd_phys_i = 32; alloc_pc_i = 32'h1000;
        #10;
        
        // Allocate entry 1
        alloc_rd_arch_i = 2; alloc_rd_phys_i = 33; alloc_pc_i = 32'h1004;
        #10;
        
        // Allocate entry 2
        alloc_rd_arch_i = 3; alloc_rd_phys_i = 34; alloc_pc_i = 32'h1008;
        #10;
        
        alloc_req_i = 0;
        #10;

        // Complete entry 0 (标记为完成)
        complete_valid_i = 1; complete_idx_i = 0; complete_result_i = 32'hDEAD;
        #10;
        complete_valid_i = 0;
        #2; // 等待组合逻辑稳定
        
        // 现在启用 commit
        commit_ready_i = 1;

        if (commit_valid_o && commit_result_o == 32'hDEAD) begin
            pass = pass + 1; $display("PASS: Commit result=%h", commit_result_o);
        end else begin
            fail = fail + 1; $display("FAIL: Commit valid=%b result=%h", commit_valid_o, commit_result_o);
        end

        // 等待 commit 完成（commit_ready_i=1，所以会自动提交）
        #10; // head 移动到 1

        // Complete remaining entries
        complete_valid_i = 1; complete_idx_i = 1; complete_result_i = 32'hBEEF;
        #10;
        complete_idx_i = 2; complete_result_i = 32'hCAFE;
        #10;
        complete_valid_i = 0;

        #50;

        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
