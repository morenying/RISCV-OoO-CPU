//=================================================================
// Testbench: Multiplier Unit
// Description: Property-based test for mul_unit
// Property 13: Functional Unit Correctness (MUL部分)
// Validates: Requirements 11.2
//=================================================================

`timescale 1ns/1ps

module tb_mul_unit;

    //=========================================================
    // Parameters
    //=========================================================
    parameter CLK_PERIOD = 10;
    parameter NUM_TESTS = 100;
    
    //=========================================================
    // Signals
    //=========================================================
    reg         clk;
    reg         rst_n;
    reg         valid_i;
    reg  [1:0]  op_i;
    reg  [31:0] src1_i;
    reg  [31:0] src2_i;
    reg  [5:0]  prd_i;
    reg  [4:0]  rob_idx_i;
    
    wire        done_o;
    wire [31:0] result_o;
    wire [5:0]  result_prd_o;
    wire [4:0]  result_rob_idx_o;
    wire        busy_o;
    
    //=========================================================
    // DUT Instantiation
    //=========================================================
    mul_unit #(
        .LATENCY(3)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (valid_i),
        .op_i           (op_i),
        .src1_i         (src1_i),
        .src2_i         (src2_i),
        .prd_i          (prd_i),
        .rob_idx_i      (rob_idx_i),
        .done_o         (done_o),
        .result_o       (result_o),
        .result_prd_o   (result_prd_o),
        .result_rob_idx_o(result_rob_idx_o),
        .busy_o         (busy_o)
    );

    //=========================================================
    // Clock Generation
    //=========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================
    // Reference Model Functions
    //=========================================================
    function [63:0] ref_mul;
        input [31:0] a, b;
        input [1:0] op;
        reg signed [63:0] sa, sb, sresult;
        reg [63:0] ua, ub, uresult;
        begin
            sa = {{32{a[31]}}, a};
            sb = {{32{b[31]}}, b};
            ua = {32'b0, a};
            ub = {32'b0, b};
            
            case (op)
                2'b00: ref_mul = ua * ub;                    // MUL
                2'b01: ref_mul = sa * sb;                    // MULH
                2'b10: ref_mul = $signed(sa) * $signed({1'b0, ub}); // MULHSU
                2'b11: ref_mul = ua * ub;                    // MULHU
                default: ref_mul = 64'b0;
            endcase
        end
    endfunction
    
    function [31:0] get_result;
        input [63:0] full_result;
        input [1:0] op;
        begin
            case (op)
                2'b00: get_result = full_result[31:0];   // MUL - low 32 bits
                2'b01: get_result = full_result[63:32];  // MULH - high 32 bits
                2'b10: get_result = full_result[63:32];  // MULHSU - high 32 bits
                2'b11: get_result = full_result[63:32];  // MULHU - high 32 bits
                default: get_result = 32'b0;
            endcase
        end
    endfunction
    
    //=========================================================
    // Test Variables
    //=========================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    reg [31:0] test_src1, test_src2;
    reg [1:0]  test_op;
    reg [5:0]  test_prd;
    reg [4:0]  test_rob;
    reg [31:0] expected_result;
    reg [63:0] full_result;
    integer seed;
    
    //=========================================================
    // Test Tasks
    //=========================================================
    task reset_dut;
        begin
            rst_n = 0;
            valid_i = 0;
            op_i = 0;
            src1_i = 0;
            src2_i = 0;
            prd_i = 0;
            rob_idx_i = 0;
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task run_mul_test;
        input [31:0] a, b;
        input [1:0] op;
        input [5:0] prd;
        input [4:0] rob;
        begin
            @(posedge clk);
            valid_i = 1;
            op_i = op;
            src1_i = a;
            src2_i = b;
            prd_i = prd;
            rob_idx_i = rob;
            
            @(posedge clk);
            valid_i = 0;
            
            // Wait for result (3 cycle latency)
            wait(done_o);
            @(posedge clk);
        end
    endtask

    //=========================================================
    // Main Test
    //=========================================================
    initial begin
        $display("==============================================");
        $display("  Multiplier Unit Property Test");
        $display("  Property 13: Functional Unit Correctness");
        $display("  Validates: Requirements 11.2");
        $display("==============================================");
        
        seed = 12345;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        // Test all operations with random values
        repeat(NUM_TESTS) begin
            test_src1 = $random(seed);
            test_src2 = $random(seed);
            test_op = $random(seed) % 4;
            test_prd = $random(seed) % 64;
            test_rob = $random(seed) % 32;
            
            // Calculate expected result
            full_result = ref_mul(test_src1, test_src2, test_op);
            expected_result = get_result(full_result, test_op);
            
            // Run test
            run_mul_test(test_src1, test_src2, test_op, test_prd, test_rob);
            
            // Check result
            test_count = test_count + 1;
            if (result_o === expected_result && 
                result_prd_o === test_prd && 
                result_rob_idx_o === test_rob) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: Test %0d", test_count);
                $display("  Op=%0d, A=0x%08h, B=0x%08h", test_op, test_src1, test_src2);
                $display("  Expected: 0x%08h, Got: 0x%08h", expected_result, result_o);
                $display("  PRD: exp=%0d got=%0d, ROB: exp=%0d got=%0d",
                         test_prd, result_prd_o, test_rob, result_rob_idx_o);
            end
        end
        
        // Edge cases
        $display("\n--- Testing Edge Cases ---");
        
        // Test: 0 * anything = 0
        test_op = 2'b00;
        run_mul_test(32'h0, 32'h12345678, test_op, 6'd1, 5'd1);
        if (result_o === 32'h0) begin
            pass_count = pass_count + 1;
            $display("PASS: 0 * X = 0");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: 0 * X != 0, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: 1 * X = X
        run_mul_test(32'h1, 32'h12345678, test_op, 6'd2, 5'd2);
        if (result_o === 32'h12345678) begin
            pass_count = pass_count + 1;
            $display("PASS: 1 * X = X");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: 1 * X != X, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: -1 * -1 = 1 (MULH should give 0)
        test_op = 2'b01; // MULH
        run_mul_test(32'hFFFFFFFF, 32'hFFFFFFFF, test_op, 6'd3, 5'd3);
        if (result_o === 32'h0) begin
            pass_count = pass_count + 1;
            $display("PASS: MULH(-1, -1) = 0");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: MULH(-1, -1) != 0, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: Max unsigned * 2 (MULHU)
        test_op = 2'b11; // MULHU
        run_mul_test(32'hFFFFFFFF, 32'h2, test_op, 6'd4, 5'd4);
        if (result_o === 32'h1) begin
            pass_count = pass_count + 1;
            $display("PASS: MULHU(0xFFFFFFFF, 2) = 1");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: MULHU(0xFFFFFFFF, 2) != 1, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Summary
        $display("\n==============================================");
        $display("  Test Summary");
        $display("==============================================");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("==============================================");
        
        if (fail_count == 0) begin
            $display("  ALL TESTS PASSED!");
        end else begin
            $display("  SOME TESTS FAILED!");
        end
        
        $finish;
    end
    
    // Timeout
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
