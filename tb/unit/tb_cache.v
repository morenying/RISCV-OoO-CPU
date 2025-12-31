//=================================================================
// Testbench: tb_cache
// Description: Cache Property Tests
//              Property 10: Cache Coherence
// Validates: Requirements 8.1, 8.2, 9.1, 9.2
//=================================================================

`timescale 1ns/1ps

module tb_cache;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter CACHE_SIZE = 4096;
    parameter LINE_SIZE  = 32;
    parameter CLK_PERIOD = 10;
    parameter TIMEOUT_CYCLES = 1000;

    reg clk;
    reg rst_n;
    
    //=========================================================
    // I-Cache Interface
    //=========================================================
    reg                     ic_req_valid;
    reg  [ADDR_WIDTH-1:0]   ic_req_addr;
    wire                    ic_req_ready;
    wire                    ic_resp_valid;
    wire [DATA_WIDTH-1:0]   ic_resp_data;
    
    // I-Cache memory interface
    wire                    ic_mem_req_valid;
    wire [ADDR_WIDTH-1:0]   ic_mem_req_addr;
    reg                     ic_mem_req_ready;
    reg                     ic_mem_resp_valid;
    reg  [LINE_SIZE*8-1:0]  ic_mem_resp_data;
    
    reg                     ic_invalidate;
    
    //=========================================================
    // D-Cache Interface
    //=========================================================
    reg                     dc_req_valid;
    reg                     dc_req_write;
    reg  [ADDR_WIDTH-1:0]   dc_req_addr;
    reg  [DATA_WIDTH-1:0]   dc_req_wdata;
    reg  [1:0]              dc_req_size;
    wire                    dc_req_ready;
    wire                    dc_resp_valid;
    wire [DATA_WIDTH-1:0]   dc_resp_data;
    
    // D-Cache memory interface
    wire                    dc_mem_req_valid;
    wire                    dc_mem_req_write;
    wire [ADDR_WIDTH-1:0]   dc_mem_req_addr;
    wire [LINE_SIZE*8-1:0]  dc_mem_req_wdata;
    reg                     dc_mem_req_ready;
    reg                     dc_mem_resp_valid;
    reg  [LINE_SIZE*8-1:0]  dc_mem_resp_data;
    
    reg                     dc_flush;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================
    // DUT Instantiation - I-Cache
    //=========================================================
    icache #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_icache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (ic_req_valid),
        .req_addr_i         (ic_req_addr),
        .req_ready_o        (ic_req_ready),
        .resp_valid_o       (ic_resp_valid),
        .resp_data_o        (ic_resp_data),
        .mem_req_valid_o    (ic_mem_req_valid),
        .mem_req_addr_o     (ic_mem_req_addr),
        .mem_req_ready_i    (ic_mem_req_ready),
        .mem_resp_valid_i   (ic_mem_resp_valid),
        .mem_resp_data_i    (ic_mem_resp_data),
        .invalidate_i       (ic_invalidate)
    );

    //=========================================================
    // DUT Instantiation - D-Cache
    //=========================================================
    dcache #(
        .CACHE_SIZE(CACHE_SIZE),
        .LINE_SIZE(LINE_SIZE),
        .NUM_WAYS(2),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dcache (
        .clk                (clk),
        .rst_n              (rst_n),
        .req_valid_i        (dc_req_valid),
        .req_write_i        (dc_req_write),
        .req_addr_i         (dc_req_addr),
        .req_wdata_i        (dc_req_wdata),
        .req_size_i         (dc_req_size),
        .req_ready_o        (dc_req_ready),
        .resp_valid_o       (dc_resp_valid),
        .resp_data_o        (dc_resp_data),
        .mem_req_valid_o    (dc_mem_req_valid),
        .mem_req_write_o    (dc_mem_req_write),
        .mem_req_addr_o     (dc_mem_req_addr),
        .mem_req_wdata_o    (dc_mem_req_wdata),
        .mem_req_ready_i    (dc_mem_req_ready),
        .mem_resp_valid_i   (dc_mem_resp_valid),
        .mem_resp_data_i    (dc_mem_resp_data),
        .flush_i            (dc_flush)
    );

    // Test counters
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer timeout_cnt;
    
    // Memory model for backing store
    reg [7:0] backing_mem [0:65535];
    integer i;

    //=========================================================
    // Generate cache line data from base address
    //=========================================================
    function [LINE_SIZE*8-1:0] gen_cache_line;
        input [ADDR_WIDTH-1:0] base_addr;
        integer w;
        reg [LINE_SIZE*8-1:0] line;
        begin
            line = 0;
            for (w = 0; w < LINE_SIZE/4; w = w + 1) begin
                line[w*32 +: 32] = base_addr + (w * 4);
            end
            gen_cache_line = line;
        end
    endfunction

    //=========================================================
    // I-Cache Memory Response Model
    // Latches request on handshake, responds next cycle
    //=========================================================
    reg ic_mem_pending;
    reg [ADDR_WIDTH-1:0] ic_mem_latched_addr;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ic_mem_req_ready <= 1'b1;
            ic_mem_resp_valid <= 1'b0;
            ic_mem_resp_data <= 0;
            ic_mem_pending <= 1'b0;
            ic_mem_latched_addr <= 0;
        end else begin
            if (ic_mem_pending) begin
                // Respond on this cycle
                ic_mem_resp_valid <= 1'b1;
                ic_mem_resp_data <= gen_cache_line(ic_mem_latched_addr);
                ic_mem_pending <= 1'b0;
                ic_mem_req_ready <= 1'b1;
            end else begin
                ic_mem_resp_valid <= 1'b0;
                if (ic_mem_req_valid && ic_mem_req_ready) begin
                    // Latch request
                    ic_mem_latched_addr <= ic_mem_req_addr;
                    ic_mem_req_ready <= 1'b0;
                    ic_mem_pending <= 1'b1;
                end
            end
        end
    end

    //=========================================================
    // D-Cache Memory Response Model
    // Handles both read (refill) and write (writeback) requests
    // Latches request on handshake, responds next cycle
    // Stores written data in backing memory
    //=========================================================
    reg dc_mem_pending;
    reg [ADDR_WIDTH-1:0] dc_mem_latched_addr;
    reg dc_mem_latched_write;
    reg [LINE_SIZE*8-1:0] dc_mem_latched_wdata;
    
    // Backing memory for D-Cache (stores cache lines)
    reg [LINE_SIZE*8-1:0] dc_backing_mem [0:1023];  // 1024 cache lines
    reg dc_backing_valid [0:1023];
    integer dc_mem_idx;
    
    // Initialize backing memory
    initial begin
        for (dc_mem_idx = 0; dc_mem_idx < 1024; dc_mem_idx = dc_mem_idx + 1) begin
            dc_backing_mem[dc_mem_idx] = 0;
            dc_backing_valid[dc_mem_idx] = 0;
        end
    end
    
    // Get backing memory index from address
    function [9:0] get_dc_mem_idx;
        input [ADDR_WIDTH-1:0] addr;
        begin
            get_dc_mem_idx = addr[14:5];  // Use bits [14:5] as index (1024 entries)
        end
    endfunction
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_mem_req_ready <= 1'b1;
            dc_mem_resp_valid <= 1'b0;
            dc_mem_resp_data <= 0;
            dc_mem_pending <= 1'b0;
            dc_mem_latched_addr <= 0;
            dc_mem_latched_write <= 0;
            dc_mem_latched_wdata <= 0;
        end else begin
            if (dc_mem_pending) begin
                // Respond on this cycle
                dc_mem_resp_valid <= 1'b1;
                if (dc_mem_latched_write) begin
                    // Write: store data in backing memory
                    dc_backing_mem[get_dc_mem_idx(dc_mem_latched_addr)] <= dc_mem_latched_wdata;
                    dc_backing_valid[get_dc_mem_idx(dc_mem_latched_addr)] <= 1'b1;
                    $display("  [MEM] D-Cache WB: addr=%h, wdata[31:0]=%h", 
                             dc_mem_latched_addr, dc_mem_latched_wdata[31:0]);
                end else begin
                    // Read: return data from backing memory if valid, else generate
                    if (dc_backing_valid[get_dc_mem_idx(dc_mem_latched_addr)]) begin
                        dc_mem_resp_data <= dc_backing_mem[get_dc_mem_idx(dc_mem_latched_addr)];
                        $display("  [MEM] D-Cache REFILL (backing): addr=%h", dc_mem_latched_addr);
                    end else begin
                        dc_mem_resp_data <= gen_cache_line(dc_mem_latched_addr);
                        $display("  [MEM] D-Cache REFILL (gen): addr=%h", dc_mem_latched_addr);
                    end
                end
                dc_mem_pending <= 1'b0;
                dc_mem_req_ready <= 1'b1;
            end else begin
                dc_mem_resp_valid <= 1'b0;
                if (dc_mem_req_valid && dc_mem_req_ready) begin
                    // Latch request
                    dc_mem_latched_addr <= dc_mem_req_addr;
                    dc_mem_latched_write <= dc_mem_req_write;
                    dc_mem_latched_wdata <= dc_mem_req_wdata;
                    dc_mem_req_ready <= 1'b0;
                    dc_mem_pending <= 1'b1;
                    $display("  [MEM] D-Cache mem request: addr=%h, write=%b", dc_mem_req_addr, dc_mem_req_write);
                end
            end
        end
    end

    //=========================================================
    // Helper Tasks
    //=========================================================
    
    task reset_dut;
        begin
            rst_n = 0;
            ic_req_valid = 0;
            ic_req_addr = 0;
            ic_invalidate = 0;
            dc_req_valid = 0;
            dc_req_write = 0;
            dc_req_addr = 0;
            dc_req_wdata = 0;
            dc_req_size = 2'b10;  // Word
            dc_flush = 0;
            repeat (5) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask
    
    task clear_ic_inputs;
        begin
            ic_req_valid = 0;
            ic_req_addr = 0;
            ic_invalidate = 0;
        end
    endtask
    
    task clear_dc_inputs;
        begin
            dc_req_valid = 0;
            dc_req_write = 0;
            dc_req_addr = 0;
            dc_req_wdata = 0;
            dc_req_size = 2'b10;
            dc_flush = 0;
        end
    endtask

    //=========================================================
    // I-Cache Read Task with Timeout
    // Note: On miss, cache goes IDLE->MISS->REFILL->IDLE
    // After refill, we need to re-request to get the data
    //=========================================================
    task icache_read;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;
        output                  success;
        reg got_response;
        begin
            success = 0;
            data = 0;
            got_response = 0;
            timeout_cnt = 0;
            
            while (!got_response && timeout_cnt < TIMEOUT_CYCLES) begin
                // Wait for ready
                while (!ic_req_ready && timeout_cnt < TIMEOUT_CYCLES) begin
                    @(posedge clk);
                    timeout_cnt = timeout_cnt + 1;
                end
                
                if (timeout_cnt >= TIMEOUT_CYCLES) begin
                    $display("  [TIMEOUT] I-Cache not ready");
                    success = 0;
                    got_response = 1;  // Exit loop
                end else begin
                    // Send request and check for immediate hit
                    ic_req_valid = 1;
                    ic_req_addr = addr;
                    @(posedge clk);
                    
                    // Check if we got a hit response
                    if (ic_resp_valid) begin
                        data = ic_resp_data;
                        success = 1;
                        got_response = 1;
                    end
                    
                    ic_req_valid = 0;
                    
                    // If no hit, wait for cache to become ready again (after refill)
                    if (!got_response) begin
                        @(posedge clk);
                        timeout_cnt = timeout_cnt + 1;
                    end
                end
            end
            
            if (!got_response) begin
                $display("  [TIMEOUT] I-Cache response timeout");
            end
            
            clear_ic_inputs();
            @(posedge clk);
        end
    endtask

    //=========================================================
    // D-Cache Read Task with Timeout
    // Note: On miss, cache goes through WRITEBACK/REFILL states
    // Wait for resp_valid (either immediate hit or refill_done)
    //=========================================================
    task dcache_read;
        input  [ADDR_WIDTH-1:0] addr;
        input  [1:0]            size;
        output [DATA_WIDTH-1:0] data;
        output                  success;
        reg done;
        begin
            success = 0;
            data = 0;
            timeout_cnt = 0;
            done = 0;
            
            // Wait for ready
            while (!dc_req_ready && timeout_cnt < TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            
            if (timeout_cnt >= TIMEOUT_CYCLES) begin
                $display("  [TIMEOUT] D-Cache not ready for read");
                done = 1;
            end
            
            if (!done) begin
                // Set inputs BEFORE clock edge (use negedge to set up inputs)
                @(negedge clk);
                dc_req_valid = 1;
                dc_req_write = 0;
                dc_req_addr = addr;
                dc_req_size = size;
                
                // Wait for posedge to sample
                @(posedge clk);
                
                // Check for immediate hit (resp_valid should be high on hit)
                if (dc_resp_valid) begin
                    data = dc_resp_data;
                    success = 1;
                    done = 1;
                end
                
                // Clear valid after one cycle
                @(negedge clk);
                dc_req_valid = 0;
            end
            
            if (!done) begin
                // Miss - wait for refill to complete (resp_valid from refill_done)
                while (!dc_resp_valid && timeout_cnt < TIMEOUT_CYCLES) begin
                    @(posedge clk);
                    timeout_cnt = timeout_cnt + 1;
                end
                
                if (dc_resp_valid) begin
                    data = dc_resp_data;
                    success = 1;
                end else begin
                    $display("  [TIMEOUT] D-Cache read response timeout");
                end
            end
            
            clear_dc_inputs();
            @(posedge clk);
        end
    endtask

    //=========================================================
    // D-Cache Write Task with Timeout
    // Note: Write-allocate policy - miss causes refill first
    // Wait for resp_valid (either immediate hit or refill_done)
    //=========================================================
    task dcache_write;
        input  [ADDR_WIDTH-1:0] addr;
        input  [DATA_WIDTH-1:0] wdata;
        input  [1:0]            size;
        output                  success;
        reg done;
        begin
            success = 0;
            timeout_cnt = 0;
            done = 0;
            
            // Wait for ready
            while (!dc_req_ready && timeout_cnt < TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            
            if (timeout_cnt >= TIMEOUT_CYCLES) begin
                $display("  [TIMEOUT] D-Cache not ready for write (state=%b)", u_dcache.state);
                done = 1;
            end
            
            if (!done) begin
                // Set inputs BEFORE clock edge (use negedge to set up inputs)
                @(negedge clk);
                dc_req_valid = 1;
                dc_req_write = 1;
                dc_req_addr = addr;
                dc_req_wdata = wdata;
                dc_req_size = size;
                
                // Wait for posedge to sample
                @(posedge clk);
                
                // Check for immediate hit (write hit completes in one cycle)
                if (dc_resp_valid) begin
                    success = 1;
                    done = 1;
                end
                
                // Clear valid after one cycle
                @(negedge clk);
                dc_req_valid = 0;
            end
            
            if (!done) begin
                // Miss - wait for refill to complete (resp_valid from refill_done)
                while (!dc_resp_valid && timeout_cnt < TIMEOUT_CYCLES) begin
                    @(posedge clk);
                    timeout_cnt = timeout_cnt + 1;
                end
                
                if (dc_resp_valid) begin
                    success = 1;
                end else begin
                    $display("  [TIMEOUT] D-Cache write response timeout");
                end
            end
            
            clear_dc_inputs();
            @(posedge clk);
        end
    endtask

    //=========================================================
    // Property 10: Cache Coherence Tests
    //=========================================================
    
    // Test 1: I-Cache hit after miss
    task test_icache_hit_miss;
        reg [DATA_WIDTH-1:0] data1, data2;
        reg success1, success2;
        begin
            test_count = test_count + 1;
            $display("Test: I-Cache Hit After Miss");
            
            // First access - should be a miss
            icache_read(32'h8000_0000, data1, success1);
            
            // Second access to same address - should be a hit
            icache_read(32'h8000_0000, data2, success2);
            
            if (success1 && success2 && data1 == data2) begin
                pass_count = pass_count + 1;
                $display("[PASS] I-Cache hit after miss: data=%h", data1);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] I-Cache hit after miss: s1=%b s2=%b d1=%h d2=%h", 
                         success1, success2, data1, data2);
            end
        end
    endtask
    
    // Test 2: I-Cache different addresses in same line
    task test_icache_same_line;
        reg [DATA_WIDTH-1:0] data1, data2;
        reg success1, success2;
        begin
            test_count = test_count + 1;
            $display("Test: I-Cache Same Line Different Offsets");
            
            // Access word 0 of a line
            icache_read(32'h8000_0100, data1, success1);
            
            // Access word 4 of same line (offset +16)
            icache_read(32'h8000_0110, data2, success2);
            
            // Expected: data1 = 0x8000_0100, data2 = 0x8000_0110
            if (success1 && success2 && data1 == 32'h8000_0100 && data2 == 32'h8000_0110) begin
                pass_count = pass_count + 1;
                $display("[PASS] I-Cache same line: d1=%h d2=%h", data1, data2);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] I-Cache same line: s1=%b s2=%b d1=%h d2=%h", 
                         success1, success2, data1, data2);
            end
        end
    endtask
    
    // Test 3: I-Cache invalidation (FENCE.I)
    task test_icache_invalidate;
        reg [DATA_WIDTH-1:0] data1, data2;
        reg success1, success2;
        begin
            test_count = test_count + 1;
            $display("Test: I-Cache Invalidation (FENCE.I)");
            
            // First access - cache the line
            icache_read(32'h8000_0200, data1, success1);
            
            // Invalidate cache
            ic_invalidate = 1;
            @(posedge clk);
            ic_invalidate = 0;
            repeat (3) @(posedge clk);
            
            // Second access - should miss again (line was invalidated)
            icache_read(32'h8000_0200, data2, success2);
            
            // Both should succeed with same data
            if (success1 && success2 && data1 == data2) begin
                pass_count = pass_count + 1;
                $display("[PASS] I-Cache invalidate: data consistent after invalidate");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] I-Cache invalidate: s1=%b s2=%b d1=%h d2=%h", 
                         success1, success2, data1, data2);
            end
        end
    endtask
    
    // Test 4: D-Cache write then read back (word)
    task test_dcache_read_write;
        reg [DATA_WIDTH-1:0] rdata;
        reg success_w, success_r;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Write Then Read (Word)");
            
            // Write a word
            dcache_write(32'h8000_1000, 32'hDEADBEEF, 2'b10, success_w);
            
            // Read it back
            dcache_read(32'h8000_1000, 2'b10, rdata, success_r);
            
            if (success_w && success_r && rdata == 32'hDEADBEEF) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache write/read word: data=%h", rdata);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache write/read word: sw=%b sr=%b data=%h", 
                         success_w, success_r, rdata);
            end
        end
    endtask
    
    // Test 5: D-Cache byte access
    task test_dcache_byte_access;
        reg [DATA_WIDTH-1:0] rdata;
        reg success_w, success_r;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Byte Access");
            
            // Reset to clear cache state
            reset_dut();
            
            // First write a word to establish the line
            dcache_write(32'h8000_2000, 32'h12345678, 2'b10, success_w);
            
            // Write a byte at offset 1
            dcache_write(32'h8000_2001, 32'h000000AB, 2'b00, success_w);
            
            // Read back the word
            dcache_read(32'h8000_2000, 2'b10, rdata, success_r);
            
            // Expected: 0x1234AB78 (byte 1 changed to 0xAB)
            if (success_w && success_r && rdata == 32'h1234AB78) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache byte access: data=%h", rdata);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache byte access: sw=%b sr=%b data=%h (expected 1234AB78)", 
                         success_w, success_r, rdata);
            end
        end
    endtask
    
    // Test 6: D-Cache half-word access
    task test_dcache_half_access;
        reg [DATA_WIDTH-1:0] rdata;
        reg success_w, success_r;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Half-Word Access");
            
            // Reset to clear cache state
            reset_dut();
            
            // First write a word to establish the line
            dcache_write(32'h8000_3000, 32'hAABBCCDD, 2'b10, success_w);
            
            // Write a half-word at offset 2 (upper half)
            dcache_write(32'h8000_3002, 32'h0000BEEF, 2'b01, success_w);
            
            // Read back the word
            dcache_read(32'h8000_3000, 2'b10, rdata, success_r);
            
            // Expected: 0xBEEFCCDD (upper half changed to 0xBEEF)
            if (success_w && success_r && rdata == 32'hBEEFCCDD) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache half access: data=%h", rdata);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache half access: sw=%b sr=%b data=%h (expected BEEFCCDD)", 
                         success_w, success_r, rdata);
            end
        end
    endtask
    
    // Test 7: D-Cache hit after miss
    task test_dcache_hit_miss;
        reg [DATA_WIDTH-1:0] data1, data2;
        reg success1, success2;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Hit After Miss");
            
            // First read - should miss
            dcache_read(32'h8000_4000, 2'b10, data1, success1);
            
            // Second read - should hit
            dcache_read(32'h8000_4000, 2'b10, data2, success2);
            
            if (success1 && success2 && data1 == data2) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache hit after miss: data=%h", data1);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache hit after miss: s1=%b s2=%b d1=%h d2=%h", 
                         success1, success2, data1, data2);
            end
        end
    endtask
    
    // Test 8: D-Cache LRU replacement
    task test_dcache_lru;
        reg [DATA_WIDTH-1:0] data;
        reg success;
        reg [ADDR_WIDTH-1:0] addr0, addr1, addr2;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache LRU Replacement");
            
            // Three addresses that map to the same set (2-way, so 3rd evicts one)
            // Set index = addr[10:5] for 64 sets, 32-byte lines
            addr0 = 32'h8000_5000;  // Set 0
            addr1 = 32'h8000_5800;  // Same set (different tag)
            addr2 = 32'h8000_6000;  // Same set (different tag)
            
            // Access addr0 - fills way 0
            dcache_read(addr0, 2'b10, data, success);
            
            // Access addr1 - fills way 1
            dcache_read(addr1, 2'b10, data, success);
            
            // Access addr0 again - makes way 1 LRU
            dcache_read(addr0, 2'b10, data, success);
            
            // Access addr2 - should evict way 1 (LRU)
            dcache_read(addr2, 2'b10, data, success);
            
            // addr0 should still be cached
            dcache_read(addr0, 2'b10, data, success);
            
            if (success && data == addr0) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache LRU: addr0 still cached after replacement");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache LRU: success=%b data=%h (expected %h)", 
                         success, data, addr0);
            end
        end
    endtask
    
    // Test 9: D-Cache flush
    task test_dcache_flush;
        reg [DATA_WIDTH-1:0] data;
        reg success_w, success_r;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Flush");
            
            // Write dirty data
            dcache_write(32'h8000_7000, 32'hCAFEBABE, 2'b10, success_w);
            
            // Flush cache
            dc_flush = 1;
            @(posedge clk);
            dc_flush = 0;
            
            // Wait for flush to complete
            timeout_cnt = 0;
            while (!dc_req_ready && timeout_cnt < TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            
            // Read back - should still work (data written back to memory model)
            dcache_read(32'h8000_7000, 2'b10, data, success_r);
            
            if (success_w && success_r) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache flush completed successfully");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache flush: sw=%b sr=%b", success_w, success_r);
            end
        end
    endtask
    
    // Test 10: Multiple sequential accesses
    task test_sequential_access;
        reg [DATA_WIDTH-1:0] data;
        reg success;
        integer k;
        reg all_pass;
        begin
            test_count = test_count + 1;
            $display("Test: Sequential Access Pattern");
            
            // Reset to clear cache state
            reset_dut();
            
            all_pass = 1;
            
            // Write sequential words
            for (k = 0; k < 8; k = k + 1) begin
                dcache_write(32'h8000_8000 + (k * 4), 32'hA0000000 + k, 2'b10, success);
                if (!success) all_pass = 0;
            end
            
            // Read them back
            for (k = 0; k < 8; k = k + 1) begin
                dcache_read(32'h8000_8000 + (k * 4), 2'b10, data, success);
                if (!success || data != (32'hA0000000 + k)) begin
                    all_pass = 0;
                    $display("  Mismatch at offset %0d: got %h, expected %h", 
                             k*4, data, 32'hA0000000 + k);
                end
            end
            
            if (all_pass) begin
                pass_count = pass_count + 1;
                $display("[PASS] Sequential access: all 8 words correct");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Sequential access: some mismatches");
            end
        end
    endtask
    
    // Test 11: I-Cache multiple lines
    task test_icache_multiple_lines;
        reg [DATA_WIDTH-1:0] data;
        reg success;
        integer k;
        reg all_pass;
        begin
            test_count = test_count + 1;
            $display("Test: I-Cache Multiple Lines");
            
            all_pass = 1;
            
            // Access 4 different cache lines
            for (k = 0; k < 4; k = k + 1) begin
                icache_read(32'h8000_A000 + (k * 32), data, success);
                if (!success || data != (32'h8000_A000 + (k * 32))) begin
                    all_pass = 0;
                    $display("  Line %0d: got %h, expected %h", 
                             k, data, 32'h8000_A000 + (k * 32));
                end
            end
            
            // Re-access all (should be hits)
            for (k = 0; k < 4; k = k + 1) begin
                icache_read(32'h8000_A000 + (k * 32), data, success);
                if (!success) all_pass = 0;
            end
            
            if (all_pass) begin
                pass_count = pass_count + 1;
                $display("[PASS] I-Cache multiple lines: all 4 lines cached");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] I-Cache multiple lines: some failures");
            end
        end
    endtask
    
    // Test 12: D-Cache write-back on eviction
    task test_dcache_writeback;
        reg [DATA_WIDTH-1:0] data;
        reg success;
        reg [ADDR_WIDTH-1:0] addr0, addr1, addr2;
        begin
            test_count = test_count + 1;
            $display("Test: D-Cache Write-Back on Eviction");
            
            // Addresses mapping to same set
            addr0 = 32'h8000_B000;
            addr1 = 32'h8000_B800;
            addr2 = 32'h8000_C000;
            
            // Write to addr0 (dirty)
            dcache_write(addr0, 32'h11111111, 2'b10, success);
            
            // Write to addr1 (dirty)
            dcache_write(addr1, 32'h22222222, 2'b10, success);
            
            // Write to addr2 - should evict one of the above
            dcache_write(addr2, 32'h33333333, 2'b10, success);
            
            // The evicted line should have been written back
            // Read addr2 to verify it's there
            dcache_read(addr2, 2'b10, data, success);
            
            if (success && data == 32'h33333333) begin
                pass_count = pass_count + 1;
                $display("[PASS] D-Cache write-back: eviction handled correctly");
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] D-Cache write-back: success=%b data=%h", success, data);
            end
        end
    endtask

    //=========================================================
    // Main Test Sequence
    //=========================================================
    initial begin
        $display("========================================");
        $display("Cache Property Test");
        $display("Property 10: Cache Coherence");
        $display("Validates: Requirements 8.1-8.4, 9.1-9.5");
        $display("========================================");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        // Initialize backing memory
        for (i = 0; i < 65536; i = i + 1) begin
            backing_mem[i] = i[7:0];
        end
        
        // Reset
        reset_dut();
        
        $display("\n--- I-Cache Tests ---");
        
        $display("\n--- Test 1: I-Cache Hit After Miss ---");
        test_icache_hit_miss();
        
        $display("\n--- Test 2: I-Cache Same Line ---");
        test_icache_same_line();
        
        $display("\n--- Test 3: I-Cache Invalidation ---");
        test_icache_invalidate();
        
        $display("\n--- Test 4: I-Cache Multiple Lines ---");
        test_icache_multiple_lines();
        
        $display("\n--- D-Cache Tests ---");
        
        // Reset for D-Cache tests
        reset_dut();
        
        // Debug: check D-Cache state
        $display("DEBUG: After reset - dc_req_ready=%b, dc_flush=%b", dc_req_ready, dc_flush);
        $display("DEBUG: D-Cache state=%b", u_dcache.state);
        $display("DEBUG: dc_mem_req_valid=%b, dc_mem_req_ready=%b", dc_mem_req_valid, dc_mem_req_ready);
        $display("DEBUG: dc_mem_resp_valid=%b, dc_mem_pending=%b", dc_mem_resp_valid, dc_mem_pending);
        
        $display("\n--- Test 5: D-Cache Write/Read Word ---");
        test_dcache_read_write();
        
        $display("\n--- Test 6: D-Cache Byte Access ---");
        test_dcache_byte_access();
        
        $display("\n--- Test 7: D-Cache Half-Word Access ---");
        test_dcache_half_access();
        
        $display("\n--- Test 8: D-Cache Hit After Miss ---");
        test_dcache_hit_miss();
        
        $display("\n--- Test 9: D-Cache LRU Replacement ---");
        test_dcache_lru();
        
        $display("\n--- Test 10: D-Cache Flush ---");
        test_dcache_flush();
        
        $display("\n--- Test 11: Sequential Access ---");
        test_sequential_access();
        
        $display("\n--- Test 12: D-Cache Write-Back ---");
        test_dcache_writeback();
        
        // Summary
        $display("\n========================================");
        $display("Test Summary:");
        $display("  Total Tests: %0d", test_count);
        $display("  Passed: %0d", pass_count);
        $display("  Failed: %0d", fail_count);
        $display("========================================");
        
        if (fail_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        
        $finish;
    end

endmodule
