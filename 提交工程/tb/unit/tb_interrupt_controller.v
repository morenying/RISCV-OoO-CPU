`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// Interrupt Controller Unit Test
//
// Tests:
// 1. Basic interrupt detection (level and edge triggered)
// 2. Priority encoder functionality
// 3. Interrupt enable/mask registers
// 4. Nested interrupt support
// 5. EOI (End of Interrupt) handling
// 6. 2-stage synchronizer for async inputs
// 7. AXI register interface
// 8. Priority threshold
// 9. Multiple simultaneous interrupts
// 10. Edge detection and latching
//////////////////////////////////////////////////////////////////////////////

module tb_interrupt_controller;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_IRQS = 8;
    
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
    localparam ADDR_EDGE_DET   = 8'h28;
    localparam ADDR_CTRL       = 8'h2C;
    
    //==========================================================================
    // Test Counters
    //==========================================================================
    integer test_count;
    integer pass_count;
    integer fail_count;
    
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
        input  [7:0]  addr;
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
    // Check Task
    //==========================================================================
    task check;
        input [255:0] test_name;
        input         condition;
        begin
            test_count = test_count + 1;
            if (condition) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s", test_name);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s", test_name);
            end
        end
    endtask
    
    //==========================================================================
    // Wait for synchronizer delay
    //==========================================================================
    task wait_sync;
        begin
            repeat(4) @(posedge clk);  // 2 sync stages + margin
        end
    endtask
    
    //==========================================================================
    // Main Test
    //==========================================================================
    reg [31:0] read_data;
    
    initial begin
        $display("==============================================");
        $display("Interrupt Controller Unit Test");
        $display("==============================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        rst_n = 0;
        axi_awvalid = 0;
        axi_wvalid = 0;
        axi_bready = 0;
        axi_arvalid = 0;
        axi_rready = 0;
        axi_awaddr = 0;
        axi_wdata = 0;
        axi_wstrb = 0;
        axi_araddr = 0;
        irq_sources = 0;
        irq_ack = 0;
        irq_complete = 0;
        
        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        //======================================================================
        // Test 1: Default register values
        //======================================================================
        $display("\n--- Test 1: Default Register Values ---");
        
        axi_read(ADDR_ENABLE, read_data);
        check("Enable register default = 0", read_data[7:0] == 8'h00);
        
        axi_read(ADDR_MASK, read_data);
        check("Mask register default = 0", read_data[7:0] == 8'h00);
        
        axi_read(ADDR_TRIGGER, read_data);
        check("Trigger register default = 0 (level)", read_data[7:0] == 8'h00);
        
        axi_read(ADDR_CTRL, read_data);
        check("Control register default = 0x01 (global enable)", read_data[7:0] == 8'h01);
        
        axi_read(ADDR_THRESHOLD, read_data);
        check("Threshold register default = 0xFF", read_data[7:0] == 8'hFF);
        
        //======================================================================
        // Test 2: Register read/write
        //======================================================================
        $display("\n--- Test 2: Register Read/Write ---");
        
        axi_write(ADDR_ENABLE, 32'h000000AA, 4'b0001);
        axi_read(ADDR_ENABLE, read_data);
        check("Enable register write/read", read_data[7:0] == 8'hAA);
        
        axi_write(ADDR_MASK, 32'h00000055, 4'b0001);
        axi_read(ADDR_MASK, read_data);
        check("Mask register write/read", read_data[7:0] == 8'h55);
        
        axi_write(ADDR_TRIGGER, 32'h000000F0, 4'b0001);
        axi_read(ADDR_TRIGGER, read_data);
        check("Trigger register write/read", read_data[7:0] == 8'hF0);
        
        // Reset for next tests
        axi_write(ADDR_ENABLE, 32'h00000000, 4'b0001);
        axi_write(ADDR_MASK, 32'h00000000, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001);
        
        //======================================================================
        // Test 3: Priority register read/write
        //======================================================================
        $display("\n--- Test 3: Priority Registers ---");
        
        axi_write(ADDR_PRIORITY0, 32'h03020100, 4'b1111);
        axi_read(ADDR_PRIORITY0, read_data);
        check("Priority0 register write/read", read_data == 32'h03020100);
        
        axi_write(ADDR_PRIORITY1, 32'h07060504, 4'b1111);
        axi_read(ADDR_PRIORITY1, read_data);
        check("Priority1 register write/read", read_data == 32'h07060504);
        
        //======================================================================
        // Test 4: Level-triggered interrupt
        //======================================================================
        $display("\n--- Test 4: Level-Triggered Interrupt ---");
        
        // Enable IRQ0
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h00000001, 4'b0001);  // Priority 1 for IRQ0
        
        // Assert IRQ0
        irq_sources[0] = 1'b1;
        wait_sync();
        
        check("Level IRQ0 detected", irq_to_cpu == 1'b1);
        check("IRQ ID = 0", irq_id == 4'd0);
        
        // Acknowledge interrupt
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        @(posedge clk);
        
        axi_read(ADDR_ACTIVE, read_data);
        check("IRQ0 marked active", read_data[0] == 1'b1);
        
        // Deassert IRQ0 (level-triggered clears pending)
        irq_sources[0] = 1'b0;
        wait_sync();
        
        // Complete interrupt
        @(posedge clk);
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        @(posedge clk);
        
        axi_read(ADDR_ACTIVE, read_data);
        check("IRQ0 no longer active after complete", read_data[0] == 1'b0);
        
        //======================================================================
        // Test 5: Edge-triggered interrupt
        //======================================================================
        $display("\n--- Test 5: Edge-Triggered Interrupt ---");
        
        // Configure IRQ1 as edge-triggered
        axi_write(ADDR_ENABLE, 32'h00000002, 4'b0001);  // Enable IRQ1
        axi_write(ADDR_TRIGGER, 32'h00000002, 4'b0001); // Edge-triggered for IRQ1
        axi_write(ADDR_PRIORITY0, 32'h00000200, 4'b0010); // Priority 2 for IRQ1
        
        // Generate rising edge on IRQ1
        irq_sources[1] = 1'b0;
        wait_sync();
        irq_sources[1] = 1'b1;
        wait_sync();
        
        check("Edge IRQ1 detected", irq_to_cpu == 1'b1);
        check("IRQ ID = 1", irq_id == 4'd1);
        
        // Deassert IRQ1 - pending should remain (edge-triggered)
        irq_sources[1] = 1'b0;
        wait_sync();
        
        axi_read(ADDR_PENDING, read_data);
        check("Edge IRQ1 pending remains after deassert", read_data[1] == 1'b1);
        
        // Acknowledge and complete
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        
        // Write EOI to clear
        axi_write(ADDR_EOI, 32'h00000002, 4'b0001);
        @(posedge clk);
        
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        repeat(2) @(posedge clk);
        
        check("IRQ cleared after EOI", irq_to_cpu == 1'b0);
        
        //======================================================================
        // Test 6: Priority ordering
        //======================================================================
        $display("\n--- Test 6: Priority Ordering ---");
        
        // Enable IRQ0, IRQ1, IRQ2 with different priorities
        axi_write(ADDR_ENABLE, 32'h00000007, 4'b0001);  // Enable IRQ0,1,2
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001); // All level-triggered
        axi_write(ADDR_PRIORITY0, 32'h00010302, 4'b1111); // IRQ0=2, IRQ1=3, IRQ2=1
        
        // Assert all three
        irq_sources[2:0] = 3'b111;
        wait_sync();
        
        check("Highest priority IRQ2 selected", irq_id == 4'd2);
        check("Priority value = 1", irq_priority_out == 8'h01);
        
        // Acknowledge IRQ2
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        repeat(2) @(posedge clk);
        
        // Deassert IRQ2 (level-triggered, so pending clears)
        irq_sources[2] = 1'b0;
        wait_sync();
        
        // Complete IRQ2
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        repeat(4) @(posedge clk);
        
        // Now IRQ0 should be selected (priority 2, lower than IRQ1's priority 3)
        check("Next priority IRQ0 selected", irq_id == 4'd0);
        
        // Clean up
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 7: Interrupt masking
        //======================================================================
        $display("\n--- Test 7: Interrupt Masking ---");
        
        axi_write(ADDR_ENABLE, 32'h00000003, 4'b0001);  // Enable IRQ0,1
        axi_write(ADDR_MASK, 32'h00000001, 4'b0001);    // Mask IRQ0
        axi_write(ADDR_PRIORITY0, 32'h00000201, 4'b0011); // IRQ0=1, IRQ1=2
        
        // Assert both
        irq_sources[1:0] = 2'b11;
        wait_sync();
        
        // IRQ0 is masked, so IRQ1 should be selected
        check("Masked IRQ0 not selected", irq_id == 4'd1);
        
        // Unmask IRQ0
        axi_write(ADDR_MASK, 32'h00000000, 4'b0001);
        @(posedge clk);
        
        // Now IRQ0 should be selected (higher priority)
        check("Unmasked IRQ0 now selected", irq_id == 4'd0);
        
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 8: Priority threshold
        //======================================================================
        $display("\n--- Test 8: Priority Threshold ---");
        
        axi_write(ADDR_ENABLE, 32'h00000003, 4'b0001);
        axi_write(ADDR_PRIORITY0, 32'h00000A05, 4'b0011); // IRQ0=5, IRQ1=10
        axi_write(ADDR_THRESHOLD, 32'h00000008, 4'b0001); // Threshold = 8
        
        // Assert both
        irq_sources[1:0] = 2'b11;
        wait_sync();
        
        // Only IRQ0 (priority 5) should pass threshold
        check("Only IRQ0 passes threshold", irq_id == 4'd0);
        check("IRQ to CPU asserted", irq_to_cpu == 1'b1);
        
        // Raise threshold to block all
        axi_write(ADDR_THRESHOLD, 32'h00000002, 4'b0001);
        @(posedge clk);
        
        check("All IRQs blocked by threshold", irq_to_cpu == 1'b0);
        
        // Reset threshold
        axi_write(ADDR_THRESHOLD, 32'h000000FF, 4'b0001);
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 9: Nested interrupts
        //======================================================================
        $display("\n--- Test 9: Nested Interrupts ---");
        
        // Enable nesting
        axi_write(ADDR_CTRL, 32'h00000003, 4'b0001);  // Global + Nest enable
        axi_write(ADDR_ENABLE, 32'h00000003, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001); // Level-triggered
        axi_write(ADDR_PRIORITY0, 32'h00000802, 4'b0011); // IRQ0=2, IRQ1=8
        
        // Assert low priority IRQ1
        irq_sources[1] = 1'b1;
        wait_sync();
        wait_sync();  // Extra wait for stability
        
        check("Low priority IRQ1 detected", irq_to_cpu == 1'b1);
        check("IRQ1 ID correct", irq_id == 4'd1);
        
        // Acknowledge IRQ1
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        repeat(4) @(posedge clk);
        
        // Now assert high priority IRQ0 (should preempt)
        irq_sources[0] = 1'b1;
        wait_sync();
        wait_sync();  // Extra wait
        
        check("High priority IRQ0 preempts", irq_to_cpu == 1'b1);
        check("IRQ0 selected for preemption", irq_id == 4'd0);
        
        // Acknowledge IRQ0
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        repeat(4) @(posedge clk);
        
        // Complete IRQ0
        irq_sources[0] = 1'b0;
        wait_sync();
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        repeat(4) @(posedge clk);
        
        // IRQ1 should still be active (was preempted, now resumed)
        axi_read(ADDR_ACTIVE, read_data);
        check("IRQ1 still active after nested return", read_data[1] == 1'b1);
        
        // Complete IRQ1
        irq_sources[1] = 1'b0;
        wait_sync();
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        repeat(2) @(posedge clk);
        
        //======================================================================
        // Test 10: Synchronizer delay
        //======================================================================
        $display("\n--- Test 10: Synchronizer Delay ---");
        
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);  // Disable nesting
        
        // Assert IRQ0 and check it takes 2+ cycles to appear
        irq_sources[0] = 1'b1;
        @(posedge clk);
        // Should not be visible yet (in sync stage 1)
        @(posedge clk);
        // Should not be visible yet (in sync stage 2)
        @(posedge clk);
        // Now should be visible
        @(posedge clk);
        check("IRQ visible after sync delay", irq_to_cpu == 1'b1);
        
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 11: Write-1-clear pending
        //======================================================================
        $display("\n--- Test 11: Write-1-Clear Pending ---");
        
        axi_write(ADDR_TRIGGER, 32'h00000001, 4'b0001); // Edge-triggered IRQ0
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        
        // Generate edge
        irq_sources[0] = 1'b1;
        wait_sync();
        irq_sources[0] = 1'b0;
        wait_sync();
        
        axi_read(ADDR_PENDING, read_data);
        check("Pending set after edge", read_data[0] == 1'b1);
        
        // Write-1-clear
        axi_write(ADDR_PENDING, 32'h00000001, 4'b0001);
        @(posedge clk);
        
        axi_read(ADDR_PENDING, read_data);
        check("Pending cleared by write-1-clear", read_data[0] == 1'b0);
        
        //======================================================================
        // Test 12: Global enable
        //======================================================================
        $display("\n--- Test 12: Global Enable ---");
        
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001); // Level-triggered
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        axi_write(ADDR_CTRL, 32'h00000000, 4'b0001);    // Disable global
        
        irq_sources[0] = 1'b1;
        wait_sync();
        
        check("IRQ blocked when global disabled", irq_to_cpu == 1'b0);
        
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);    // Enable global
        @(posedge clk);
        
        check("IRQ passes when global enabled", irq_to_cpu == 1'b1);
        
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 13: Auto-EOI mode
        //======================================================================
        $display("\n--- Test 13: Auto-EOI Mode ---");
        
        axi_write(ADDR_TRIGGER, 32'h00000001, 4'b0001); // Edge-triggered
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        axi_write(ADDR_CTRL, 32'h00000005, 4'b0001);    // Global + Auto-EOI
        
        // Generate edge
        irq_sources[0] = 1'b1;
        wait_sync();
        irq_sources[0] = 1'b0;
        wait_sync();
        
        check("IRQ pending before ack", irq_to_cpu == 1'b1);
        
        // Acknowledge - should auto-clear pending
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        repeat(2) @(posedge clk);
        
        axi_read(ADDR_PENDING, read_data);
        check("Pending auto-cleared on ack", read_data[0] == 1'b0);
        
        // Complete
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        @(posedge clk);
        
        //======================================================================
        // Test 14: All 8 IRQ sources
        //======================================================================
        $display("\n--- Test 14: All 8 IRQ Sources ---");
        
        axi_write(ADDR_CTRL, 32'h00000001, 4'b0001);    // Global enable only
        axi_write(ADDR_ENABLE, 32'h000000FF, 4'b0001);  // Enable all
        axi_write(ADDR_TRIGGER, 32'h00000000, 4'b0001); // All level
        axi_write(ADDR_PRIORITY0, 32'h07050301, 4'b1111); // IRQ0=1, IRQ1=3, IRQ2=5, IRQ3=7
        axi_write(ADDR_PRIORITY1, 32'h08060402, 4'b1111); // IRQ4=2, IRQ5=4, IRQ6=6, IRQ7=8
        
        // Assert all
        irq_sources = 8'hFF;
        wait_sync();
        wait_sync();
        
        // IRQ0 has priority 1 (highest)
        check("IRQ0 selected (priority 1)", irq_id == 4'd0);
        
        // Acknowledge and complete IRQ0
        @(posedge clk);
        irq_ack = 1'b1;
        @(posedge clk);
        irq_ack = 1'b0;
        repeat(2) @(posedge clk);
        irq_sources[0] = 1'b0;
        wait_sync();
        irq_complete = 1'b1;
        @(posedge clk);
        irq_complete = 1'b0;
        repeat(2) @(posedge clk);
        
        // IRQ4 has priority 2 (next highest)
        check("IRQ4 selected (priority 2)", irq_id == 4'd4);
        
        irq_sources = 0;
        wait_sync();
        
        //======================================================================
        // Test 15: Edge detection doesn't miss pulses
        //======================================================================
        $display("\n--- Test 15: Edge Detection Pulse Capture ---");
        
        axi_write(ADDR_ENABLE, 32'h00000001, 4'b0001);
        axi_write(ADDR_TRIGGER, 32'h00000001, 4'b0001); // Edge-triggered
        
        // Short pulse (1 cycle)
        irq_sources[0] = 1'b1;
        @(posedge clk);
        irq_sources[0] = 1'b0;
        
        // Wait for sync
        wait_sync();
        wait_sync();  // Extra wait for edge detection
        
        axi_read(ADDR_PENDING, read_data);
        check("Short pulse captured", read_data[0] == 1'b1);
        
        // Clear pending
        axi_write(ADDR_PENDING, 32'h00000001, 4'b0001);
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n==============================================");
        $display("Test Summary: %0d/%0d passed", pass_count, test_count);
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("FAILURES: %0d", fail_count);
        end
        $display("==============================================");
        
        $finish;
    end

endmodule
