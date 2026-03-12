//=================================================================
// Module: icache_enhanced
// Description: Enhanced Instruction Cache
//              16KB, 4-way set associative
//              64-byte cache lines
//              Supports prefetch interface
//              Non-blocking with MSHR support
//=================================================================

`timescale 1ns/1ps

module icache_enhanced #(
    parameter CACHE_SIZE     = 16384,      // 16KB
    parameter LINE_SIZE      = 64,         // 64 bytes per line
    parameter WAYS           = 4,          // 4-way set associative
    parameter ADDR_WIDTH     = 32,
    parameter DATA_WIDTH     = 32,
    parameter FETCH_WIDTH    = 128,        // Fetch 4 instructions at once
    parameter MSHR_ENTRIES   = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // CPU Interface
    //=========================================================
    input  wire                     req_valid_i,
    input  wire [ADDR_WIDTH-1:0]    req_addr_i,
    output wire                     req_ready_o,
    
    output reg                      resp_valid_o,
    output reg  [FETCH_WIDTH-1:0]   resp_data_o,
    output reg                      resp_error_o,
    
    //=========================================================
    // Prefetch Interface
    //=========================================================
    input  wire                     pf_req_valid_i,
    input  wire [ADDR_WIDTH-1:0]    pf_req_addr_i,
    output wire                     pf_req_ready_o,
    
    //=========================================================
    // Memory Interface
    //=========================================================
    output reg                      mem_req_valid_o,
    output reg  [ADDR_WIDTH-1:0]    mem_req_addr_o,
    input  wire                     mem_req_ready_i,
    
    input  wire                     mem_resp_valid_i,
    input  wire [511:0]             mem_resp_data_i,  // Full cache line
    
    //=========================================================
    // Invalidation Interface
    //=========================================================
    input  wire                     inv_valid_i,
    input  wire [ADDR_WIDTH-1:0]    inv_addr_i,
    input  wire                     inv_all_i         // Invalidate entire cache
);

    //=========================================================
    // Derived Parameters
    //=========================================================
    localparam SETS = CACHE_SIZE / (LINE_SIZE * WAYS);  // 64 sets
    localparam SET_BITS = $clog2(SETS);                  // 6 bits
    localparam LINE_BITS = $clog2(LINE_SIZE);            // 6 bits
    localparam TAG_BITS = ADDR_WIDTH - SET_BITS - LINE_BITS;  // 20 bits
    localparam WAY_BITS = $clog2(WAYS);                  // 2 bits
    
    //=========================================================
    // Cache Storage
    //=========================================================
    // Tag array: valid + tag
    reg [TAG_BITS-1:0]  tag_array  [0:SETS-1][0:WAYS-1];
    reg                 valid_array[0:SETS-1][0:WAYS-1];
    
    // Data array: 512 bits (64 bytes) per line
    reg [511:0]         data_array [0:SETS-1][0:WAYS-1];
    
    // LRU (Tree-based PLRU for 4-way)
    reg [2:0]           plru_bits  [0:SETS-1];
    
    //=========================================================
    // Address Decomposition
    //=========================================================
    wire [TAG_BITS-1:0]   req_tag   = req_addr_i[ADDR_WIDTH-1:SET_BITS+LINE_BITS];
    wire [SET_BITS-1:0]   req_set   = req_addr_i[SET_BITS+LINE_BITS-1:LINE_BITS];
    wire [LINE_BITS-1:0]  req_offset= req_addr_i[LINE_BITS-1:0];
    
    wire [TAG_BITS-1:0]   pf_tag    = pf_req_addr_i[ADDR_WIDTH-1:SET_BITS+LINE_BITS];
    wire [SET_BITS-1:0]   pf_set    = pf_req_addr_i[SET_BITS+LINE_BITS-1:LINE_BITS];
    
    // Saved address decomposition for refill
    wire [TAG_BITS-1:0]   saved_tag = saved_addr[ADDR_WIDTH-1:SET_BITS+LINE_BITS];
    wire [SET_BITS-1:0]   saved_set = saved_addr[SET_BITS+LINE_BITS-1:LINE_BITS];
    
    //=========================================================
    // Hit Detection
    //=========================================================
    wire [WAYS-1:0] way_hit;
    wire [TAG_BITS-1:0] tag_read [0:WAYS-1];
    wire valid_read [0:WAYS-1];
    wire [511:0] data_read [0:WAYS-1];
    
    genvar w;
    generate
        for (w = 0; w < WAYS; w = w + 1) begin : gen_way_hit
            assign tag_read[w] = tag_array[req_set][w];
            assign valid_read[w] = valid_array[req_set][w];
            assign data_read[w] = data_array[req_set][w];
            assign way_hit[w] = valid_read[w] && (tag_read[w] == req_tag);
        end
    endgenerate
    
    wire cache_hit = |way_hit;
    
    // Find hitting way
    reg [WAY_BITS-1:0] hit_way;
    always @(*) begin
        hit_way = 0;
        if (way_hit[0]) hit_way = 2'd0;
        else if (way_hit[1]) hit_way = 2'd1;
        else if (way_hit[2]) hit_way = 2'd2;
        else if (way_hit[3]) hit_way = 2'd3;
    end
    
    //=========================================================
    // PLRU Replacement (uses saved_set for refill)
    //=========================================================
    reg [WAY_BITS-1:0] replace_way;
    
    always @(*) begin
        // Tree-based PLRU for 4-way
        // plru_bits[0] = root (0=left subtree, 1=right subtree)
        // plru_bits[1] = left subtree (0=way0, 1=way1)
        // plru_bits[2] = right subtree (0=way2, 1=way3)
        if (plru_bits[saved_set][0] == 0) begin
            replace_way = plru_bits[saved_set][1] ? 2'd0 : 2'd1;
        end else begin
            replace_way = plru_bits[saved_set][2] ? 2'd2 : 2'd3;
        end
    end
    
    //=========================================================
    // Data Selection and Output Alignment
    //=========================================================
    wire [511:0] hit_data = data_read[hit_way];
    
    // Select 128-bit fetch from cache line based on offset
    wire [3:0] fetch_sel = req_offset[5:4];  // Which 128-bit chunk
    
    reg [FETCH_WIDTH-1:0] selected_data;
    always @(*) begin
        case (fetch_sel)
            4'd0: selected_data = hit_data[127:0];
            4'd1: selected_data = hit_data[255:128];
            4'd2: selected_data = hit_data[383:256];
            4'd3: selected_data = hit_data[511:384];
            default: selected_data = hit_data[127:0];
        endcase
    end
    
    //=========================================================
    // MSHR (Miss Status Holding Registers)
    //=========================================================
    reg                     mshr_valid [0:MSHR_ENTRIES-1];
    reg [ADDR_WIDTH-1:0]    mshr_addr  [0:MSHR_ENTRIES-1];
    reg                     mshr_is_pf [0:MSHR_ENTRIES-1];  // Is prefetch?
    
    // Find free MSHR entry
    reg mshr_full;
    reg [1:0] mshr_free_idx;
    
    integer m;
    always @(*) begin
        mshr_full = 1;
        mshr_free_idx = 0;
        
        for (m = MSHR_ENTRIES-1; m >= 0; m = m - 1) begin
            if (!mshr_valid[m]) begin
                mshr_full = 0;
                mshr_free_idx = m[1:0];
            end
        end
    end
    
    // Check if address is already in MSHR
    wire mshr_hit;
    reg [1:0] mshr_hit_idx;
    
    always @(*) begin
        mshr_hit_idx = 0;
        for (m = 0; m < MSHR_ENTRIES; m = m + 1) begin
            if (mshr_valid[m] && 
                (mshr_addr[m][ADDR_WIDTH-1:LINE_BITS] == req_addr_i[ADDR_WIDTH-1:LINE_BITS])) begin
                mshr_hit_idx = m[1:0];
            end
        end
    end
    
    assign mshr_hit = mshr_valid[0] && (mshr_addr[0][ADDR_WIDTH-1:LINE_BITS] == req_addr_i[ADDR_WIDTH-1:LINE_BITS]) ||
                      mshr_valid[1] && (mshr_addr[1][ADDR_WIDTH-1:LINE_BITS] == req_addr_i[ADDR_WIDTH-1:LINE_BITS]) ||
                      mshr_valid[2] && (mshr_addr[2][ADDR_WIDTH-1:LINE_BITS] == req_addr_i[ADDR_WIDTH-1:LINE_BITS]) ||
                      mshr_valid[3] && (mshr_addr[3][ADDR_WIDTH-1:LINE_BITS] == req_addr_i[ADDR_WIDTH-1:LINE_BITS]);
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_LOOKUP     = 3'd1;
    localparam STATE_MISS       = 3'd2;
    localparam STATE_WAIT       = 3'd3;
    localparam STATE_REFILL     = 3'd4;
    localparam STATE_PREFETCH   = 3'd5;
    
    reg [2:0] state;
    reg [2:0] next_state;
    
    // Saved request
    reg [ADDR_WIDTH-1:0] saved_addr;
    reg                  saved_is_pf;
    
    //=========================================================
    // Ready/Valid Logic
    //=========================================================
    assign req_ready_o = (state == STATE_IDLE) || (state == STATE_LOOKUP && cache_hit);
    assign pf_req_ready_o = (state == STATE_IDLE) && !req_valid_i && !mshr_full;
    
    //=========================================================
    // State Transition
    //=========================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (req_valid_i) begin
                    next_state = STATE_LOOKUP;
                end else if (pf_req_valid_i && !mshr_full) begin
                    next_state = STATE_PREFETCH;
                end
            end
            
            STATE_LOOKUP: begin
                if (cache_hit) begin
                    next_state = STATE_IDLE;
                end else if (!mshr_full) begin
                    next_state = STATE_MISS;
                end
                // If MSHR full and miss, stay in LOOKUP (stall)
            end
            
            STATE_MISS: begin
                if (mem_req_ready_i) begin
                    next_state = STATE_WAIT;
                end
            end
            
            STATE_WAIT: begin
                if (mem_resp_valid_i) begin
                    next_state = STATE_REFILL;
                end
            end
            
            STATE_REFILL: begin
                next_state = STATE_IDLE;
            end
            
            STATE_PREFETCH: begin
                if (mem_req_ready_i) begin
                    next_state = STATE_IDLE;
                end
            end
        endcase
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    integer i, j;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            saved_addr <= 0;
            saved_is_pf <= 0;
            
            resp_valid_o <= 0;
            resp_data_o <= 0;
            resp_error_o <= 0;
            
            mem_req_valid_o <= 0;
            mem_req_addr_o <= 0;
            
            for (i = 0; i < SETS; i = i + 1) begin
                plru_bits[i] <= 0;
                for (j = 0; j < WAYS; j = j + 1) begin
                    valid_array[i][j] <= 0;
                    tag_array[i][j] <= 0;
                end
            end
            
            for (i = 0; i < MSHR_ENTRIES; i = i + 1) begin
                mshr_valid[i] <= 0;
                mshr_addr[i] <= 0;
                mshr_is_pf[i] <= 0;
            end
        end else begin
            state <= next_state;
            resp_valid_o <= 0;
            mem_req_valid_o <= 0;
            
            // Invalidation
            if (inv_valid_i) begin
                if (inv_all_i) begin
                    for (i = 0; i < SETS; i = i + 1) begin
                        for (j = 0; j < WAYS; j = j + 1) begin
                            valid_array[i][j] <= 0;
                        end
                    end
                end else begin
                    // Single line invalidation
                    for (j = 0; j < WAYS; j = j + 1) begin
                        if (valid_array[inv_addr_i[SET_BITS+LINE_BITS-1:LINE_BITS]][j] &&
                            tag_array[inv_addr_i[SET_BITS+LINE_BITS-1:LINE_BITS]][j] == 
                            inv_addr_i[ADDR_WIDTH-1:SET_BITS+LINE_BITS]) begin
                            valid_array[inv_addr_i[SET_BITS+LINE_BITS-1:LINE_BITS]][j] <= 0;
                        end
                    end
                end
            end
            
            case (state)
                STATE_IDLE: begin
                    if (req_valid_i) begin
                        saved_addr <= req_addr_i;
                        saved_is_pf <= 0;
                    end else if (pf_req_valid_i && !mshr_full) begin
                        saved_addr <= pf_req_addr_i;
                        saved_is_pf <= 1;
                    end
                end
                
                STATE_LOOKUP: begin
                    if (cache_hit) begin
                        // Hit: return data
                        resp_valid_o <= 1;
                        resp_data_o <= selected_data;
                        resp_error_o <= 0;
                        
                        // Update PLRU
                        case (hit_way)
                            2'd0: begin
                                plru_bits[req_set][0] <= 1;
                                plru_bits[req_set][1] <= 1;
                            end
                            2'd1: begin
                                plru_bits[req_set][0] <= 1;
                                plru_bits[req_set][1] <= 0;
                            end
                            2'd2: begin
                                plru_bits[req_set][0] <= 0;
                                plru_bits[req_set][2] <= 1;
                            end
                            2'd3: begin
                                plru_bits[req_set][0] <= 0;
                                plru_bits[req_set][2] <= 0;
                            end
                        endcase
                    end
                end
                
                STATE_MISS: begin
                    // Allocate MSHR and send memory request
                    if (!mshr_hit) begin
                        mshr_valid[mshr_free_idx] <= 1;
                        mshr_addr[mshr_free_idx] <= saved_addr;
                        mshr_is_pf[mshr_free_idx] <= saved_is_pf;
                    end
                    
                    mem_req_valid_o <= 1;
                    mem_req_addr_o <= {saved_addr[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}};
                end
                
                STATE_WAIT: begin
                    // Wait for memory response
                end
                
                STATE_REFILL: begin
                    // Refill cache line - use saved_set/saved_tag (stable during memory access)
                    tag_array[saved_set][replace_way] <= saved_tag;
                    valid_array[saved_set][replace_way] <= 1;
                    data_array[saved_set][replace_way] <= mem_resp_data_i;
                    
                    // Clear MSHR
                    for (i = 0; i < MSHR_ENTRIES; i = i + 1) begin
                        if (mshr_valid[i] && 
                            (mshr_addr[i][ADDR_WIDTH-1:LINE_BITS] == saved_addr[ADDR_WIDTH-1:LINE_BITS])) begin
                            mshr_valid[i] <= 0;
                            
                            // If not prefetch, return data
                            if (!mshr_is_pf[i]) begin
                                resp_valid_o <= 1;
                                // Select correct chunk from refill data
                                case (saved_addr[5:4])
                                    2'd0: resp_data_o <= mem_resp_data_i[127:0];
                                    2'd1: resp_data_o <= mem_resp_data_i[255:128];
                                    2'd2: resp_data_o <= mem_resp_data_i[383:256];
                                    2'd3: resp_data_o <= mem_resp_data_i[511:384];
                                endcase
                                resp_error_o <= 0;
                            end
                        end
                    end
                    
                    // Update PLRU for replaced way (use saved_set)
                    case (replace_way)
                        2'd0: begin
                            plru_bits[saved_set][0] <= 1;
                            plru_bits[saved_set][1] <= 1;
                        end
                        2'd1: begin
                            plru_bits[saved_set][0] <= 1;
                            plru_bits[saved_set][1] <= 0;
                        end
                        2'd2: begin
                            plru_bits[saved_set][0] <= 0;
                            plru_bits[saved_set][2] <= 1;
                        end
                        2'd3: begin
                            plru_bits[saved_set][0] <= 0;
                            plru_bits[saved_set][2] <= 0;
                        end
                    endcase
                end
                
                STATE_PREFETCH: begin
                    // Issue prefetch request to memory
                    mshr_valid[mshr_free_idx] <= 1;
                    mshr_addr[mshr_free_idx] <= saved_addr;
                    mshr_is_pf[mshr_free_idx] <= 1;
                    
                    mem_req_valid_o <= 1;
                    mem_req_addr_o <= {saved_addr[ADDR_WIDTH-1:LINE_BITS], {LINE_BITS{1'b0}}};
                end
            endcase
        end
    end

endmodule
