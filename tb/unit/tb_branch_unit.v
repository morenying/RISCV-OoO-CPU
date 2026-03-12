//=================================================================
// Testbench: tb_branch_unit
// Description: Branch Unit Property Tests
//              Property 4: Branch Unit Correctness
// Validates: Requirements 2.4
//=================================================================

`timescale 1ns/1ps

module tb_branch_unit;

    parameter CLK_PERIOD = 10;
    
    reg         clk;
    reg         rst_n;
    
    // Input interface
    reg         valid_i;
    reg  [3:0]  op_i;
    reg  [31:0] src1_i;
    reg  [31:0] src2_i;
    reg  [31:0] pc_i;
    reg  [31:0] imm_i;
    reg         pred_taken_i;
    reg  [31:0] pred_target_i;
    reg  [5:0]  prd_i;
    reg  [4:0]  rob_idx_i;
    
    // Output interface
    wire        done_o;
    wire        taken_o;
    wire [31:0] target_o;
    wire        mispredict_o;
    wire [31:0] link_addr_o;
    wire [5:0]  result_prd_o;
    wire [4:0]  result_rob_idx_o;
    
    // Branch operation codes
    localparam OP_BEQ   = 4'b0000;
    localparam OP_BNE   = 4'b0001;
    localparam OP_BLT   = 4'b0100;
    localparam OP_BGE   = 4'b0101;
    localparam OP_BLTU  = 4'b0110;
    localparam OP_BGEU  = 4'b0111;
    localparam OP_JAL   = 4'b1000;
    localparam OP_JALR  = 4'b1001;
    
    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT instantiation
    branch_unit u_branch_unit (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (valid_i),
        .op_i           (op_i),
        .src1_i         (src1_i),
        .src2_i         (src2_i),
        .pc_i           (pc_i),
        .imm_i          (imm_i),
        .pred_taken_i   (pred_taken_i),
        .pred_target_i  (pred_target_i),
        .prd_i          (prd_i),
        .rob_idx_i      (rob_idx_i),
        .done_o         (done_o),
        .taken_o        (taken_o),
        .target_o       (target_o),
        .mispredict_o   (mispredict_o),
        .link_addr_o    (link_addr_o),
        .result_prd_o   (result_prd_o),
        .result_rob_idx_o(result_rob_idx_o)
    );
    
    //=========================================================
    // Expected Result Calculation
    //=========================================================
    function expected_taken;
        input [3:0] op;
        input [31:0] a, b;
        begin
            case (op)
                OP_BEQ:  expected_taken = (a == b);
                OP_BNE:  expected_taken = (a != b);
                OP_BLT:  expected_taken = ($signed(a) < $signed(b));
                OP_BGE:  expected_taken = ($signed(a) >= $signed(b));
                OP_BLTU: expected_taken = (a < b);
                OP_BGEU: expected_taken = (a >= b);
                OP_JAL:  expected_taken = 1'b1;
                OP_JALR: expected_taken = 1'b1;
                default: expected_taken = 1'b0;
            endcase
        end
    endfunction
    
    function [31:0] expected_target;
        input [3:0] op;
        input [31:0] pc, imm, rs1;
        begin
            if (op == OP_JALR)
                expected_target = (rs1 + imm) & 32'hFFFFFFFE;
            else
                expected_target = pc + imm;
        end
    endfunction
    
    //=========================================================
    // Test Task
    //=========================================================
    task run_branch_test;
        input [3:0] op;
        input [31:0] a, b, pc, imm;
        input pred_taken;
        input [31:0] pred_target;
        reg exp_taken;
        reg [31:0] exp_target;
        begin
            test_count = test_count + 1;
            
            exp_taken = expected_taken(op, a, b);
            exp_target = expected_target(op, pc, imm, a);
            
            // Setup inputs before clock edge
            valid_i = 1;
            op_i = op;
            src1_i = a;
            src2_i = b;
            pc_i = pc;
            imm_i = imm;
            pred_taken_i = pred_taken;
            pred_target_i = pred_target;
            prd_i = 6'd1;
            rob_idx_i = 5'd1;
            
            // Wait for clock edge - outputs will be registered
            @(posedge clk);
            // Now outputs are valid (registered on this edge)
            // Wait a small delta for outputs to settle
            #1;
            
            // Check results immediately after the clock edge
            if (taken_o == exp_taken) begin
                if (!exp_taken || target_o == exp_target) begin
                    pass_count = pass_count + 1;
                end else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] op=%b: target mismatch, expected=%h, got=%h", 
                             op, exp_target, target_o);
                end
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] op=%b a=%h b=%h: taken mismatch, expected=%b, got=%b",
                         op, a, b, exp_taken, taken_o);
            end
            
            // Clear valid for next test
            valid_i = 0;
            @(posedge clk);
        end
    endtask

    //=========================================================
    // Property 4: Branch Unit Correctness Tests
    //=========================================================
    integer i;
    reg [31:0] rand_a, rand_b, rand_pc, rand_imm;
    
    initial begin
        $display("========================================");
        $display("Branch Unit Property Test");
        $display("Property 4: Branch Unit Correctness");
        $display("Validates: Requirements 2.4");
        $display("========================================");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize
        rst_n = 0;
        valid_i = 0;
        op_i = 0;
        src1_i = 0;
        src2_i = 0;
        pc_i = 0;
        imm_i = 0;
        pred_taken_i = 0;
        pred_target_i = 0;
        prd_i = 0;
        rob_idx_i = 0;
        
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        
        //=====================================================
        // Test BEQ (Branch if Equal)
        //=====================================================
        $display("\n--- Testing BEQ ---");
        // Equal values - should take
        run_branch_test(OP_BEQ, 32'h12345678, 32'h12345678, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Not equal - should not take
        run_branch_test(OP_BEQ, 32'h12345678, 32'h87654321, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Zero comparison
        run_branch_test(OP_BEQ, 32'h0, 32'h0, 32'h2000, 32'h200, 1'b1, 32'h2200);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = (i % 2 == 0) ? rand_a : $random;  // 50% equal
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BEQ, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BEQ: %0d tests completed", test_count);
        
        //=====================================================
        // Test BNE (Branch if Not Equal)
        //=====================================================
        $display("\n--- Testing BNE ---");
        // Not equal - should take
        run_branch_test(OP_BNE, 32'h12345678, 32'h87654321, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Equal - should not take
        run_branch_test(OP_BNE, 32'h12345678, 32'h12345678, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BNE, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BNE: %0d tests completed", test_count);
        
        //=====================================================
        // Test BLT (Branch if Less Than - Signed)
        //=====================================================
        $display("\n--- Testing BLT ---");
        // Negative < Positive
        run_branch_test(OP_BLT, 32'hFFFFFFFF, 32'h00000001, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Positive > Negative
        run_branch_test(OP_BLT, 32'h00000001, 32'hFFFFFFFF, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Equal - not less
        run_branch_test(OP_BLT, 32'h00000005, 32'h00000005, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BLT, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BLT: %0d tests completed", test_count);
        
        //=====================================================
        // Test BGE (Branch if Greater or Equal - Signed)
        //=====================================================
        $display("\n--- Testing BGE ---");
        // Positive >= Negative
        run_branch_test(OP_BGE, 32'h00000001, 32'hFFFFFFFF, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Equal
        run_branch_test(OP_BGE, 32'h00000005, 32'h00000005, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Less than
        run_branch_test(OP_BGE, 32'hFFFFFFFF, 32'h00000001, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BGE, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BGE: %0d tests completed", test_count);
        
        //=====================================================
        // Test BLTU (Branch if Less Than - Unsigned)
        //=====================================================
        $display("\n--- Testing BLTU ---");
        // 0xFFFFFFFF > 0x00000001 (unsigned)
        run_branch_test(OP_BLTU, 32'h00000001, 32'hFFFFFFFF, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // 0xFFFFFFFF not < 0x00000001
        run_branch_test(OP_BLTU, 32'hFFFFFFFF, 32'h00000001, 32'h1000, 32'h100, 1'b0, 32'h1100);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BLTU, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BLTU: %0d tests completed", test_count);
        
        //=====================================================
        // Test BGEU (Branch if Greater or Equal - Unsigned)
        //=====================================================
        $display("\n--- Testing BGEU ---");
        // 0xFFFFFFFF >= 0x00000001 (unsigned)
        run_branch_test(OP_BGEU, 32'hFFFFFFFF, 32'h00000001, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Equal
        run_branch_test(OP_BGEU, 32'h00000005, 32'h00000005, 32'h1000, 32'h100, 1'b1, 32'h1100);
        // Random tests
        for (i = 0; i < 50; i = i + 1) begin
            rand_a = $random;
            rand_b = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00001FFC);
            run_branch_test(OP_BGEU, rand_a, rand_b, rand_pc, rand_imm, 1'b0, 32'h0);
        end
        $display("BGEU: %0d tests completed", test_count);
        
        //=====================================================
        // Test JAL (Jump and Link)
        //=====================================================
        $display("\n--- Testing JAL ---");
        run_branch_test(OP_JAL, 32'h0, 32'h0, 32'h1000, 32'h100, 1'b1, 32'h1100);
        run_branch_test(OP_JAL, 32'h0, 32'h0, 32'h2000, 32'hFFFFF000, 1'b1, 32'h1000);  // Negative offset
        // Random tests
        for (i = 0; i < 20; i = i + 1) begin
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h001FFFFE);
            run_branch_test(OP_JAL, 32'h0, 32'h0, rand_pc, rand_imm, 1'b1, rand_pc + rand_imm);
        end
        $display("JAL: %0d tests completed", test_count);
        
        //=====================================================
        // Test JALR (Jump and Link Register)
        //=====================================================
        $display("\n--- Testing JALR ---");
        run_branch_test(OP_JALR, 32'h1000, 32'h0, 32'h2000, 32'h100, 1'b1, 32'h1100);
        run_branch_test(OP_JALR, 32'h1001, 32'h0, 32'h2000, 32'h100, 1'b1, 32'h1100);  // LSB cleared
        // Random tests
        for (i = 0; i < 20; i = i + 1) begin
            rand_a = $random;
            rand_pc = ($random & 32'hFFFFFFFC);
            rand_imm = ($random & 32'h00000FFF);
            run_branch_test(OP_JALR, rand_a, 32'h0, rand_pc, rand_imm, 1'b1, (rand_a + rand_imm) & 32'hFFFFFFFE);
        end
        $display("JALR: %0d tests completed", test_count);
        
        //=====================================================
        // Test Misprediction Detection
        //=====================================================
        $display("\n--- Testing Misprediction Detection ---");
        // Predicted taken, actually not taken
        valid_i = 1;
        op_i = OP_BEQ;
        src1_i = 32'h1;
        src2_i = 32'h2;  // Not equal
        pc_i = 32'h1000;
        imm_i = 32'h100;
        pred_taken_i = 1'b1;  // Predicted taken
        pred_target_i = 32'h1100;
        @(posedge clk);
        #1;  // Wait for outputs to settle
        
        test_count = test_count + 1;
        if (mispredict_o == 1'b1 && taken_o == 1'b0) begin
            pass_count = pass_count + 1;
            $display("[PASS] Misprediction detected: predicted taken, actually not taken");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Misprediction not detected: mispredict=%b, taken=%b", mispredict_o, taken_o);
        end
        valid_i = 0;
        @(posedge clk);
        
        // Predicted not taken, actually taken
        valid_i = 1;
        op_i = OP_BEQ;
        src1_i = 32'h1;
        src2_i = 32'h1;  // Equal
        pc_i = 32'h1000;
        imm_i = 32'h100;
        pred_taken_i = 1'b0;  // Predicted not taken
        pred_target_i = 32'h0;
        @(posedge clk);
        #1;  // Wait for outputs to settle
        
        test_count = test_count + 1;
        if (mispredict_o == 1'b1 && taken_o == 1'b1) begin
            pass_count = pass_count + 1;
            $display("[PASS] Misprediction detected: predicted not taken, actually taken");
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Misprediction not detected: mispredict=%b, taken=%b", mispredict_o, taken_o);
        end
        valid_i = 0;
        @(posedge clk);
        
        //=====================================================
        // Summary
        //=====================================================
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** SOME TESTS FAILED ***");
        
        $display("========================================");
        $finish;
    end

endmodule
