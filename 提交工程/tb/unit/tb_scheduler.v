//=================================================================
// Testbench: tb_scheduler
// Description: Testbench for Reservation Station and ROB
//              Tests dispatch, issue, completion, and commit
//              Validates data forwarding and in-order commit
// Requirements: 4.1-4.6, 5.1, 5.2, 6.1
//=================================================================

`timescale 1ns/1ps

module tb_scheduler;

    //=========================================================
    // Parameters
    //=========================================================
    parameter CLK_PERIOD = 10;
    parameter NUM_RS_ENTRIES = 4;
    parameter NUM_ROB_ENTRIES = 32;
    parameter PHYS_REG_BITS = 6;
    parameter ROB_IDX_BITS = 5;
    parameter DATA_WIDTH = 32;

    //=========================================================
    // Clock and Reset
    //=========================================================
    reg clk;
    reg rst_n;
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================
    // Reservation Station Signals
    //=========================================================
    reg                     rs_dispatch_valid;
    wire                    rs_dispatch_ready;
    reg  [3:0]              rs_dispatch_op;
    reg  [PHYS_REG_BITS-1:0] rs_dispatch_src1_preg;
    reg  [DATA_WIDTH-1:0]   rs_dispatch_src1_data;
    reg                     rs_dispatch_src1_ready;
    reg  [PHYS_REG_BITS-1:0] rs_dispatch_src2_preg;
    reg  [DATA_WIDTH-1:0]   rs_dispatch_src2_data;
    reg                     rs_dispatch_src2_ready;
    reg  [PHYS_REG_BITS-1:0] rs_dispatch_dst_preg;
    reg  [ROB_IDX_BITS-1:0] rs_dispatch_rob_idx;
    reg  [DATA_WIDTH-1:0]   rs_dispatch_imm;
    reg                     rs_dispatch_use_imm;
    reg  [DATA_WIDTH-1:0]   rs_dispatch_pc;
    
    wire                    rs_issue_valid;
    reg                     rs_issue_ready;
    wire [3:0]              rs_issue_op;
    wire [DATA_WIDTH-1:0]   rs_issue_src1_data;
    wire [DATA_WIDTH-1:0]   rs_issue_src2_data;
    wire [PHYS_REG_BITS-1:0] rs_issue_dst_preg;
    wire [ROB_IDX_BITS-1:0] rs_issue_rob_idx;
    wire [DATA_WIDTH-1:0]   rs_issue_pc;
    
    reg                     rs_cdb_valid;
    reg  [PHYS_REG_BITS-1:0] rs_cdb_preg;
    reg  [DATA_WIDTH-1:0]   rs_cdb_data;
    
    reg                     rs_flush;
    wire                    rs_empty;
    wire                    rs_full;

    //=========================================================
    // ROB Signals
    //=========================================================
    reg                     rob_alloc_req;
    wire                    rob_alloc_ready;
    wire [ROB_IDX_BITS-1:0] rob_alloc_idx;
    reg  [4:0]              rob_alloc_rd_arch;
    reg  [PHYS_REG_BITS-1:0] rob_alloc_rd_phys;
    reg  [PHYS_REG_BITS-1:0] rob_alloc_rd_phys_old;
    reg  [DATA_WIDTH-1:0]   rob_alloc_pc;
    reg  [3:0]              rob_alloc_instr_type;
    reg                     rob_alloc_is_branch;
    reg                     rob_alloc_is_store;
    
    reg                     rob_complete_valid;
    reg  [ROB_IDX_BITS-1:0] rob_complete_idx;
    reg  [DATA_WIDTH-1:0]   rob_complete_result;
    reg                     rob_complete_exception;
    reg  [3:0]              rob_complete_exc_code;
    reg                     rob_complete_branch_taken;
    reg  [DATA_WIDTH-1:0]   rob_complete_branch_target;
    
    wire                    rob_commit_valid;
    reg                     rob_commit_ready;
    wire [ROB_IDX_BITS-1:0] rob_commit_idx;
    wire [4:0]              rob_commit_rd_arch;
    wire [PHYS_REG_BITS-1:0] rob_commit_rd_phys;
    wire [PHYS_REG_BITS-1:0] rob_commit_rd_phys_old;
    wire [DATA_WIDTH-1:0]   rob_commit_result;
    wire [DATA_WIDTH-1:0]   rob_commit_pc;
    wire                    rob_commit_is_branch;
    wire                    rob_commit_branch_taken;
    wire [DATA_WIDTH-1:0]   rob_commit_branch_target;
    wire                    rob_commit_is_store;
    wire                    rob_commit_exception;
    wire [3:0]              rob_commit_exc_code;
    
    reg                     rob_flush;
    wire                    rob_empty;
    wire                    rob_full;
    wire [ROB_IDX_BITS:0]   rob_count;

    //=========================================================
    // DUT Instantiation
    //=========================================================
    reservation_station #(
        .NUM_ENTRIES(NUM_RS_ENTRIES),
        .ENTRY_IDX_BITS(2),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(DATA_WIDTH),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .ALU_OP_WIDTH(4)
    ) u_rs (
        .clk                (clk),
        .rst_n              (rst_n),
        .dispatch_valid_i   (rs_dispatch_valid),
        .dispatch_ready_o   (rs_dispatch_ready),
        .dispatch_op_i      (rs_dispatch_op),
        .dispatch_src1_preg_i(rs_dispatch_src1_preg),
        .dispatch_src1_data_i(rs_dispatch_src1_data),
        .dispatch_src1_ready_i(rs_dispatch_src1_ready),
        .dispatch_src2_preg_i(rs_dispatch_src2_preg),
        .dispatch_src2_data_i(rs_dispatch_src2_data),
        .dispatch_src2_ready_i(rs_dispatch_src2_ready),
        .dispatch_dst_preg_i(rs_dispatch_dst_preg),
        .dispatch_rob_idx_i (rs_dispatch_rob_idx),
        .dispatch_imm_i     (rs_dispatch_imm),
        .dispatch_use_imm_i (rs_dispatch_use_imm),
        .dispatch_pc_i      (rs_dispatch_pc),
        .issue_valid_o      (rs_issue_valid),
        .issue_ready_i      (rs_issue_ready),
        .issue_op_o         (rs_issue_op),
        .issue_src1_data_o  (rs_issue_src1_data),
        .issue_src2_data_o  (rs_issue_src2_data),
        .issue_dst_preg_o   (rs_issue_dst_preg),
        .issue_rob_idx_o    (rs_issue_rob_idx),
        .issue_pc_o         (rs_issue_pc),
        .cdb_valid_i        (rs_cdb_valid),
        .cdb_preg_i         (rs_cdb_preg),
        .cdb_data_i         (rs_cdb_data),
        .flush_i            (rs_flush),
        .empty_o            (rs_empty),
        .full_o             (rs_full)
    );

    rob #(
        .NUM_ENTRIES(NUM_ROB_ENTRIES),
        .ROB_IDX_BITS(ROB_IDX_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .ARCH_REG_BITS(5),
        .DATA_WIDTH(DATA_WIDTH),
        .EXC_CODE_WIDTH(4)
    ) u_rob (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .alloc_req_i            (rob_alloc_req),
        .alloc_ready_o          (rob_alloc_ready),
        .alloc_idx_o            (rob_alloc_idx),
        .alloc_rd_arch_i        (rob_alloc_rd_arch),
        .alloc_rd_phys_i        (rob_alloc_rd_phys),
        .alloc_rd_phys_old_i    (rob_alloc_rd_phys_old),
        .alloc_pc_i             (rob_alloc_pc),
        .alloc_instr_type_i     (rob_alloc_instr_type),
        .alloc_is_branch_i      (rob_alloc_is_branch),
        .alloc_is_store_i       (rob_alloc_is_store),
        .complete_valid_i       (rob_complete_valid),
        .complete_idx_i         (rob_complete_idx),
        .complete_result_i      (rob_complete_result),
        .complete_exception_i   (rob_complete_exception),
        .complete_exc_code_i    (rob_complete_exc_code),
        .complete_branch_taken_i(rob_complete_branch_taken),
        .complete_branch_target_i(rob_complete_branch_target),
        .commit_valid_o         (rob_commit_valid),
        .commit_ready_i         (rob_commit_ready),
        .commit_idx_o           (rob_commit_idx),
        .commit_rd_arch_o       (rob_commit_rd_arch),
        .commit_rd_phys_o       (rob_commit_rd_phys),
        .commit_rd_phys_old_o   (rob_commit_rd_phys_old),
        .commit_result_o        (rob_commit_result),
        .commit_pc_o            (rob_commit_pc),
        .commit_is_branch_o     (rob_commit_is_branch),
        .commit_branch_taken_o  (rob_commit_branch_taken),
        .commit_branch_target_o (rob_commit_branch_target),
        .commit_is_store_o      (rob_commit_is_store),
        .commit_exception_o     (rob_commit_exception),
        .commit_exc_code_o      (rob_commit_exc_code),
        .flush_i                (rob_flush),
        .empty_o                (rob_empty),
        .full_o                 (rob_full),
        .count_o                (rob_count)
    );

    //=========================================================
    // Test Counters
    //=========================================================
    integer test_count;
    integer pass_count;
    integer fail_count;

    //=========================================================
    // Test Tasks
    //=========================================================
    task reset_inputs;
        begin
            rs_dispatch_valid = 0;
            rs_dispatch_op = 0;
            rs_dispatch_src1_preg = 0;
            rs_dispatch_src1_data = 0;
            rs_dispatch_src1_ready = 0;
            rs_dispatch_src2_preg = 0;
            rs_dispatch_src2_data = 0;
            rs_dispatch_src2_ready = 0;
            rs_dispatch_dst_preg = 0;
            rs_dispatch_rob_idx = 0;
            rs_dispatch_imm = 0;
            rs_dispatch_use_imm = 0;
            rs_dispatch_pc = 0;
            rs_issue_ready = 1;
            rs_cdb_valid = 0;
            rs_cdb_preg = 0;
            rs_cdb_data = 0;
            rs_flush = 0;
            
            rob_alloc_req = 0;
            rob_alloc_rd_arch = 0;
            rob_alloc_rd_phys = 0;
            rob_alloc_rd_phys_old = 0;
            rob_alloc_pc = 0;
            rob_alloc_instr_type = 0;
            rob_alloc_is_branch = 0;
            rob_alloc_is_store = 0;
            rob_complete_valid = 0;
            rob_complete_idx = 0;
            rob_complete_result = 0;
            rob_complete_exception = 0;
            rob_complete_exc_code = 0;
            rob_complete_branch_taken = 0;
            rob_complete_branch_target = 0;
            rob_commit_ready = 1;
            rob_flush = 0;
        end
    endtask

    task check_pass;
        input [255:0] test_name;
        input         condition;
        begin
            test_count = test_count + 1;
            if (condition) begin
                pass_count = pass_count + 1;
                $display("PASS: %s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %s", test_name);
            end
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $display("========================================");
        $display("Scheduler Testbench Starting");
        $display("========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize
        reset_inputs();
        rst_n = 0;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);
        
        //=====================================================
        // Test 1: RS Initial State
        //=====================================================
        $display("\n--- Test 1: RS Initial State ---");
        check_pass("RS initially empty", rs_empty);
        check_pass("RS not full", !rs_full);
        check_pass("RS dispatch ready", rs_dispatch_ready);
        check_pass("RS no issue", !rs_issue_valid);
        
        //=====================================================
        // Test 2: RS Dispatch with Ready Operands
        //=====================================================
        $display("\n--- Test 2: RS Dispatch with Ready Operands ---");
        rs_dispatch_valid = 1;
        rs_dispatch_op = 4'b0000;  // ADD
        rs_dispatch_src1_preg = 6'd1;
        rs_dispatch_src1_data = 32'h0000_0010;
        rs_dispatch_src1_ready = 1;
        rs_dispatch_src2_preg = 6'd2;
        rs_dispatch_src2_data = 32'h0000_0020;
        rs_dispatch_src2_ready = 1;
        rs_dispatch_dst_preg = 6'd3;
        rs_dispatch_rob_idx = 5'd0;
        rs_dispatch_pc = 32'h8000_0000;
        rs_issue_ready = 0;  // Don't issue yet
        @(posedge clk);
        rs_dispatch_valid = 0;
        #1;
        
        check_pass("RS not empty after dispatch", !rs_empty);
        check_pass("RS issue valid (operands ready)", rs_issue_valid);
        check_pass("RS issue src1 correct", rs_issue_src1_data == 32'h0000_0010);
        check_pass("RS issue src2 correct", rs_issue_src2_data == 32'h0000_0020);
        
        //=====================================================
        // Test 3: RS Issue
        //=====================================================
        $display("\n--- Test 3: RS Issue ---");
        rs_issue_ready = 1;
        @(posedge clk);
        #1;
        check_pass("RS empty after issue", rs_empty);
        
        //=====================================================
        // Test 4: RS Dispatch with Pending Operand
        //=====================================================
        $display("\n--- Test 4: RS Dispatch with Pending Operand ---");
        rs_dispatch_valid = 1;
        rs_dispatch_src1_preg = 6'd4;
        rs_dispatch_src1_data = 32'h0;
        rs_dispatch_src1_ready = 0;  // Not ready
        rs_dispatch_src2_preg = 6'd5;
        rs_dispatch_src2_data = 32'h0000_0030;
        rs_dispatch_src2_ready = 1;
        rs_dispatch_dst_preg = 6'd6;
        rs_dispatch_rob_idx = 5'd1;
        @(posedge clk);
        rs_dispatch_valid = 0;
        #1;
        
        check_pass("RS not empty", !rs_empty);
        check_pass("RS no issue (operand pending)", !rs_issue_valid);
        
        //=====================================================
        // Test 5: RS CDB Operand Capture
        //=====================================================
        $display("\n--- Test 5: RS CDB Operand Capture ---");
        rs_cdb_valid = 1;
        rs_cdb_preg = 6'd4;  // Match pending src1
        rs_cdb_data = 32'h0000_0040;
        @(posedge clk);
        rs_cdb_valid = 0;
        #1;
        
        check_pass("RS issue valid after CDB", rs_issue_valid);
        check_pass("RS captured CDB data", rs_issue_src1_data == 32'h0000_0040);
        
        // Issue the instruction
        @(posedge clk);
        #1;
        check_pass("RS empty after issue", rs_empty);
        
        //=====================================================
        // Test 6: RS Immediate Operand
        //=====================================================
        $display("\n--- Test 6: RS Immediate Operand ---");
        rs_dispatch_valid = 1;
        rs_dispatch_src1_preg = 6'd7;
        rs_dispatch_src1_data = 32'h0000_0050;
        rs_dispatch_src1_ready = 1;
        rs_dispatch_use_imm = 1;
        rs_dispatch_imm = 32'h0000_0100;
        rs_dispatch_dst_preg = 6'd8;
        rs_dispatch_rob_idx = 5'd2;
        @(posedge clk);
        rs_dispatch_valid = 0;
        #1;
        
        check_pass("RS issue valid with imm", rs_issue_valid);
        check_pass("RS src2 is immediate", rs_issue_src2_data == 32'h0000_0100);
        
        @(posedge clk);  // Issue
        reset_inputs();
        
        //=====================================================
        // Test 7: RS Flush
        //=====================================================
        $display("\n--- Test 7: RS Flush ---");
        // Dispatch some entries
        rs_dispatch_valid = 1;
        rs_dispatch_src1_ready = 1;
        rs_dispatch_src2_ready = 1;
        rs_issue_ready = 0;
        @(posedge clk);
        @(posedge clk);
        rs_dispatch_valid = 0;
        #1;
        check_pass("RS not empty before flush", !rs_empty);
        
        rs_flush = 1;
        @(posedge clk);
        rs_flush = 0;
        #1;
        check_pass("RS empty after flush", rs_empty);
        
        reset_inputs();
        
        //=====================================================
        // Test 8: ROB Initial State
        //=====================================================
        $display("\n--- Test 8: ROB Initial State ---");
        check_pass("ROB initially empty", rob_empty);
        check_pass("ROB not full", !rob_full);
        check_pass("ROB alloc ready", rob_alloc_ready);
        check_pass("ROB no commit", !rob_commit_valid);
        check_pass("ROB count = 0", rob_count == 0);
        
        //=====================================================
        // Test 9: ROB Allocation
        //=====================================================
        $display("\n--- Test 9: ROB Allocation ---");
        rob_alloc_req = 1;
        rob_alloc_rd_arch = 5'd1;
        rob_alloc_rd_phys = 6'd32;
        rob_alloc_rd_phys_old = 6'd1;
        rob_alloc_pc = 32'h8000_0000;
        rob_alloc_instr_type = 4'b0000;
        @(posedge clk);
        rob_alloc_req = 0;
        #1;
        
        check_pass("ROB not empty after alloc", !rob_empty);
        check_pass("ROB count = 1", rob_count == 1);
        check_pass("ROB no commit (not complete)", !rob_commit_valid);
        
        //=====================================================
        // Test 10: ROB Completion
        //=====================================================
        $display("\n--- Test 10: ROB Completion ---");
        rob_complete_valid = 1;
        rob_complete_idx = 5'd0;
        rob_complete_result = 32'hDEAD_BEEF;
        rob_complete_exception = 0;
        @(posedge clk);
        rob_complete_valid = 0;
        #1;
        
        check_pass("ROB commit valid after complete", rob_commit_valid);
        check_pass("ROB commit result correct", rob_commit_result == 32'hDEAD_BEEF);
        check_pass("ROB commit rd_arch correct", rob_commit_rd_arch == 5'd1);
        check_pass("ROB commit rd_phys correct", rob_commit_rd_phys == 6'd32);
        
        //=====================================================
        // Test 11: ROB Commit
        //=====================================================
        $display("\n--- Test 11: ROB Commit ---");
        rob_commit_ready = 1;
        @(posedge clk);
        #1;
        
        check_pass("ROB empty after commit", rob_empty);
        check_pass("ROB count = 0", rob_count == 0);
        
        //=====================================================
        // Test 12: ROB In-Order Commit
        //=====================================================
        $display("\n--- Test 12: ROB In-Order Commit ---");
        // Allocate 3 entries
        rob_alloc_req = 1;
        rob_alloc_rd_arch = 5'd1;
        rob_alloc_pc = 32'h8000_0000;
        @(posedge clk);
        rob_alloc_rd_arch = 5'd2;
        rob_alloc_pc = 32'h8000_0004;
        @(posedge clk);
        rob_alloc_rd_arch = 5'd3;
        rob_alloc_pc = 32'h8000_0008;
        @(posedge clk);
        rob_alloc_req = 0;
        #1;
        check_pass("ROB count = 3", rob_count == 3);
        
        // Complete entry 2 (out of order)
        rob_complete_valid = 1;
        rob_complete_idx = 5'd2;
        rob_complete_result = 32'h3333_3333;
        @(posedge clk);
        rob_complete_valid = 0;
        #1;
        check_pass("ROB no commit (entry 0 not complete)", !rob_commit_valid);
        
        // Complete entry 0
        rob_complete_valid = 1;
        rob_complete_idx = 5'd0;
        rob_complete_result = 32'h1111_1111;
        @(posedge clk);
        rob_complete_valid = 0;
        #1;
        check_pass("ROB commit valid (entry 0 complete)", rob_commit_valid);
        check_pass("ROB commits entry 0 first", rob_commit_result == 32'h1111_1111);
        
        // Commit entry 0
        @(posedge clk);
        #1;
        check_pass("ROB no commit (entry 1 not complete)", !rob_commit_valid);
        
        // Complete entry 1
        rob_complete_valid = 1;
        rob_complete_idx = 5'd1;
        rob_complete_result = 32'h2222_2222;
        @(posedge clk);
        rob_complete_valid = 0;
        #1;
        check_pass("ROB commit valid (entry 1 complete)", rob_commit_valid);
        
        // Commit entries 1 and 2
        @(posedge clk);
        check_pass("ROB commits entry 2 next", rob_commit_result == 32'h3333_3333);
        @(posedge clk);
        #1;
        check_pass("ROB empty after all commits", rob_empty);
        
        //=====================================================
        // Test 13: ROB Flush
        //=====================================================
        $display("\n--- Test 13: ROB Flush ---");
        rob_alloc_req = 1;
        @(posedge clk);
        @(posedge clk);
        rob_alloc_req = 0;
        #1;
        check_pass("ROB not empty before flush", !rob_empty);
        
        rob_flush = 1;
        @(posedge clk);
        rob_flush = 0;
        #1;
        check_pass("ROB empty after flush", rob_empty);
        
        //=====================================================
        // Summary
        //=====================================================
        $display("\n========================================");
        $display("Scheduler Testbench Complete");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        
        $finish;
    end

endmodule
