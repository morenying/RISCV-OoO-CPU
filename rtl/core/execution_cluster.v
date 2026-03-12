//=================================================================
// Module: execution_cluster
// Description: Unified Execution Cluster for 4-issue Superscalar
//              Contains: 2x ALU, 1x MUL (pipelined), 1x DIV, 1x BRU
//              With clock gating for power optimization
//=================================================================

`timescale 1ns/1ps
`include "cpu_defines.vh"

module execution_cluster #(
    parameter PHYS_REG_BITS  = 7,
    parameter DATA_WIDTH     = 32,
    parameter ROB_IDX_BITS   = 6,
    parameter RS_ENTRIES     = 8         // Per-unit RS entries
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Flush control
    input  wire                     flush_i,
    
    //=========================================================
    // Issue Queue Interface - 4 issue ports
    //=========================================================
    // Issue port 0 (can go to ALU0, MUL, DIV, BRU)
    input  wire                     issue0_valid_i,
    output wire                     issue0_ready_o,
    input  wire [4:0]               issue0_op_i,
    input  wire [DATA_WIDTH-1:0]    issue0_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]    issue0_rs2_data_i,
    input  wire [DATA_WIDTH-1:0]    issue0_imm_i,
    input  wire [DATA_WIDTH-1:0]    issue0_pc_i,
    input  wire [PHYS_REG_BITS-1:0] issue0_prd_i,
    input  wire [ROB_IDX_BITS-1:0]  issue0_rob_idx_i,
    input  wire [2:0]               issue0_fu_type_i,    // 0:ALU, 1:MUL, 2:DIV, 3:BRU
    input  wire                     issue0_use_imm_i,
    input  wire                     issue0_br_predict_i,
    input  wire [DATA_WIDTH-1:0]    issue0_br_target_i,
    
    // Issue port 1 (can go to ALU0, ALU1, MUL)
    input  wire                     issue1_valid_i,
    output wire                     issue1_ready_o,
    input  wire [4:0]               issue1_op_i,
    input  wire [DATA_WIDTH-1:0]    issue1_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]    issue1_rs2_data_i,
    input  wire [DATA_WIDTH-1:0]    issue1_imm_i,
    input  wire [DATA_WIDTH-1:0]    issue1_pc_i,
    input  wire [PHYS_REG_BITS-1:0] issue1_prd_i,
    input  wire [ROB_IDX_BITS-1:0]  issue1_rob_idx_i,
    input  wire [2:0]               issue1_fu_type_i,
    input  wire                     issue1_use_imm_i,
    input  wire                     issue1_br_predict_i,
    input  wire [DATA_WIDTH-1:0]    issue1_br_target_i,
    
    // Issue port 2 (can go to ALU1, DIV)
    input  wire                     issue2_valid_i,
    output wire                     issue2_ready_o,
    input  wire [4:0]               issue2_op_i,
    input  wire [DATA_WIDTH-1:0]    issue2_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]    issue2_rs2_data_i,
    input  wire [DATA_WIDTH-1:0]    issue2_imm_i,
    input  wire [DATA_WIDTH-1:0]    issue2_pc_i,
    input  wire [PHYS_REG_BITS-1:0] issue2_prd_i,
    input  wire [ROB_IDX_BITS-1:0]  issue2_rob_idx_i,
    input  wire [2:0]               issue2_fu_type_i,
    input  wire                     issue2_use_imm_i,
    input  wire                     issue2_br_predict_i,
    input  wire [DATA_WIDTH-1:0]    issue2_br_target_i,
    
    // Issue port 3 (can go to ALU0, ALU1, BRU)
    input  wire                     issue3_valid_i,
    output wire                     issue3_ready_o,
    input  wire [4:0]               issue3_op_i,
    input  wire [DATA_WIDTH-1:0]    issue3_rs1_data_i,
    input  wire [DATA_WIDTH-1:0]    issue3_rs2_data_i,
    input  wire [DATA_WIDTH-1:0]    issue3_imm_i,
    input  wire [DATA_WIDTH-1:0]    issue3_pc_i,
    input  wire [PHYS_REG_BITS-1:0] issue3_prd_i,
    input  wire [ROB_IDX_BITS-1:0]  issue3_rob_idx_i,
    input  wire [2:0]               issue3_fu_type_i,
    input  wire                     issue3_use_imm_i,
    input  wire                     issue3_br_predict_i,
    input  wire [DATA_WIDTH-1:0]    issue3_br_target_i,
    
    //=========================================================
    // CDB Interface - Results to CDB
    //=========================================================
    // ALU0 result
    output reg                      alu0_valid_o,
    input  wire                     alu0_ready_i,
    output reg  [PHYS_REG_BITS-1:0] alu0_prd_o,
    output reg  [DATA_WIDTH-1:0]    alu0_data_o,
    output reg  [ROB_IDX_BITS-1:0]  alu0_rob_idx_o,
    output wire                     alu0_exception_o,
    output wire [3:0]               alu0_exc_code_o,
    
    // ALU1 result
    output reg                      alu1_valid_o,
    input  wire                     alu1_ready_i,
    output reg  [PHYS_REG_BITS-1:0] alu1_prd_o,
    output reg  [DATA_WIDTH-1:0]    alu1_data_o,
    output reg  [ROB_IDX_BITS-1:0]  alu1_rob_idx_o,
    output wire                     alu1_exception_o,
    output wire [3:0]               alu1_exc_code_o,
    
    // MUL result (3-cycle latency)
    output reg                      mul_valid_o,
    input  wire                     mul_ready_i,
    output reg  [PHYS_REG_BITS-1:0] mul_prd_o,
    output reg  [DATA_WIDTH-1:0]    mul_data_o,
    output reg  [ROB_IDX_BITS-1:0]  mul_rob_idx_o,
    output wire                     mul_exception_o,
    output wire [3:0]               mul_exc_code_o,
    
    // DIV result (variable latency)
    output reg                      div_valid_o,
    input  wire                     div_ready_i,
    output reg  [PHYS_REG_BITS-1:0] div_prd_o,
    output reg  [DATA_WIDTH-1:0]    div_data_o,
    output reg  [ROB_IDX_BITS-1:0]  div_rob_idx_o,
    output wire                     div_exception_o,
    output wire [3:0]               div_exc_code_o,
    
    // BRU result
    output reg                      bru_valid_o,
    input  wire                     bru_ready_i,
    output reg  [PHYS_REG_BITS-1:0] bru_prd_o,
    output reg  [DATA_WIDTH-1:0]    bru_data_o,
    output reg  [ROB_IDX_BITS-1:0]  bru_rob_idx_o,
    output wire                     bru_exception_o,
    output wire [3:0]               bru_exc_code_o,
    output reg                      bru_taken_o,
    output reg  [DATA_WIDTH-1:0]    bru_target_o,
    output reg                      bru_mispredict_o,
    
    // Clock gating status
    output wire [4:0]               unit_active_o
);

    // Function unit type encoding (must match decode_4way.v)
    localparam FU_ALU = 3'd0;
    localparam FU_MUL = 3'd1;
    localparam FU_DIV = 3'd2;
    localparam FU_LSU = 3'd3;  // Load/Store Unit - handled separately in cpu_core
    localparam FU_BRU = 3'd4;  // Branch Unit

    //=========================================================
    // Issue Routing Logic
    //=========================================================
    // Route issue ports to execution units based on fu_type
    wire alu0_issue_valid, alu1_issue_valid, mul_issue_valid, div_issue_valid, bru_issue_valid;
    wire [4:0]               alu0_op, alu1_op, mul_op, div_op, bru_op;
    wire [DATA_WIDTH-1:0]    alu0_rs1, alu0_rs2, alu1_rs1, alu1_rs2;
    wire [DATA_WIDTH-1:0]    mul_rs1, mul_rs2, div_rs1, div_rs2;
    wire [DATA_WIDTH-1:0]    bru_rs1, bru_rs2, bru_pc, bru_imm;
    wire [DATA_WIDTH-1:0]    alu0_imm, alu0_pc, alu1_imm, alu1_pc;
    wire [PHYS_REG_BITS-1:0] alu0_prd_in, alu1_prd_in, mul_prd_in, div_prd_in, bru_prd_in;
    wire [ROB_IDX_BITS-1:0]  alu0_rob_in, alu1_rob_in, mul_rob_in, div_rob_in, bru_rob_in;
    wire                     alu0_use_imm, alu1_use_imm;
    wire                     bru_predict_in;
    wire [DATA_WIDTH-1:0]    bru_target_in;
    
    // ALU0 can accept from port 0, 1, or 3 (priority: 0 > 1 > 3)
    wire alu0_from_p0 = issue0_valid_i && (issue0_fu_type_i == FU_ALU);
    wire alu0_from_p1 = issue1_valid_i && (issue1_fu_type_i == FU_ALU) && !alu0_from_p0;
    wire alu0_from_p3 = issue3_valid_i && (issue3_fu_type_i == FU_ALU) && !alu0_from_p0 && !alu0_from_p1;
    
    assign alu0_issue_valid = alu0_from_p0 || alu0_from_p1 || alu0_from_p3;
    assign alu0_op      = alu0_from_p0 ? issue0_op_i      : (alu0_from_p1 ? issue1_op_i      : issue3_op_i);
    assign alu0_rs1     = alu0_from_p0 ? issue0_rs1_data_i: (alu0_from_p1 ? issue1_rs1_data_i: issue3_rs1_data_i);
    assign alu0_rs2     = alu0_from_p0 ? issue0_rs2_data_i: (alu0_from_p1 ? issue1_rs2_data_i: issue3_rs2_data_i);
    assign alu0_imm     = alu0_from_p0 ? issue0_imm_i     : (alu0_from_p1 ? issue1_imm_i     : issue3_imm_i);
    assign alu0_pc      = alu0_from_p0 ? issue0_pc_i      : (alu0_from_p1 ? issue1_pc_i      : issue3_pc_i);
    assign alu0_prd_in  = alu0_from_p0 ? issue0_prd_i     : (alu0_from_p1 ? issue1_prd_i     : issue3_prd_i);
    assign alu0_rob_in  = alu0_from_p0 ? issue0_rob_idx_i : (alu0_from_p1 ? issue1_rob_idx_i : issue3_rob_idx_i);
    assign alu0_use_imm = alu0_from_p0 ? issue0_use_imm_i : (alu0_from_p1 ? issue1_use_imm_i : issue3_use_imm_i);
    
    // ALU1 can accept from port 1, 2, or 3 (priority: 1 > 2 > 3)
    wire alu1_from_p1 = issue1_valid_i && (issue1_fu_type_i == FU_ALU) && !alu0_from_p1;
    wire alu1_from_p2 = issue2_valid_i && (issue2_fu_type_i == FU_ALU) && !alu1_from_p1;
    wire alu1_from_p3 = issue3_valid_i && (issue3_fu_type_i == FU_ALU) && !alu0_from_p3 && !alu1_from_p1 && !alu1_from_p2;
    
    assign alu1_issue_valid = alu1_from_p1 || alu1_from_p2 || alu1_from_p3;
    assign alu1_op      = alu1_from_p1 ? issue1_op_i      : (alu1_from_p2 ? issue2_op_i      : issue3_op_i);
    assign alu1_rs1     = alu1_from_p1 ? issue1_rs1_data_i: (alu1_from_p2 ? issue2_rs1_data_i: issue3_rs1_data_i);
    assign alu1_rs2     = alu1_from_p1 ? issue1_rs2_data_i: (alu1_from_p2 ? issue2_rs2_data_i: issue3_rs2_data_i);
    assign alu1_imm     = alu1_from_p1 ? issue1_imm_i     : (alu1_from_p2 ? issue2_imm_i     : issue3_imm_i);
    assign alu1_pc      = alu1_from_p1 ? issue1_pc_i      : (alu1_from_p2 ? issue2_pc_i      : issue3_pc_i);
    assign alu1_prd_in  = alu1_from_p1 ? issue1_prd_i     : (alu1_from_p2 ? issue2_prd_i     : issue3_prd_i);
    assign alu1_rob_in  = alu1_from_p1 ? issue1_rob_idx_i : (alu1_from_p2 ? issue2_rob_idx_i : issue3_rob_idx_i);
    assign alu1_use_imm = alu1_from_p1 ? issue1_use_imm_i : (alu1_from_p2 ? issue2_use_imm_i : issue3_use_imm_i);
    
    // MUL can accept from port 0 or 1
    wire mul_from_p0 = issue0_valid_i && (issue0_fu_type_i == FU_MUL);
    wire mul_from_p1 = issue1_valid_i && (issue1_fu_type_i == FU_MUL) && !mul_from_p0;
    
    assign mul_issue_valid = mul_from_p0 || mul_from_p1;
    assign mul_op      = mul_from_p0 ? issue0_op_i      : issue1_op_i;
    assign mul_rs1     = mul_from_p0 ? issue0_rs1_data_i: issue1_rs1_data_i;
    assign mul_rs2     = mul_from_p0 ? issue0_rs2_data_i: issue1_rs2_data_i;
    assign mul_prd_in  = mul_from_p0 ? issue0_prd_i     : issue1_prd_i;
    assign mul_rob_in  = mul_from_p0 ? issue0_rob_idx_i : issue1_rob_idx_i;
    
    // DIV can accept from port 0 or 2
    wire div_from_p0 = issue0_valid_i && (issue0_fu_type_i == FU_DIV);
    wire div_from_p2 = issue2_valid_i && (issue2_fu_type_i == FU_DIV) && !div_from_p0;
    
    assign div_issue_valid = div_from_p0 || div_from_p2;
    assign div_op      = div_from_p0 ? issue0_op_i      : issue2_op_i;
    assign div_rs1     = div_from_p0 ? issue0_rs1_data_i: issue2_rs1_data_i;
    assign div_rs2     = div_from_p0 ? issue0_rs2_data_i: issue2_rs2_data_i;
    assign div_prd_in  = div_from_p0 ? issue0_prd_i     : issue2_prd_i;
    assign div_rob_in  = div_from_p0 ? issue0_rob_idx_i : issue2_rob_idx_i;
    
    // BRU can accept from port 0 or 3
    wire bru_from_p0 = issue0_valid_i && (issue0_fu_type_i == FU_BRU);
    wire bru_from_p3 = issue3_valid_i && (issue3_fu_type_i == FU_BRU) && !bru_from_p0;
    
    assign bru_issue_valid = bru_from_p0 || bru_from_p3;
    assign bru_op         = bru_from_p0 ? issue0_op_i         : issue3_op_i;
    assign bru_rs1        = bru_from_p0 ? issue0_rs1_data_i   : issue3_rs1_data_i;
    assign bru_rs2        = bru_from_p0 ? issue0_rs2_data_i   : issue3_rs2_data_i;
    assign bru_pc         = bru_from_p0 ? issue0_pc_i         : issue3_pc_i;
    assign bru_imm        = bru_from_p0 ? issue0_imm_i        : issue3_imm_i;
    assign bru_prd_in     = bru_from_p0 ? issue0_prd_i        : issue3_prd_i;
    assign bru_rob_in     = bru_from_p0 ? issue0_rob_idx_i    : issue3_rob_idx_i;
    assign bru_predict_in = bru_from_p0 ? issue0_br_predict_i : issue3_br_predict_i;
    assign bru_target_in  = bru_from_p0 ? issue0_br_target_i  : issue3_br_target_i;
    
    // Ready signals back to issue queue
    assign issue0_ready_o = (issue0_fu_type_i == FU_ALU) ? alu0_ready_i :
                            (issue0_fu_type_i == FU_MUL) ? mul_ready_i :
                            (issue0_fu_type_i == FU_DIV) ? div_ready_i :
                            (issue0_fu_type_i == FU_BRU) ? bru_ready_i : 1'b0;
                            
    assign issue1_ready_o = (issue1_fu_type_i == FU_ALU) ? (alu0_ready_i || alu1_ready_i) :
                            (issue1_fu_type_i == FU_MUL) ? mul_ready_i : 1'b0;
                            
    assign issue2_ready_o = (issue2_fu_type_i == FU_ALU) ? alu1_ready_i :
                            (issue2_fu_type_i == FU_DIV) ? div_ready_i : 1'b0;
                            
    assign issue3_ready_o = (issue3_fu_type_i == FU_ALU) ? (alu0_ready_i || alu1_ready_i) :
                            (issue3_fu_type_i == FU_BRU) ? bru_ready_i : 1'b0;

    //=========================================================
    // Clock Gating for Power Optimization
    //=========================================================
    wire clk_alu0, clk_alu1, clk_mul, clk_div, clk_bru;
    
    // Clock enable signals based on activity
    reg alu0_active, alu1_active, mul_active, div_active, bru_active;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu0_active <= 0;
            alu1_active <= 0;
            mul_active <= 0;
            div_active <= 0;
            bru_active <= 0;
        end else begin
            alu0_active <= alu0_issue_valid || alu0_valid_o;
            alu1_active <= alu1_issue_valid || alu1_valid_o;
            mul_active <= mul_issue_valid || mul_valid_o || |mul_pipe_valid;
            div_active <= div_issue_valid || div_valid_o || div_busy;
            bru_active <= bru_issue_valid || bru_valid_o;
        end
    end
    
    assign unit_active_o = {bru_active, div_active, mul_active, alu1_active, alu0_active};
    
    // ICG cells (Integrated Clock Gating)
    `ifdef USE_CLOCK_GATING
    icg_cell u_icg_alu0 (.clk_i(clk), .en_i(alu0_active || alu0_issue_valid), .clk_o(clk_alu0));
    icg_cell u_icg_alu1 (.clk_i(clk), .en_i(alu1_active || alu1_issue_valid), .clk_o(clk_alu1));
    icg_cell u_icg_mul  (.clk_i(clk), .en_i(mul_active  || mul_issue_valid),  .clk_o(clk_mul));
    icg_cell u_icg_div  (.clk_i(clk), .en_i(div_active  || div_issue_valid),  .clk_o(clk_div));
    icg_cell u_icg_bru  (.clk_i(clk), .en_i(bru_active  || bru_issue_valid),  .clk_o(clk_bru));
    `else
    assign clk_alu0 = clk;
    assign clk_alu1 = clk;
    assign clk_mul  = clk;
    assign clk_div  = clk;
    assign clk_bru  = clk;
    `endif

    //=========================================================
    // ALU 0 - Single Cycle
    //=========================================================
    wire [DATA_WIDTH-1:0] alu0_operand2 = alu0_use_imm ? alu0_imm : alu0_rs2;
    wire [DATA_WIDTH-1:0] alu0_result;
    
    alu_core u_alu0 (
        .op_i       (alu0_op),
        .rs1_data_i (alu0_rs1),
        .rs2_data_i (alu0_operand2),
        .pc_i       (alu0_pc),
        .result_o   (alu0_result)
    );
    
    always @(posedge clk_alu0 or negedge rst_n) begin
        if (!rst_n) begin
            alu0_valid_o <= 0;
            alu0_prd_o <= 0;
            alu0_data_o <= 0;
            alu0_rob_idx_o <= 0;
        end else if (flush_i) begin
            alu0_valid_o <= 0;
        end else begin
            alu0_valid_o <= alu0_issue_valid;
            alu0_prd_o <= alu0_prd_in;
            alu0_data_o <= alu0_result;
            alu0_rob_idx_o <= alu0_rob_in;
        end
    end
    
    assign alu0_exception_o = 1'b0;
    assign alu0_exc_code_o = 4'd0;

    //=========================================================
    // ALU 1 - Single Cycle
    //=========================================================
    wire [DATA_WIDTH-1:0] alu1_operand2 = alu1_use_imm ? alu1_imm : alu1_rs2;
    wire [DATA_WIDTH-1:0] alu1_result;
    
    alu_core u_alu1 (
        .op_i       (alu1_op),
        .rs1_data_i (alu1_rs1),
        .rs2_data_i (alu1_operand2),
        .pc_i       (alu1_pc),
        .result_o   (alu1_result)
    );
    
    always @(posedge clk_alu1 or negedge rst_n) begin
        if (!rst_n) begin
            alu1_valid_o <= 0;
            alu1_prd_o <= 0;
            alu1_data_o <= 0;
            alu1_rob_idx_o <= 0;
        end else if (flush_i) begin
            alu1_valid_o <= 0;
        end else begin
            alu1_valid_o <= alu1_issue_valid;
            alu1_prd_o <= alu1_prd_in;
            alu1_data_o <= alu1_result;
            alu1_rob_idx_o <= alu1_rob_in;
        end
    end
    
    assign alu1_exception_o = 1'b0;
    assign alu1_exc_code_o = 4'd0;

    //=========================================================
    // MUL Unit - 3-stage pipeline
    //=========================================================
    reg [2:0] mul_pipe_valid;
    reg [PHYS_REG_BITS-1:0] mul_pipe_prd [0:2];
    reg [ROB_IDX_BITS-1:0] mul_pipe_rob [0:2];
    
    // Pipeline stage 1: operand preparation
    reg signed [DATA_WIDTH-1:0] mul_a_s1, mul_b_s1;
    reg [1:0] mul_type_s1;  // 0:MUL, 1:MULH, 2:MULHSU, 3:MULHU
    
    // Pipeline stage 2: partial products
    reg signed [63:0] mul_product_s2;
    reg [1:0] mul_type_s2;
    
    // Pipeline stage 3: result selection
    reg [DATA_WIDTH-1:0] mul_result_s3;
    
    always @(posedge clk_mul or negedge rst_n) begin
        if (!rst_n) begin
            mul_pipe_valid <= 0;
            mul_valid_o <= 0;
        end else if (flush_i) begin
            mul_pipe_valid <= 0;
            mul_valid_o <= 0;
        end else begin
            // Stage 1
            mul_pipe_valid[0] <= mul_issue_valid;
            mul_pipe_prd[0] <= mul_prd_in;
            mul_pipe_rob[0] <= mul_rob_in;
            
            if (mul_issue_valid) begin
                mul_a_s1 <= mul_rs1;
                mul_b_s1 <= mul_rs2;
                mul_type_s1 <= mul_op[1:0];  // Extract mul type from opcode
            end
            
            // Stage 2
            mul_pipe_valid[1] <= mul_pipe_valid[0];
            mul_pipe_prd[1] <= mul_pipe_prd[0];
            mul_pipe_rob[1] <= mul_pipe_rob[0];
            mul_type_s2 <= mul_type_s1;
            
            case (mul_type_s1)
                2'b00: mul_product_s2 <= $signed(mul_a_s1) * $signed(mul_b_s1);           // MUL
                2'b01: mul_product_s2 <= $signed(mul_a_s1) * $signed(mul_b_s1);           // MULH
                2'b10: mul_product_s2 <= $signed(mul_a_s1) * $signed({1'b0, mul_b_s1});   // MULHSU
                2'b11: mul_product_s2 <= {1'b0, mul_a_s1} * {1'b0, mul_b_s1};             // MULHU
            endcase
            
            // Stage 3
            mul_pipe_valid[2] <= mul_pipe_valid[1];
            mul_pipe_prd[2] <= mul_pipe_prd[1];
            mul_pipe_rob[2] <= mul_pipe_rob[1];
            
            case (mul_type_s2)
                2'b00: mul_result_s3 <= mul_product_s2[31:0];   // MUL: lower 32 bits
                default: mul_result_s3 <= mul_product_s2[63:32]; // MULH*: upper 32 bits
            endcase
            
            // Output
            mul_valid_o <= mul_pipe_valid[2];
            mul_prd_o <= mul_pipe_prd[2];
            mul_data_o <= mul_result_s3;
            mul_rob_idx_o <= mul_pipe_rob[2];
        end
    end
    
    assign mul_exception_o = 1'b0;
    assign mul_exc_code_o = 4'd0;

    //=========================================================
    // DIV Unit - Radix-4 SRT Division (16-34 cycles)
    //=========================================================
    reg div_busy;
    reg [5:0] div_cycle;
    reg [DATA_WIDTH-1:0] div_dividend, div_divisor;
    reg [DATA_WIDTH-1:0] div_quotient, div_remainder;
    reg [PHYS_REG_BITS-1:0] div_prd_reg;
    reg [ROB_IDX_BITS-1:0] div_rob_reg;
    reg div_is_rem;
    reg div_signed;
    reg div_neg_result;
    
    always @(posedge clk_div or negedge rst_n) begin
        if (!rst_n) begin
            div_busy <= 0;
            div_valid_o <= 0;
            div_cycle <= 0;
        end else if (flush_i) begin
            div_busy <= 0;
            div_valid_o <= 0;
            div_cycle <= 0;
        end else begin
            div_valid_o <= 0;
            
            if (!div_busy && div_issue_valid) begin
                // Start division
                div_busy <= 1;
                div_cycle <= 0;
                div_prd_reg <= div_prd_in;
                div_rob_reg <= div_rob_in;
                div_is_rem <= div_op[1];  // REM/REMU
                div_signed <= ~div_op[0]; // DIV/REM (signed)
                
                // Handle signs
                if (~div_op[0]) begin  // Signed
                    div_dividend <= div_rs1[31] ? (~div_rs1 + 1) : div_rs1;
                    div_divisor <= div_rs2[31] ? (~div_rs2 + 1) : div_rs2;
                    div_neg_result <= div_op[1] ? div_rs1[31] : (div_rs1[31] ^ div_rs2[31]);
                end else begin  // Unsigned
                    div_dividend <= div_rs1;
                    div_divisor <= div_rs2;
                    div_neg_result <= 0;
                end
                
                div_quotient <= 0;
                div_remainder <= 0;
            end else if (div_busy) begin
                div_cycle <= div_cycle + 1;
                
                // Simple restoring division (1 bit per cycle)
                if (div_cycle < 32) begin
                    div_remainder <= {div_remainder[30:0], div_dividend[31-div_cycle]};
                    if ({div_remainder[30:0], div_dividend[31-div_cycle]} >= div_divisor) begin
                        div_quotient[31-div_cycle] <= 1;
                        div_remainder <= {div_remainder[30:0], div_dividend[31-div_cycle]} - div_divisor;
                    end
                end else begin
                    // Division complete
                    div_busy <= 0;
                    div_valid_o <= 1;
                    div_prd_o <= div_prd_reg;
                    div_rob_idx_o <= div_rob_reg;
                    
                    if (div_is_rem)
                        div_data_o <= div_neg_result ? (~div_remainder + 1) : div_remainder;
                    else
                        div_data_o <= div_neg_result ? (~div_quotient + 1) : div_quotient;
                end
            end
        end
    end
    
    assign div_exception_o = 1'b0;  // Division by zero handled in software
    assign div_exc_code_o = 4'd0;

    //=========================================================
    // BRU - Branch Resolution Unit
    //=========================================================
    // Combinational logic for branch resolution
    wire bru_is_jump = bru_op[3];  // JAL/JALR have bit[3]=1
    wire bru_is_jalr = bru_op[3] && bru_op[0];  // JALR has bit[0]=1
    
    // Branch condition evaluation (combinational)
    reg bru_cond_taken;
    always @(*) begin
        case (bru_op[2:0])
            3'b000: bru_cond_taken = (bru_rs1 == bru_rs2);           // BEQ
            3'b001: bru_cond_taken = (bru_rs1 != bru_rs2);           // BNE
            3'b100: bru_cond_taken = ($signed(bru_rs1) < $signed(bru_rs2));  // BLT
            3'b101: bru_cond_taken = ($signed(bru_rs1) >= $signed(bru_rs2)); // BGE
            3'b110: bru_cond_taken = (bru_rs1 < bru_rs2);            // BLTU
            3'b111: bru_cond_taken = (bru_rs1 >= bru_rs2);           // BGEU
            default: bru_cond_taken = 1'b0;
        endcase
    end
    
    // Final taken and target (combinational)
    wire bru_taken_comb = bru_is_jump ? 1'b1 : bru_cond_taken;
    wire [DATA_WIDTH-1:0] bru_target_comb = bru_is_jalr ? ((bru_rs1 + bru_imm) & ~32'h1) :
                                                           (bru_pc + bru_imm);
    wire [DATA_WIDTH-1:0] bru_data_comb = bru_is_jump ? (bru_pc + 4) : 32'd0;
    
    // Mispredict detection (combinational)
    wire bru_mispredict_comb = (bru_taken_comb != bru_predict_in) ||
                               (bru_taken_comb && (bru_target_comb != bru_target_in));
    
    // Sequential output register
    always @(posedge clk_bru or negedge rst_n) begin
        if (!rst_n) begin
            bru_valid_o <= 0;
            bru_taken_o <= 0;
            bru_target_o <= 0;
            bru_mispredict_o <= 0;
            bru_prd_o <= 0;
            bru_data_o <= 0;
            bru_rob_idx_o <= 0;
        end else if (flush_i) begin
            bru_valid_o <= 0;
            bru_taken_o <= 0;
            bru_mispredict_o <= 0;
        end else begin
            bru_valid_o <= bru_issue_valid;
            bru_prd_o <= bru_prd_in;
            bru_rob_idx_o <= bru_rob_in;
            
            if (bru_issue_valid) begin
                bru_taken_o <= bru_taken_comb;
                bru_target_o <= bru_target_comb;
                bru_data_o <= bru_data_comb;
                bru_mispredict_o <= bru_mispredict_comb;
            end
        end
    end
    
    assign bru_exception_o = 1'b0;
    assign bru_exc_code_o = 4'd0;

endmodule

//=================================================================
// ALU Core - Combinational ALU
//=================================================================
module alu_core (
    input  wire [4:0]  op_i,
    input  wire [31:0] rs1_data_i,
    input  wire [31:0] rs2_data_i,
    input  wire [31:0] pc_i,
    output reg  [31:0] result_o
);

    wire [4:0] shamt = rs2_data_i[4:0];
    
    always @(*) begin
        case (op_i)
            5'b00000: result_o = rs1_data_i + rs2_data_i;                    // ADD
            5'b00001: result_o = rs1_data_i - rs2_data_i;                    // SUB
            5'b00010: result_o = rs1_data_i << shamt;                        // SLL
            5'b00011: result_o = ($signed(rs1_data_i) < $signed(rs2_data_i)) ? 32'd1 : 32'd0; // SLT
            5'b00100: result_o = (rs1_data_i < rs2_data_i) ? 32'd1 : 32'd0;  // SLTU
            5'b00101: result_o = rs1_data_i ^ rs2_data_i;                    // XOR
            5'b00110: result_o = rs1_data_i >> shamt;                        // SRL
            5'b00111: result_o = $signed(rs1_data_i) >>> shamt;              // SRA
            5'b01000: result_o = rs1_data_i | rs2_data_i;                    // OR
            5'b01001: result_o = rs1_data_i & rs2_data_i;                    // AND
            5'b01010: result_o = rs2_data_i;                                 // LUI (pass imm)
            5'b01011: result_o = pc_i + rs2_data_i;                          // AUIPC
            default:  result_o = 32'd0;
        endcase
    end

endmodule

//=================================================================
// ICG Cell - Integrated Clock Gating (for synthesis)
//=================================================================
module icg_cell (
    input  wire clk_i,
    input  wire en_i,
    output wire clk_o
);
    reg en_latch;
    
    // Latch enable on falling edge to avoid glitches
    always @(clk_i or en_i) begin
        if (!clk_i)
            en_latch <= en_i;
    end
    
    assign clk_o = clk_i & en_latch;
    
endmodule
