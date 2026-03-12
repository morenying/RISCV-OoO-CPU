//==============================================================================
// Reservation Station 精简波形测试 - 覆盖分配/CDB捕获/发射，约25周期
//==============================================================================
`timescale 1ns/1ps

module tb_rs_wave;
    reg clk, rst_n, flush_i;
    // Dispatch
    reg dispatch_valid_i, dispatch_src1_ready_i, dispatch_src2_ready_i, dispatch_use_imm_i;
    reg [3:0] dispatch_op_i;
    reg [5:0] dispatch_src1_preg_i, dispatch_src2_preg_i, dispatch_dst_preg_i;
    reg [31:0] dispatch_src1_data_i, dispatch_src2_data_i, dispatch_imm_i, dispatch_pc_i;
    reg [4:0] dispatch_rob_idx_i;
    wire dispatch_ready_o;
    // Issue
    wire issue_valid_o;
    reg issue_ready_i;
    wire [3:0] issue_op_o;
    wire [31:0] issue_src1_data_o, issue_src2_data_o, issue_pc_o;
    wire [5:0] issue_dst_preg_o;
    wire [4:0] issue_rob_idx_o;
    // CDB
    reg cdb_valid_i;
    reg [5:0] cdb_preg_i;
    reg [31:0] cdb_data_i;
    // Status
    wire empty_o, full_o;

    reservation_station #(.NUM_ENTRIES(4), .ENTRY_IDX_BITS(2)) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/rs_wave.vcd");
        $dumpvars(0, tb_rs_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== RS Wave Test ===");
        rst_n = 0; flush_i = 0; dispatch_valid_i = 0; issue_ready_i = 0; cdb_valid_i = 0;
        dispatch_op_i = 0; dispatch_src1_preg_i = 0; dispatch_src2_preg_i = 0;
        dispatch_src1_data_i = 0; dispatch_src2_data_i = 0; dispatch_src1_ready_i = 0;
        dispatch_src2_ready_i = 0; dispatch_dst_preg_i = 0; dispatch_rob_idx_i = 0;
        dispatch_imm_i = 0; dispatch_use_imm_i = 0; dispatch_pc_i = 0;
        cdb_preg_i = 0; cdb_data_i = 0;
        #20 rst_n = 1; #10;

        // Dispatch entry with both operands ready
        dispatch_valid_i = 1; dispatch_op_i = 4'b0000;
        dispatch_src1_preg_i = 1; dispatch_src1_data_i = 32'h100; dispatch_src1_ready_i = 1;
        dispatch_src2_preg_i = 2; dispatch_src2_data_i = 32'h200; dispatch_src2_ready_i = 1;
        dispatch_dst_preg_i = 32; dispatch_rob_idx_i = 0; dispatch_pc_i = 32'h1000;
        #10; // Wait for dispatch to be captured at clock edge
        dispatch_valid_i = 0;
        #10; // Entry is now valid in RS, issue logic should see it ready
        #2;  // Extra delay for combinational logic

        // Check issue output (issue_ready_i=0 so entry stays in RS)
        if (issue_valid_o && issue_src1_data_o == 32'h100) begin
            pass = pass + 1; $display("PASS: Ready entry issued");
        end else begin
            fail = fail + 1; $display("FAIL: Ready entry not issued (valid=%b, src1=%h)", issue_valid_o, issue_src1_data_o);
        end

        // Now allow issue to complete
        issue_ready_i = 1;
        #10; // Entry is deallocated
        issue_ready_i = 0;
        #10;

        // Dispatch entry waiting for operand (src1 not ready)
        dispatch_valid_i = 1;
        dispatch_src1_preg_i = 33; dispatch_src1_data_i = 0; dispatch_src1_ready_i = 0;
        dispatch_src2_preg_i = 0; dispatch_src2_data_i = 32'h50; dispatch_src2_ready_i = 1;
        dispatch_dst_preg_i = 34; dispatch_rob_idx_i = 1;
        #10; // Wait for dispatch
        dispatch_valid_i = 0;
        #10; // Entry is now in RS but not ready (waiting for src1)

        // CDB broadcast P33 - this should wake up the entry
        cdb_valid_i = 1; cdb_preg_i = 33; cdb_data_i = 32'hABCD;
        #10; // CDB captured at clock edge, src1_ready becomes 1
        cdb_valid_i = 0;
        #10; // Wait for issue logic to see the ready entry
        #2;  // Extra delay for stability

        // Should issue now with CDB data (issue_ready_i=0 so entry stays)
        if (issue_valid_o && issue_src1_data_o == 32'hABCD) begin
            pass = pass + 1; $display("PASS: CDB wakeup worked");
        end else begin
            fail = fail + 1; $display("FAIL: CDB wakeup (valid=%b, src1=%h)", issue_valid_o, issue_src1_data_o);
        end

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
