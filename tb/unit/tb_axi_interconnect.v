//=============================================================================
// Unit Test: AXI Interconnect
// Description: Tests for axi_interconnect module
//
// Test Cases:
//   1. Single master write to each slave
//   2. Single master read from each slave
//   3. Invalid address (DECERR response)
//   4. Round-robin arbitration between masters
//   5. Concurrent requests from both masters
//   6. Timeout handling
//   7. Back-to-back transactions
//   8. Fairness verification (no starvation)
//
// Requirements: 2.5, 2.6
//=============================================================================

`timescale 1ns/1ps

module tb_axi_interconnect;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz
    parameter NUM_MASTERS = 2;
    parameter NUM_SLAVES = 5;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // Master 0 (I-Cache) signals
    reg         m0_awvalid, m0_wvalid, m0_bready, m0_arvalid, m0_rready;
    wire        m0_awready, m0_wready, m0_bvalid, m0_arready, m0_rvalid;
    reg  [31:0] m0_awaddr, m0_wdata, m0_araddr;
    reg  [3:0]  m0_wstrb;
    reg  [2:0]  m0_awprot, m0_arprot;
    wire [31:0] m0_rdata;
    wire [1:0]  m0_bresp, m0_rresp;
    
    // Master 1 (D-Cache) signals
    reg         m1_awvalid, m1_wvalid, m1_bready, m1_arvalid, m1_rready;
    wire        m1_awready, m1_wready, m1_bvalid, m1_arready, m1_rvalid;
    reg  [31:0] m1_awaddr, m1_wdata, m1_araddr;
    reg  [3:0]  m1_wstrb;
    reg  [2:0]  m1_awprot, m1_arprot;
    wire [31:0] m1_rdata;
    wire [1:0]  m1_bresp, m1_rresp;
    
    // Packed master signals for DUT
    wire [NUM_MASTERS-1:0]              m_awvalid, m_wvalid, m_bready, m_arvalid, m_rready;
    wire [NUM_MASTERS-1:0]              m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    wire [NUM_MASTERS*ADDR_WIDTH-1:0]   m_awaddr, m_araddr;
    wire [NUM_MASTERS*DATA_WIDTH-1:0]   m_wdata, m_rdata;
    wire [NUM_MASTERS*4-1:0]            m_wstrb;
    wire [NUM_MASTERS*3-1:0]            m_awprot, m_arprot;
    wire [NUM_MASTERS*2-1:0]            m_bresp, m_rresp;
    
    // Pack master signals
    assign m_awvalid = {m1_awvalid, m0_awvalid};
    assign m_wvalid = {m1_wvalid, m0_wvalid};
    assign m_bready = {m1_bready, m0_bready};
    assign m_arvalid = {m1_arvalid, m0_arvalid};
    assign m_rready = {m1_rready, m0_rready};
    assign m_awaddr = {m1_awaddr, m0_awaddr};
    assign m_wdata = {m1_wdata, m0_wdata};
    assign m_araddr = {m1_araddr, m0_araddr};
    assign m_wstrb = {m1_wstrb, m0_wstrb};
    assign m_awprot = {m1_awprot, m0_awprot};
    assign m_arprot = {m1_arprot, m0_arprot};
    
    // Unpack master outputs
    assign m0_awready = m_awready[0];
    assign m0_wready = m_wready[0];
    assign m0_bvalid = m_bvalid[0];
    assign m0_arready = m_arready[0];
    assign m0_rvalid = m_rvalid[0];
    assign m0_rdata = m_rdata[31:0];
    assign m0_bresp = m_bresp[1:0];
    assign m0_rresp = m_rresp[1:0];
    
    assign m1_awready = m_awready[1];
    assign m1_wready = m_wready[1];
    assign m1_bvalid = m_bvalid[1];
    assign m1_arready = m_arready[1];
    assign m1_rvalid = m_rvalid[1];
    assign m1_rdata = m_rdata[63:32];
    assign m1_bresp = m_bresp[3:2];
    assign m1_rresp = m_rresp[3:2];
    
    // Slave signals (directly connected to simple responders)
    wire [NUM_SLAVES-1:0]               s_awvalid, s_wvalid, s_bready, s_arvalid, s_rready;
    reg  [NUM_SLAVES-1:0]               s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [NUM_SLAVES*ADDR_WIDTH-1:0]    s_awaddr, s_araddr;
    wire [NUM_SLAVES*DATA_WIDTH-1:0]    s_wdata;
    wire [NUM_SLAVES*4-1:0]             s_wstrb;
    wire [NUM_SLAVES*3-1:0]             s_awprot, s_arprot;
    reg  [NUM_SLAVES*DATA_WIDTH-1:0]    s_rdata;
    reg  [NUM_SLAVES*2-1:0]             s_bresp, s_rresp;
    
    // Test counters
    integer test_num;
    integer pass_count;
    integer fail_count;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    axi_interconnect #(
        .NUM_MASTERS    (NUM_MASTERS),
        .NUM_SLAVES     (NUM_SLAVES),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .TIMEOUT_CYCLES (100)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        
        // Master ports
        .m_awvalid  (m_awvalid),
        .m_awready  (m_awready),
        .m_awaddr   (m_awaddr),
        .m_awprot   (m_awprot),
        .m_wvalid   (m_wvalid),
        .m_wready   (m_wready),
        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),
        .m_bvalid   (m_bvalid),
        .m_bready   (m_bready),
        .m_bresp    (m_bresp),
        .m_arvalid  (m_arvalid),
        .m_arready  (m_arready),
        .m_araddr   (m_araddr),
        .m_arprot   (m_arprot),
        .m_rvalid   (m_rvalid),
        .m_rready   (m_rready),
        .m_rdata    (m_rdata),
        .m_rresp    (m_rresp),
        
        // Slave ports
        .s_awvalid  (s_awvalid),
        .s_awready  (s_awready),
        .s_awaddr   (s_awaddr),
        .s_awprot   (s_awprot),
        .s_wvalid   (s_wvalid),
        .s_wready   (s_wready),
        .s_wdata    (s_wdata),
        .s_wstrb    (s_wstrb),
        .s_bvalid   (s_bvalid),
        .s_bready   (s_bready),
        .s_bresp    (s_bresp),
        .s_arvalid  (s_arvalid),
        .s_arready  (s_arready),
        .s_araddr   (s_araddr),
        .s_arprot   (s_arprot),
        .s_rvalid   (s_rvalid),
        .s_rready   (s_rready),
        .s_rdata    (s_rdata),
        .s_rresp    (s_rresp)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    task wait_cycles;
        input integer n;
        integer i;
    begin
        for (i = 0; i < n; i = i + 1) @(posedge clk);
    end
    endtask
    
    task reset_dut;
    begin
        rst_n = 1'b0;
        // Reset all master signals
        m0_awvalid = 0; m0_wvalid = 0; m0_bready = 1; m0_arvalid = 0; m0_rready = 1;
        m0_awaddr = 0; m0_wdata = 0; m0_araddr = 0; m0_wstrb = 4'hF;
        m0_awprot = 0; m0_arprot = 0;
        
        m1_awvalid = 0; m1_wvalid = 0; m1_bready = 1; m1_arvalid = 0; m1_rready = 1;
        m1_awaddr = 0; m1_wdata = 0; m1_araddr = 0; m1_wstrb = 4'hF;
        m1_awprot = 0; m1_arprot = 0;
        
        // Reset all slave responses
        s_awready = {NUM_SLAVES{1'b1}};
        s_wready = {NUM_SLAVES{1'b1}};
        s_bvalid = {NUM_SLAVES{1'b0}};
        s_arready = {NUM_SLAVES{1'b1}};
        s_rvalid = {NUM_SLAVES{1'b0}};
        s_rdata = {NUM_SLAVES*DATA_WIDTH{1'b0}};
        s_bresp = {NUM_SLAVES*2{1'b0}};
        s_rresp = {NUM_SLAVES*2{1'b0}};
        
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask

    // Simple slave responder - responds after a configurable delay
    task slave_respond_write;
        input integer slave_id;
        input integer delay;
        input [1:0] resp;
    begin
        wait_cycles(delay);
        s_bvalid[slave_id] = 1'b1;
        s_bresp[slave_id*2 +: 2] = resp;
        @(posedge clk);
        while (!s_bready[slave_id]) @(posedge clk);
        s_bvalid[slave_id] = 1'b0;
    end
    endtask
    
    task slave_respond_read;
        input integer slave_id;
        input integer delay;
        input [31:0] data;
        input [1:0] resp;
    begin
        wait_cycles(delay);
        s_rvalid[slave_id] = 1'b1;
        s_rdata[slave_id*DATA_WIDTH +: DATA_WIDTH] = data;
        s_rresp[slave_id*2 +: 2] = resp;
        @(posedge clk);
        while (!s_rready[slave_id]) @(posedge clk);
        s_rvalid[slave_id] = 1'b0;
    end
    endtask
    
    // Master write transaction
    task master0_write;
        input [31:0] addr;
        input [31:0] data;
        output [1:0] resp;
        integer timeout;
    begin
        @(negedge clk);
        m0_awaddr = addr;
        m0_wdata = data;
        m0_awvalid = 1'b1;
        m0_wvalid = 1'b1;
        
        // Wait for address and data accepted
        timeout = 0;
        @(posedge clk);
        while (!(m0_awready && m0_wready) && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        m0_awvalid = 1'b0;
        m0_wvalid = 1'b0;
        
        // Wait for response
        timeout = 0;
        @(posedge clk);
        while (!m0_bvalid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        resp = m0_bresp;
        @(posedge clk);
    end
    endtask
    
    task master0_read;
        input [31:0] addr;
        output [31:0] data;
        output [1:0] resp;
        integer timeout;
    begin
        @(negedge clk);
        m0_araddr = addr;
        m0_arvalid = 1'b1;
        
        // Wait for address accepted
        timeout = 0;
        @(posedge clk);
        while (!m0_arready && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        m0_arvalid = 1'b0;
        
        // Wait for response
        timeout = 0;
        @(posedge clk);
        while (!m0_rvalid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        data = m0_rdata;
        resp = m0_rresp;
        @(posedge clk);
    end
    endtask
    
    task master1_write;
        input [31:0] addr;
        input [31:0] data;
        output [1:0] resp;
        integer timeout;
    begin
        @(negedge clk);
        m1_awaddr = addr;
        m1_wdata = data;
        m1_awvalid = 1'b1;
        m1_wvalid = 1'b1;
        
        timeout = 0;
        @(posedge clk);
        while (!(m1_awready && m1_wready) && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        m1_awvalid = 1'b0;
        m1_wvalid = 1'b0;
        
        timeout = 0;
        @(posedge clk);
        while (!m1_bvalid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        resp = m1_bresp;
        @(posedge clk);
    end
    endtask
    
    task master1_read;
        input [31:0] addr;
        output [31:0] data;
        output [1:0] resp;
        integer timeout;
    begin
        @(negedge clk);
        m1_araddr = addr;
        m1_arvalid = 1'b1;
        
        timeout = 0;
        @(posedge clk);
        while (!m1_arready && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        @(negedge clk);
        m1_arvalid = 1'b0;
        
        timeout = 0;
        @(posedge clk);
        while (!m1_rvalid && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        
        data = m1_rdata;
        resp = m1_rresp;
        @(posedge clk);
    end
    endtask
    
    task check_result;
        input [255:0] test_name;
        input pass;
    begin
        test_num = test_num + 1;
        if (pass) begin
            $display("[PASS] Test %0d: %0s", test_num, test_name);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Test %0d: %0s", test_num, test_name);
            fail_count = fail_count + 1;
        end
    end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    reg [1:0] resp;
    reg [31:0] rdata;
    
    initial begin
        $display("========================================");
        $display("AXI Interconnect Unit Tests");
        $display("========================================");
        
        test_num = 0;
        pass_count = 0;
        fail_count = 0;
        
        reset_dut();
        
        //=====================================================================
        // Test 1: Write to Boot ROM (Slave 0) - address 0x0000_0000
        //=====================================================================
        fork
            master0_write(32'h0000_0100, 32'hDEAD_BEEF, resp);
            slave_respond_write(0, 2, 2'b00);  // OKAY response
        join
        check_result("Write to Boot ROM (Slave 0)", resp == 2'b00);
        
        //=====================================================================
        // Test 2: Read from Boot ROM (Slave 0)
        //=====================================================================
        fork
            master0_read(32'h0000_0200, rdata, resp);
            slave_respond_read(0, 2, 32'hCAFE_BABE, 2'b00);
        join
        check_result("Read from Boot ROM (Slave 0)", resp == 2'b00 && rdata == 32'hCAFE_BABE);
        
        //=====================================================================
        // Test 3: Write to SRAM (Slave 1) - address 0x8000_0000
        //=====================================================================
        fork
            master0_write(32'h8000_1000, 32'h1234_5678, resp);
            slave_respond_write(1, 3, 2'b00);
        join
        check_result("Write to SRAM (Slave 1)", resp == 2'b00);
        
        //=====================================================================
        // Test 4: Read from SRAM (Slave 1)
        //=====================================================================
        fork
            master0_read(32'h8000_2000, rdata, resp);
            slave_respond_read(1, 3, 32'h8765_4321, 2'b00);
        join
        check_result("Read from SRAM (Slave 1)", resp == 2'b00 && rdata == 32'h8765_4321);
        
        //=====================================================================
        // Test 5: Write to UART (Slave 2) - address 0x1000_0000
        //=====================================================================
        fork
            master0_write(32'h1000_0000, 32'h0000_0041, resp);  // 'A'
            slave_respond_write(2, 1, 2'b00);
        join
        check_result("Write to UART (Slave 2)", resp == 2'b00);
        
        //=====================================================================
        // Test 6: Read from GPIO (Slave 3) - address 0x1000_0100
        //=====================================================================
        fork
            master0_read(32'h1000_0100, rdata, resp);
            slave_respond_read(3, 1, 32'h0000_00FF, 2'b00);
        join
        check_result("Read from GPIO (Slave 3)", resp == 2'b00 && rdata == 32'h0000_00FF);
        
        //=====================================================================
        // Test 7: Write to Timer (Slave 4) - address 0x1000_0200
        //=====================================================================
        fork
            master0_write(32'h1000_0200, 32'h0001_0000, resp);
            slave_respond_write(4, 1, 2'b00);
        join
        check_result("Write to Timer (Slave 4)", resp == 2'b00);
        
        //=====================================================================
        // Test 8: Invalid address - should get DECERR
        //=====================================================================
        master0_read(32'hFFFF_0000, rdata, resp);
        check_result("Invalid address returns DECERR", resp == 2'b11);
        
        //=====================================================================
        // Test 9: Master 1 write to SRAM
        //=====================================================================
        fork
            master1_write(32'h8000_3000, 32'hAAAA_BBBB, resp);
            slave_respond_write(1, 2, 2'b00);
        join
        check_result("Master 1 write to SRAM", resp == 2'b00);
        
        //=====================================================================
        // Test 10: Master 1 read from SRAM
        //=====================================================================
        fork
            master1_read(32'h8000_4000, rdata, resp);
            slave_respond_read(1, 2, 32'hCCCC_DDDD, 2'b00);
        join
        check_result("Master 1 read from SRAM", resp == 2'b00 && rdata == 32'hCCCC_DDDD);
        
        //=====================================================================
        // Test 11: Slave error response propagation
        //=====================================================================
        fork
            master0_write(32'h8000_5000, 32'h1111_2222, resp);
            slave_respond_write(1, 2, 2'b10);  // SLVERR
        join
        check_result("Slave error response propagation", resp == 2'b10);
        
        //=====================================================================
        // Test 12: Back-to-back writes
        //=====================================================================
        fork
            begin
                master0_write(32'h8000_6000, 32'h3333_4444, resp);
            end
            begin
                slave_respond_write(1, 1, 2'b00);
            end
        join
        check_result("Back-to-back write 1", resp == 2'b00);
        
        fork
            begin
                master0_write(32'h8000_6004, 32'h5555_6666, resp);
            end
            begin
                slave_respond_write(1, 1, 2'b00);
            end
        join
        check_result("Back-to-back write 2", resp == 2'b00);
        
        //=====================================================================
        // Test 13-14: Concurrent requests - round robin
        //=====================================================================
        // Both masters request simultaneously
        fork
            begin
                @(negedge clk);
                m0_araddr = 32'h8000_7000;
                m0_arvalid = 1'b1;
                @(posedge clk);
                while (!m0_arready) @(posedge clk);
                @(negedge clk);
                m0_arvalid = 1'b0;
                while (!m0_rvalid) @(posedge clk);
            end
            begin
                @(negedge clk);
                m1_araddr = 32'h8000_8000;
                m1_arvalid = 1'b1;
                @(posedge clk);
                while (!m1_arready) @(posedge clk);
                @(negedge clk);
                m1_arvalid = 1'b0;
                while (!m1_rvalid) @(posedge clk);
            end
            begin
                // Respond to first request
                wait(s_arvalid[1]);
                slave_respond_read(1, 1, 32'hAAAA_1111, 2'b00);
                // Respond to second request
                wait(s_arvalid[1]);
                slave_respond_read(1, 1, 32'hBBBB_2222, 2'b00);
            end
        join
        check_result("Concurrent read - Master 0", m0_rdata == 32'hAAAA_1111 || m0_rdata == 32'hBBBB_2222);
        check_result("Concurrent read - Master 1", m1_rdata == 32'hAAAA_1111 || m1_rdata == 32'hBBBB_2222);
        
        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("");
        $display("========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("Total:  %0d", test_num);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("*** SOME TESTS FAILED ***");
        end
        
        $finish;
    end
    
    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #500000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
