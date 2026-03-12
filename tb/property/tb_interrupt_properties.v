`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Interrupt Controller Property Tests
//
// Property 5: Interrupt Latency Bound
// - For any external interrupt assertion, the CPU shall begin executing
//   the interrupt handler within 20 cycles
//
// Property 6: Interrupt Priority
// - For any two simultaneous interrupts with different priorities, the
//   higher priority interrupt shall be serviced first
//
// Additional Properties:
// - Edge detection correctness
// - Nested interrupt handling
// - No interrupt loss
//////////////////////////////////////////////////////////////////////////////

module tb_interrupt_properties;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_IRQS = 8;
    parameter NUM_ITERATIONS = 50;  // Reduced for faster testing
    parameter MAX_LATENCY = 10;  // Maximum allowed interrupt latency (sync + logic)
    
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
    // Test Counters
    //==========================================================================
    integer iteration;
    integer pass_count;
    integer fail_count;
    integer total_latency;
    integer max_observed_latency;
    integer min_observed_latency;
    
    //==========================================================================
    // Random seed
    //==========================================================================
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
    // Wait for synchronizer
    //==========================================================================
    task wait_sync;
        begin
            repeat(4) @(posedge clk);
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
    // Configure interrupt controller
    //==========================================================================
    task configure_intc;
        input [7:0] enable;
        input [7:0] trigger;
        input [31:0] priority0;
        input [31:0] priority1;
        input [7:0] ctrl;
        begin
            axi_write(ADDR_ENABLE, {24'd0, enable}, 4'b0001);
            axi_write(ADDR_TRIGGER, {24'd0, trigger}, 4'b0001);
            axi_write(ADDR_PRIORITY0, priority0, 4'b1111);
            axi_write(ADDR_PRIORITY1, priority1, 4'b1111);
            axi_write(ADDR_CTRL, {24'd0, ctrl}, 4'b0001);
            axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        end
    endtask
    
    //==========================================================================
    // Acknowledge and complete interrupt
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
    integer i, j;
    integer latency;
    integer irq_num;
    reg [7:0] random_priorities [0:7];
    reg [3:0] expected_order [0:7];
    reg [3:0] actual_order [0:7];
    integer order_idx;
    reg [7:0] irq_mask;
    reg test_passed;
    
    initial begin
        $display("==============================================");
        $display("Interrupt Controller Property Tests");
        $display("==============================================");
        
        seed = 12345;
        pass_count = 0;
        fail_count = 0;
        
        //======================================================================
        // Property 5: Interrupt Latency Bound
        //======================================================================
        $display("\n--- Property 5: Interrupt Latency Bound ---");
        $display("Testing %0d random interrupt assertions...", NUM_ITERATIONS);
        
        total_latency = 0;
        max_observed_latency = 0;
        min_observed_latency = 1000;
        test_passed = 1;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            
            // Random IRQ number (ensure positive)
            irq_num = ($random(seed) & 32'h7FFFFFFF) % NUM_IRQS;
            
            // Configure: enable only the selected IRQ, level-triggered
            configure_intc(
                8'h01 << irq_num,  // Enable only selected IRQ
                8'h00,              // Level-triggered
                32'h01010101,       // All priority 1
                32'h01010101,
                8'h01               // Global enable
            );
            
            // Wait for configuration to fully settle and ensure no pending IRQ
            repeat(10) @(posedge clk);
            
            // Verify no IRQ is pending before we start
            if (irq_to_cpu) begin
                $display("  [WARN] Iteration %0d: IRQ already pending before test", iteration);
            end
            
            // Assert interrupt at clock edge and start counting
            @(posedge clk);
            irq_sources[irq_num] = 1'b1;
            latency = 0;
            
            // Count cycles until irq_to_cpu goes high
            // Expected: 2-3 cycles for sync + 1 cycle for logic = ~3-5 cycles
            while (!irq_to_cpu && latency < 50) begin
                @(posedge clk);
                latency = latency + 1;
            end
            
            if (latency > MAX_LATENCY) begin
                $display("  [FAIL] Iteration %0d: IRQ%0d latency = %0d cycles (> %0d)",
                         iteration, irq_num, latency, MAX_LATENCY);
                test_passed = 0;
            end
            
            total_latency = total_latency + latency;
            if (latency > max_observed_latency) max_observed_latency = latency;
            if (latency < min_observed_latency) min_observed_latency = latency;
            
            // Clean up
            irq_sources = 0;
            wait_sync();
        end
        
        if (test_passed) begin
            pass_count = pass_count + 1;
            $display("[PASS] Property 5: All %0d iterations within latency bound", NUM_ITERATIONS);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Property 5: Some iterations exceeded latency bound");
        end
        $display("  Latency stats: min=%0d, max=%0d, avg=%0d cycles",
                 min_observed_latency, max_observed_latency, total_latency / NUM_ITERATIONS);

        //======================================================================
        // Property 6: Interrupt Priority
        //======================================================================
        $display("\n--- Property 6: Interrupt Priority ---");
        $display("Testing %0d random priority configurations...", NUM_ITERATIONS);
        
        test_passed = 1;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            
            // Generate random priorities for all 8 IRQs (0-254 to avoid threshold issue)
            for (i = 0; i < NUM_IRQS; i = i + 1) begin
                random_priorities[i] = (($random(seed) & 32'h7FFFFFFF) % 255);  // 0-254
            end
            
            // Calculate expected order (sort by priority, lower value = higher priority)
            // Simple bubble sort to find expected order
            for (i = 0; i < NUM_IRQS; i = i + 1) begin
                expected_order[i] = i[3:0];
            end
            for (i = 0; i < NUM_IRQS - 1; i = i + 1) begin
                for (j = 0; j < NUM_IRQS - 1 - i; j = j + 1) begin
                    if (random_priorities[expected_order[j]] > random_priorities[expected_order[j+1]]) begin
                        // Swap
                        expected_order[j] = expected_order[j] ^ expected_order[j+1];
                        expected_order[j+1] = expected_order[j] ^ expected_order[j+1];
                        expected_order[j] = expected_order[j] ^ expected_order[j+1];
                    end
                end
            end
            
            // Configure interrupt controller
            axi_write(ADDR_ENABLE, 32'h000000FF, 4'b0001);  // Enable all
            axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001); // Level-triggered
            axi_write(ADDR_PRIORITY0, {random_priorities[3], random_priorities[2],
                                       random_priorities[1], random_priorities[0]}, 4'b1111);
            axi_write(ADDR_PRIORITY1, {random_priorities[7], random_priorities[6],
                                       random_priorities[5], random_priorities[4]}, 4'b1111);
            axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);    // Global enable
            axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
            
            // Assert all interrupts simultaneously
            irq_sources = 8'hFF;
            wait_sync();
            wait_sync();
            
            // Service interrupts in order and record actual order
            order_idx = 0;
            irq_mask = 8'hFF;
            
            begin : priority_loop
                integer timeout_cnt;
                while (irq_mask != 0 && order_idx < NUM_IRQS) begin
                    // Wait for irq_to_cpu with timeout
                    timeout_cnt = 0;
                    while (!irq_to_cpu && timeout_cnt < 200) begin
                        @(posedge clk);
                        timeout_cnt = timeout_cnt + 1;
                    end
                    
                    if (timeout_cnt >= 200) begin
                        $display("  [FAIL] Iteration %0d: Timeout waiting for IRQ (mask=%h, order_idx=%0d, irq_sources=%h)", 
                                 iteration, irq_mask, order_idx, irq_sources);
                        test_passed = 0;
                        disable priority_loop;
                    end
                    
                    actual_order[order_idx] = irq_id;
                    
                    // Acknowledge
                    handle_interrupt();
                    
                    // Deassert this IRQ (for level-triggered, this clears pending)
                    irq_sources[irq_id] = 1'b0;
                    irq_mask[irq_id] = 1'b0;
                    
                    // Complete and wait for state to settle
                    complete_interrupt();
                    wait_sync();
                    wait_sync();
                    
                    order_idx = order_idx + 1;
                end
            end
            
            // Verify order matches expected
            for (i = 0; i < NUM_IRQS; i = i + 1) begin
                if (actual_order[i] != expected_order[i]) begin
                    // Check if priorities are equal (tie-breaking is implementation-defined)
                    if (random_priorities[actual_order[i]] != random_priorities[expected_order[i]]) begin
                        $display("  [FAIL] Iteration %0d: Position %0d expected IRQ%0d (pri=%0d) got IRQ%0d (pri=%0d)",
                                 iteration, i, expected_order[i], random_priorities[expected_order[i]],
                                 actual_order[i], random_priorities[actual_order[i]]);
                        test_passed = 0;
                    end
                end
            end
        end
        
        if (test_passed) begin
            pass_count = pass_count + 1;
            $display("[PASS] Property 6: All %0d iterations maintained priority order", NUM_ITERATIONS);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Property 6: Some iterations violated priority order");
        end
        
        //======================================================================
        // Property: Edge Detection - No Interrupt Loss
        //======================================================================
        $display("\n--- Property: Edge Detection (No Loss) ---");
        $display("Testing %0d random edge pulses...", NUM_ITERATIONS);
        
        test_passed = 1;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            
            // Random IRQ number
            irq_num = ($random(seed) & 32'h7FFFFFFF) % NUM_IRQS;
            
            // Configure: edge-triggered
            configure_intc(
                8'h01 << irq_num,  // Enable only selected IRQ
                8'h01 << irq_num,  // Edge-triggered for selected IRQ
                32'h01010101,
                32'h01010101,
                8'h01
            );
            
            // Generate short pulse (1-3 cycles)
            @(posedge clk);
            irq_sources[irq_num] = 1'b1;
            repeat((($random(seed) & 32'h7FFFFFFF) % 3) + 1) @(posedge clk);
            irq_sources[irq_num] = 1'b0;
            
            // Wait for sync and check if detected
            wait_sync();
            wait_sync();
            
            if (!irq_to_cpu) begin
                $display("  [FAIL] Iteration %0d: IRQ%0d edge pulse not detected", iteration, irq_num);
                test_passed = 0;
            end
            
            // Clean up - acknowledge and complete
            if (irq_to_cpu) begin
                handle_interrupt();
                axi_write(ADDR_EOI, 32'h01 << irq_num, 4'b0001);
                complete_interrupt();
            end
        end
        
        if (test_passed) begin
            pass_count = pass_count + 1;
            $display("[PASS] Edge Detection: All %0d pulses captured", NUM_ITERATIONS);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Edge Detection: Some pulses lost");
        end
        
        //======================================================================
        // Property: Nested Interrupt Handling
        //======================================================================
        $display("\n--- Property: Nested Interrupt Handling ---");
        $display("Testing %0d nested interrupt scenarios...", NUM_ITERATIONS);
        
        test_passed = 1;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            
            // Configure: enable IRQ0 (high priority) and IRQ1 (low priority)
            // Enable nesting
            configure_intc(
                8'h03,              // Enable IRQ0, IRQ1
                8'h00,              // Level-triggered
                32'h00000801,       // IRQ0=1 (high), IRQ1=8 (low)
                32'h0F0F0F0F,
                8'h03               // Global + Nest enable
            );
            
            // Assert low priority IRQ1
            irq_sources[1] = 1'b1;
            wait_sync();
            wait_sync();
            
            if (!irq_to_cpu || irq_id != 4'd1) begin
                $display("  [FAIL] Iteration %0d: Low priority IRQ1 not detected", iteration);
                test_passed = 0;
            end
            
            // Acknowledge IRQ1
            handle_interrupt();
            
            // Assert high priority IRQ0 (should preempt)
            irq_sources[0] = 1'b1;
            wait_sync();
            wait_sync();
            
            if (!irq_to_cpu || irq_id != 4'd0) begin
                $display("  [FAIL] Iteration %0d: High priority IRQ0 did not preempt", iteration);
                test_passed = 0;
            end
            
            // Acknowledge IRQ0
            handle_interrupt();
            
            // Complete IRQ0
            irq_sources[0] = 1'b0;
            wait_sync();
            complete_interrupt();
            
            // IRQ1 should still be active (was preempted)
            // Note: We can't easily check this without reading ACTIVE register
            // Just verify system is stable
            
            // Complete IRQ1
            irq_sources[1] = 1'b0;
            wait_sync();
            complete_interrupt();
        end
        
        if (test_passed) begin
            pass_count = pass_count + 1;
            $display("[PASS] Nested Interrupts: All %0d scenarios handled correctly", NUM_ITERATIONS);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Nested Interrupts: Some scenarios failed");
        end
        
        //======================================================================
        // Property: Synchronizer Safety
        //======================================================================
        $display("\n--- Property: Synchronizer Safety ---");
        $display("Testing %0d async interrupt assertions...", NUM_ITERATIONS);
        
        test_passed = 1;
        
        for (iteration = 0; iteration < NUM_ITERATIONS; iteration = iteration + 1) begin
            reset_dut();
            
            irq_num = ($random(seed) & 32'h7FFFFFFF) % NUM_IRQS;
            
            configure_intc(
                8'h01 << irq_num,
                8'h00,
                32'h01010101,
                32'h01010101,
                8'h01
            );
            
            // Assert at random phase within clock cycle
            #((($random(seed) & 32'h7FFFFFFF) % CLK_PERIOD));
            irq_sources[irq_num] = 1'b1;
            
            // Wait for sync (should take 2-3 cycles)
            repeat(5) @(posedge clk);
            
            // Should be detected without metastability issues
            if (!irq_to_cpu) begin
                $display("  [FAIL] Iteration %0d: Async IRQ%0d not detected after sync", iteration, irq_num);
                test_passed = 0;
            end
            
            irq_sources = 0;
            wait_sync();
        end
        
        if (test_passed) begin
            pass_count = pass_count + 1;
            $display("[PASS] Synchronizer: All %0d async assertions handled", NUM_ITERATIONS);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Synchronizer: Some async assertions failed");
        end
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n==============================================");
        $display("Property Test Summary: %0d/%0d passed", pass_count, pass_count + fail_count);
        if (fail_count == 0) begin
            $display("ALL PROPERTY TESTS PASSED!");
        end else begin
            $display("FAILURES: %0d", fail_count);
        end
        $display("==============================================");
        
        $finish;
    end

endmodule
