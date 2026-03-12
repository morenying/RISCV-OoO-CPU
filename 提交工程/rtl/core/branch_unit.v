//=================================================================
// Module: branch_unit
// Description: Branch Execution Unit for RISC-V
//              Handles BEQ, BNE, BLT, BGE, BLTU, BGEU
//              Also handles JAL, JALR
//              Detects branch misprediction
// Requirements: 11.4, 1.1
//=================================================================

`timescale 1ns/1ps

module branch_unit (
    input  wire        clk,
    input  wire        rst_n,
    
    // Input interface
    input  wire        valid_i,
    input  wire [3:0]  op_i,           // Branch/Jump type
    input  wire [31:0] src1_i,         // rs1 value
    input  wire [31:0] src2_i,         // rs2 value
    input  wire [31:0] pc_i,           // Instruction PC
    input  wire [31:0] imm_i,          // Immediate offset
    input  wire        pred_taken_i,   // Predicted taken
    input  wire [31:0] pred_target_i,  // Predicted target
    input  wire [5:0]  prd_i,          // Physical dest reg (for JAL/JALR)
    input  wire [4:0]  rob_idx_i,
    
    // Output interface
    output reg         done_o,
    output reg         taken_o,        // Actual branch taken
    output reg  [31:0] target_o,       // Actual target address
    output reg         mispredict_o,   // Misprediction detected
    output reg  [31:0] link_addr_o,    // Return address (PC+4)
    output reg  [5:0]  result_prd_o,
    output reg  [4:0]  result_rob_idx_o
);

    //=========================================================
    // Local Parameters - Branch Operations
    //=========================================================
    localparam OP_BEQ   = 4'b0000;
    localparam OP_BNE   = 4'b0001;
    localparam OP_BLT   = 4'b0100;
    localparam OP_BGE   = 4'b0101;
    localparam OP_BLTU  = 4'b0110;
    localparam OP_BGEU  = 4'b0111;
    localparam OP_JAL   = 4'b1000;
    localparam OP_JALR  = 4'b1001;
    
    //=========================================================
    // Internal Signals
    //=========================================================
    wire        eq;
    wire        lt_signed;
    wire        lt_unsigned;
    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] jalr_target;
    wire [31:0] actual_target;
    wire        is_branch;
    wire        is_jal;
    wire        is_jalr;

    //=========================================================
    // Comparison Logic
    //=========================================================
    assign eq = (src1_i == src2_i);
    assign lt_signed = ($signed(src1_i) < $signed(src2_i));
    assign lt_unsigned = (src1_i < src2_i);
    
    //=========================================================
    // Branch Condition Evaluation
    //=========================================================
    reg branch_cond;
    
    always @(*) begin
        case (op_i)
            OP_BEQ:  branch_cond = eq;
            OP_BNE:  branch_cond = ~eq;
            OP_BLT:  branch_cond = lt_signed;
            OP_BGE:  branch_cond = ~lt_signed;
            OP_BLTU: branch_cond = lt_unsigned;
            OP_BGEU: branch_cond = ~lt_unsigned;
            default: branch_cond = 1'b0;
        endcase
    end
    
    //=========================================================
    // Instruction Type Detection
    //=========================================================
    assign is_branch = (op_i[3:1] == 3'b000) || (op_i[3:1] == 3'b010) || (op_i[3:1] == 3'b011);
    assign is_jal = (op_i == OP_JAL);
    assign is_jalr = (op_i == OP_JALR);
    
    //=========================================================
    // Target Address Calculation
    //=========================================================
    // Branch target: PC + imm
    assign branch_target = pc_i + imm_i;
    
    // JALR target: (rs1 + imm) & ~1
    assign jalr_target = (src1_i + imm_i) & 32'hFFFFFFFE;
    
    // Actual target selection
    assign actual_target = is_jalr ? jalr_target : branch_target;
    
    // Branch taken determination
    assign branch_taken = is_jal || is_jalr || (is_branch && branch_cond);
    
    //=========================================================
    // Output Logic (Single Cycle)
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_o <= 1'b0;
            taken_o <= 1'b0;
            target_o <= 32'b0;
            mispredict_o <= 1'b0;
            link_addr_o <= 32'b0;
            result_prd_o <= 6'b0;
            result_rob_idx_o <= 5'b0;
        end else begin
            done_o <= valid_i;
            
            if (valid_i) begin
                taken_o <= branch_taken;
                target_o <= actual_target;
                link_addr_o <= pc_i + 32'd4;
                result_prd_o <= prd_i;
                result_rob_idx_o <= rob_idx_i;
                
                // Misprediction detection
                if (branch_taken) begin
                    // Taken: check if prediction was taken and target matches
                    mispredict_o <= ~pred_taken_i || (pred_target_i != actual_target);
                end else begin
                    // Not taken: check if prediction was not taken
                    mispredict_o <= pred_taken_i;
                end
            end else begin
                mispredict_o <= 1'b0;
            end
        end
    end

endmodule
