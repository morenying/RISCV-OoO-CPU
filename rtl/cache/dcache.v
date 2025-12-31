//=================================================================
// Module: dcache
// Description: Data Cache
//              4KB 2-way set associative
//              32-byte cache line, LRU replacement
//              Write-back, write-allocate policy
//              Supports byte/half/word access
// Requirements: 9.1, 9.2, 9.3, 9.4, 9.5
//=================================================================

`timescale 1ns/1ps

module dcache #(
    parameter CACHE_SIZE    = 4096,     // 4KB
    parameter LINE_SIZE     = 32,       // 32 bytes per line
    parameter NUM_WAYS      = 2,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // CPU interface
    input  wire                    req_valid_i,
    input  wire                    req_write_i,
    input  wire [ADDR_WIDTH-1:0]   req_addr_i,
    input  wire [DATA_WIDTH-1:0]   req_wdata_i,
    input  wire [1:0]              req_size_i,     // 00:byte, 01:half, 10:word
    output wire                    req_ready_o,
    output wire                    resp_valid_o,
    output wire [DATA_WIDTH-1:0]   resp_data_o,
    
    // Memory interface
    output wire                    mem_req_valid_o,
    output wire                    mem_req_write_o,
    output wire [ADDR_WIDTH-1:0]   mem_req_addr_o,
    output wire [LINE_SIZE*8-1:0]  mem_req_wdata_o,
    input  wire                    mem_req_ready_i,
    input  wire                    mem_resp_valid_i,
    input  wire [LINE_SIZE*8-1:0]  mem_resp_data_i,
    
    // Flush interface
    input  wire                    flush_i
);

    //=========================================================
    // Cache Parameters
    //=========================================================
    localparam NUM_SETS     = CACHE_SIZE / (LINE_SIZE * NUM_WAYS);  // 64 sets
    localparam INDEX_BITS   = $clog2(NUM_SETS);        // 6 bits
    localparam OFFSET_BITS  = $clog2(LINE_SIZE);       // 5 bits
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;  // 21 bits
    localparam WORDS_PER_LINE = LINE_SIZE / 4;         // 8 words
    
    //=========================================================
    // Cache Storage
    //=========================================================
    reg                     valid [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                     dirty [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [TAG_BITS-1:0]      tag   [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [LINE_SIZE*8-1:0]   data  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                     lru   [0:NUM_SETS-1];  // 0 = way0 is LRU
    
    integer i, j;
    
    //=========================================================
    // Address Decomposition
    //=========================================================
    wire [TAG_BITS-1:0]    req_tag;
    wire [INDEX_BITS-1:0]  req_index;
    wire [OFFSET_BITS-1:0] req_offset;
    wire [2:0]             word_offset;
    wire [1:0]             byte_offset;
    
    assign req_tag    = req_addr_i[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
    assign req_index  = req_addr_i[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS];
    assign req_offset = req_addr_i[OFFSET_BITS-1:0];
    assign word_offset = req_offset[OFFSET_BITS-1:2];
    assign byte_offset = req_offset[1:0];
    
    //=========================================================
    // Cache Lookup
    //=========================================================
    wire way0_hit, way1_hit, cache_hit;
    wire hit_way;
    
    assign way0_hit = valid[req_index][0] && (tag[req_index][0] == req_tag);
    assign way1_hit = valid[req_index][1] && (tag[req_index][1] == req_tag);
    assign cache_hit = way0_hit || way1_hit;
    assign hit_way = way1_hit;  // 0 if way0 hit, 1 if way1 hit
    
    // Extract word from cache line
    wire [LINE_SIZE*8-1:0] hit_line;
    wire [DATA_WIDTH-1:0] hit_word;
    
    assign hit_line = way0_hit ? data[req_index][0] : data[req_index][1];
    assign hit_word = hit_line[word_offset*32 +: 32];
    
    // Handle different access sizes
    reg [DATA_WIDTH-1:0] read_data;
    always @(*) begin
        case (req_size_i)
            2'b00: begin  // Byte
                case (byte_offset)
                    2'b00: read_data = {24'd0, hit_word[7:0]};
                    2'b01: read_data = {24'd0, hit_word[15:8]};
                    2'b10: read_data = {24'd0, hit_word[23:16]};
                    2'b11: read_data = {24'd0, hit_word[31:24]};
                endcase
            end
            2'b01: begin  // Half
                case (byte_offset[1])
                    1'b0: read_data = {16'd0, hit_word[15:0]};
                    1'b1: read_data = {16'd0, hit_word[31:16]};
                endcase
            end
            default: read_data = hit_word;  // Word
        endcase
    end

    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE      = 3'b000;
    localparam WRITEBACK = 3'b001;
    localparam WB_WAIT   = 3'b010;
    localparam REFILL    = 3'b011;
    localparam RF_WAIT   = 3'b100;
    localparam FLUSH_ST  = 3'b101;
    
    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] miss_addr;
    reg miss_write;
    reg [DATA_WIDTH-1:0] miss_wdata;
    reg [1:0] miss_size;
    reg replace_way;
    reg [INDEX_BITS-1:0] flush_index;
    reg flush_way;
    
    //=========================================================
    // Output Logic
    //=========================================================
    assign req_ready_o = (state == IDLE) && !flush_i;
    assign resp_valid_o = (state == IDLE) && req_valid_i && cache_hit && !flush_i;
    assign resp_data_o = read_data;
    
    // Memory interface
    reg mem_req_valid_reg;
    reg mem_req_write_reg;
    reg [ADDR_WIDTH-1:0] mem_req_addr_reg;
    reg [LINE_SIZE*8-1:0] mem_req_wdata_reg;
    
    assign mem_req_valid_o = mem_req_valid_reg;
    assign mem_req_write_o = mem_req_write_reg;
    assign mem_req_addr_o = mem_req_addr_reg;
    assign mem_req_wdata_o = mem_req_wdata_reg;
    
    //=========================================================
    // Write Data Merge
    //=========================================================
    function [LINE_SIZE*8-1:0] merge_write;
        input [LINE_SIZE*8-1:0] old_line;
        input [DATA_WIDTH-1:0] wdata;
        input [2:0] word_off;
        input [1:0] byte_off;
        input [1:0] size;
        reg [LINE_SIZE*8-1:0] new_line;
        reg [31:0] old_word;
        reg [31:0] new_word;
        begin
            new_line = old_line;
            old_word = old_line[word_off*32 +: 32];
            new_word = old_word;
            
            case (size)
                2'b00: begin  // Byte
                    case (byte_off)
                        2'b00: new_word[7:0] = wdata[7:0];
                        2'b01: new_word[15:8] = wdata[7:0];
                        2'b10: new_word[23:16] = wdata[7:0];
                        2'b11: new_word[31:24] = wdata[7:0];
                    endcase
                end
                2'b01: begin  // Half
                    case (byte_off[1])
                        1'b0: new_word[15:0] = wdata[15:0];
                        1'b1: new_word[31:16] = wdata[15:0];
                    endcase
                end
                default: new_word = wdata;  // Word
            endcase
            
            new_line[word_off*32 +: 32] = new_word;
            merge_write = new_line;
        end
    endfunction
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            miss_addr <= 0;
            miss_write <= 0;
            miss_wdata <= 0;
            miss_size <= 0;
            replace_way <= 0;
            flush_index <= 0;
            flush_way <= 0;
            mem_req_valid_reg <= 0;
            mem_req_write_reg <= 0;
            mem_req_addr_reg <= 0;
            mem_req_wdata_reg <= 0;
            
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    valid[i][j] <= 1'b0;
                    dirty[i][j] <= 1'b0;
                    tag[i][j] <= 0;
                    data[i][j] <= 0;
                end
                lru[i] <= 1'b0;
            end
        end else begin
            case (state)
                IDLE: begin
                    mem_req_valid_reg <= 0;
                    
                    if (flush_i) begin
                        state <= FLUSH_ST;
                        flush_index <= 0;
                        flush_way <= 0;
                    end else if (req_valid_i) begin
                        if (cache_hit) begin
                            // Update LRU
                            lru[req_index] <= hit_way ? 1'b0 : 1'b1;
                            
                            // Handle write hit
                            if (req_write_i) begin
                                data[req_index][hit_way] <= merge_write(
                                    hit_line, req_wdata_i, word_offset, byte_offset, req_size_i);
                                dirty[req_index][hit_way] <= 1'b1;
                            end
                        end else begin
                            // Cache miss
                            miss_addr <= req_addr_i;
                            miss_write <= req_write_i;
                            miss_wdata <= req_wdata_i;
                            miss_size <= req_size_i;
                            replace_way <= lru[req_index];
                            
                            // Check if need writeback
                            if (valid[req_index][lru[req_index]] && 
                                dirty[req_index][lru[req_index]]) begin
                                state <= WRITEBACK;
                            end else begin
                                state <= REFILL;
                            end
                        end
                    end
                end
                
                WRITEBACK: begin
                    // Send writeback request
                    mem_req_valid_reg <= 1;
                    mem_req_write_reg <= 1;
                    mem_req_addr_reg <= {tag[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way],
                                         miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS],
                                         {OFFSET_BITS{1'b0}}};
                    mem_req_wdata_reg <= data[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way];
                    
                    if (mem_req_ready_i) begin
                        state <= WB_WAIT;
                        mem_req_valid_reg <= 0;
                    end
                end
                
                WB_WAIT: begin
                    if (mem_resp_valid_i) begin
                        state <= REFILL;
                    end
                end
                
                REFILL: begin
                    // Send refill request
                    mem_req_valid_reg <= 1;
                    mem_req_write_reg <= 0;
                    mem_req_addr_reg <= {miss_addr[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
                    
                    if (mem_req_ready_i) begin
                        state <= RF_WAIT;
                        mem_req_valid_reg <= 0;
                    end
                end
                
                RF_WAIT: begin
                    if (mem_resp_valid_i) begin
                        // Install new line
                        valid[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= 1'b1;
                        tag[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= 
                            miss_addr[ADDR_WIDTH-1:INDEX_BITS+OFFSET_BITS];
                        
                        if (miss_write) begin
                            // Write-allocate: merge write data
                            data[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= 
                                merge_write(mem_resp_data_i, miss_wdata,
                                           miss_addr[OFFSET_BITS-1:2], miss_addr[1:0], miss_size);
                            dirty[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= 1'b1;
                        end else begin
                            data[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= mem_resp_data_i;
                            dirty[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]][replace_way] <= 1'b0;
                        end
                        
                        lru[miss_addr[INDEX_BITS+OFFSET_BITS-1:OFFSET_BITS]] <= ~replace_way;
                        state <= IDLE;
                    end
                end
                
                FLUSH_ST: begin
                    // Flush dirty lines
                    if (valid[flush_index][flush_way] && dirty[flush_index][flush_way]) begin
                        mem_req_valid_reg <= 1;
                        mem_req_write_reg <= 1;
                        mem_req_addr_reg <= {tag[flush_index][flush_way], flush_index, {OFFSET_BITS{1'b0}}};
                        mem_req_wdata_reg <= data[flush_index][flush_way];
                        
                        if (mem_req_ready_i) begin
                            dirty[flush_index][flush_way] <= 1'b0;
                            mem_req_valid_reg <= 0;
                            
                            // Move to next
                            if (flush_way == 0) begin
                                flush_way <= 1;
                            end else begin
                                flush_way <= 0;
                                if (flush_index == NUM_SETS - 1) begin
                                    state <= IDLE;
                                end else begin
                                    flush_index <= flush_index + 1;
                                end
                            end
                        end
                    end else begin
                        // Move to next
                        if (flush_way == 0) begin
                            flush_way <= 1;
                        end else begin
                            flush_way <= 0;
                            if (flush_index == NUM_SETS - 1) begin
                                state <= IDLE;
                            end else begin
                                flush_index <= flush_index + 1;
                            end
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
