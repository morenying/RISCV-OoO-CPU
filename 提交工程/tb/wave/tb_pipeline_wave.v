//==============================================================================
// Pipeline Control 精简波形测试 - 覆盖stall/flush/redirect，约20周期
//==============================================================================
`timescale 1ns/1ps

module tb_pipeline_wave;
    reg clk, rst_n;
    // Resource availability
    reg rob_full_i, rs_alu_full_i, rs_mul_full_i, rs_lsu_full_i, rs_br_full_i;
    reg lq_full_i, sq_full_i, free_list_empty_i;
    // Cache status
    reg icache_miss_i, dcache_miss_i;
    // Branch misprediction
    reg branch_mispredict_i;
    reg [31:0] branch_target_i;
    reg [2:0] branch_checkpoint_i;
    // Exception
    reg exception_i;
    reg [31:0] exception_pc_i;
    // MRET
    reg mret_i;
    reg [31:0] mepc_i, mtvec_i;
    // Outputs
    wire stall_if_o, stall_id_o, stall_rn_o, stall_is_o, stall_ex_o, stall_mem_o, stall_wb_o;
    wire flush_if_o, flush_id_o, flush_rn_o, flush_is_o, flush_ex_o, flush_mem_o;
    wire recover_o, redirect_valid_o;
    wire [2:0] recover_checkpoint_o;
    wire [31:0] redirect_pc_o;

    pipeline_ctrl dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/pipeline_wave.vcd");
        $dumpvars(0, tb_pipeline_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== Pipeline Control Wave Test ===");
        rst_n = 0;
        rob_full_i = 0; rs_alu_full_i = 0; rs_mul_full_i = 0; rs_lsu_full_i = 0; rs_br_full_i = 0;
        lq_full_i = 0; sq_full_i = 0; free_list_empty_i = 0;
        icache_miss_i = 0; dcache_miss_i = 0;
        branch_mispredict_i = 0; branch_target_i = 0; branch_checkpoint_i = 0;
        exception_i = 0; exception_pc_i = 0;
        mret_i = 0; mepc_i = 32'h2000; mtvec_i = 32'h100;
        #20 rst_n = 1; #10;

        // Test ROB full stall
        @(posedge clk);
        rob_full_i = 1;
        #1;
        if (stall_is_o) begin pass = pass + 1; $display("PASS: ROB full stalls IS"); end
        else begin fail = fail + 1; $display("FAIL: ROB full stall"); end
        @(posedge clk);
        rob_full_i = 0;

        // Test I-cache miss stall
        @(posedge clk);
        icache_miss_i = 1;
        #1;
        if (stall_if_o) begin pass = pass + 1; $display("PASS: I-cache miss stalls IF"); end
        else begin fail = fail + 1; $display("FAIL: I-cache miss stall"); end
        @(posedge clk);
        icache_miss_i = 0;

        // Test branch misprediction flush
        @(posedge clk);
        branch_mispredict_i = 1; branch_target_i = 32'h3000; branch_checkpoint_i = 2;
        #1;
        if (flush_if_o && redirect_valid_o && redirect_pc_o == 32'h3000) begin
            pass = pass + 1; $display("PASS: Branch mispredict flush");
        end else begin
            fail = fail + 1; $display("FAIL: Branch mispredict");
        end
        @(posedge clk);
        branch_mispredict_i = 0;

        // Test exception flush
        @(posedge clk);
        exception_i = 1; exception_pc_i = 32'h1000;
        #1;
        if (flush_if_o && redirect_pc_o == mtvec_i) begin
            pass = pass + 1; $display("PASS: Exception redirects to mtvec");
        end else begin
            fail = fail + 1; $display("FAIL: Exception redirect");
        end
        @(posedge clk);
        exception_i = 0;

        // Test MRET
        @(posedge clk);
        mret_i = 1;
        #1;
        if (redirect_pc_o == mepc_i) begin
            pass = pass + 1; $display("PASS: MRET redirects to mepc");
        end else begin
            fail = fail + 1; $display("FAIL: MRET redirect");
        end
        @(posedge clk);
        mret_i = 0;

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
