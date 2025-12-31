//==============================================================================
// RISC-V Out-of-Order CPU - ALU Unit Testbench
// File: tb_alu_unit.v
// Description: Property-based testing for ALU unit
//              Validates: Requirements 11.1 (Property 13: Functional Unit Correctness)
//==============================================================================

`timescale 1ns/1ps

`include "cpu_defines.vh"

module tb_alu_unit;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    parameter NUM_TESTS = 1000;         // Number of random tests per operation
    parameter SEED = 32'hDEADBEEF;      // Random seed
    
    //==========================================================================
    // Signals
    //==========================================================================
    
    reg                         clk;
    reg                         rst_n;
    reg                         valid_i;
    reg  [`ALU_OP_WIDTH-1:0]    op_i;
    reg  [`XLEN-1:0]            src1_i;
    reg  [`XLEN-1:0]            src2_i;
    reg  [`PHYS_REG_BITS-1:0]   prd_i;
    reg  [`ROB_IDX_BITS-1:0]    rob_idx_i;
    reg  [`XLEN-1:0]            pc_i;
    
    wire                        valid_o;
    wire [`XLEN-1:0]            result_o;
    wire [`PHYS_REG_BITS-1:0]   prd_o;
    wire [`ROB_IDX_BITS-1:0]    rob_idx_o;
    
    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;
    
    // Expected result
    reg [`XLEN-1:0] expected;
    
    // Random number generator state
    reg [31:0] rand_state;
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    alu_unit dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .valid_i    (valid_i),
        .op_i       (op_i),
        .src1_i     (src1_i),
        .src2_i     (src2_i),
        .prd_i      (prd_i),
        .rob_idx_i  (rob_idx_i),
        .pc_i       (pc_i),
        .valid_o    (valid_o),
        .result_o   (result_o),
        .prd_o      (prd_o),
        .rob_idx_o  (rob_idx_o)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial clk = 0;
    always #5 clk = ~clk;
    
    //==========================================================================
    // Random Number Generator (LFSR-based)
    //==========================================================================
    
    function [31:0] next_rand;
        input [31:0] state;
        begin
            // LFSR with taps at bits 31, 21, 1, 0
            next_rand = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
        end
    endfunction
    
    task generate_random;
        begin
            rand_state = next_rand(rand_state);
            src1_i = rand_state;
            rand_state = next_rand(rand_state);
            src2_i = rand_state;
            rand_state = next_rand(rand_state);
            pc_i = {rand_state[31:2], 2'b00};  // PC must be aligned
            rand_state = next_rand(rand_state);
            prd_i = rand_state[`PHYS_REG_BITS-1:0];
            rob_idx_i = rand_state[`ROB_IDX_BITS+7:8];
        end
    endtask
    
    //==========================================================================
    // Expected Result Calculation
    //==========================================================================
    
    task calculate_expected;
        input [`ALU_OP_WIDTH-1:0] op;
        input [`XLEN-1:0] s1, s2, pc;
        output [`XLEN-1:0] exp;
        reg signed [`XLEN-1:0] s1_signed, s2_signed;
        begin
            s1_signed = s1;
            s2_signed = s2;
            case (op)
                `ALU_OP_ADD:    exp = s1 + s2;
                `ALU_OP_SUB:    exp = s1 - s2;
                `ALU_OP_SLL:    exp = s1 << s2[4:0];
                `ALU_OP_SLT:    exp = (s1_signed < s2_signed) ? 32'd1 : 32'd0;
                `ALU_OP_SLTU:   exp = (s1 < s2) ? 32'd1 : 32'd0;
                `ALU_OP_XOR:    exp = s1 ^ s2;
                `ALU_OP_SRL:    exp = s1 >> s2[4:0];
                `ALU_OP_SRA:    exp = s1_signed >>> s2[4:0];
                `ALU_OP_OR:     exp = s1 | s2;
                `ALU_OP_AND:    exp = s1 & s2;
                `ALU_OP_LUI:    exp = s2;
                `ALU_OP_AUIPC:  exp = pc + s2;
                default:        exp = 32'd0;
            endcase
        end
    endtask
    
    //==========================================================================
    // Test Tasks
    //==========================================================================
    
    task test_operation;
        input [`ALU_OP_WIDTH-1:0] op;
        input [127:0] op_name;  // String for operation name
        integer i;
        begin
            $display("\n--- Testing %s ---", op_name);
            
            for (i = 0; i < NUM_TESTS; i = i + 1) begin
                generate_random();
                op_i = op;
                valid_i = 1'b1;
                
                #1;  // Allow combinational logic to settle
                
                calculate_expected(op, src1_i, src2_i, pc_i, expected);
                
                test_count = test_count + 1;
                
                if (result_o !== expected) begin
                    fail_count = fail_count + 1;
                    $display("FAIL: %s test %0d", op_name, i);
                    $display("  src1 = 0x%08h, src2 = 0x%08h, pc = 0x%08h", src1_i, src2_i, pc_i);
                    $display("  Expected: 0x%08h, Got: 0x%08h", expected, result_o);
                end else begin
                    pass_count = pass_count + 1;
                end
                
                // Check passthrough signals
                if (valid_o !== valid_i || prd_o !== prd_i || rob_idx_o !== rob_idx_i) begin
                    $display("FAIL: Passthrough mismatch in %s test %0d", op_name, i);
                    fail_count = fail_count + 1;
                end
            end
            
            $display("%s: %0d/%0d tests passed", op_name, pass_count - (test_count - NUM_TESTS - pass_count), NUM_TESTS);
        end
    endtask
    
    // Test edge cases
    task test_edge_cases;
        begin
            $display("\n--- Testing Edge Cases ---");
            
            // Test with zero
            valid_i = 1'b1;
            src1_i = 32'h0;
            src2_i = 32'h0;
            pc_i = 32'h0;
            
            op_i = `ALU_OP_ADD;
            #1;
            if (result_o !== 32'h0) begin
                $display("FAIL: 0 + 0 != 0");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test overflow
            src1_i = 32'hFFFFFFFF;
            src2_i = 32'h00000001;
            op_i = `ALU_OP_ADD;
            #1;
            if (result_o !== 32'h0) begin
                $display("FAIL: 0xFFFFFFFF + 1 != 0 (overflow)");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test signed comparison edge case
            src1_i = 32'h80000000;  // Most negative
            src2_i = 32'h7FFFFFFF;  // Most positive
            op_i = `ALU_OP_SLT;
            #1;
            if (result_o !== 32'h1) begin
                $display("FAIL: SLT(0x80000000, 0x7FFFFFFF) != 1");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test unsigned comparison edge case
            op_i = `ALU_OP_SLTU;
            #1;
            if (result_o !== 32'h0) begin
                $display("FAIL: SLTU(0x80000000, 0x7FFFFFFF) != 0");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test shift by 0
            src1_i = 32'hDEADBEEF;
            src2_i = 32'h0;
            op_i = `ALU_OP_SLL;
            #1;
            if (result_o !== 32'hDEADBEEF) begin
                $display("FAIL: SLL by 0 changed value");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test shift by 31
            src1_i = 32'h00000001;
            src2_i = 32'h0000001F;
            op_i = `ALU_OP_SLL;
            #1;
            if (result_o !== 32'h80000000) begin
                $display("FAIL: 1 << 31 != 0x80000000");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            // Test SRA sign extension
            src1_i = 32'h80000000;
            src2_i = 32'h00000004;
            op_i = `ALU_OP_SRA;
            #1;
            if (result_o !== 32'hF8000000) begin
                $display("FAIL: SRA(0x80000000, 4) != 0xF8000000");
                fail_count = fail_count + 1;
            end else pass_count = pass_count + 1;
            test_count = test_count + 1;
            
            $display("Edge cases: %0d tests completed", 7);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    initial begin
        $display("============================================================");
        $display("ALU Unit Testbench");
        $display("Property 13: Functional Unit Correctness (ALU)");
        $display("Validates: Requirements 11.1");
        $display("============================================================");
        
        // Initialize
        rst_n = 0;
        valid_i = 0;
        op_i = 0;
        src1_i = 0;
        src2_i = 0;
        prd_i = 0;
        rob_idx_i = 0;
        pc_i = 0;
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        rand_state = SEED;
        
        // Reset
        #20;
        rst_n = 1;
        #10;
        
        // Test all operations
        test_operation(`ALU_OP_ADD,  "ADD");
        test_operation(`ALU_OP_SUB,  "SUB");
        test_operation(`ALU_OP_SLL,  "SLL");
        test_operation(`ALU_OP_SLT,  "SLT");
        test_operation(`ALU_OP_SLTU, "SLTU");
        test_operation(`ALU_OP_XOR,  "XOR");
        test_operation(`ALU_OP_SRL,  "SRL");
        test_operation(`ALU_OP_SRA,  "SRA");
        test_operation(`ALU_OP_OR,   "OR");
        test_operation(`ALU_OP_AND,  "AND");
        test_operation(`ALU_OP_LUI,  "LUI");
        test_operation(`ALU_OP_AUIPC,"AUIPC");
        
        // Test edge cases
        test_edge_cases();
        
        // Summary
        $display("\n============================================================");
        $display("Test Summary");
        $display("============================================================");
        $display("Total tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        
        $display("============================================================");
        
        #10;
        $finish;
    end
    
    //==========================================================================
    // Timeout
    //==========================================================================
    
    initial begin
        #1000000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
