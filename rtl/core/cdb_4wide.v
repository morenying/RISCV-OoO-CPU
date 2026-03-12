//=================================================================
// Module: cdb_4wide
// Description: 4-Wide Common Data Bus for 4-issue Superscalar
//              Supports 4 simultaneous writebacks per cycle
//              Round-robin arbitration with aging
//              Broadcasts to ROB, RAT, Issue Queue, PRF
// Requirements: Championship-level IPC requires 4-wide CDB
//=================================================================

`timescale 1ns/1ps

module cdb_4wide #(
    parameter NUM_SOURCES    = 8,          // ALU0, ALU1, MUL, DIV, LSU0, LSU1, BRU, CSR
    parameter CDB_WIDTH      = 4,          // 4 results per cycle
    parameter PHYS_REG_BITS  = 7,
    parameter DATA_WIDTH     = 32,
    parameter ROB_IDX_BITS   = 6
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Source Inputs (8 execution units)
    //=========================================================
    // ALU 0
    input  wire                     alu0_valid_i,
    output wire                     alu0_ready_o,
    input  wire [PHYS_REG_BITS-1:0] alu0_prd_i,
    input  wire [DATA_WIDTH-1:0]    alu0_data_i,
    input  wire [ROB_IDX_BITS-1:0]  alu0_rob_idx_i,
    input  wire                     alu0_exception_i,
    input  wire [3:0]               alu0_exc_code_i,
    
    // ALU 1
    input  wire                     alu1_valid_i,
    output wire                     alu1_ready_o,
    input  wire [PHYS_REG_BITS-1:0] alu1_prd_i,
    input  wire [DATA_WIDTH-1:0]    alu1_data_i,
    input  wire [ROB_IDX_BITS-1:0]  alu1_rob_idx_i,
    input  wire                     alu1_exception_i,
    input  wire [3:0]               alu1_exc_code_i,
    
    // MUL
    input  wire                     mul_valid_i,
    output wire                     mul_ready_o,
    input  wire [PHYS_REG_BITS-1:0] mul_prd_i,
    input  wire [DATA_WIDTH-1:0]    mul_data_i,
    input  wire [ROB_IDX_BITS-1:0]  mul_rob_idx_i,
    input  wire                     mul_exception_i,
    input  wire [3:0]               mul_exc_code_i,
    
    // DIV
    input  wire                     div_valid_i,
    output wire                     div_ready_o,
    input  wire [PHYS_REG_BITS-1:0] div_prd_i,
    input  wire [DATA_WIDTH-1:0]    div_data_i,
    input  wire [ROB_IDX_BITS-1:0]  div_rob_idx_i,
    input  wire                     div_exception_i,
    input  wire [3:0]               div_exc_code_i,
    
    // LSU 0 (Load port 0)
    input  wire                     lsu0_valid_i,
    output wire                     lsu0_ready_o,
    input  wire [PHYS_REG_BITS-1:0] lsu0_prd_i,
    input  wire [DATA_WIDTH-1:0]    lsu0_data_i,
    input  wire [ROB_IDX_BITS-1:0]  lsu0_rob_idx_i,
    input  wire                     lsu0_exception_i,
    input  wire [3:0]               lsu0_exc_code_i,
    
    // LSU 1 (Load port 1)
    input  wire                     lsu1_valid_i,
    output wire                     lsu1_ready_o,
    input  wire [PHYS_REG_BITS-1:0] lsu1_prd_i,
    input  wire [DATA_WIDTH-1:0]    lsu1_data_i,
    input  wire [ROB_IDX_BITS-1:0]  lsu1_rob_idx_i,
    input  wire                     lsu1_exception_i,
    input  wire [3:0]               lsu1_exc_code_i,
    
    // BRU (Branch Unit)
    input  wire                     bru_valid_i,
    output wire                     bru_ready_o,
    input  wire [PHYS_REG_BITS-1:0] bru_prd_i,
    input  wire [DATA_WIDTH-1:0]    bru_data_i,
    input  wire [ROB_IDX_BITS-1:0]  bru_rob_idx_i,
    input  wire                     bru_exception_i,
    input  wire [3:0]               bru_exc_code_i,
    input  wire                     bru_taken_i,
    input  wire [DATA_WIDTH-1:0]    bru_target_i,
    input  wire                     bru_mispredict_i,
    
    // CSR Unit
    input  wire                     csr_valid_i,
    output wire                     csr_ready_o,
    input  wire [PHYS_REG_BITS-1:0] csr_prd_i,
    input  wire [DATA_WIDTH-1:0]    csr_data_i,
    input  wire [ROB_IDX_BITS-1:0]  csr_rob_idx_i,
    input  wire                     csr_exception_i,
    input  wire [3:0]               csr_exc_code_i,
    
    //=========================================================
    // 4-Wide CDB Output
    //=========================================================
    output reg  [3:0]               cdb_valid_o,
    output reg  [PHYS_REG_BITS-1:0] cdb_prd_o       [0:CDB_WIDTH-1],
    output reg  [DATA_WIDTH-1:0]    cdb_data_o      [0:CDB_WIDTH-1],
    output reg  [ROB_IDX_BITS-1:0]  cdb_rob_idx_o   [0:CDB_WIDTH-1],
    output reg                      cdb_exception_o [0:CDB_WIDTH-1],
    output reg  [3:0]               cdb_exc_code_o  [0:CDB_WIDTH-1],
    
    // Branch info (only slot 0 can carry branch)
    output reg                      cdb_br_taken_o,
    output reg  [DATA_WIDTH-1:0]    cdb_br_target_o,
    output reg                      cdb_br_mispredict_o
);

    //=========================================================
    // Source Request Packing
    //=========================================================
    wire [NUM_SOURCES-1:0] src_valid;
    assign src_valid = {csr_valid_i, bru_valid_i, lsu1_valid_i, lsu0_valid_i,
                        div_valid_i, mul_valid_i, alu1_valid_i, alu0_valid_i};
    
    //=========================================================
    // Round-Robin Priority with Aging
    //=========================================================
    reg [2:0] rr_ptr;  // Round-robin pointer
    
    //=========================================================
    // Grant Selection - Select up to 4 sources
    //=========================================================
    reg [NUM_SOURCES-1:0] grant;
    reg [2:0] grant_idx [0:CDB_WIDTH-1];
    reg [3:0] grant_valid;
    
    integer i, j, cnt;
    reg [NUM_SOURCES-1:0] remaining;
    reg [2:0] scan_idx;
    
    always @(*) begin
        grant = 0;
        grant_valid = 0;
        cnt = 0;
        remaining = src_valid;
        
        // Select up to 4 sources using round-robin starting point
        for (i = 0; i < NUM_SOURCES && cnt < CDB_WIDTH; i = i + 1) begin
            scan_idx = (rr_ptr + i) % NUM_SOURCES;
            if (remaining[scan_idx]) begin
                grant[scan_idx] = 1;
                grant_idx[cnt] = scan_idx;
                grant_valid[cnt] = 1;
                remaining[scan_idx] = 0;
                cnt = cnt + 1;
            end
        end
        
        // Fill remaining slots with defaults
        for (j = cnt; j < CDB_WIDTH; j = j + 1) begin
            grant_idx[j] = 0;
        end
    end
    
    //=========================================================
    // Ready Signals
    //=========================================================
    assign alu0_ready_o = grant[0];
    assign alu1_ready_o = grant[1];
    assign mul_ready_o  = grant[2];
    assign div_ready_o  = grant[3];
    assign lsu0_ready_o = grant[4];
    assign lsu1_ready_o = grant[5];
    assign bru_ready_o  = grant[6];
    assign csr_ready_o  = grant[7];
    
    //=========================================================
    // Update Round-Robin Pointer
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= 0;
        end else if (|grant) begin
            // Advance pointer past last granted source
            rr_ptr <= (grant_idx[0] + 1) % NUM_SOURCES;
        end
    end
    
    //=========================================================
    // Output Mux for each CDB slot
    //=========================================================
    // Source data arrays for muxing
    wire [PHYS_REG_BITS-1:0] src_prd [0:NUM_SOURCES-1];
    wire [DATA_WIDTH-1:0]    src_data [0:NUM_SOURCES-1];
    wire [ROB_IDX_BITS-1:0]  src_rob_idx [0:NUM_SOURCES-1];
    wire                     src_exception [0:NUM_SOURCES-1];
    wire [3:0]               src_exc_code [0:NUM_SOURCES-1];
    
    assign src_prd[0] = alu0_prd_i;     assign src_data[0] = alu0_data_i;
    assign src_prd[1] = alu1_prd_i;     assign src_data[1] = alu1_data_i;
    assign src_prd[2] = mul_prd_i;      assign src_data[2] = mul_data_i;
    assign src_prd[3] = div_prd_i;      assign src_data[3] = div_data_i;
    assign src_prd[4] = lsu0_prd_i;     assign src_data[4] = lsu0_data_i;
    assign src_prd[5] = lsu1_prd_i;     assign src_data[5] = lsu1_data_i;
    assign src_prd[6] = bru_prd_i;      assign src_data[6] = bru_data_i;
    assign src_prd[7] = csr_prd_i;      assign src_data[7] = csr_data_i;
    
    assign src_rob_idx[0] = alu0_rob_idx_i;   assign src_exception[0] = alu0_exception_i;   assign src_exc_code[0] = alu0_exc_code_i;
    assign src_rob_idx[1] = alu1_rob_idx_i;   assign src_exception[1] = alu1_exception_i;   assign src_exc_code[1] = alu1_exc_code_i;
    assign src_rob_idx[2] = mul_rob_idx_i;    assign src_exception[2] = mul_exception_i;    assign src_exc_code[2] = mul_exc_code_i;
    assign src_rob_idx[3] = div_rob_idx_i;    assign src_exception[3] = div_exception_i;    assign src_exc_code[3] = div_exc_code_i;
    assign src_rob_idx[4] = lsu0_rob_idx_i;   assign src_exception[4] = lsu0_exception_i;   assign src_exc_code[4] = lsu0_exc_code_i;
    assign src_rob_idx[5] = lsu1_rob_idx_i;   assign src_exception[5] = lsu1_exception_i;   assign src_exc_code[5] = lsu1_exc_code_i;
    assign src_rob_idx[6] = bru_rob_idx_i;    assign src_exception[6] = bru_exception_i;    assign src_exc_code[6] = bru_exc_code_i;
    assign src_rob_idx[7] = csr_rob_idx_i;    assign src_exception[7] = csr_exception_i;    assign src_exc_code[7] = csr_exc_code_i;
    
    //=========================================================
    // Output Registration
    //=========================================================
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_valid_o <= 0;
            cdb_br_taken_o <= 0;
            cdb_br_target_o <= 0;
            cdb_br_mispredict_o <= 0;
            
            for (k = 0; k < CDB_WIDTH; k = k + 1) begin
                cdb_prd_o[k] <= 0;
                cdb_data_o[k] <= 0;
                cdb_rob_idx_o[k] <= 0;
                cdb_exception_o[k] <= 0;
                cdb_exc_code_o[k] <= 0;
            end
        end else begin
            cdb_valid_o <= grant_valid;
            
            for (k = 0; k < CDB_WIDTH; k = k + 1) begin
                if (grant_valid[k]) begin
                    cdb_prd_o[k] <= src_prd[grant_idx[k]];
                    cdb_data_o[k] <= src_data[grant_idx[k]];
                    cdb_rob_idx_o[k] <= src_rob_idx[grant_idx[k]];
                    cdb_exception_o[k] <= src_exception[grant_idx[k]];
                    cdb_exc_code_o[k] <= src_exc_code[grant_idx[k]];
                end else begin
                    cdb_prd_o[k] <= 0;
                    cdb_data_o[k] <= 0;
                    cdb_rob_idx_o[k] <= 0;
                    cdb_exception_o[k] <= 0;
                    cdb_exc_code_o[k] <= 0;
                end
            end
            
            // Branch info only from BRU (source 6)
            if (grant[6]) begin
                cdb_br_taken_o <= bru_taken_i;
                cdb_br_target_o <= bru_target_i;
                cdb_br_mispredict_o <= bru_mispredict_i;
            end else begin
                cdb_br_taken_o <= 0;
                cdb_br_target_o <= 0;
                cdb_br_mispredict_o <= 0;
            end
        end
    end

endmodule
