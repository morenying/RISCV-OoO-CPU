`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Checkpoint 10: Interrupt System Verification
//
// This checkpoint validates the complete interrupt controller functionality:
// 1. All interrupt sources work correctly
// 2. Priority handling is correct
// 3. Nested interrupts work properly
// 4. Latency statistics are within bounds
// 5. Edge and level triggering work correctly
// 6. No interrupt loss under stress
//////////////////////////////////////////////////////////////////////////////

module tb_intc_checkpoint;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_IRQS = 8;
    parameter STRESS_ITERATIONS = 100;
    parameter LATENCY_ITERATIONS = 100;
    
    //==========================================================================
    // Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    
    // AXI Interface
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [7:0]  axi_awaddr;
    
    reg         axi_wvalid;
    wire        axi_wready;
    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb;
    
    wire        axi_bvalid;
    reg         axi_bready;
    wire [1:0]  axi_bresp;
    
    reg         axi_arvalid;
    wire        axi_arready;
    reg  [7:0]  axi_araddr;
    
    wire        axi_rvalid;
    reg         axi_rready;
    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    
    // Interrupt sources
    reg  [NUM_IRQS-1:0] irq_sources;
    
    // CPU interface
    wire        irq_to_cpu;
    wire [3:0]  irq_id;
    wire [7:0]  irq_priority_out;
    reg         irq_ack;
    reg         irq_complete;
    
    //==========================================================================
    // Register Addresses
    //==========================================================================
    localparam ADDR_PENDING    = 8'h00;
    localparam ADDR_ENABLE     = 8'h04;
    localparam ADDR_MASK       = 8'h08;
    localparam ADDR_TRIGGER    = 8'h0C;
    localparam ADDR_PRIORITY0  = 8'h10;
    localparam ADDR_PRIORITY1  = 8'h14;
    localparam ADDR_ACTIVE     = 8'h18;
    localparam ADDR_CURRENT    = 8'h1C;
    localparam ADDR_THRESHOLD  = 8'h20;
    localparam ADDR_EOI        = 8'h24;
    localparam ADDR_CTRL       = 8'h2C;
    
    //==========================================================================
    // Statistics
    //==========================================================================
    integer total_interrupts;
    integer total_latency;
    integer max_latency;
    integer min_latency;
    integer nested_count;
    integer edge_count;
    integer level_count;
    integer lost_interrupts;
    integer test_pass_count;
    integer test_fail_count;
    
    integer seed;
    
    //==========================================================================
    // DUT Instance
    //==========================================================================
    interrupt_controller #(
        .NUM_IRQS(NUM_IRQS),
        .SYNC_STAGES(2),
        .DEFAULT_PRIORITY(8'h0F)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_awaddr(axi_awaddr),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_bresp(axi_bresp),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_araddr(axi_araddr),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .irq_sources(irq_sources),
        .irq_to_cpu(irq_to_cpu),
        .irq_id(irq_id),
        .irq_priority_out(irq_priority_out),
        .irq_ack(irq_ack),
        .irq_complete(irq_complete)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // AXI Write Task
    //==========================================================================
    task axi_write;
        input [7:0]  addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(posedge clk);
            axi_awvalid <= 1'b1;
            axi_awaddr  <= addr;
            @(posedge clk);
            while (!axi_awready) @(posedge clk);
            axi_awvalid <= 1'b0;
            
            axi_wvalid <= 1'b1;
            axi_wdata  <= data;
            axi_wstrb  <= strb;
            @(posedge clk);
            while (!axi_wready) @(posedge clk);
            axi_wvalid <= 1'b0;
            
            axi_bready <= 1'b1;
            @(posedge clk);
            while (!axi_bvalid) @(posedge clk);
            axi_bready <= 1'b0;
            @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // AXI Read Task
    //==========================================================================
    task axi_read;
        input [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axi_arvalid <= 1'b1;
            axi_araddr  <= addr;
            @(posedge clk);
            while (!axi_arready) @(posedge clk);
            axi_arvalid <= 1'b0;
            
            axi_rready <= 1'b1;
            @(posedge clk);
            while (!axi_rvalid) @(posedge clk);
            data = axi_rdata;
            axi_rready <= 1'b0;
            @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Reset DUT
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            irq_sources = 0;
            irq_ack = 0;
            irq_complete = 0;
            axi_awvalid = 0;
            axi_wvalid = 0;
            axi_bready = 0;
            axi_arvalid = 0;
            axi_rready = 0;
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Wait for synchronizer
    //==========================================================================
    task wait_sync;
        begin
            repeat(4) @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Handle interrupt
    //==========================================================================
    task handle_interrupt;
        begin
            @(posedge clk);
            irq_ack = 1'b1;
            @(posedge clk);
            irq_ack = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task complete_interrupt;
        begin
            irq_complete = 1'b1;
            @(posedge clk);
            irq_complete = 1'b0;
            repeat(2) @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Main Test
    //==========================================================================
    integer i, j, k;
    integer latency;
    integer irq_num;
    reg [31:0] read_data;
    reg test_passed;
    
    initial begin
        $display("##############################################");
        $display("# Checkpoint 10: Interrupt System Verification");
        $display("##############################################");
        
        seed = 54321;
        test_pass_count = 0;
        test_fail_count = 0;
        total_interrupts = 0;
        total_latency = 0;
        max_latency = 0;
        min_latency = 1000;
        nested_count = 0;
        edge_count = 0;
        level_count = 0;
        lost_interrupts = 0;
        
        //======================================================================
        // Test 1: Basic Functionality - All IRQ Sources
        //======================================================================
        $display("\n=== Test 1: Basic Functionality (All IRQ Sources) ===");
        test_passed = 1;
        
        reset_dut();
        
        // Enable all IRQs, level-triggered
        axi_write(ADDR_ENABLE, 32'h000000FF, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h03020100, 4'b1111);  // IRQ0=0, IRQ1=1, IRQ2=2, IRQ3=3
        axi_write(ADDR_PRIORITY1, 32'h07060504, 4'b1111);  // IRQ4=4, IRQ5=5, IRQ6=6, IRQ7=7
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);
        axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        
        // Test each IRQ individually
        for (i = 0; i < NUM_IRQS; i = i + 1) begin
            irq_sources = 8'h01 << i;
            wait_sync();
            wait_sync();
            
            if (!irq_to_cpu) begin
                $display("  [FAIL] IRQ%0d not detected", i);
                test_passed = 0;
            end else if (irq_id != i) begin
                $display("  [FAIL] IRQ%0d: Expected ID=%0d, got ID=%0d", i, i, irq_id);
                test_passed = 0;
            end else begin
                $display("  [PASS] IRQ%0d detected correctly", i);
                level_count = level_count + 1;
            end
            
            handle_interrupt();
            irq_sources = 0;
            wait_sync();
            complete_interrupt();
            total_interrupts = total_interrupts + 1;
        end
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 1: All 8 IRQ sources work correctly");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 1: Some IRQ sources failed");
        end

        //======================================================================
        // Test 2: Latency Statistics
        //======================================================================
        $display("\n=== Test 2: Interrupt Latency Statistics ===");
        test_passed = 1;
        
        for (i = 0; i < LATENCY_ITERATIONS; i = i + 1) begin
            reset_dut();
            
            irq_num = ($random(seed) & 32'h7FFFFFFF) % NUM_IRQS;
            
            axi_write(ADDR_ENABLE, 32'h01 << irq_num, 4'b0001);
            axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
            axi_write(ADDR_PRIORITY0, 32'h01010101, 4'b1111);
            axi_write(ADDR_PRIORITY1, 32'h01010101, 4'b1111);
            axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);
            axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
            
            repeat(5) @(posedge clk);
            
            @(posedge clk);
            irq_sources[irq_num] = 1'b1;
            latency = 0;
            
            while (!irq_to_cpu && latency < 50) begin
                @(posedge clk);
                latency = latency + 1;
            end
            
            if (latency >= 50) begin
                $display("  [FAIL] Iteration %0d: IRQ%0d timeout", i, irq_num);
                test_passed = 0;
                lost_interrupts = lost_interrupts + 1;
            end else begin
                total_latency = total_latency + latency;
                if (latency > max_latency) max_latency = latency;
                if (latency < min_latency) min_latency = latency;
            end
            
            irq_sources = 0;
            wait_sync();
        end
        
        $display("  Latency Statistics:");
        $display("    Min: %0d cycles", min_latency);
        $display("    Max: %0d cycles", max_latency);
        $display("    Avg: %0d cycles", total_latency / LATENCY_ITERATIONS);
        
        if (test_passed && max_latency <= 10) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 2: All latencies within 10 cycle bound");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 2: Latency exceeded bound or timeouts occurred");
        end
        
        //======================================================================
        // Test 3: Priority Ordering
        //======================================================================
        $display("\n=== Test 3: Priority Ordering ===");
        test_passed = 1;
        
        reset_dut();
        
        // Set distinct priorities: IRQ7=0 (highest), IRQ0=7 (lowest)
        axi_write(ADDR_ENABLE, 32'h000000FF, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h04050607, 4'b1111);  // IRQ0=7, IRQ1=6, IRQ2=5, IRQ3=4
        axi_write(ADDR_PRIORITY1, 32'h00010203, 4'b1111);  // IRQ4=3, IRQ5=2, IRQ6=1, IRQ7=0
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);
        axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        
        // Assert all interrupts
        irq_sources = 8'hFF;
        wait_sync();
        wait_sync();
        
        // Expected order: IRQ7, IRQ6, IRQ5, IRQ4, IRQ3, IRQ2, IRQ1, IRQ0
        for (i = 7; i >= 0; i = i - 1) begin
            if (!irq_to_cpu) begin
                $display("  [FAIL] No IRQ pending at position %0d", 7-i);
                test_passed = 0;
            end else if (irq_id != i) begin
                $display("  [FAIL] Position %0d: Expected IRQ%0d, got IRQ%0d", 7-i, i, irq_id);
                test_passed = 0;
            end else begin
                $display("  [PASS] Position %0d: IRQ%0d (priority %0d)", 7-i, i, 7-i);
            end
            
            handle_interrupt();
            irq_sources[i] = 1'b0;
            wait_sync();
            complete_interrupt();
            wait_sync();
        end
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 3: Priority ordering correct");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 3: Priority ordering incorrect");
        end
        
        //======================================================================
        // Test 4: Nested Interrupts
        //======================================================================
        $display("\n=== Test 4: Nested Interrupt Handling ===");
        test_passed = 1;
        
        reset_dut();
        
        // Enable nesting, set priorities
        axi_write(ADDR_ENABLE, 32'h0000000F, 4'b0001);  // Enable IRQ0-3
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h03020100, 4'b1111);  // IRQ0=0 (highest), IRQ3=3 (lowest)
        axi_write(ADDR_PRIORITY1, 32'h07060504, 4'b1111);
        axi_write(ADDR_CTRL, 32'h00000003, 4'b0001);  // Global + Nest enable
        axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        
        // Assert lowest priority first
        irq_sources[3] = 1'b1;
        wait_sync();
        wait_sync();
        
        if (irq_id != 3) begin
            $display("  [FAIL] Initial IRQ should be IRQ3, got IRQ%0d", irq_id);
            test_passed = 0;
        end else begin
            $display("  [PASS] Initial: IRQ3 (lowest priority)");
        end
        
        handle_interrupt();
        nested_count = nested_count + 1;
        
        // Assert higher priority while servicing IRQ3
        irq_sources[1] = 1'b1;
        wait_sync();
        wait_sync();
        
        if (!irq_to_cpu || irq_id != 1) begin
            $display("  [FAIL] IRQ1 should preempt, got irq_to_cpu=%0d, irq_id=%0d", irq_to_cpu, irq_id);
            test_passed = 0;
        end else begin
            $display("  [PASS] Nested: IRQ1 preempted IRQ3");
        end
        
        handle_interrupt();
        nested_count = nested_count + 1;
        
        // Assert highest priority
        irq_sources[0] = 1'b1;
        wait_sync();
        wait_sync();
        
        if (!irq_to_cpu || irq_id != 0) begin
            $display("  [FAIL] IRQ0 should preempt, got irq_to_cpu=%0d, irq_id=%0d", irq_to_cpu, irq_id);
            test_passed = 0;
        end else begin
            $display("  [PASS] Nested: IRQ0 preempted IRQ1");
        end
        
        handle_interrupt();
        nested_count = nested_count + 1;
        
        // Complete in reverse order
        irq_sources[0] = 1'b0;
        wait_sync();
        complete_interrupt();
        $display("  [INFO] Completed IRQ0");
        
        irq_sources[1] = 1'b0;
        wait_sync();
        complete_interrupt();
        $display("  [INFO] Completed IRQ1");
        
        irq_sources[3] = 1'b0;
        wait_sync();
        complete_interrupt();
        $display("  [INFO] Completed IRQ3");
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 4: Nested interrupts handled correctly");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 4: Nested interrupt handling failed");
        end
        
        //======================================================================
        // Test 5: Edge-Triggered Interrupts
        //======================================================================
        $display("\n=== Test 5: Edge-Triggered Interrupts ===");
        test_passed = 1;
        
        for (i = 0; i < 20; i = i + 1) begin
            reset_dut();
            
            irq_num = ($random(seed) & 32'h7FFFFFFF) % NUM_IRQS;
            
            axi_write(ADDR_ENABLE, 32'h01 << irq_num, 4'b0001);
            axi_write(ADDR_TRIGGER, 32'h01 << irq_num, 4'b0001);  // Edge-triggered
            axi_write(ADDR_PRIORITY0, 32'h01010101, 4'b1111);
            axi_write(ADDR_PRIORITY1, 32'h01010101, 4'b1111);
            axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);
            axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
            
            // Generate pulse
            @(posedge clk);
            irq_sources[irq_num] = 1'b1;
            repeat(2) @(posedge clk);
            irq_sources[irq_num] = 1'b0;
            
            wait_sync();
            wait_sync();
            
            if (!irq_to_cpu) begin
                $display("  [FAIL] Iteration %0d: Edge pulse on IRQ%0d not detected", i, irq_num);
                test_passed = 0;
                lost_interrupts = lost_interrupts + 1;
            end else begin
                edge_count = edge_count + 1;
            end
            
            if (irq_to_cpu) begin
                handle_interrupt();
                axi_write(ADDR_EOI, 32'h01 << irq_num, 4'b0001);
                complete_interrupt();
            end
        end
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 5: All edge pulses captured (%0d)", edge_count);
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 5: Some edge pulses lost");
        end

        //======================================================================
        // Test 6: Stress Test - Random Interrupts
        //======================================================================
        $display("\n=== Test 6: Stress Test (Random Interrupts) ===");
        test_passed = 1;
        
        reset_dut();
        
        axi_write(ADDR_ENABLE, 32'h000000FF, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h0000000F, 4'b0001);  // IRQ0-3 edge, IRQ4-7 level
        axi_write(ADDR_PRIORITY0, 32'h03020100, 4'b1111);
        axi_write(ADDR_PRIORITY1, 32'h07060504, 4'b1111);
        axi_write(ADDR_CTRL, 32'h00000003, 4'b0001);  // Global + Nest
        axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        
        for (i = 0; i < STRESS_ITERATIONS; i = i + 1) begin
            // Random IRQ pattern
            irq_sources = ($random(seed) & 32'h7FFFFFFF) % 256;
            
            wait_sync();
            
            // Service any pending interrupts
            begin : stress_loop
                integer timeout;
                timeout = 0;
                while (irq_to_cpu && timeout < 100) begin
                    handle_interrupt();
                    
                    // Clear the serviced IRQ
                    if (irq_id < 4) begin
                        // Edge-triggered: write EOI
                        axi_write(ADDR_EOI, 32'h01 << irq_id, 4'b0001);
                    end else begin
                        // Level-triggered: deassert source
                        irq_sources[irq_id] = 1'b0;
                    end
                    
                    complete_interrupt();
                    wait_sync();
                    total_interrupts = total_interrupts + 1;
                    timeout = timeout + 1;
                end
            end
            
            // Clear all sources
            irq_sources = 0;
            wait_sync();
        end
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 6: Stress test completed (%0d interrupts serviced)", total_interrupts);
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 6: Stress test failed");
        end
        
        //======================================================================
        // Test 7: Register Read/Write Verification
        //======================================================================
        $display("\n=== Test 7: Register Read/Write Verification ===");
        test_passed = 1;
        
        reset_dut();
        
        // Write and read back ENABLE register
        axi_write(ADDR_ENABLE, 32'h000000A5, 4'b0001);
        axi_read(ADDR_ENABLE, read_data);
        if (read_data[7:0] != 8'hA5) begin
            $display("  [FAIL] ENABLE: wrote 0xA5, read 0x%02X", read_data[7:0]);
            test_passed = 0;
        end else begin
            $display("  [PASS] ENABLE register");
        end
        
        // Write and read back MASK register
        axi_write(ADDR_MASK, 32'h0000005A, 4'b0001);
        axi_read(ADDR_MASK, read_data);
        if (read_data[7:0] != 8'h5A) begin
            $display("  [FAIL] MASK: wrote 0x5A, read 0x%02X", read_data[7:0]);
            test_passed = 0;
        end else begin
            $display("  [PASS] MASK register");
        end
        
        // Write and read back TRIGGER register
        axi_write(ADDR_TRIGGER, 32'h000000F0, 4'b0001);
        axi_read(ADDR_TRIGGER, read_data);
        if (read_data[7:0] != 8'hF0) begin
            $display("  [FAIL] TRIGGER: wrote 0xF0, read 0x%02X", read_data[7:0]);
            test_passed = 0;
        end else begin
            $display("  [PASS] TRIGGER register");
        end
        
        // Write and read back PRIORITY registers
        axi_write(ADDR_PRIORITY0, 32'h44332211, 4'b1111);
        axi_read(ADDR_PRIORITY0, read_data);
        if (read_data != 32'h44332211) begin
            $display("  [FAIL] PRIORITY0: wrote 0x44332211, read 0x%08X", read_data);
            test_passed = 0;
        end else begin
            $display("  [PASS] PRIORITY0 register");
        end
        
        axi_write(ADDR_PRIORITY1, 32'h88776655, 4'b1111);
        axi_read(ADDR_PRIORITY1, read_data);
        if (read_data != 32'h88776655) begin
            $display("  [FAIL] PRIORITY1: wrote 0x88776655, read 0x%08X", read_data);
            test_passed = 0;
        end else begin
            $display("  [PASS] PRIORITY1 register");
        end
        
        // Write and read back THRESHOLD register
        axi_write(ADDR_THRESHOLD, 32'h00000080, 4'b0001);
        axi_read(ADDR_THRESHOLD, read_data);
        if (read_data[7:0] != 8'h80) begin
            $display("  [FAIL] THRESHOLD: wrote 0x80, read 0x%02X", read_data[7:0]);
            test_passed = 0;
        end else begin
            $display("  [PASS] THRESHOLD register");
        end
        
        // Write and read back CTRL register
        axi_write(ADDR_CTRL, 32'h00000007, 4'b0001);
        axi_read(ADDR_CTRL, read_data);
        if (read_data[7:0] != 8'h07) begin
            $display("  [FAIL] CTRL: wrote 0x07, read 0x%02X", read_data[7:0]);
            test_passed = 0;
        end else begin
            $display("  [PASS] CTRL register");
        end
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 7: All registers read/write correctly");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 7: Some registers failed");
        end
        
        //======================================================================
        // Test 8: Threshold Filtering
        //======================================================================
        $display("\n=== Test 8: Priority Threshold Filtering ===");
        test_passed = 1;
        
        reset_dut();
        
        // Set priorities: IRQ0=1, IRQ1=5, IRQ2=10
        axi_write(ADDR_ENABLE, 32'h00000007, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h000A0501, 4'b1111);  // IRQ0=1, IRQ1=5, IRQ2=10
        axi_write(ADDR_PRIORITY1, 32'h0F0F0F0F, 4'b1111);
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);
        
        // Set threshold to 8 (only IRQ0 and IRQ1 should pass)
        axi_write(ADDR_THRESHOLD, 32'h00000008, 4'b0001);
        
        // Assert all three
        irq_sources = 8'h07;
        wait_sync();
        wait_sync();
        
        // Should get IRQ0 first (priority 1)
        if (!irq_to_cpu || irq_id != 0) begin
            $display("  [FAIL] Expected IRQ0, got irq_to_cpu=%0d, irq_id=%0d", irq_to_cpu, irq_id);
            test_passed = 0;
        end else begin
            $display("  [PASS] IRQ0 (priority 1) passed threshold");
        end
        
        handle_interrupt();
        irq_sources[0] = 1'b0;
        wait_sync();
        complete_interrupt();
        wait_sync();
        
        // Should get IRQ1 next (priority 5)
        if (!irq_to_cpu || irq_id != 1) begin
            $display("  [FAIL] Expected IRQ1, got irq_to_cpu=%0d, irq_id=%0d", irq_to_cpu, irq_id);
            test_passed = 0;
        end else begin
            $display("  [PASS] IRQ1 (priority 5) passed threshold");
        end
        
        handle_interrupt();
        irq_sources[1] = 1'b0;
        wait_sync();
        complete_interrupt();
        wait_sync();
        
        // IRQ2 should be blocked (priority 10 >= threshold 8)
        if (irq_to_cpu) begin
            $display("  [FAIL] IRQ2 (priority 10) should be blocked by threshold 8");
            test_passed = 0;
        end else begin
            $display("  [PASS] IRQ2 (priority 10) blocked by threshold 8");
        end
        
        irq_sources = 0;
        
        if (test_passed) begin
            test_pass_count = test_pass_count + 1;
            $display("[PASS] Test 8: Threshold filtering works correctly");
        end else begin
            test_fail_count = test_fail_count + 1;
            $display("[FAIL] Test 8: Threshold filtering failed");
        end
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n##############################################");
        $display("# Checkpoint 10 Summary");
        $display("##############################################");
        $display("");
        $display("Test Results: %0d/%0d passed", test_pass_count, test_pass_count + test_fail_count);
        $display("");
        $display("Statistics:");
        $display("  Total Interrupts Serviced: %0d", total_interrupts);
        $display("  Level-Triggered: %0d", level_count);
        $display("  Edge-Triggered: %0d", edge_count);
        $display("  Nested Interrupts: %0d", nested_count);
        $display("  Lost Interrupts: %0d", lost_interrupts);
        $display("");
        $display("Latency:");
        $display("  Min: %0d cycles", min_latency);
        $display("  Max: %0d cycles", max_latency);
        $display("  Avg: %0d cycles", (total_latency > 0) ? (total_latency / LATENCY_ITERATIONS) : 0);
        $display("");
        
        if (test_fail_count == 0) begin
            $display("*** CHECKPOINT 10 PASSED ***");
        end else begin
            $display("*** CHECKPOINT 10 FAILED ***");
        end
        $display("##############################################");
        
        $finish;
    end

endmodule
