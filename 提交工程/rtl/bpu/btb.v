//=================================================================
// Module: btb
// Description: Branch Target Buffer
//              512 entries, 2-way set associative
//              Stores branch type and target address
// Requirements: 7.5
//=================================================================

`timescale 1ns/1ps

module btb #(
    parameter NUM_SETS   = 256,
    parameter NUM_WAYS   = 2,
    parameter INDEX_BITS = 8,
    parameter TAG_BITS   = 20
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Lookup interface
    input  wire [31:0]             pc_i,
    output wire                    hit_o,
    output wire [31:0]             target_o,
    output wire [1:0]              br_type_o,    // 00:cond, 01:uncond, 10:call, 11:ret
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire [31:0]             update_target_i,
    input  wire [1:0]              update_br_type_i
);

    //=========================================================
    // BTB Entry Storage
    //=========================================================
    reg                valid  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [TAG_BITS-1:0] tag    [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [31:0]         target [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [1:0]          br_type[0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                lru    [0:NUM_SETS-1];  // 0 = way0 is LRU
    
    integer i, j;
    
    //=========================================================
    // Index and Tag Extraction
    //=========================================================
    wire [INDEX_BITS-1:0] lookup_idx;
    wire [TAG_BITS-1:0]   lookup_tag;
    wire [INDEX_BITS-1:0] update_idx;
    wire [TAG_BITS-1:0]   update_tag;
    
    assign lookup_idx = pc_i[INDEX_BITS+1:2];
    assign lookup_tag = pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];
    assign update_idx = update_pc_i[INDEX_BITS+1:2];
    assign update_tag = update_pc_i[TAG_BITS+INDEX_BITS+1:INDEX_BITS+2];
    
    //=========================================================
    // Lookup Logic
    //=========================================================
    wire way0_hit, way1_hit;
    
    assign way0_hit = valid[lookup_idx][0] && (tag[lookup_idx][0] == lookup_tag);
    assign way1_hit = valid[lookup_idx][1] && (tag[lookup_idx][1] == lookup_tag);
    assign hit_o = way0_hit || way1_hit;
    
    assign target_o = way0_hit ? target[lookup_idx][0] :
                      way1_hit ? target[lookup_idx][1] : 32'd0;
    assign br_type_o = way0_hit ? br_type[lookup_idx][0] :
                       way1_hit ? br_type[lookup_idx][1] : 2'd0;
    
    //=========================================================
    // Update Logic
    //=========================================================
    wire update_way0_hit, update_way1_hit;
    wire replace_way;
    
    assign update_way0_hit = valid[update_idx][0] && (tag[update_idx][0] == update_tag);
    assign update_way1_hit = valid[update_idx][1] && (tag[update_idx][1] == update_tag);
    assign replace_way = lru[update_idx];  // Replace LRU way
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < NUM_WAYS; j = j + 1) begin
                    valid[i][j] <= 1'b0;
                    tag[i][j] <= 0;
                    target[i][j] <= 0;
                    br_type[i][j] <= 0;
                end
                lru[i] <= 1'b0;
            end
        end else begin
            // Update LRU on lookup hit
            if (way0_hit) begin
                lru[lookup_idx] <= 1'b1;  // Way 1 becomes LRU
            end else if (way1_hit) begin
                lru[lookup_idx] <= 1'b0;  // Way 0 becomes LRU
            end
            
            // Update BTB entry
            if (update_valid_i) begin
                if (update_way0_hit) begin
                    // Update existing entry in way 0
                    target[update_idx][0] <= update_target_i;
                    br_type[update_idx][0] <= update_br_type_i;
                    lru[update_idx] <= 1'b1;
                end else if (update_way1_hit) begin
                    // Update existing entry in way 1
                    target[update_idx][1] <= update_target_i;
                    br_type[update_idx][1] <= update_br_type_i;
                    lru[update_idx] <= 1'b0;
                end else begin
                    // Allocate new entry in LRU way
                    valid[update_idx][replace_way] <= 1'b1;
                    tag[update_idx][replace_way] <= update_tag;
                    target[update_idx][replace_way] <= update_target_i;
                    br_type[update_idx][replace_way] <= update_br_type_i;
                    lru[update_idx] <= ~replace_way;
                end
            end
        end
    end

endmodule
