//=================================================================
// Module: prefetcher
// Description: Hardware Prefetch Unit
//              Implements Stride Prefetcher + Stream Prefetcher
//              Reduces cache miss latency for regular access patterns
//=================================================================

`timescale 1ns/1ps

module prefetcher #(
    parameter ADDR_WIDTH     = 32,
    parameter CACHE_LINE     = 64,         // Cache line size in bytes
    parameter RPT_ENTRIES    = 16,         // Reference Prediction Table entries
    parameter STREAM_ENTRIES = 4,          // Stream buffer entries
    parameter PREFETCH_DEPTH = 4           // How many lines ahead to prefetch
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Memory Access Observation
    //=========================================================
    input  wire                     mem_access_valid_i,
    input  wire [ADDR_WIDTH-1:0]    mem_access_addr_i,
    input  wire [ADDR_WIDTH-1:0]    mem_access_pc_i,    // PC of load instruction
    input  wire                     mem_access_miss_i,  // Was it a cache miss?
    
    //=========================================================
    // Prefetch Request Output
    //=========================================================
    output reg                      pf_req_valid_o,
    output reg  [ADDR_WIDTH-1:0]    pf_req_addr_o,
    input  wire                     pf_req_ready_i,
    
    //=========================================================
    // Control
    //=========================================================
    input  wire                     enable_i,
    input  wire                     flush_i
);

    //=========================================================
    // Derived Parameters
    //=========================================================
    localparam LINE_BITS = $clog2(CACHE_LINE);
    localparam RPT_IDX_BITS = $clog2(RPT_ENTRIES);
    localparam STREAM_IDX_BITS = $clog2(STREAM_ENTRIES);
    
    //=========================================================
    // Reference Prediction Table (Stride Prefetcher)
    //=========================================================
    // Each entry tracks access patterns from a specific PC
    reg                     rpt_valid [0:RPT_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    rpt_tag   [0:RPT_ENTRIES-1];   // PC tag
    reg [ADDR_WIDTH-1:0]    rpt_prev_addr [0:RPT_ENTRIES-1];
    reg signed [15:0]       rpt_stride [0:RPT_ENTRIES-1];
    reg [1:0]               rpt_conf   [0:RPT_ENTRIES-1];   // Confidence
    reg [2:0]               rpt_state  [0:RPT_ENTRIES-1];   // State machine
    
    // RPT states
    localparam RPT_INIT    = 3'd0;
    localparam RPT_TRANSIENT = 3'd1;
    localparam RPT_STEADY  = 3'd2;
    localparam RPT_NO_PRED = 3'd3;
    
    //=========================================================
    // Stream Buffer (Sequential Prefetcher)
    //=========================================================
    reg                     stream_valid [0:STREAM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    stream_start [0:STREAM_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    stream_end   [0:STREAM_ENTRIES-1];
    reg                     stream_dir   [0:STREAM_ENTRIES-1];  // 0=up, 1=down
    reg [3:0]               stream_ahead [0:STREAM_ENTRIES-1];  // Lines prefetched ahead
    
    //=========================================================
    // RPT Lookup
    //=========================================================
    wire [RPT_IDX_BITS-1:0] rpt_idx = mem_access_pc_i[RPT_IDX_BITS+1:2];
    wire rpt_hit = rpt_valid[rpt_idx] && (rpt_tag[rpt_idx] == mem_access_pc_i);
    
    //=========================================================
    // Stream Lookup
    //=========================================================
    wire [ADDR_WIDTH-1:0] line_addr = {mem_access_addr_i[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}};
    
    reg stream_hit;
    reg [STREAM_IDX_BITS-1:0] stream_hit_idx;
    
    integer s;
    always @(*) begin
        stream_hit = 0;
        stream_hit_idx = 0;
        
        for (s = 0; s < STREAM_ENTRIES; s = s + 1) begin
            if (stream_valid[s]) begin
                // Check if access is within stream range or adjacent
                if ((line_addr >= stream_start[s] && line_addr <= stream_end[s]) ||
                    (line_addr == stream_end[s] + CACHE_LINE) ||
                    (line_addr + CACHE_LINE == stream_start[s])) begin
                    stream_hit = 1;
                    stream_hit_idx = s[STREAM_IDX_BITS-1:0];
                end
            end
        end
    end
    
    //=========================================================
    // Stride Calculation
    //=========================================================
    wire signed [ADDR_WIDTH-1:0] new_stride = $signed(mem_access_addr_i) - $signed(rpt_prev_addr[rpt_idx]);
    wire stride_match = (rpt_stride[rpt_idx] == new_stride[15:0]);
    
    //=========================================================
    // Prefetch Decision
    //=========================================================
    reg                     pf_stride_valid;
    reg [ADDR_WIDTH-1:0]    pf_stride_addr;
    reg                     pf_stream_valid;
    reg [ADDR_WIDTH-1:0]    pf_stream_addr;
    
    // Stride prefetch: predict next address
    always @(*) begin
        pf_stride_valid = 0;
        pf_stride_addr = 0;
        
        if (enable_i && rpt_hit && rpt_state[rpt_idx] == RPT_STEADY && rpt_conf[rpt_idx] == 2'b11) begin
            pf_stride_valid = 1;
            pf_stride_addr = mem_access_addr_i + {{(ADDR_WIDTH-16){rpt_stride[rpt_idx][15]}}, rpt_stride[rpt_idx]};
        end
    end
    
    // Stream prefetch: prefetch next line in stream
    always @(*) begin
        pf_stream_valid = 0;
        pf_stream_addr = 0;
        
        if (enable_i && stream_hit && stream_ahead[stream_hit_idx] < PREFETCH_DEPTH) begin
            pf_stream_valid = 1;
            if (stream_dir[stream_hit_idx] == 0) begin  // Ascending
                pf_stream_addr = stream_end[stream_hit_idx] + CACHE_LINE;
            end else begin  // Descending
                pf_stream_addr = stream_start[stream_hit_idx] - CACHE_LINE;
            end
        end
    end
    
    //=========================================================
    // LRU for RPT and Stream Replacement
    //=========================================================
    reg [RPT_IDX_BITS-1:0] rpt_replace_ptr;
    reg [STREAM_IDX_BITS-1:0] stream_replace_ptr;
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    integer i;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pf_req_valid_o <= 0;
            pf_req_addr_o <= 0;
            rpt_replace_ptr <= 0;
            stream_replace_ptr <= 0;
            
            for (i = 0; i < RPT_ENTRIES; i = i + 1) begin
                rpt_valid[i] <= 0;
                rpt_tag[i] <= 0;
                rpt_prev_addr[i] <= 0;
                rpt_stride[i] <= 0;
                rpt_conf[i] <= 0;
                rpt_state[i] <= RPT_INIT;
            end
            
            for (i = 0; i < STREAM_ENTRIES; i = i + 1) begin
                stream_valid[i] <= 0;
                stream_start[i] <= 0;
                stream_end[i] <= 0;
                stream_dir[i] <= 0;
                stream_ahead[i] <= 0;
            end
        end else begin
            if (flush_i) begin
                pf_req_valid_o <= 0;
                
                for (i = 0; i < STREAM_ENTRIES; i = i + 1) begin
                    stream_valid[i] <= 0;
                end
            end else begin
                // Prefetch request arbitration (stride > stream)
                pf_req_valid_o <= 0;
                
                if (pf_req_ready_i) begin
                    if (pf_stride_valid) begin
                        pf_req_valid_o <= 1;
                        pf_req_addr_o <= {pf_stride_addr[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}};
                    end else if (pf_stream_valid) begin
                        pf_req_valid_o <= 1;
                        pf_req_addr_o <= pf_stream_addr;
                        
                        // Update stream ahead count
                        stream_ahead[stream_hit_idx] <= stream_ahead[stream_hit_idx] + 1;
                    end
                end
                
                // Update RPT on memory access
                if (mem_access_valid_i && enable_i) begin
                    if (rpt_hit) begin
                        // Update existing entry
                        rpt_prev_addr[rpt_idx] <= mem_access_addr_i;
                        
                        case (rpt_state[rpt_idx])
                            RPT_INIT: begin
                                rpt_stride[rpt_idx] <= new_stride[15:0];
                                rpt_state[rpt_idx] <= RPT_TRANSIENT;
                            end
                            
                            RPT_TRANSIENT: begin
                                if (stride_match) begin
                                    rpt_conf[rpt_idx] <= 2'b01;
                                    rpt_state[rpt_idx] <= RPT_STEADY;
                                end else begin
                                    rpt_stride[rpt_idx] <= new_stride[15:0];
                                end
                            end
                            
                            RPT_STEADY: begin
                                if (stride_match) begin
                                    if (rpt_conf[rpt_idx] < 2'b11) begin
                                        rpt_conf[rpt_idx] <= rpt_conf[rpt_idx] + 1;
                                    end
                                end else begin
                                    if (rpt_conf[rpt_idx] > 0) begin
                                        rpt_conf[rpt_idx] <= rpt_conf[rpt_idx] - 1;
                                    end else begin
                                        rpt_stride[rpt_idx] <= new_stride[15:0];
                                        rpt_state[rpt_idx] <= RPT_TRANSIENT;
                                    end
                                end
                            end
                        endcase
                    end else begin
                        // Allocate new entry
                        rpt_valid[rpt_idx] <= 1;
                        rpt_tag[rpt_idx] <= mem_access_pc_i;
                        rpt_prev_addr[rpt_idx] <= mem_access_addr_i;
                        rpt_stride[rpt_idx] <= 0;
                        rpt_conf[rpt_idx] <= 0;
                        rpt_state[rpt_idx] <= RPT_INIT;
                    end
                    
                    // Update stream buffers
                    if (stream_hit) begin
                        // Extend existing stream
                        if (line_addr == stream_end[stream_hit_idx] + CACHE_LINE) begin
                            stream_end[stream_hit_idx] <= line_addr;
                            stream_dir[stream_hit_idx] <= 0;  // Ascending
                            if (stream_ahead[stream_hit_idx] > 0) begin
                                stream_ahead[stream_hit_idx] <= stream_ahead[stream_hit_idx] - 1;
                            end
                        end else if (line_addr + CACHE_LINE == stream_start[stream_hit_idx]) begin
                            stream_start[stream_hit_idx] <= line_addr;
                            stream_dir[stream_hit_idx] <= 1;  // Descending
                            if (stream_ahead[stream_hit_idx] > 0) begin
                                stream_ahead[stream_hit_idx] <= stream_ahead[stream_hit_idx] - 1;
                            end
                        end
                    end else if (mem_access_miss_i) begin
                        // Allocate new stream on cache miss
                        stream_valid[stream_replace_ptr] <= 1;
                        stream_start[stream_replace_ptr] <= line_addr;
                        stream_end[stream_replace_ptr] <= line_addr;
                        stream_dir[stream_replace_ptr] <= 0;
                        stream_ahead[stream_replace_ptr] <= 0;
                        stream_replace_ptr <= stream_replace_ptr + 1;
                    end
                end
            end
        end
    end

endmodule
