//==============================================================================
// RAT 精简波形测试 - 覆盖重命名/CDB更新/检查点恢复，约25周期
//==============================================================================
`timescale 1ns/1ps

module tb_rat_wave;
    reg clk, rst_n;
    // Lookup
    reg [4:0] rs1_arch_i, rs2_arch_i;
    wire [5:0] rs1_phys_o, rs2_phys_o;
    wire rs1_ready_o, rs2_ready_o;
    // Rename
    reg rename_valid_i;
    reg [4:0] rd_arch_i;
    reg [5:0] rd_phys_new_i;
    wire [5:0] rd_phys_old_o;
    // CDB
    reg cdb_valid_i;
    reg [5:0] cdb_preg_i;
    // Checkpoint
    reg checkpoint_create_i, recover_i;
    reg [2:0] checkpoint_id_i, recover_id_i;
    // Commit
    reg commit_valid_i;
    reg [4:0] commit_rd_arch_i;
    reg [5:0] commit_rd_phys_i;

    rat dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/rat_wave.vcd");
        $dumpvars(0, tb_rat_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== RAT Wave Test ===");
        rst_n = 0; rename_valid_i = 0; cdb_valid_i = 0;
        checkpoint_create_i = 0; recover_i = 0; commit_valid_i = 0;
        rs1_arch_i = 0; rs2_arch_i = 0; rd_arch_i = 0; rd_phys_new_i = 0;
        cdb_preg_i = 0; checkpoint_id_i = 0; recover_id_i = 0;
        commit_rd_arch_i = 0; commit_rd_phys_i = 0;
        #20 rst_n = 1; #10;

        // Check x0 always maps to P0
        @(posedge clk);
        rs1_arch_i = 0;
        #1;
        if (rs1_phys_o == 6'd0 && rs1_ready_o == 1'b1) begin
            pass = pass + 1; $display("PASS: x0 -> P0");
        end else begin
            fail = fail + 1; $display("FAIL: x0 mapping");
        end

        // Rename x1 -> P32
        @(posedge clk);
        rename_valid_i = 1; rd_arch_i = 1; rd_phys_new_i = 32;
        @(posedge clk);
        rename_valid_i = 0;

        // Check x1 maps to P32 and not ready
        @(posedge clk);
        rs1_arch_i = 1;
        #1;
        if (rs1_phys_o == 6'd32 && rs1_ready_o == 1'b0) begin
            pass = pass + 1; $display("PASS: x1 -> P32, not ready");
        end else begin
            fail = fail + 1; $display("FAIL: x1 rename");
        end

        // Create checkpoint
        @(posedge clk);
        checkpoint_create_i = 1; checkpoint_id_i = 0;
        @(posedge clk);
        checkpoint_create_i = 0;

        // Rename x1 -> P33
        @(posedge clk);
        rename_valid_i = 1; rd_arch_i = 1; rd_phys_new_i = 33;
        @(posedge clk);
        rename_valid_i = 0;

        // Recover to checkpoint 0
        @(posedge clk);
        recover_i = 1; recover_id_i = 0;
        @(posedge clk);
        recover_i = 0;

        // Check x1 restored to P32
        @(posedge clk);
        rs1_arch_i = 1;
        #1;
        if (rs1_phys_o == 6'd32) begin
            pass = pass + 1; $display("PASS: x1 restored to P32");
        end else begin
            fail = fail + 1; $display("FAIL: checkpoint recovery");
        end

        // CDB broadcast P32 ready
        @(posedge clk);
        cdb_valid_i = 1; cdb_preg_i = 32;
        @(posedge clk);
        cdb_valid_i = 0;

        @(posedge clk);
        #1;
        if (rs1_ready_o == 1'b1) begin
            pass = pass + 1; $display("PASS: P32 now ready");
        end else begin
            fail = fail + 1; $display("FAIL: CDB broadcast");
        end

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
