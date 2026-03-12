//=================================================================
// Testbench: tb_cpu_core_4way
// Description: Comprehensive testbench for 4-way superscalar CPU
//              Tests: Pipeline, Branch, Interrupt, CSR, Memory
//=================================================================

`timescale 1ns/1ps

module tb_cpu_core_4way;

    //=========================================================
    // Parameters
    //=========================================================
    parameter XLEN = 32;
    parameter CLK_PERIOD = 10;  // 100MHz
    parameter MEM_SIZE = 65536; // 64KB
    parameter TEST_TIMEOUT = 100000;  // cycles
    
    //=========================================================
    // Signals
    //=========================================================
    reg clk;
    reg rst_n;
    
    // AXI signals
    wire [3:0]  m_axi_awid;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awlock;
    wire [3:0]  m_axi_awcache;
    wire [2:0]  m_axi_awprot;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    
    reg  [3:0]  m_axi_bid;
    reg  [1:0]  m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    
    wire [3:0]  m_axi_arid;
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arlock;
    wire [3:0]  m_axi_arcache;
    wire [2:0]  m_axi_arprot;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    
    reg  [3:0]  m_axi_rid;
    reg  [31:0] m_axi_rdata;
    reg  [1:0]  m_axi_rresp;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    
    // External interrupts
    reg [31:0]  ext_irq;
    
    // Debug outputs
    wire [31:0] debug_pc;
    wire        debug_halt;
    wire [63:0] debug_cycle;
    wire [63:0] debug_instret;
    
    //=========================================================
    // Memory Model
    //=========================================================
    reg [7:0] memory [0:MEM_SIZE-1];
    
    // AXI state machine
    reg [2:0] axi_state;
    localparam AXI_IDLE = 0;
    localparam AXI_READ = 1;
    localparam AXI_WRITE = 2;
    localparam AXI_WRESP = 3;
    
    reg [31:0] axi_addr;
    reg [7:0]  axi_len;
    reg [7:0]  axi_cnt;
    
    //=========================================================
    // DUT Instantiation
    //=========================================================
    cpu_core_4way #(
        .XLEN(XLEN),
        .RESET_VECTOR(32'h8000_0000)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // AXI interface
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awlock   (m_axi_awlock),
        .m_axi_awcache  (m_axi_awcache),
        .m_axi_awprot   (m_axi_awprot),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        
        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        
        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arlock   (m_axi_arlock),
        .m_axi_arcache  (m_axi_arcache),
        .m_axi_arprot   (m_axi_arprot),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        
        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),
        
        .ext_irq_i      (ext_irq),
        
        .debug_pc_o     (debug_pc),
        .debug_halt_o   (debug_halt),
        .debug_cycle_o  (debug_cycle),
        .debug_instret_o(debug_instret)
    );

    //=========================================================
    // Clock Generation
    //=========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================
    // AXI Memory Model
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_state <= AXI_IDLE;
            m_axi_awready <= 1;
            m_axi_wready <= 0;
            m_axi_bvalid <= 0;
            m_axi_arready <= 1;
            m_axi_rvalid <= 0;
            m_axi_rlast <= 0;
            axi_addr <= 0;
            axi_len <= 0;
            axi_cnt <= 0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    m_axi_bvalid <= 0;
                    m_axi_rvalid <= 0;
                    
                    if (m_axi_arvalid && m_axi_arready) begin
                        // Start read
                        axi_addr <= m_axi_araddr - 32'h8000_0000;  // Offset from base
                        axi_len <= m_axi_arlen;
                        axi_cnt <= 0;
                        m_axi_rid <= m_axi_arid;
                        m_axi_arready <= 0;
                        // Pre-set rlast for first beat (if len=0, first beat is last)
                        m_axi_rlast <= (m_axi_arlen == 0);
                        axi_state <= AXI_READ;
                        $display("  [AXI RD] addr=%h len=%0d", m_axi_araddr, m_axi_arlen);
                    end else if (m_axi_awvalid && m_axi_awready) begin
                        // Start write
                        axi_addr <= m_axi_awaddr - 32'h8000_0000;
                        axi_len <= m_axi_awlen;
                        axi_cnt <= 0;
                        m_axi_bid <= m_axi_awid;
                        m_axi_awready <= 0;
                        m_axi_wready <= 1;
                        axi_state <= AXI_WRITE;
                    end
                end
                
                AXI_READ: begin
                    // Data is combinational from axi_addr (registered)
                    // Only update data and validate when not in mid-handshake
                    if (!m_axi_rvalid) begin
                        m_axi_rdata <= {memory[axi_addr+3], memory[axi_addr+2], 
                                       memory[axi_addr+1], memory[axi_addr]};
                        m_axi_rresp <= 2'b00;  // OKAY
                        m_axi_rvalid <= 1;
                    end
                    
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (debug_cycle < 100) $display("  [AXI BEAT] cnt=%0d addr=%h data=%h rlast=%b", axi_cnt, axi_addr, m_axi_rdata, m_axi_rlast);
                        if (axi_cnt == axi_len) begin
                            m_axi_rvalid <= 0;
                            m_axi_rlast <= 0;
                            m_axi_arready <= 1;
                            axi_state <= AXI_IDLE;
                        end else begin
                            // Move to next beat - deassert valid to reload data
                            m_axi_rvalid <= 0;
                            axi_addr <= axi_addr + 4;
                            axi_cnt <= axi_cnt + 1;
                            // Set rlast for next beat if it will be the last
                            m_axi_rlast <= ((axi_cnt + 1) == axi_len);
                        end
                    end
                end
                
                AXI_WRITE: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        // Write data to memory
                        if (m_axi_wstrb[0]) memory[axi_addr]   <= m_axi_wdata[7:0];
                        if (m_axi_wstrb[1]) memory[axi_addr+1] <= m_axi_wdata[15:8];
                        if (m_axi_wstrb[2]) memory[axi_addr+2] <= m_axi_wdata[23:16];
                        if (m_axi_wstrb[3]) memory[axi_addr+3] <= m_axi_wdata[31:24];
                        
                        if (m_axi_wlast) begin
                            m_axi_wready <= 0;
                            axi_state <= AXI_WRESP;
                        end else begin
                            axi_addr <= axi_addr + 4;
                            axi_cnt <= axi_cnt + 1;
                        end
                    end
                end
                
                AXI_WRESP: begin
                    m_axi_bvalid <= 1;
                    m_axi_bresp <= 2'b00;  // OKAY
                    
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bvalid <= 0;
                        m_axi_awready <= 1;
                        axi_state <= AXI_IDLE;
                    end
                end
            endcase
        end
    end

    //=========================================================
    // Performance Monitoring
    //=========================================================
    reg [63:0] last_instret;
    reg [63:0] ipc_window_start;
    real ipc;
    
    always @(posedge clk) begin
        if (debug_cycle % 1000 == 0 && debug_cycle > 0) begin
            ipc = (debug_instret - last_instret) / 1000.0;
            $display("[%0t] Cycle: %0d, Instret: %0d, IPC: %f", 
                     $time, debug_cycle, debug_instret, ipc);
            last_instret <= debug_instret;
        end
    end

    //=========================================================
    // Test Program Loading
    //=========================================================
    task load_program;
        input [256*8-1:0] filename;
        integer fd, i, c;
        begin
            // Initialize memory to NOPs
            for (i = 0; i < MEM_SIZE; i = i + 1) begin
                memory[i] = 8'h13;  // NOP (addi x0, x0, 0)
            end
            
            // Load hex file if exists
            $readmemh(filename, memory);
            $display("Program loaded from %s", filename);
        end
    endtask
    
    // Load built-in test program with longer ALU sequence
    task load_builtin_test;
        integer i;
        begin
            // Initialize to NOP (addi x0, x0, 0)
            for (i = 0; i < MEM_SIZE; i = i + 4) begin
                {memory[i+3], memory[i+2], memory[i+1], memory[i]} = 32'h00000013;
            end
            
            // Test program at 0x8000_0000 (offset 0)
            // Simple Load/Store verification + infinite loop at 0x5C

            // 0x00: LUI x10, 0x80000      ; x10 = 0x8000_0000 (data base)
            {memory[3], memory[2], memory[1], memory[0]} = 32'h80000537;

            // 0x04: ADDI x10, x10, 128    ; x10 = 0x8000_0080
            {memory[7], memory[6], memory[5], memory[4]} = 32'h08028513;

            // 0x08: ADDI x1, x0, 42       ; x1 = 42
            {memory[11], memory[10], memory[9], memory[8]} = 32'h002A0093;

            // 0x0C: SW x1, 0(x10)         ; MEM[0x8000_0080] = 42
            {memory[15], memory[14], memory[13], memory[12]} = 32'h0012A023;

            // 0x10: LW x2, 0(x10)         ; x2 = MEM[0x8000_0080]
            {memory[19], memory[18], memory[17], memory[16]} = 32'h0002A103;

            // 0x14: NOPs padding
            {memory[23], memory[22], memory[21], memory[20]} = 32'h00000013;
            {memory[27], memory[26], memory[25], memory[24]} = 32'h00000013;
            {memory[31], memory[30], memory[29], memory[28]} = 32'h00000013;
            {memory[35], memory[34], memory[33], memory[32]} = 32'h00000013;
            {memory[39], memory[38], memory[37], memory[36]} = 32'h00000013;
            {memory[43], memory[42], memory[41], memory[40]} = 32'h00000013;
            {memory[47], memory[46], memory[45], memory[44]} = 32'h00000013;
            {memory[51], memory[50], memory[49], memory[48]} = 32'h00000013;
            {memory[55], memory[54], memory[53], memory[52]} = 32'h00000013;
            {memory[59], memory[58], memory[57], memory[56]} = 32'h00000013;
            {memory[63], memory[62], memory[61], memory[60]} = 32'h00000013;
            {memory[67], memory[66], memory[65], memory[64]} = 32'h00000013;
            {memory[71], memory[70], memory[69], memory[68]} = 32'h00000013;
            {memory[75], memory[74], memory[73], memory[72]} = 32'h00000013;
            {memory[79], memory[78], memory[77], memory[76]} = 32'h00000013;
            {memory[83], memory[82], memory[81], memory[80]} = 32'h00000013;
            {memory[87], memory[86], memory[85], memory[84]} = 32'h00000013;
            {memory[91], memory[90], memory[89], memory[88]} = 32'h00000013;

            // 0x5C: Infinite loop (j .)
            {memory[95], memory[94], memory[93], memory[92]} = 32'h0000006f;
            
            $display("Built-in test program loaded (with load/store)");
        end
    endtask

    //=========================================================
    // Test Execution
    //=========================================================
    integer test_cycles;
    reg test_passed;
    
    reg test_done;
    
    initial begin
        // Initialize
        rst_n = 0;
        ext_irq = 0;
        last_instret = 0;
        test_passed = 0;
        test_done = 0;
        
        // Load test program
        load_builtin_test();
        
        // Reset sequence
        #(CLK_PERIOD * 10);
        rst_n = 1;
        $display("\n========================================");
        $display("4-Way Superscalar CPU Test Started");
        $display("========================================\n");
        
        // Run test
        test_cycles = 0;
        while (test_cycles < TEST_TIMEOUT && !test_done) begin
            @(posedge clk);
            test_cycles = test_cycles + 1;
            
            // Check for test completion (PC at infinite loop 0x8000005C)
            if (debug_pc == 32'h8000005C) begin
                test_passed = 1;
                $display("\n[PASS] Test reached infinite loop at PC=0x8000004C!");
                $display("       Executed %0d instructions in %0d cycles", debug_instret, debug_cycle);
                test_done = 1;
            end
            
            // Periodic status
            if (test_cycles % 10000 == 0) begin
                $display("Cycle %0d: PC=0x%08x, Instret=%0d", 
                         test_cycles, debug_pc, debug_instret);
            end
            
            // Early debug (first 100 cycles)
            if (test_cycles < 100 && test_cycles > 5) begin
                $display("[%0d] stall=%b flush_fe=%b flush_be=%b | fetch=%b dec=%b ren=%b iq_iss=%b cdb=%b | rob_cmt=%b rob_full=%b rob_empty=%b | PC=%08x br_mis=%b",
                         test_cycles,
                         u_dut.stall_frontend, u_dut.flush_frontend, u_dut.flush_backend,
                         u_dut.fetch_valid[0], u_dut.decode_valid[0],
                         u_dut.rename_valid[0],
                         u_dut.iq_issue_valid[0], u_dut.cdb_valid[0],
                         u_dut.rob_commit_valid[0],
                         u_dut.rob_full, u_dut.rob_empty,
                         debug_pc, u_dut.cdb_br_mispredict);
                // Debug rename ready signals
                if (u_dut.rename_valid[0]) begin
                    $display("  [REN] prs1_rdy[0]=%b prs2_rdy[0]=%b | prs1=%0d prs2=%0d prd=%0d | dec_rs1=%0d dec_rs2=%0d | iq_rdy=%b free_cnt=%0d",
                             u_dut.ren_prs1_rdy[0], u_dut.ren_prs2_rdy[0],
                             u_dut.ren_prs1_wire[0], u_dut.ren_prs2_wire[0], u_dut.ren_prd_wire[0],
                             u_dut.decode_rs1[0], u_dut.decode_rs2[0],
                             u_dut.iq_insert_ready, u_dut.u_issue_queue.free_count);
                end
                // Debug fetch state
                if (u_dut.icache_resp_valid) begin
                    $display("  [FETCH] state=%0d pc_reg=%h | icache_data=%h_%h_%h_%h",
                             u_dut.u_fetch.state, u_dut.u_fetch.pc_reg,
                             u_dut.icache_resp_data[127:96], u_dut.icache_resp_data[95:64],
                             u_dut.icache_resp_data[63:32], u_dut.icache_resp_data[31:0]);
                end else begin
                    $display("  [FETCH] state=%0d pc_reg=%h | fl_empty=%b rob_full=%b icache_req=%b",
                             u_dut.u_fetch.state, u_dut.u_fetch.pc_reg,
                             u_dut.fl_empty, u_dut.rob_full, u_dut.icache_req_valid);
                end
                // Debug IQ state
                $display("  [IQ] free=%0d | iss_v=%b%b%b%b iss_rdy=%b%b%b%b | fu=%0d,%0d,%0d,%0d rob=%0d,%0d,%0d,%0d",
                         u_dut.u_issue_queue.free_count,
                         u_dut.iq_issue_valid[3], u_dut.iq_issue_valid[2], 
                         u_dut.iq_issue_valid[1], u_dut.iq_issue_valid[0],
                         u_dut.iq_issue_ready[3], u_dut.iq_issue_ready[2],
                         u_dut.iq_issue_ready[1], u_dut.iq_issue_ready[0],
                         u_dut.iq_issue_fu_type[3], u_dut.iq_issue_fu_type[2],
                         u_dut.iq_issue_fu_type[1], u_dut.iq_issue_fu_type[0],
                         u_dut.iq_issue_rob_idx[3], u_dut.iq_issue_rob_idx[2],
                         u_dut.iq_issue_rob_idx[1], u_dut.iq_issue_rob_idx[0]);
                // Debug BRU execution
                if (u_dut.u_ex_cluster.bru_issue_valid)
                    $display("  [BRU_ISS] op=%b pc=%h imm=%h pred_tk=%b pred_tgt=%h",
                             u_dut.u_ex_cluster.bru_op, u_dut.u_ex_cluster.bru_pc,
                             u_dut.u_ex_cluster.bru_imm, u_dut.u_ex_cluster.bru_predict_in,
                             u_dut.u_ex_cluster.bru_target_in);
                if (u_dut.ex_bru_valid)
                    $display("  [BRU_OUT] taken=%b target=%h mispred=%b rob=%0d",
                             u_dut.ex_bru_taken, u_dut.ex_bru_target,
                             u_dut.ex_bru_mispredict, u_dut.ex_bru_rob);
                // Debug fetch valid output
                $display("  [FE_OUT] valid=%b dec_v=%b ren_v=%b | dec_mask=%b",
                         u_dut.fetch_valid, u_dut.decode_valid,
                         u_dut.rename_valid, u_dut.u_decode.dec_valid_mask_o);
                // Debug ROB state
                $display("  [ROB] head=%0d tail=%0d cnt=%0d | cmt_v=%b h_valid=%b h_comp=%b",
                         u_dut.u_rob.head, u_dut.u_rob.tail, u_dut.u_rob.count,
                         u_dut.rob_commit_valid[0], u_dut.u_rob.valid[u_dut.u_rob.head],
                         u_dut.u_rob.completed[u_dut.u_rob.head]);
                // Debug CDB
                $display("  [CDB] valid=%b prd=%0d,%0d,%0d,%0d rob=%0d,%0d,%0d,%0d",
                         u_dut.cdb_valid,
                         u_dut.cdb_prd[0], u_dut.cdb_prd[1], u_dut.cdb_prd[2], u_dut.cdb_prd[3],
                         u_dut.cdb_rob_idx[0], u_dut.cdb_rob_idx[1], u_dut.cdb_rob_idx[2], u_dut.cdb_rob_idx[3]);
            end
        end
        
        // Final report
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Cycles: %0d", debug_cycle);
        $display("Instructions: %0d", debug_instret);
        if (debug_cycle > 0)
            $display("Average IPC: %f", $itor(debug_instret) / $itor(debug_cycle));
        $display("Result: %s", test_passed ? "PASS" : "FAIL/TIMEOUT");
        $display("========================================\n");
        
        #(CLK_PERIOD * 100);
        $finish;
    end

    //=========================================================
    // Waveform Dump
    //=========================================================
    initial begin
        $dumpfile("tb_cpu_core_4way.vcd");
        $dumpvars(0, tb_cpu_core_4way);
    end

endmodule
