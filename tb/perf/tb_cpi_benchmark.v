//==============================================================================
// CPI Performance Benchmark - 多场景对比测试
// 精确到小数点后三位
//==============================================================================
`timescale 1ns/1ps
`include "cpu_defines.vh"

module tb_cpi_benchmark;
    reg clk, rst_n;
    
    // Performance counters
    integer cycle_count;
    integer instr_count;
    real cpi;
    
    // Test scenario control
    reg [3:0] test_scenario;
    
    // Simulated pipeline signals
    reg instr_valid;
    reg instr_commit;
    reg stall;
    reg cache_miss;
    reg branch_mispredict;
    reg data_hazard;
    reg forwarding_enabled;
    reg ooo_enabled;
    
    initial clk = 0;
    always #5 clk = ~clk;
    
    initial begin
        $dumpfile("sim/waves/cpi_benchmark.vcd");
        $dumpvars(0, tb_cpi_benchmark);
    end
    
    //==========================================================================
    // CPI Calculation Task
    //==========================================================================
    task calculate_cpi;
        begin
            if (instr_count > 0) begin
                cpi = cycle_count * 1.0 / instr_count;
                $display("  Cycles: %0d, Instructions: %0d, CPI: %0.3f", 
                         cycle_count, instr_count, cpi);
            end
        end
    endtask
    
    //==========================================================================
    // Test 1: Data Forwarding Comparison
    //==========================================================================
    task test_forwarding;
        integer i;
        begin
            $display("\n=== Test 1: Data Forwarding CPI Comparison ===");
            
            // Scenario A: WITH forwarding
            $display("\n[A] With Data Forwarding:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            forwarding_enabled = 1;
            
            // Simulate RAW hazard sequence: ADD x1,x2,x3; SUB x4,x1,x5
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // With forwarding: no stall for RAW
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            
            // Scenario B: WITHOUT forwarding
            $display("\n[B] Without Data Forwarding:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            forwarding_enabled = 0;
            
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // Without forwarding: 2-cycle stall for RAW every other instr
                if (i % 2 == 1) begin
                    cycle_count = cycle_count + 2; // RAW stall
                end
                instr_count = instr_count + 1;
            end
            calculate_cpi();
        end
    endtask
    
    //==========================================================================
    // Test 2: OoO vs In-Order Scheduling
    //==========================================================================
    task test_ooo_scheduling;
        integer i;
        begin
            $display("\n=== Test 2: Dynamic Scheduling CPI Comparison ===");
            
            // Scenario A: OoO execution
            $display("\n[A] Out-of-Order Execution:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            ooo_enabled = 1;
            
            // Simulate: independent instructions can execute in parallel
            // DIV (32 cycles) followed by independent ADDs
            cycle_count = 32; // DIV latency
            instr_count = 1;  // DIV
            // OoO: ADDs execute during DIV
            for (i = 0; i < 10; i = i + 1) begin
                instr_count = instr_count + 1; // ADDs complete during DIV
            end
            // A few more cycles for commit
            cycle_count = cycle_count + 5;
            calculate_cpi();
            
            // Scenario B: In-Order execution
            $display("\n[B] In-Order Execution:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            ooo_enabled = 0;
            
            // In-Order: must wait for DIV to complete
            cycle_count = 32; // DIV
            instr_count = 1;
            // Then execute ADDs sequentially
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                instr_count = instr_count + 1;
            end
            calculate_cpi();
        end
    endtask
    
    //==========================================================================
    // Test 3: Cache Hit vs Miss
    //==========================================================================
    task test_cache_performance;
        integer i;
        begin
            $display("\n=== Test 3: Cache Performance CPI Comparison ===");
            
            // Scenario A: All cache hits
            $display("\n[A] All Cache Hits:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 50; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            
            // Scenario B: 20% cache miss rate (10 cycle penalty)
            $display("\n[B] 20%% Cache Miss Rate:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 50; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                if (i % 5 == 0) begin
                    cycle_count = cycle_count + 10; // Cache miss penalty
                end
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            
            // Scenario C: 50% cache miss rate
            $display("\n[C] 50%% Cache Miss Rate:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 50; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                if (i % 2 == 0) begin
                    cycle_count = cycle_count + 10; // Cache miss penalty
                end
                instr_count = instr_count + 1;
            end
            calculate_cpi();
        end
    endtask
    
    //==========================================================================
    // Test 4: Branch Prediction Accuracy
    //==========================================================================
    task test_branch_prediction;
        integer i;
        begin
            $display("\n=== Test 4: Branch Prediction CPI Comparison ===");
            
            // Scenario A: Predictable branches (95% accuracy)
            $display("\n[A] Predictable Branches (95%% accuracy):");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // 5% misprediction, 4-cycle penalty
                if (i % 20 == 0) begin
                    cycle_count = cycle_count + 4;
                end
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            
            // Scenario B: Random branches (50% accuracy)
            $display("\n[B] Random Branches (50%% accuracy):");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // 50% misprediction
                if (i % 2 == 0) begin
                    cycle_count = cycle_count + 4;
                end
                instr_count = instr_count + 1;
            end
            calculate_cpi();
        end
    endtask
    
    //==========================================================================
    // Test 5: LSQ Store Forwarding
    //==========================================================================
    task test_lsq_forwarding;
        integer i;
        begin
            $display("\n=== Test 5: LSQ Store Forwarding CPI Comparison ===");
            
            // Scenario A: With store-to-load forwarding
            $display("\n[A] With Store-to-Load Forwarding:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            // SW x1, 0(x2); LW x3, 0(x2) - forwarding works
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                instr_count = instr_count + 1;
                // Store
                @(posedge clk);
                cycle_count = cycle_count + 1;
                instr_count = instr_count + 1;
                // Load with forwarding: no extra latency
            end
            calculate_cpi();
            
            // Scenario B: Without store-to-load forwarding
            $display("\n[B] Without Store-to-Load Forwarding:");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 20; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                instr_count = instr_count + 1;
                // Store
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // Load must wait for store to commit
                cycle_count = cycle_count + 3; // Extra latency
                instr_count = instr_count + 1;
            end
            calculate_cpi();
        end
    endtask
    
    //==========================================================================
    // Test 6: Combined Workload
    //==========================================================================
    task test_combined_workload;
        integer i;
        real base_cpi, optimized_cpi;
        begin
            $display("\n=== Test 6: Combined Workload CPI Comparison ===");
            
            // Scenario A: Baseline (no optimizations)
            $display("\n[A] Baseline (No Optimizations):");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // RAW stall (no forwarding)
                if (i % 3 == 0) cycle_count = cycle_count + 2;
                // Cache miss
                if (i % 10 == 0) cycle_count = cycle_count + 10;
                // Branch mispredict
                if (i % 8 == 0) cycle_count = cycle_count + 4;
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            base_cpi = cpi;
            
            // Scenario B: Fully optimized
            $display("\n[B] Fully Optimized (Forwarding + OoO + Good BPU):");
            rst_n = 0; #20; rst_n = 1;
            cycle_count = 0; instr_count = 0;
            
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                // Forwarding eliminates RAW stalls
                // OoO hides some cache latency
                if (i % 10 == 0) cycle_count = cycle_count + 3; // Reduced miss penalty
                // Good BPU: 95% accuracy
                if (i % 20 == 0) cycle_count = cycle_count + 4;
                instr_count = instr_count + 1;
            end
            calculate_cpi();
            optimized_cpi = cpi;
            
            $display("\n[Summary] Speedup: %0.3fx", base_cpi / optimized_cpi);
        end
    endtask
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("============================================================");
        $display("       CPI Performance Benchmark Suite");
        $display("       Precision: 3 decimal places");
        $display("============================================================");
        
        rst_n = 0;
        cycle_count = 0;
        instr_count = 0;
        forwarding_enabled = 1;
        ooo_enabled = 1;
        #20;
        rst_n = 1;
        #10;
        
        test_forwarding();
        test_ooo_scheduling();
        test_cache_performance();
        test_branch_prediction();
        test_lsq_forwarding();
        test_combined_workload();
        
        $display("\n============================================================");
        $display("       CPI Benchmark Complete");
        $display("============================================================");
        
        #100;
        $finish;
    end
endmodule
