//=================================================================
// Module: icache
// Description: Instruction Cache
//              4KB direct-mapped cache
//              32-byte cache line
//              Supports FENCE.I invalidation
// Requirements: 8.1, 8.2, 8.3, 8.4
//=================================================================

`timescale 1ns/1ps

module icache #(
    parameter CACHE_SIZE    = 4096,     // 4KB
    parameter LINE_SIZE     = 32,       // 32 bytes per line
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // CPU interface
    input  wire                    req_valid_i,
    input  wire [ADDR_WIDTH-1:0]   req_addr_i,
    output wire                    req_ready_o,
    output wire                    resp_valid_o,
    output wire [DATA_WIDTH-1:0]   resp_data_o,
    
    // Memory interface (for cache miss)
    output wire                    mem_req_valid_o,
    output wire [ADDR_WIDTH-1:0]   mem_req_addr_o,
    input  wire                    mem_req_ready_i,
    input  wire                    mem_resp_valid_i,
    input  wire [LINE_SIZE*8-1:0]  mem_resp_data_i,
    
    // Control
    input  wire                    invalidate_i    // FENCE.I
);

    //=========================================================
    // Cache Parameters
    //=========================================================
    localparam NUM_LINES    = CACHE_SIZE / LINE_SIZE;  // 128 lines
    localparam INDEX_BITS   = $clog2(NUM_LINES);       // 7 bits
    localparam OFFSET_BITS  = $clog2(LINE_SIZE);       // 5 bits
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;  // 20 bits
    localparam WORDS_PER_LINE = LINE_SIZE / 4;         // 8 words
    
    //=========================================================
    // Cache Storage
    //=========================================================
    reg                     valid [0:NUM_LINES-1];
    reg [TAG_BITS-1:0]      tag   [0:NUM_LINES-1];
    reg [LINE_SIZE*8-1:0]   data  [0:NUM_LINES-1];
    
    integer i;
    
    //=========================================================
    // Address Decomposition
    //=========================================================
    wire [TAG_BITS-1:0]    req_tag;
    wire [INDEX_BITS-1:0]  req_index;
    wire [OFFSET_BITS-1:0] req_offset;
    wire [2:0]             word_offset;
    
    assign req_tag    = req_addr_i[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
    assign req_index  = req_addr_i[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    assign req_offset = req_addr_i[OFFSET_BITS-1:0];
    assign word_offset = req_offset[OFFSET_BITS-1:2];  // Word within line
    
    //=========================================================
    // Cache Lookup
    //=========================================================
    wire cache_hit;
    wire [LINE_SIZE*8-1:0] cache_line;
    
    assign cache_hit = valid[req_index] && (tag[req_index] == req_tag);
    assign cache_line = data[req_index];
    
    // Extract word from cache line
    wire [DATA_WIDTH-1:0] hit_data;
    assign hit_data = cache_line[word_offset*32 +: 32];
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE     = 2'b00;
    localparam MISS     = 2'b01;
    localparam REFILL   = 2'b10;
    localparam RESPOND  = 2'b11;  // New state for refill response
    
    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] miss_addr;
    reg [LINE_SIZE*8-1:0] refill_data;
    reg [DATA_WIDTH-1:0] refill_word;  // Word to return after refill
    
    //=========================================================
    // Output Logic
    //=========================================================
    assign req_ready_o = (state == IDLE);
    // resp_valid on cache hit OR after refill complete
    assign resp_valid_o = ((state == IDLE) && req_valid_i && cache_hit) || (state == RESPOND);
    // Return hit data or refill word
    assign resp_data_o = (state == RESPOND) ? refill_word : hit_data;
    
    assign mem_req_valid_o = (state == MISS);
    assign mem_req_addr_o = {miss_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            miss_addr <= 0;
            refill_data <= 0;
            refill_word <= 0;
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 0;
                data[i] <= 0;
            end
        end else if (invalidate_i) begin
            // FENCE.I: invalidate all lines
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid[i] <= 1'b0;
            end
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (req_valid_i && !cache_hit) begin
                        // Cache miss
                        state <= MISS;
                        miss_addr <= req_addr_i;
                    end
                end
                
                MISS: begin
                    if (mem_req_ready_i) begin
                        state <= REFILL;
                    end
                end
                
                REFILL: begin
                    if (mem_resp_valid_i) begin
                        // Write refill data to cache
                        valid[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]] <= 1'b1;
                        tag[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]] <= 
                            miss_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
                        data[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]] <= mem_resp_data_i;
                        // Extract the requested word from refill data
                        refill_word <= mem_resp_data_i[miss_addr[OFFSET_BITS-1:2]*32 +: 32];
                        state <= RESPOND;
                    end
                end
                
                RESPOND: begin
                    // Response sent, return to IDLE
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
