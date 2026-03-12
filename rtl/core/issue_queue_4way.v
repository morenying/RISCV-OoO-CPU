//=================================================================
// Module: issue_queue_4way
// Description: 4-Way Issue Queue with Out-of-Order Issue
//              Supports 4 instruction insert per cycle
//              Supports 4 instruction issue per cycle
//              Age-based priority with operand readiness
//=================================================================

`timescale 1ns/1ps

module issue_queue_4way #(
    parameter IQ_DEPTH       = 32,
    parameter ISSUE_WIDTH    = 4,
    parameter PHYS_REG_BITS  = 7,
    parameter ROB_IDX_BITS   = 6,
    parameter XLEN           = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Rename Interface (4 instructions insert)
    //=========================================================
    input  wire                     insert_valid_i,
    input  wire [3:0]               insert_mask_i,
    output wire                     insert_ready_o,
    
    // Per-instruction data
    input  wire [PHYS_REG_BITS-1:0] insert_prs1_i       [0:ISSUE_WIDTH-1],
    input  wire [PHYS_REG_BITS-1:0] insert_prs2_i       [0:ISSUE_WIDTH-1],
    input  wire [PHYS_REG_BITS-1:0] insert_prd_i        [0:ISSUE_WIDTH-1],
    input  wire                     insert_prs1_ready_i [0:ISSUE_WIDTH-1],
    input  wire                     insert_prs2_ready_i [0:ISSUE_WIDTH-1],
    input  wire [ROB_IDX_BITS-1:0]  insert_rob_idx_i    [0:ISSUE_WIDTH-1],
    input  wire [2:0]               insert_fu_type_i    [0:ISSUE_WIDTH-1],
    input  wire [3:0]               insert_alu_op_i     [0:ISSUE_WIDTH-1],
    input  wire [XLEN-1:0]          insert_imm_i        [0:ISSUE_WIDTH-1],
    input  wire                     insert_use_imm_i    [0:ISSUE_WIDTH-1],
    input  wire [XLEN-1:0]          insert_pc_i         [0:ISSUE_WIDTH-1],
    
    //=========================================================
    // Issue Interface (4 instructions out)
    //=========================================================
    output reg  [3:0]               issue_valid_o,
    input  wire [3:0]               issue_ready_i,      // FU ready to accept
    
    output reg  [PHYS_REG_BITS-1:0] issue_prs1_o        [0:ISSUE_WIDTH-1],
    output reg  [PHYS_REG_BITS-1:0] issue_prs2_o        [0:ISSUE_WIDTH-1],
    output reg  [PHYS_REG_BITS-1:0] issue_prd_o         [0:ISSUE_WIDTH-1],
    output reg  [ROB_IDX_BITS-1:0]  issue_rob_idx_o     [0:ISSUE_WIDTH-1],
    output reg  [2:0]               issue_fu_type_o     [0:ISSUE_WIDTH-1],
    output reg  [3:0]               issue_alu_op_o      [0:ISSUE_WIDTH-1],
    output reg  [XLEN-1:0]          issue_imm_o         [0:ISSUE_WIDTH-1],
    output reg                      issue_use_imm_o     [0:ISSUE_WIDTH-1],
    output reg  [XLEN-1:0]          issue_pc_o          [0:ISSUE_WIDTH-1],
    
    //=========================================================
    // Wakeup Interface (from execution units)
    //=========================================================
    input  wire [3:0]               wakeup_valid_i,
    input  wire [PHYS_REG_BITS-1:0] wakeup_prd_i        [0:ISSUE_WIDTH-1],
    
    //=========================================================
    // Flush Interface
    //=========================================================
    input  wire                     flush_i,
    input  wire [ROB_IDX_BITS-1:0]  flush_rob_idx_i
);

    //=========================================================
    // FU Type Constants
    //=========================================================
    localparam FU_ALU = 3'd0;
    localparam FU_MUL = 3'd1;
    localparam FU_DIV = 3'd2;
    localparam FU_LSU = 3'd3;
    localparam FU_BRU = 3'd4;
    localparam FU_CSR = 3'd5;
    localparam FU_AMO = 3'd6;
    
    //=========================================================
    // Issue Queue Entry
    //=========================================================
    localparam IQ_IDX_BITS = $clog2(IQ_DEPTH);
    
    reg                     iq_valid    [0:IQ_DEPTH-1];
    reg [PHYS_REG_BITS-1:0] iq_prs1     [0:IQ_DEPTH-1];
    reg [PHYS_REG_BITS-1:0] iq_prs2     [0:IQ_DEPTH-1];
    reg [PHYS_REG_BITS-1:0] iq_prd      [0:IQ_DEPTH-1];
    reg                     iq_prs1_rdy [0:IQ_DEPTH-1];
    reg                     iq_prs2_rdy [0:IQ_DEPTH-1];
    reg [ROB_IDX_BITS-1:0]  iq_rob_idx  [0:IQ_DEPTH-1];
    reg [2:0]               iq_fu_type  [0:IQ_DEPTH-1];
    reg [3:0]               iq_alu_op   [0:IQ_DEPTH-1];
    reg [XLEN-1:0]          iq_imm      [0:IQ_DEPTH-1];
    reg                     iq_use_imm  [0:IQ_DEPTH-1];
    reg [XLEN-1:0]          iq_pc       [0:IQ_DEPTH-1];
    reg [5:0]               iq_age      [0:IQ_DEPTH-1];  // Age counter for priority
    
    //=========================================================
    // Free Entry Tracking
    //=========================================================
    reg [IQ_DEPTH-1:0] free_mask;
    wire [5:0] free_count;
    
    // Count free entries using explicit popcount (Icarus-friendly)
    function [5:0] popcount32;
        input [31:0] x;
        reg [5:0] cnt;
        integer i;
        begin
            cnt = 0;
            for (i = 0; i < 32; i = i + 1) begin
                cnt = cnt + x[i];
            end
            popcount32 = cnt;
        end
    endfunction
    
    assign free_count = popcount32(free_mask);
    
    // Count insert requests
    wire [2:0] insert_count = insert_mask_i[0] + insert_mask_i[1] + 
                               insert_mask_i[2] + insert_mask_i[3];
    
    assign insert_ready_o = (free_count >= {3'b0, insert_count});
    
    //=========================================================
    // Find Free Entries (priority encoder)
    //=========================================================
    reg [IQ_IDX_BITS-1:0] free_idx [0:ISSUE_WIDTH-1];
    
    integer fi, found;
    always @(*) begin
        found = 0;
        for (fi = 0; fi < ISSUE_WIDTH; fi = fi + 1) begin
            free_idx[fi] = 0;
        end
        
        for (fi = 0; fi < IQ_DEPTH && found < ISSUE_WIDTH; fi = fi + 1) begin
            if (free_mask[fi]) begin
                free_idx[found] = fi[IQ_IDX_BITS-1:0];
                found = found + 1;
            end
        end
    end
    
    //=========================================================
    // Ready-to-Issue Detection
    //=========================================================
    wire [IQ_DEPTH-1:0] ready_mask;
    
    genvar g;
    generate
        for (g = 0; g < IQ_DEPTH; g = g + 1) begin : gen_ready
            assign ready_mask[g] = iq_valid[g] && iq_prs1_rdy[g] && iq_prs2_rdy[g];
        end
    endgenerate
    
    //=========================================================
    // Issue Selection (oldest-first per FU type)
    //=========================================================
    // For simplicity, select 4 oldest ready instructions
    // A more realistic design would have per-FU issue ports
    
    reg [IQ_IDX_BITS-1:0] issue_idx [0:ISSUE_WIDTH-1];
    reg [3:0] issue_found;
    
    integer si, sj;
    reg [5:0] max_age [0:ISSUE_WIDTH-1];
    reg [IQ_IDX_BITS-1:0] max_idx [0:ISSUE_WIDTH-1];
    reg [IQ_DEPTH-1:0] selected_mask;
    
    always @(*) begin
        issue_found = 0;
        selected_mask = 0;
        
        for (si = 0; si < ISSUE_WIDTH; si = si + 1) begin
            max_age[si] = 0;
            max_idx[si] = 0;
            issue_idx[si] = 0;
            
            // Find oldest ready entry not yet selected
            // Use strictly greater to prioritize lower indices for same age
            for (sj = 0; sj < IQ_DEPTH; sj = sj + 1) begin
                if (ready_mask[sj] && !selected_mask[sj]) begin
                    if (iq_age[sj] > max_age[si]) begin
                        max_age[si] = iq_age[sj];
                        max_idx[si] = sj[IQ_IDX_BITS-1:0];
                    end else if (iq_age[sj] == max_age[si] && max_age[si] == 0) begin
                        // For age 0 (just inserted), pick first found (lowest index)
                        // Only update if max_idx hasn't been set yet
                        if (!ready_mask[max_idx[si]] || selected_mask[max_idx[si]]) begin
                            max_idx[si] = sj[IQ_IDX_BITS-1:0];
                        end
                    end
                end
            end
            
            // Mark as selected if found
            if (ready_mask[max_idx[si]] && !selected_mask[max_idx[si]]) begin
                issue_found[si] = 1;
                issue_idx[si] = max_idx[si];
                selected_mask[max_idx[si]] = 1;
            end
        end
    end
    
    //=========================================================
    // Wakeup Logic
    //=========================================================
    integer wi, wj;
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset handled below
        end else begin
            // Wakeup: mark operands ready
            for (wi = 0; wi < IQ_DEPTH; wi = wi + 1) begin
                if (iq_valid[wi]) begin
                    for (wj = 0; wj < ISSUE_WIDTH; wj = wj + 1) begin
                        if (wakeup_valid_i[wj]) begin
                            if (iq_prs1[wi] == wakeup_prd_i[wj]) begin
                                iq_prs1_rdy[wi] <= 1;
                            end
                            if (iq_prs2[wi] == wakeup_prd_i[wj]) begin
                                iq_prs2_rdy[wi] <= 1;
                            end
                        end
                    end
                end
            end
        end
    end
    
    //=========================================================
    // Age Counter Update
    //=========================================================
    integer ai;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (ai = 0; ai < IQ_DEPTH; ai = ai + 1) begin
                iq_age[ai] <= 0;
            end
        end else begin
            for (ai = 0; ai < IQ_DEPTH; ai = ai + 1) begin
                if (iq_valid[ai] && iq_age[ai] < 63) begin
                    iq_age[ai] <= iq_age[ai] + 1;
                end
            end
        end
    end
    
    //=========================================================
    // Main Sequential Logic
    //=========================================================
    integer i, j, ins_ptr;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                iq_valid[i] <= 0;
                free_mask[i] <= 1;
                iq_prs1[i] <= 0;
                iq_prs2[i] <= 0;
                iq_prd[i] <= 0;
                iq_prs1_rdy[i] <= 0;
                iq_prs2_rdy[i] <= 0;
                iq_rob_idx[i] <= 0;
                iq_fu_type[i] <= 0;
                iq_alu_op[i] <= 0;
                iq_imm[i] <= 0;
                iq_use_imm[i] <= 0;
                iq_pc[i] <= 0;
            end
            
            issue_valid_o <= 0;
            for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
                issue_prs1_o[i] <= 0;
                issue_prs2_o[i] <= 0;
                issue_prd_o[i] <= 0;
                issue_rob_idx_o[i] <= 0;
                issue_fu_type_o[i] <= 0;
                issue_alu_op_o[i] <= 0;
                issue_imm_o[i] <= 0;
                issue_use_imm_o[i] <= 0;
                issue_pc_o[i] <= 0;
            end
        end else if (flush_i) begin
            // Flush all entries
            for (i = 0; i < IQ_DEPTH; i = i + 1) begin
                iq_valid[i] <= 0;
                free_mask[i] <= 1;
            end
            issue_valid_o <= 0;
        end else begin
            // Insert new instructions
            if (insert_valid_i && insert_ready_o) begin
                ins_ptr = 0;
                for (j = 0; j < ISSUE_WIDTH; j = j + 1) begin
                    if (insert_mask_i[j]) begin
                        iq_valid[free_idx[ins_ptr]] <= 1;
                        free_mask[free_idx[ins_ptr]] <= 0;
                        iq_prs1[free_idx[ins_ptr]] <= insert_prs1_i[j];
                        iq_prs2[free_idx[ins_ptr]] <= insert_prs2_i[j];
                        iq_prd[free_idx[ins_ptr]] <= insert_prd_i[j];
                        iq_prs1_rdy[free_idx[ins_ptr]] <= insert_prs1_ready_i[j];
                        iq_prs2_rdy[free_idx[ins_ptr]] <= insert_prs2_ready_i[j];
                        iq_rob_idx[free_idx[ins_ptr]] <= insert_rob_idx_i[j];
                        iq_fu_type[free_idx[ins_ptr]] <= insert_fu_type_i[j];
                        iq_alu_op[free_idx[ins_ptr]] <= insert_alu_op_i[j];
                        iq_imm[free_idx[ins_ptr]] <= insert_imm_i[j];
                        iq_use_imm[free_idx[ins_ptr]] <= insert_use_imm_i[j];
                        iq_pc[free_idx[ins_ptr]] <= insert_pc_i[j];
                        iq_age[free_idx[ins_ptr]] <= 0;
                        ins_ptr = ins_ptr + 1;
                    end
                end
            end
            
            // Issue selected instructions
            issue_valid_o <= issue_found & issue_ready_i;
            
            for (i = 0; i < ISSUE_WIDTH; i = i + 1) begin
                if (issue_found[i] && issue_ready_i[i]) begin
                    // Output instruction
                    issue_prs1_o[i] <= iq_prs1[issue_idx[i]];
                    issue_prs2_o[i] <= iq_prs2[issue_idx[i]];
                    issue_prd_o[i] <= iq_prd[issue_idx[i]];
                    issue_rob_idx_o[i] <= iq_rob_idx[issue_idx[i]];
                    issue_fu_type_o[i] <= iq_fu_type[issue_idx[i]];
                    issue_alu_op_o[i] <= iq_alu_op[issue_idx[i]];
                    issue_imm_o[i] <= iq_imm[issue_idx[i]];
                    issue_use_imm_o[i] <= iq_use_imm[issue_idx[i]];
                    issue_pc_o[i] <= iq_pc[issue_idx[i]];
                    
                    // Free the entry
                    iq_valid[issue_idx[i]] <= 0;
                    free_mask[issue_idx[i]] <= 1;
                end else begin
                    issue_prs1_o[i] <= 0;
                    issue_prs2_o[i] <= 0;
                    issue_prd_o[i] <= 0;
                    issue_rob_idx_o[i] <= 0;
                    issue_fu_type_o[i] <= 0;
                    issue_alu_op_o[i] <= 0;
                    issue_imm_o[i] <= 0;
                    issue_use_imm_o[i] <= 0;
                    issue_pc_o[i] <= 0;
                end
            end
        end
    end

endmodule
