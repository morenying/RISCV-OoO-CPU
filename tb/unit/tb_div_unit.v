//=================================================================
// Testbench: Division Unit
// Description: Property-based test for div_unit
// Property 13: Functional Unit Correctness (DIV部分)
// Validates: Requirements 11.3
//=================================================================

`timescale 1ns/1ps

module tb_div_unit;

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
    div_unit #(
        .MAX_LATENCY(32)
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
    function [31:0] ref_div;
        input [31:0] a, b;
        input [1:0] op;
        reg signed [31:0] sa, sb;
        begin
            sa = a;
            sb = b;
            
            if (b == 32'b0) begin
                // Division by zero
                case (op)
                    2'b00: ref_div = 32'hFFFFFFFF;  // DIV
                    2'b01: ref_div = 32'hFFFFFFFF;  // DIVU
                    2'b10: ref_div = a;             // REM
                    2'b11: ref_div = a;             // REMU
                endcase
            end else if (op == 2'b00 && a == 32'h80000000 && b == 32'hFFFFFFFF) begin
                // Signed overflow
                ref_div = 32'h80000000;
            end else if (op == 2'b10 && a == 32'h80000000 && b == 32'hFFFFFFFF) begin
                // Signed overflow remainder
                ref_div = 32'h0;
            end else begin
                case (op)
                    2'b00: ref_div = sa / sb;       // DIV (signed)
                    2'b01: ref_div = a / b;         // DIVU (unsigned)
                    2'b10: ref_div = sa % sb;       // REM (signed)
                    2'b11: ref_div = a % b;         // REMU (unsigned)
                    default: ref_div = 32'b0;
                endcase
            end
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
    integer seed;
    integer timeout_count;
    
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
    
    task run_div_test;
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
            
            // Wait for result (variable latency, max 40 cycles)
            timeout_count = 0;
            while (!done_o && timeout_count < 50) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            
            if (timeout_count >= 50) begin
                $display("ERROR: Division timeout!");
            end
            
            @(posedge clk);
        end
    endtask

    //=========================================================
    // Main Test
    //=========================================================
    initial begin
        $display("==============================================");
        $display("  Division Unit Property Test");
        $display("  Property 13: Functional Unit Correctness");
        $display("  Validates: Requirements 11.3");
        $display("==============================================");
        
        seed = 54321;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        // Test all operations with random values
        repeat(NUM_TESTS) begin
            test_src1 = $random(seed);
            test_src2 = $random(seed);
            // Avoid too many div-by-zero in random tests
            if (test_src2 == 0) test_src2 = $random(seed) | 32'h1;
            test_op = $random(seed) % 4;
            test_prd = $random(seed) % 64;
            test_rob = $random(seed) % 32;
            
            // Calculate expected result
            expected_result = ref_div(test_src1, test_src2, test_op);
            
            // Run test
            run_div_test(test_src1, test_src2, test_op, test_prd, test_rob);
            
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
            end
        end
        
        // Edge cases
        $display("\n--- Testing Edge Cases ---");
        
        // Test: Division by zero (DIV)
        test_op = 2'b00;
        run_div_test(32'h12345678, 32'h0, test_op, 6'd1, 5'd1);
        if (result_o === 32'hFFFFFFFF) begin
            pass_count = pass_count + 1;
            $display("PASS: DIV by zero = -1");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: DIV by zero, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: Division by zero (REM)
        test_op = 2'b10;
        run_div_test(32'h12345678, 32'h0, test_op, 6'd2, 5'd2);
        if (result_o === 32'h12345678) begin
            pass_count = pass_count + 1;
            $display("PASS: REM by zero = dividend");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: REM by zero, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: Signed overflow (-2^31 / -1)
        test_op = 2'b00;
        run_div_test(32'h80000000, 32'hFFFFFFFF, test_op, 6'd3, 5'd3);
        if (result_o === 32'h80000000) begin
            pass_count = pass_count + 1;
            $display("PASS: Signed overflow DIV");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Signed overflow DIV, got 0x%08h", result_o);
        end
        test_count = test_count + 1;
        
        // Test: Simple division
        test_op = 2'b01; // DIVU
        run_div_test(32'd100, 32'd10, test_op, 6'd4, 5'd4);
        if (result_o === 32'd10) begin
            pass_count = pass_count + 1;
            $display("PASS: 100 / 10 = 10");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: 100 / 10, got %0d", result_o);
        end
        test_count = test_count + 1;
        
        // Test: Remainder
        test_op = 2'b11; // REMU
        run_div_test(32'd17, 32'd5, test_op, 6'd5, 5'd5);
        if (result_o === 32'd2) begin
            pass_count = pass_count + 1;
            $display("PASS: 17 %% 5 = 2");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: 17 %% 5, got %0d", result_o);
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
        #(CLK_PERIOD * 100000);
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule
