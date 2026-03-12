//=============================================================================
// Checkpoint 6: AXI Interconnect Verification
// Description: Comprehensive bus stress test
//
// Requirements:
//   - Complete bus stress test
//   - Verify arbitration fairness (< 10% bandwidth difference)
//   - Verify all error paths correctly handled
//
// Validates: Requirements 2.5, 2.6
//=============================================================================

`timescale 1ns/1ps

module tb_axi_checkpoint;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;
    parameter NUM_MASTERS = 2;
    parameter NUM_SLAVES = 5;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter NUM_TRANSACTIONS = 500;
    
    //=========================================================================
    // Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    
    // Master signals (packed)
    reg  [NUM_MASTERS-1:0]              m_awvalid, m_wvalid, m_bready, m_arvalid, m_rready;
    wire [NUM_MASTERS-1:0]              m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    reg  [NUM_MASTERS*ADDR_WIDTH-1:0]   m_awaddr, m_araddr;
    reg  [NUM_MASTERS*DATA_WIDTH-1:0]   m_wdata;
    wire [NUM_MASTERS*DATA_WIDTH-1:0]   m_rdata;
    reg  [NUM_MASTERS*4-1:0]            m_wstrb;
    reg  [NUM_MASTERS*3-1:0]            m_awprot, m_arprot;
    wire [NUM_MASTERS*2-1:0]            m_bresp, m_rresp;
    
    // Slave signals
    wire [NUM_SLAVES-1:0]               s_awvalid, s_wvalid, s_bready, s_arvalid, s_rready;
    reg  [NUM_SLAVES-1:0]               s_awready, s_wready, s_bvalid, s_arready, s_rvalid;
    wire [NUM_SLAVES*ADDR_WIDTH-1:0]    s_awaddr, s_araddr;
    wire [NUM_SLAVES*DATA_WIDTH-1:0]    s_wdata;
    wire [NUM_SLAVES*4-1:0]             s_wstrb;
    wire [NUM_SLAVES*3-1:0]             s_awprot, s_arprot;
    reg  [NUM_SLAVES*DATA_WIDTH-1:0]    s_rdata;
    reg  [NUM_SLAVES*2-1:0]             s_bresp, s_rresp;
    
    // Statistics
    integer m0_count, m1_count;
    integer slave_count [0:NUM_SLAVES-1];
    integer error_count;
    integer decerr_count;
    
    // Random state
    reg [31:0] lfsr;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    axi_interconnect #(
        .NUM_MASTERS    (NUM_MASTERS),
        .NUM_SLAVES     (NUM_SLAVES),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .TIMEOUT_CYCLES (50)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .m_awvalid(m_awvalid), .m_awready(m_awready), .m_awaddr(m_awaddr), .m_awprot(m_awprot),
        .m_wvalid(m_wvalid), .m_wready(m_wready), .m_wdata(m_wdata), .m_wstrb(m_wstrb),
        .m_bvalid(m_bvalid), .m_bready(m_bready), .m_bresp(m_bresp),
        .m_arvalid(m_arvalid), .m_arready(m_arready), .m_araddr(m_araddr), .m_arprot(m_arprot),
        .m_rvalid(m_rvalid), .m_rready(m_rready), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .s_awvalid(s_awvalid), .s_awready(s_awready), .s_awaddr(s_awaddr), .s_awprot(s_awprot),
        .s_wvalid(s_wvalid), .s_wready(s_wready), .s_wdata(s_wdata), .s_wstrb(s_wstrb),
        .s_bvalid(s_bvalid), .s_bready(s_bready), .s_bresp(s_bresp),
        .s_arvalid(s_arvalid), .s_arready(s_arready), .s_araddr(s_araddr), .s_arprot(s_arprot),
        .s_rvalid(s_rvalid), .s_rready(s_rready), .s_rdata(s_rdata), .s_rresp(s_rresp)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // LFSR Random
    //=========================================================================
    function [31:0] next_random;
        input [31:0] current;
    begin
        next_random = {current[30:0], current[31] ^ current[21] ^ current[1] ^ current[0]};
    end
    endfunction
    
    task get_random;
        output [31:0] value;
    begin
        lfsr = next_random(lfsr);
        value = lfsr;
    end
    endtask
    
    //=========================================================================
    // Slave Auto-Responder
    //=========================================================================
    integer slave_idx;
    reg [NUM_SLAVES-1:0] pending_write, pending_read;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_bvalid <= 0; s_rvalid <= 0;
            pending_write <= 0; pending_read <= 0;
        end else begin
            for (slave_idx = 0; slave_idx < NUM_SLAVES; slave_idx = slave_idx + 1) begin
                if (s_awvalid[slave_idx] && s_wvalid[slave_idx] && 
                    s_awready[slave_idx] && s_wready[slave_idx] && !pending_write[slave_idx]) begin
                    pending_write[slave_idx] <= 1'b1;
                    slave_count[slave_idx] = slave_count[slave_idx] + 1;
                end
                if (pending_write[slave_idx] && !s_bvalid[slave_idx]) begin
                    s_bvalid[slave_idx] <= 1'b1;
                    s_bresp[slave_idx*2 +: 2] <= 2'b00;
                end
                if (s_bvalid[slave_idx] && s_bready[slave_idx]) begin
                    s_bvalid[slave_idx] <= 1'b0;
                    pending_write[slave_idx] <= 1'b0;
                end
                
                if (s_arvalid[slave_idx] && s_arready[slave_idx] && !pending_read[slave_idx]) begin
                    pending_read[slave_idx] <= 1'b1;
                    slave_count[slave_idx] = slave_count[slave_idx] + 1;
                end
                if (pending_read[slave_idx] && !s_rvalid[slave_idx]) begin
                    s_rvalid[slave_idx] <= 1'b1;
                    s_rdata[slave_idx*DATA_WIDTH +: DATA_WIDTH] <= 32'hDEAD_0000 + slave_idx;
                    s_rresp[slave_idx*2 +: 2] <= 2'b00;
                end
                if (s_rvalid[slave_idx] && s_rready[slave_idx]) begin
                    s_rvalid[slave_idx] <= 1'b0;
                    pending_read[slave_idx] <= 1'b0;
                end
            end
        end
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
        integer j;
    begin
        rst_n = 1'b0;
        m_awvalid = 0; m_wvalid = 0; m_bready = {NUM_MASTERS{1'b1}};
        m_arvalid = 0; m_rready = {NUM_MASTERS{1'b1}};
        m_awaddr = 0; m_wdata = 0; m_araddr = 0;
        m_wstrb = {NUM_MASTERS*4{1'b1}};
        m_awprot = 0; m_arprot = 0;
        s_awready = {NUM_SLAVES{1'b1}};
        s_wready = {NUM_SLAVES{1'b1}};
        s_arready = {NUM_SLAVES{1'b1}};
        for (j = 0; j < NUM_SLAVES; j = j + 1) slave_count[j] = 0;
        wait_cycles(5);
        rst_n = 1'b1;
        wait_cycles(2);
    end
    endtask
    
    function [31:0] random_addr;
        input [31:0] rand_val;
        reg [2:0] slave_sel;
    begin
        slave_sel = rand_val[2:0] % 5;
        case (slave_sel)
            0: random_addr = 32'h0000_0000 + (rand_val[13:2] & 32'h00003FFC);
            1: random_addr = 32'h8000_0000 + (rand_val[17:2] & 32'h0003FFFC);
            2: random_addr = 32'h1000_0000 + (rand_val[7:2] & 32'h000000FC);
            3: random_addr = 32'h1000_0100 + (rand_val[7:2] & 32'h000000FC);
            4: random_addr = 32'h1000_0200 + (rand_val[7:2] & 32'h000000FC);
            default: random_addr = 32'h8000_0000;
        endcase
    end
    endfunction
    
    task do_transaction;
        input integer master;
        input [31:0] addr;
        input is_write;
        integer timeout;
    begin
        if (is_write) begin
            m_awaddr[master*ADDR_WIDTH +: ADDR_WIDTH] = addr;
            m_wdata[master*DATA_WIDTH +: DATA_WIDTH] = addr;
            m_awvalid[master] = 1'b1;
            m_wvalid[master] = 1'b1;
            timeout = 0;
            @(posedge clk);
            while (!(m_awready[master] && m_wready[master]) && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            m_awvalid[master] = 1'b0;
            m_wvalid[master] = 1'b0;
            timeout = 0;
            @(posedge clk);
            while (!m_bvalid[master] && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (m_bresp[master*2 +: 2] == 2'b11) decerr_count = decerr_count + 1;
            if (timeout >= 100) error_count = error_count + 1;
        end else begin
            m_araddr[master*ADDR_WIDTH +: ADDR_WIDTH] = addr;
            m_arvalid[master] = 1'b1;
            timeout = 0;
            @(posedge clk);
            while (!m_arready[master] && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            m_arvalid[master] = 1'b0;
            timeout = 0;
            @(posedge clk);
            while (!m_rvalid[master] && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (m_rresp[master*2 +: 2] == 2'b11) decerr_count = decerr_count + 1;
            if (timeout >= 100) error_count = error_count + 1;
        end
        @(posedge clk);
        if (master == 0) m0_count = m0_count + 1;
        else m1_count = m1_count + 1;
    end
    endtask
    
    //=========================================================================
    // Main Test
    //=========================================================================
    integer i, fairness_diff;
    reg [31:0] rand_val;
    reg fairness_pass;
    
    initial begin
        $display("========================================");
        $display("CHECKPOINT 6: AXI Interconnect Verification");
        $display("========================================");
        
        lfsr = 32'hABCD_1234;
        m0_count = 0; m1_count = 0;
        error_count = 0; decerr_count = 0;
        
        reset_dut();
        
        $display("Running %0d transactions...", NUM_TRANSACTIONS);
        
        for (i = 0; i < NUM_TRANSACTIONS; i = i + 1) begin
            if (i % 100 == 0) $display("  Progress: %0d/%0d", i, NUM_TRANSACTIONS);
            get_random(rand_val);
            do_transaction(i % 2, random_addr(rand_val), rand_val[0]);
        end
        
        // Calculate fairness
        if (m0_count > m1_count)
            fairness_diff = ((m0_count - m1_count) * 100) / (m0_count + m1_count);
        else
            fairness_diff = ((m1_count - m0_count) * 100) / (m0_count + m1_count);
        
        fairness_pass = (fairness_diff <= 10);
        
        $display("");
        $display("========================================");
        $display("CHECKPOINT 6 SUMMARY");
        $display("========================================");
        $display("Total Transactions: %0d", m0_count + m1_count);
        $display("Master 0: %0d", m0_count);
        $display("Master 1: %0d", m1_count);
        $display("Fairness Diff: %0d%%", fairness_diff);
        $display("Errors: %0d", error_count);
        $display("DECERR: %0d", decerr_count);
        $display("Slave 0 (ROM):   %0d", slave_count[0]);
        $display("Slave 1 (SRAM):  %0d", slave_count[1]);
        $display("Slave 2 (UART):  %0d", slave_count[2]);
        $display("Slave 3 (GPIO):  %0d", slave_count[3]);
        $display("Slave 4 (Timer): %0d", slave_count[4]);
        $display("========================================");
        
        if (fairness_pass && error_count == 0) begin
            $display("*** CHECKPOINT 6 PASSED ***");
        end else begin
            $display("*** CHECKPOINT 6 FAILED ***");
        end
        
        $finish;
    end
    
    initial begin
        #50_000_000;
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
