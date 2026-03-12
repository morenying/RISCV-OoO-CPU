//=================================================================
// Module: cdb
// Description: Common Data Bus (CDB) Arbiter
//              6 input sources with fixed priority arbitration
//              Broadcasts results to all listeners
// Requirements: 5.1, 5.3, 11.6
//=================================================================

`timescale 1ns/1ps

module cdb #(
    parameter NUM_SOURCES   = 6,
    parameter PHYS_REG_BITS = 6,
    parameter DATA_WIDTH    = 32,
    parameter ROB_IDX_BITS  = 5
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Source 0: ALU0
    input  wire                     src0_valid_i,
    output wire                     src0_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src0_preg_i,
    input  wire [DATA_WIDTH-1:0]    src0_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src0_rob_idx_i,
    input  wire                     src0_exception_i,
    input  wire [3:0]               src0_exc_code_i,
    
    // Source 1: ALU1
    input  wire                     src1_valid_i,
    output wire                     src1_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src1_preg_i,
    input  wire [DATA_WIDTH-1:0]    src1_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src1_rob_idx_i,
    input  wire                     src1_exception_i,
    input  wire [3:0]               src1_exc_code_i,
    
    // Source 2: MUL
    input  wire                     src2_valid_i,
    output wire                     src2_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src2_preg_i,
    input  wire [DATA_WIDTH-1:0]    src2_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src2_rob_idx_i,
    input  wire                     src2_exception_i,
    input  wire [3:0]               src2_exc_code_i,
    
    // Source 3: DIV
    input  wire                     src3_valid_i,
    output wire                     src3_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src3_preg_i,
    input  wire [DATA_WIDTH-1:0]    src3_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src3_rob_idx_i,
    input  wire                     src3_exception_i,
    input  wire [3:0]               src3_exc_code_i,
    
    // Source 4: LSU
    input  wire                     src4_valid_i,
    output wire                     src4_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src4_preg_i,
    input  wire [DATA_WIDTH-1:0]    src4_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src4_rob_idx_i,
    input  wire                     src4_exception_i,
    input  wire [3:0]               src4_exc_code_i,
    
    // Source 5: BRU
    input  wire                     src5_valid_i,
    output wire                     src5_ready_o,
    input  wire [PHYS_REG_BITS-1:0] src5_preg_i,
    input  wire [DATA_WIDTH-1:0]    src5_data_i,
    input  wire [ROB_IDX_BITS-1:0]  src5_rob_idx_i,
    input  wire                     src5_exception_i,
    input  wire [3:0]               src5_exc_code_i,
    input  wire                     src5_branch_taken_i,
    input  wire [DATA_WIDTH-1:0]    src5_branch_target_i,
    
    // CDB Output (broadcast)
    output reg                      cdb_valid_o,
    output reg  [PHYS_REG_BITS-1:0] cdb_preg_o,
    output reg  [DATA_WIDTH-1:0]    cdb_data_o,
    output reg  [ROB_IDX_BITS-1:0]  cdb_rob_idx_o,
    output reg                      cdb_exception_o,
    output reg  [3:0]               cdb_exc_code_o,
    output reg                      cdb_branch_taken_o,
    output reg  [DATA_WIDTH-1:0]    cdb_branch_target_o,
    output reg  [2:0]               cdb_src_id_o
);

    //=========================================================
    // Priority Encoder (fixed priority: 0 > 1 > 2 > 3 > 4 > 5)
    //=========================================================
    reg [2:0] grant_id;
    reg       grant_valid;
    
    always @(*) begin
        grant_id = 3'd0;
        grant_valid = 1'b0;
        
        if (src0_valid_i) begin
            grant_id = 3'd0;
            grant_valid = 1'b1;
        end else if (src1_valid_i) begin
            grant_id = 3'd1;
            grant_valid = 1'b1;
        end else if (src2_valid_i) begin
            grant_id = 3'd2;
            grant_valid = 1'b1;
        end else if (src3_valid_i) begin
            grant_id = 3'd3;
            grant_valid = 1'b1;
        end else if (src4_valid_i) begin
            grant_id = 3'd4;
            grant_valid = 1'b1;
        end else if (src5_valid_i) begin
            grant_id = 3'd5;
            grant_valid = 1'b1;
        end
    end
    
    //=========================================================
    // Ready Signals (grant to winning source)
    //=========================================================
    assign src0_ready_o = (grant_id == 3'd0) && grant_valid;
    assign src1_ready_o = (grant_id == 3'd1) && grant_valid;
    assign src2_ready_o = (grant_id == 3'd2) && grant_valid;
    assign src3_ready_o = (grant_id == 3'd3) && grant_valid;
    assign src4_ready_o = (grant_id == 3'd4) && grant_valid;
    assign src5_ready_o = (grant_id == 3'd5) && grant_valid;
    
    //=========================================================
    // Output Mux and Register
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_valid_o <= 1'b0;
            cdb_preg_o <= 0;
            cdb_data_o <= 0;
            cdb_rob_idx_o <= 0;
            cdb_exception_o <= 0;
            cdb_exc_code_o <= 0;
            cdb_branch_taken_o <= 0;
            cdb_branch_target_o <= 0;
            cdb_src_id_o <= 0;
        end else begin
            cdb_valid_o <= grant_valid;
            cdb_src_id_o <= grant_id;
            
            case (grant_id)
                3'd0: begin
                    cdb_preg_o <= src0_preg_i;
                    cdb_data_o <= src0_data_i;
                    cdb_rob_idx_o <= src0_rob_idx_i;
                    cdb_exception_o <= src0_exception_i;
                    cdb_exc_code_o <= src0_exc_code_i;
                    cdb_branch_taken_o <= 1'b0;
                    cdb_branch_target_o <= 32'd0;
                end
                3'd1: begin
                    cdb_preg_o <= src1_preg_i;
                    cdb_data_o <= src1_data_i;
                    cdb_rob_idx_o <= src1_rob_idx_i;
                    cdb_exception_o <= src1_exception_i;
                    cdb_exc_code_o <= src1_exc_code_i;
                    cdb_branch_taken_o <= 1'b0;
                    cdb_branch_target_o <= 32'd0;
                end
                3'd2: begin
                    cdb_preg_o <= src2_preg_i;
                    cdb_data_o <= src2_data_i;
                    cdb_rob_idx_o <= src2_rob_idx_i;
                    cdb_exception_o <= src2_exception_i;
                    cdb_exc_code_o <= src2_exc_code_i;
                    cdb_branch_taken_o <= 1'b0;
                    cdb_branch_target_o <= 32'd0;
                end
                3'd3: begin
                    cdb_preg_o <= src3_preg_i;
                    cdb_data_o <= src3_data_i;
                    cdb_rob_idx_o <= src3_rob_idx_i;
                    cdb_exception_o <= src3_exception_i;
                    cdb_exc_code_o <= src3_exc_code_i;
                    cdb_branch_taken_o <= 1'b0;
                    cdb_branch_target_o <= 32'd0;
                end
                3'd4: begin
                    cdb_preg_o <= src4_preg_i;
                    cdb_data_o <= src4_data_i;
                    cdb_rob_idx_o <= src4_rob_idx_i;
                    cdb_exception_o <= src4_exception_i;
                    cdb_exc_code_o <= src4_exc_code_i;
                    cdb_branch_taken_o <= 1'b0;
                    cdb_branch_target_o <= 32'd0;
                end
                3'd5: begin
                    cdb_preg_o <= src5_preg_i;
                    cdb_data_o <= src5_data_i;
                    cdb_rob_idx_o <= src5_rob_idx_i;
                    cdb_exception_o <= src5_exception_i;
                    cdb_exc_code_o <= src5_exc_code_i;
                    cdb_branch_taken_o <= src5_branch_taken_i;
                    cdb_branch_target_o <= src5_branch_target_i;
                end
                default: begin
                    cdb_preg_o <= 0;
                    cdb_data_o <= 0;
                    cdb_rob_idx_o <= 0;
                    cdb_exception_o <= 0;
                    cdb_exc_code_o <= 0;
                    cdb_branch_taken_o <= 0;
                    cdb_branch_target_o <= 0;
                end
            endcase
        end
    end

endmodule
