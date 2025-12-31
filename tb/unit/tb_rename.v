//=================================================================
// Testbench: tb_rename
// Description: Testbench for Register Renaming modules
//              Tests Free List, RAT, and PRF
//              Validates x0 hardwired zero
//              Tests checkpoint and recovery
// Requirements: 1.5, 3.1-3.6
//=================================================================

`timescale 1ns/1ps

module tb_rename;

    //=========================================================
    // Parameters
    //=========================================================
    parameter NUM_ARCH_REGS = 32;
    parameter NUM_PHYS_REGS = 64;
    parameter ARCH_REG_BITS = 5;
    parameter PHYS_REG_BITS = 6;
    parameter CLK_PERIOD = 10;

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
    // Free List Signals
    //=========================================================
    reg                     fl_alloc_req;
    wire [PHYS_REG_BITS-1:0] fl_alloc_preg;
    wire                    fl_alloc_valid;
    reg                     fl_release_req;
    reg  [PHYS_REG_BITS-1:0] fl_release_preg;
    reg                     fl_recover;
    reg  [PHYS_REG_BITS-1:0] fl_recover_head;
    reg  [PHYS_REG_BITS-1:0] fl_recover_tail;
    reg  [PHYS_REG_BITS-1:0] fl_recover_count;
    wire [PHYS_REG_BITS-1:0] fl_checkpoint_head;
    wire [PHYS_REG_BITS-1:0] fl_checkpoint_tail;
    wire [PHYS_REG_BITS-1:0] fl_checkpoint_count;
    wire                    fl_empty;
    wire                    fl_full;
    wire [PHYS_REG_BITS-1:0] fl_free_count;

    //=========================================================
    // RAT Signals
    //=========================================================
    reg  [ARCH_REG_BITS-1:0] rat_rs1_arch;
    reg  [ARCH_REG_BITS-1:0] rat_rs2_arch;
    wire [PHYS_REG_BITS-1:0] rat_rs1_phys;
    wire [PHYS_REG_BITS-1:0] rat_rs2_phys;
    wire                    rat_rs1_ready;
    wire                    rat_rs2_ready;
    reg                     rat_rename_valid;
    reg  [ARCH_REG_BITS-1:0] rat_rd_arch;
    reg  [PHYS_REG_BITS-1:0] rat_rd_phys_new;
    wire [PHYS_REG_BITS-1:0] rat_rd_phys_old;
    reg                     rat_cdb_valid;
    reg  [PHYS_REG_BITS-1:0] rat_cdb_preg;
    reg                     rat_checkpoint_create;
    reg  [2:0]              rat_checkpoint_id;
    reg                     rat_recover;
    reg  [2:0]              rat_recover_id;
    reg                     rat_commit_valid;
    reg  [ARCH_REG_BITS-1:0] rat_commit_rd_arch;
    reg  [PHYS_REG_BITS-1:0] rat_commit_rd_phys;

    //=========================================================
    // PRF Signals
    //=========================================================
    reg  [PHYS_REG_BITS-1:0] prf_rd_addr0;
    reg  [PHYS_REG_BITS-1:0] prf_rd_addr1;
    reg  [PHYS_REG_BITS-1:0] prf_rd_addr2;
    reg  [PHYS_REG_BITS-1:0] prf_rd_addr3;
    wire [31:0]             prf_rd_data0;
    wire [31:0]             prf_rd_data1;
    wire [31:0]             prf_rd_data2;
    wire [31:0]             prf_rd_data3;
    reg                     prf_wr_en0;
    reg  [PHYS_REG_BITS-1:0] prf_wr_addr0;
    reg  [31:0]             prf_wr_data0;
    reg                     prf_wr_en1;
    reg  [PHYS_REG_BITS-1:0] prf_wr_addr1;
    reg  [31:0]             prf_wr_data1;

    //=========================================================
    // DUT Instantiation
    //=========================================================
    free_list #(
        .NUM_PHYS_REGS(NUM_PHYS_REGS),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_free_list (
        .clk              (clk),
        .rst_n            (rst_n),
        .alloc_req_i      (fl_alloc_req),
        .alloc_preg_o     (fl_alloc_preg),
        .alloc_valid_o    (fl_alloc_valid),
        .release_req_i    (fl_release_req),
        .release_preg_i   (fl_release_preg),
        .recover_i        (fl_recover),
        .recover_head_i   (fl_recover_head),
        .recover_tail_i   (fl_recover_tail),
        .recover_count_i  (fl_recover_count),
        .checkpoint_head_o(fl_checkpoint_head),
        .checkpoint_tail_o(fl_checkpoint_tail),
        .checkpoint_count_o(fl_checkpoint_count),
        .empty_o          (fl_empty),
        .full_o           (fl_full),
        .free_count_o     (fl_free_count)
    );

    rat #(
        .NUM_ARCH_REGS(NUM_ARCH_REGS),
        .NUM_PHYS_REGS(NUM_PHYS_REGS),
        .ARCH_REG_BITS(ARCH_REG_BITS),
        .PHYS_REG_BITS(PHYS_REG_BITS)
    ) u_rat (
        .clk                (clk),
        .rst_n              (rst_n),
        .rs1_arch_i         (rat_rs1_arch),
        .rs2_arch_i         (rat_rs2_arch),
        .rs1_phys_o         (rat_rs1_phys),
        .rs2_phys_o         (rat_rs2_phys),
        .rs1_ready_o        (rat_rs1_ready),
        .rs2_ready_o        (rat_rs2_ready),
        .rename_valid_i     (rat_rename_valid),
        .rd_arch_i          (rat_rd_arch),
        .rd_phys_new_i      (rat_rd_phys_new),
        .rd_phys_old_o      (rat_rd_phys_old),
        .cdb_valid_i        (rat_cdb_valid),
        .cdb_preg_i         (rat_cdb_preg),
        .checkpoint_create_i(rat_checkpoint_create),
        .checkpoint_id_i    (rat_checkpoint_id),
        .recover_i          (rat_recover),
        .recover_id_i       (rat_recover_id),
        .commit_valid_i     (rat_commit_valid),
        .commit_rd_arch_i   (rat_commit_rd_arch),
        .commit_rd_phys_i   (rat_commit_rd_phys)
    );

    prf #(
        .NUM_PHYS_REGS(NUM_PHYS_REGS),
        .PHYS_REG_BITS(PHYS_REG_BITS),
        .DATA_WIDTH(32)
    ) u_prf (
        .clk       (clk),
        .rst_n     (rst_n),
        .rd_addr0_i(prf_rd_addr0),
        .rd_data0_o(prf_rd_data0),
        .rd_addr1_i(prf_rd_addr1),
        .rd_data1_o(prf_rd_data1),
        .rd_addr2_i(prf_rd_addr2),
        .rd_data2_o(prf_rd_data2),
        .rd_addr3_i(prf_rd_addr3),
        .rd_data3_o(prf_rd_data3),
        .wr_en0_i  (prf_wr_en0),
        .wr_addr0_i(prf_wr_addr0),
        .wr_data0_i(prf_wr_data0),
        .wr_en1_i  (prf_wr_en1),
        .wr_addr1_i(prf_wr_addr1),
        .wr_data1_i(prf_wr_data1)
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
            fl_alloc_req = 0;
            fl_release_req = 0;
            fl_release_preg = 0;
            fl_recover = 0;
            fl_recover_head = 0;
            fl_recover_tail = 0;
            fl_recover_count = 0;
            
            rat_rs1_arch = 0;
            rat_rs2_arch = 0;
            rat_rename_valid = 0;
            rat_rd_arch = 0;
            rat_rd_phys_new = 0;
            rat_cdb_valid = 0;
            rat_cdb_preg = 0;
            rat_checkpoint_create = 0;
            rat_checkpoint_id = 0;
            rat_recover = 0;
            rat_recover_id = 0;
            rat_commit_valid = 0;
            rat_commit_rd_arch = 0;
            rat_commit_rd_phys = 0;
            
            prf_rd_addr0 = 0;
            prf_rd_addr1 = 0;
            prf_rd_addr2 = 0;
            prf_rd_addr3 = 0;
            prf_wr_en0 = 0;
            prf_wr_addr0 = 0;
            prf_wr_data0 = 0;
            prf_wr_en1 = 0;
            prf_wr_addr1 = 0;
            prf_wr_data1 = 0;
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
        $display("Register Renaming Testbench Starting");
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
        // Test 1: Free List Initial State
        //=====================================================
        $display("\n--- Test 1: Free List Initial State ---");
        check_pass("FL initial count = 32", fl_free_count == 32);
        check_pass("FL not empty", !fl_empty);
        check_pass("FL not full", !fl_full);
        check_pass("FL first free = P32", fl_alloc_preg == 32);
        
        //=====================================================
        // Test 2: Free List Allocation
        //=====================================================
        $display("\n--- Test 2: Free List Allocation ---");
        fl_alloc_req = 1;
        @(posedge clk);
        #1;
        check_pass("FL alloc valid", fl_alloc_valid);
        check_pass("FL count = 31", fl_free_count == 31);
        check_pass("FL next free = P33", fl_alloc_preg == 33);
        
        fl_alloc_req = 0;
        @(posedge clk);
        
        //=====================================================
        // Test 3: Free List Release
        //=====================================================
        $display("\n--- Test 3: Free List Release ---");
        fl_release_req = 1;
        fl_release_preg = 6'd1;  // Release P1
        @(posedge clk);
        #1;
        check_pass("FL count = 32 after release", fl_free_count == 32);
        fl_release_req = 0;
        @(posedge clk);
        
        //=====================================================
        // Test 4: RAT x0 Hardwired Zero
        //=====================================================
        $display("\n--- Test 4: RAT x0 Hardwired Zero ---");
        rat_rs1_arch = 5'd0;
        rat_rs2_arch = 5'd0;
        #1;
        check_pass("x0 maps to P0 (rs1)", rat_rs1_phys == 6'd0);
        check_pass("x0 maps to P0 (rs2)", rat_rs2_phys == 6'd0);
        check_pass("x0 always ready (rs1)", rat_rs1_ready == 1'b1);
        check_pass("x0 always ready (rs2)", rat_rs2_ready == 1'b1);
        
        // Try to rename x0 - should have no effect
        rat_rename_valid = 1;
        rat_rd_arch = 5'd0;
        rat_rd_phys_new = 6'd40;
        @(posedge clk);
        rat_rename_valid = 0;
        #1;
        rat_rs1_arch = 5'd0;
        #1;
        check_pass("x0 still maps to P0 after rename attempt", rat_rs1_phys == 6'd0);
        
        //=====================================================
        // Test 5: RAT Initial Mapping
        //=====================================================
        $display("\n--- Test 5: RAT Initial Mapping ---");
        rat_rs1_arch = 5'd1;
        rat_rs2_arch = 5'd31;
        #1;
        check_pass("x1 initially maps to P1", rat_rs1_phys == 6'd1);
        check_pass("x31 initially maps to P31", rat_rs2_phys == 6'd31);
        check_pass("x1 initially ready", rat_rs1_ready == 1'b1);
        check_pass("x31 initially ready", rat_rs2_ready == 1'b1);
        
        //=====================================================
        // Test 6: RAT Rename Operation
        //=====================================================
        $display("\n--- Test 6: RAT Rename Operation ---");
        // Rename x1 -> P32
        rat_rename_valid = 1;
        rat_rd_arch = 5'd1;
        rat_rd_phys_new = 6'd32;
        #1;
        check_pass("Old mapping returned (P1)", rat_rd_phys_old == 6'd1);
        @(posedge clk);
        rat_rename_valid = 0;
        #1;
        
        rat_rs1_arch = 5'd1;
        #1;
        check_pass("x1 now maps to P32", rat_rs1_phys == 6'd32);
        check_pass("x1 not ready after rename", rat_rs1_ready == 1'b0);
        
        //=====================================================
        // Test 7: RAT CDB Broadcast
        //=====================================================
        $display("\n--- Test 7: RAT CDB Broadcast ---");
        rat_cdb_valid = 1;
        rat_cdb_preg = 6'd32;
        @(posedge clk);
        rat_cdb_valid = 0;
        #1;
        
        rat_rs1_arch = 5'd1;
        #1;
        check_pass("x1 ready after CDB broadcast", rat_rs1_ready == 1'b1);
        
        //=====================================================
        // Test 8: RAT Checkpoint and Recovery
        //=====================================================
        $display("\n--- Test 8: RAT Checkpoint and Recovery ---");
        // Create checkpoint 0
        rat_checkpoint_create = 1;
        rat_checkpoint_id = 3'd0;
        @(posedge clk);
        rat_checkpoint_create = 0;
        
        // Rename x2 -> P33
        rat_rename_valid = 1;
        rat_rd_arch = 5'd2;
        rat_rd_phys_new = 6'd33;
        @(posedge clk);
        rat_rename_valid = 0;
        #1;
        
        rat_rs1_arch = 5'd2;
        #1;
        check_pass("x2 maps to P33 after rename", rat_rs1_phys == 6'd33);
        
        // Recover to checkpoint 0
        rat_recover = 1;
        rat_recover_id = 3'd0;
        @(posedge clk);
        rat_recover = 0;
        #1;
        
        rat_rs1_arch = 5'd2;
        #1;
        check_pass("x2 maps to P2 after recovery", rat_rs1_phys == 6'd2);
        
        //=====================================================
        // Test 9: PRF P0 Hardwired Zero
        //=====================================================
        $display("\n--- Test 9: PRF P0 Hardwired Zero ---");
        prf_rd_addr0 = 6'd0;
        #1;
        check_pass("P0 reads as zero", prf_rd_data0 == 32'd0);
        
        // Try to write to P0
        prf_wr_en0 = 1;
        prf_wr_addr0 = 6'd0;
        prf_wr_data0 = 32'hDEADBEEF;
        @(posedge clk);
        prf_wr_en0 = 0;
        #1;
        
        prf_rd_addr0 = 6'd0;
        #1;
        check_pass("P0 still zero after write attempt", prf_rd_data0 == 32'd0);
        
        //=====================================================
        // Test 10: PRF Write and Read
        //=====================================================
        $display("\n--- Test 10: PRF Write and Read ---");
        // Write to P1
        prf_wr_en0 = 1;
        prf_wr_addr0 = 6'd1;
        prf_wr_data0 = 32'h12345678;
        @(posedge clk);
        prf_wr_en0 = 0;
        #1;
        
        prf_rd_addr0 = 6'd1;
        #1;
        check_pass("P1 contains written value", prf_rd_data0 == 32'h12345678);
        
        //=====================================================
        // Test 11: PRF Write Bypass
        //=====================================================
        $display("\n--- Test 11: PRF Write Bypass ---");
        prf_wr_en0 = 1;
        prf_wr_addr0 = 6'd2;
        prf_wr_data0 = 32'hCAFEBABE;
        prf_rd_addr0 = 6'd2;
        #1;
        check_pass("Write bypass works", prf_rd_data0 == 32'hCAFEBABE);
        @(posedge clk);
        prf_wr_en0 = 0;
        
        //=====================================================
        // Test 12: PRF Dual Write Ports
        //=====================================================
        $display("\n--- Test 12: PRF Dual Write Ports ---");
        prf_wr_en0 = 1;
        prf_wr_addr0 = 6'd3;
        prf_wr_data0 = 32'hAAAAAAAA;
        prf_wr_en1 = 1;
        prf_wr_addr1 = 6'd4;
        prf_wr_data1 = 32'hBBBBBBBB;
        @(posedge clk);
        prf_wr_en0 = 0;
        prf_wr_en1 = 0;
        #1;
        
        prf_rd_addr0 = 6'd3;
        prf_rd_addr1 = 6'd4;
        #1;
        check_pass("P3 written correctly", prf_rd_data0 == 32'hAAAAAAAA);
        check_pass("P4 written correctly", prf_rd_data1 == 32'hBBBBBBBB);
        
        //=====================================================
        // Test 13: Free List Exhaustion
        //=====================================================
        $display("\n--- Test 13: Free List Exhaustion ---");
        reset_inputs();
        
        // Allocate all 32 free registers
        repeat (32) begin
            fl_alloc_req = 1;
            @(posedge clk);
        end
        fl_alloc_req = 0;
        #1;
        
        check_pass("FL empty after 32 allocations", fl_empty);
        check_pass("FL count = 0", fl_free_count == 0);
        
        // Try to allocate when empty
        fl_alloc_req = 1;
        #1;
        check_pass("Alloc invalid when empty", !fl_alloc_valid);
        fl_alloc_req = 0;
        
        //=====================================================
        // Summary
        //=====================================================
        $display("\n========================================");
        $display("Register Renaming Testbench Complete");
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
