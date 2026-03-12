//=================================================================
// Module: rename_4way
// Description: 4-Way Superscalar Register Rename Unit
//              Renames 4 architectural registers to physical registers
//              Handles RAW dependencies within rename group
//=================================================================

`timescale 1ns/1ps

module rename_4way #(
    parameter ARCH_REGS      = 32,
    parameter PHYS_REGS      = 128,
    parameter RENAME_WIDTH   = 4,
    parameter ROB_DEPTH      = 64,
    parameter ARCH_REG_BITS  = 5,
    parameter PHYS_REG_BITS  = 7,
    parameter ROB_IDX_BITS   = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Decode Interface (4 instructions)
    //=========================================================
    input  wire                     dec_valid_i,
    input  wire [3:0]               dec_valid_mask_i,
    
    input  wire [ARCH_REG_BITS-1:0] dec_rs1_i       [0:RENAME_WIDTH-1],
    input  wire [ARCH_REG_BITS-1:0] dec_rs2_i       [0:RENAME_WIDTH-1],
    input  wire [ARCH_REG_BITS-1:0] dec_rd_i        [0:RENAME_WIDTH-1],
    input  wire                     dec_rs1_valid_i [0:RENAME_WIDTH-1],
    input  wire                     dec_rs2_valid_i [0:RENAME_WIDTH-1],
    input  wire                     dec_rd_valid_i  [0:RENAME_WIDTH-1],
    
    output wire                     dec_ready_o,
    
    //=========================================================
    // Renamed Output (to Issue Queue)
    //=========================================================
    output reg                      ren_valid_o,
    output reg  [3:0]               ren_valid_mask_o,
    
    output reg  [PHYS_REG_BITS-1:0] ren_prs1_o      [0:RENAME_WIDTH-1],
    output reg  [PHYS_REG_BITS-1:0] ren_prs2_o      [0:RENAME_WIDTH-1],
    output reg  [PHYS_REG_BITS-1:0] ren_prd_o       [0:RENAME_WIDTH-1],
    output reg  [PHYS_REG_BITS-1:0] ren_old_prd_o   [0:RENAME_WIDTH-1],  // For ROB
    output reg                      ren_prs1_ready_o[0:RENAME_WIDTH-1],
    output reg                      ren_prs2_ready_o[0:RENAME_WIDTH-1],
    
    //=========================================================
    // Free List Interface
    //=========================================================
    output wire                     fl_pop_valid_o,
    output wire [2:0]               fl_pop_count_o,  // How many to pop (0-4)
    input  wire [3:0]               fl_pop_ready_i,  // Which slots have free regs
    input  wire [PHYS_REG_BITS-1:0] fl_pop_preg_i [0:RENAME_WIDTH-1],
    
    //=========================================================
    // ROB Interface
    //=========================================================
    output wire                     rob_alloc_valid_o,
    output wire [2:0]               rob_alloc_count_o,
    input  wire [3:0]               rob_alloc_ready_i,
    input  wire [ROB_IDX_BITS-1:0]  rob_alloc_idx_i [0:RENAME_WIDTH-1],
    
    output reg  [ROB_IDX_BITS-1:0]  ren_rob_idx_o   [0:RENAME_WIDTH-1],
    
    //=========================================================
    // Commit Interface (for freeing old physical registers)
    //=========================================================
    input  wire                     commit_valid_i,
    input  wire [3:0]               commit_mask_i,
    input  wire [ARCH_REG_BITS-1:0] commit_rd_i     [0:RENAME_WIDTH-1],
    input  wire [PHYS_REG_BITS-1:0] commit_prd_i    [0:RENAME_WIDTH-1],
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire [ROB_IDX_BITS-1:0]  flush_rob_idx_i,
    
    //=========================================================
    // Scoreboard Interface (operand ready status)
    //=========================================================
    input  wire [PHYS_REGS-1:0]     scoreboard_i    // 1 = ready, 0 = not ready
);

    //=========================================================
    // Register Alias Table (RAT)
    //=========================================================
    reg [PHYS_REG_BITS-1:0] rat [0:ARCH_REGS-1];
    
    // Committed RAT (for recovery)
    reg [PHYS_REG_BITS-1:0] crat [0:ARCH_REGS-1];
    
    //=========================================================
    // Count valid destinations in this rename group
    //=========================================================
    wire [2:0] rd_count;
    assign rd_count = (dec_valid_mask_i[0] & dec_rd_valid_i[0]) +
                      (dec_valid_mask_i[1] & dec_rd_valid_i[1]) +
                      (dec_valid_mask_i[2] & dec_rd_valid_i[2]) +
                      (dec_valid_mask_i[3] & dec_rd_valid_i[3]);
    
    //=========================================================
    // Resource availability check
    //=========================================================
    wire resources_available = (fl_pop_ready_i >= {1'b0, rd_count}) &&
                               (rob_alloc_ready_i >= {1'b0, rd_count});
    
    assign dec_ready_o = resources_available && !flush_i;
    
    assign fl_pop_valid_o = dec_valid_i && resources_available;
    assign fl_pop_count_o = rd_count;
    
    assign rob_alloc_valid_o = dec_valid_i && resources_available;
    assign rob_alloc_count_o = rd_count;
    
    //=========================================================
    // Intra-group RAW dependency detection
    // Check if rs1/rs2 matches a previous rd in the same group
    //=========================================================
    reg [PHYS_REG_BITS-1:0] group_prd [0:RENAME_WIDTH-1];
    reg                     group_prd_valid [0:RENAME_WIDTH-1];
    
    // Compute renamed physical registers for each instruction
    wire [PHYS_REG_BITS-1:0] new_prs1 [0:RENAME_WIDTH-1];
    wire [PHYS_REG_BITS-1:0] new_prs2 [0:RENAME_WIDTH-1];
    wire                     new_prs1_ready [0:RENAME_WIDTH-1];
    wire                     new_prs2_ready [0:RENAME_WIDTH-1];
    
    //=========================================================
    // Free register allocation mapping
    // Map valid destinations to free list outputs
    //=========================================================
    reg [1:0] fl_idx [0:RENAME_WIDTH-1];  // Which fl_pop_preg to use
    
    always @(*) begin
        integer i, cnt;
        cnt = 0;
        for (i = 0; i < RENAME_WIDTH; i = i + 1) begin
            if (dec_valid_mask_i[i] && dec_rd_valid_i[i]) begin
                fl_idx[i] = cnt[1:0];
                cnt = cnt + 1;
            end else begin
                fl_idx[i] = 0;
            end
        end
    end
    
    //=========================================================
    // Generate renamed source operands with forwarding
    //=========================================================
    genvar g;
    generate
        for (g = 0; g < RENAME_WIDTH; g = g + 1) begin : gen_rename
            // Default: read from RAT
            wire [PHYS_REG_BITS-1:0] rat_prs1 = (dec_rs1_i[g] == 0) ? 0 : rat[dec_rs1_i[g]];
            wire [PHYS_REG_BITS-1:0] rat_prs2 = (dec_rs2_i[g] == 0) ? 0 : rat[dec_rs2_i[g]];
            
            // Check forwarding from earlier instructions in same group
            reg [PHYS_REG_BITS-1:0] fwd_prs1, fwd_prs2;
            reg fwd_prs1_match, fwd_prs2_match;
            
            integer j;
            always @(*) begin
                fwd_prs1 = rat_prs1;
                fwd_prs2 = rat_prs2;
                fwd_prs1_match = 0;
                fwd_prs2_match = 0;
                
                // Check against earlier instructions (j < g)
                for (j = 0; j < g; j = j + 1) begin
                    if (dec_valid_mask_i[j] && dec_rd_valid_i[j] && dec_rd_i[j] != 0) begin
                        if (dec_rs1_valid_i[g] && dec_rs1_i[g] == dec_rd_i[j]) begin
                            fwd_prs1 = fl_pop_preg_i[fl_idx[j]];
                            fwd_prs1_match = 1;
                        end
                        if (dec_rs2_valid_i[g] && dec_rs2_i[g] == dec_rd_i[j]) begin
                            fwd_prs2 = fl_pop_preg_i[fl_idx[j]];
                            fwd_prs2_match = 1;
                        end
                    end
                end
            end
            
            assign new_prs1[g] = fwd_prs1;
            assign new_prs2[g] = fwd_prs2;
            
            // Ready if x0, or scoreboard says ready, and no forward from this group
            assign new_prs1_ready[g] = (dec_rs1_i[g] == 0) || 
                                       (!fwd_prs1_match && scoreboard_i[rat_prs1]);
            assign new_prs2_ready[g] = (dec_rs2_i[g] == 0) || 
                                       (!fwd_prs2_match && scoreboard_i[rat_prs2]);
        end
    endgenerate
    
    //=========================================================
    // RAT Update Logic
    //=========================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize RAT: arch reg i -> phys reg i
            for (i = 0; i < ARCH_REGS; i = i + 1) begin
                rat[i] <= i[PHYS_REG_BITS-1:0];
                crat[i] <= i[PHYS_REG_BITS-1:0];
            end
        end else if (flush_i) begin
            // Restore RAT from committed RAT
            for (i = 0; i < ARCH_REGS; i = i + 1) begin
                rat[i] <= crat[i];
            end
        end else begin
            // Normal rename: update RAT with new mappings
            if (dec_valid_i && resources_available) begin
                for (i = 0; i < RENAME_WIDTH; i = i + 1) begin
                    if (dec_valid_mask_i[i] && dec_rd_valid_i[i] && dec_rd_i[i] != 0) begin
                        rat[dec_rd_i[i]] <= fl_pop_preg_i[fl_idx[i]];
                    end
                end
            end
            
            // Commit: update committed RAT
            if (commit_valid_i) begin
                for (i = 0; i < RENAME_WIDTH; i = i + 1) begin
                    if (commit_mask_i[i] && commit_rd_i[i] != 0) begin
                        crat[commit_rd_i[i]] <= commit_prd_i[i];
                    end
                end
            end
        end
    end
    
    //=========================================================
    // Output Pipeline Register
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            ren_valid_o <= 0;
            ren_valid_mask_o <= 0;
            
            for (i = 0; i < RENAME_WIDTH; i = i + 1) begin
                ren_prs1_o[i] <= 0;
                ren_prs2_o[i] <= 0;
                ren_prd_o[i] <= 0;
                ren_old_prd_o[i] <= 0;
                ren_prs1_ready_o[i] <= 0;
                ren_prs2_ready_o[i] <= 0;
                ren_rob_idx_o[i] <= 0;
            end
        end else if (dec_valid_i && resources_available) begin
            ren_valid_o <= 1;
            ren_valid_mask_o <= dec_valid_mask_i;
            
            for (i = 0; i < RENAME_WIDTH; i = i + 1) begin
                ren_prs1_o[i] <= new_prs1[i];
                ren_prs2_o[i] <= new_prs2[i];
                ren_prs1_ready_o[i] <= new_prs1_ready[i];
                ren_prs2_ready_o[i] <= new_prs2_ready[i];
                ren_rob_idx_o[i] <= rob_alloc_idx_i[i];
                
                if (dec_valid_mask_i[i] && dec_rd_valid_i[i]) begin
                    ren_prd_o[i] <= fl_pop_preg_i[fl_idx[i]];
                    ren_old_prd_o[i] <= rat[dec_rd_i[i]];
                end else begin
                    ren_prd_o[i] <= 0;
                    ren_old_prd_o[i] <= 0;
                end
            end
        end else begin
            ren_valid_o <= 0;
        end
    end

endmodule
