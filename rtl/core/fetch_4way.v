//=================================================================
// Module: fetch_4way
// Description: 4-Wide Instruction Fetch Stage
//              Fetches up to 4 instructions per cycle
//              Handles branch prediction and redirects
//=================================================================

`timescale 1ns/1ps

module fetch_4way #(
    parameter XLEN         = 32,
    parameter FETCH_WIDTH  = 4,
    parameter GHR_WIDTH    = 256,
    parameter RESET_VECTOR = 32'h8000_0000
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control
    input  wire                     stall_i,
    input  wire                     flush_i,
    input  wire                     redirect_valid_i,
    input  wire [XLEN-1:0]          redirect_pc_i,
    
    // I-Cache interface
    output reg                      icache_req_valid_o,
    output reg  [XLEN-1:0]          icache_req_pc_o,
    input  wire                     icache_req_ready_i,
    input  wire                     icache_resp_valid_i,
    input  wire [FETCH_WIDTH*32-1:0] icache_resp_data_i,
    
    // BPU interface
    output wire                     bpu_req_o,
    output wire [XLEN-1:0]          bpu_pc_o,
    input  wire [FETCH_WIDTH-1:0]   bpu_pred_taken_i,
    input  wire [XLEN-1:0]          bpu_pred_target_i,
    input  wire [GHR_WIDTH-1:0]     bpu_ghr_i,
    
    // Output to decode (4 instructions)
    output reg  [FETCH_WIDTH-1:0]   valid_o,
    output reg  [XLEN-1:0]          pc_o     [0:FETCH_WIDTH-1],
    output reg  [31:0]              instr_o  [0:FETCH_WIDTH-1],
    output reg  [FETCH_WIDTH-1:0]   pred_taken_o,
    output reg  [XLEN-1:0]          pred_target_o [0:FETCH_WIDTH-1],
    output reg  [GHR_WIDTH-1:0]     ghr_o
);

    //=========================================================
    // PC Register
    //=========================================================
    reg [XLEN-1:0] pc_reg;
    reg [XLEN-1:0] next_pc;
    
    // PC increment (4 instructions = 16 bytes)
    wire [XLEN-1:0] pc_plus_16 = pc_reg + 16;
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam S_IDLE    = 2'd0;
    localparam S_WAIT    = 2'd1;
    localparam S_RESP    = 2'd2;
    
    reg [1:0] state;
    
    //=========================================================
    // Branch Prediction
    //=========================================================
    // Find first taken branch in fetch group
    wire [FETCH_WIDTH-1:0] pred_taken = bpu_pred_taken_i;
    
    wire has_taken_branch = |pred_taken;
    
    // Priority encoder for first taken branch
    reg [1:0] first_taken_idx;
    always @(*) begin
        if (pred_taken[0])      first_taken_idx = 2'd0;
        else if (pred_taken[1]) first_taken_idx = 2'd1;
        else if (pred_taken[2]) first_taken_idx = 2'd2;
        else                    first_taken_idx = 2'd3;
    end
    
    // Mask for valid instructions (before and including first taken branch)
    wire [FETCH_WIDTH-1:0] valid_mask;
    assign valid_mask[0] = 1'b1;
    assign valid_mask[1] = !pred_taken[0];
    assign valid_mask[2] = !pred_taken[0] && !pred_taken[1];
    assign valid_mask[3] = !pred_taken[0] && !pred_taken[1] && !pred_taken[2];
    
    //=========================================================
    // Next PC Calculation
    //=========================================================
    always @(*) begin
        if (redirect_valid_i) begin
            next_pc = redirect_pc_i;
        end else if (has_taken_branch) begin
            next_pc = bpu_pred_target_i;
        end else begin
            next_pc = pc_plus_16;
        end
    end
    
    //=========================================================
    // BPU Request
    //=========================================================
    assign bpu_req_o = (state == S_IDLE) && !stall_i && !flush_i;
    assign bpu_pc_o = pc_reg;
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            pc_reg <= RESET_VECTOR;
            icache_req_valid_o <= 1'b0;
            icache_req_pc_o <= RESET_VECTOR;
            valid_o <= 0;
            pred_taken_o <= 0;
            ghr_o <= 0;
        end else if (flush_i) begin
            state <= S_IDLE;
            pc_reg <= redirect_pc_i;
            icache_req_valid_o <= 1'b0;
            valid_o <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (!stall_i) begin
                        // Send I-Cache request
                        icache_req_valid_o <= 1'b1;
                        icache_req_pc_o <= pc_reg;
                        state <= S_WAIT;
                    end
                    valid_o <= 0;
                end
                
                S_WAIT: begin
                    if (icache_req_ready_i) begin
                        icache_req_valid_o <= 1'b0;
                        state <= S_RESP;
                    end
                end
                
                S_RESP: begin
                    if (icache_resp_valid_i && !stall_i) begin
                        // Output valid instructions
                        valid_o <= valid_mask;
                        pred_taken_o <= pred_taken & valid_mask;
                        ghr_o <= bpu_ghr_i;
                        
                        // Output instructions and PCs
                        pc_o[0] <= pc_reg;
                        pc_o[1] <= pc_reg + 4;
                        pc_o[2] <= pc_reg + 8;
                        pc_o[3] <= pc_reg + 12;
                        
                        instr_o[0] <= icache_resp_data_i[31:0];
                        instr_o[1] <= icache_resp_data_i[63:32];
                        instr_o[2] <= icache_resp_data_i[95:64];
                        instr_o[3] <= icache_resp_data_i[127:96];
                        
                        pred_target_o[0] <= has_taken_branch && (first_taken_idx == 0) ? bpu_pred_target_i : 0;
                        pred_target_o[1] <= has_taken_branch && (first_taken_idx == 1) ? bpu_pred_target_i : 0;
                        pred_target_o[2] <= has_taken_branch && (first_taken_idx == 2) ? bpu_pred_target_i : 0;
                        pred_target_o[3] <= has_taken_branch && (first_taken_idx == 3) ? bpu_pred_target_i : 0;
                        
                        // Update PC
                        pc_reg <= next_pc;
                        state <= S_IDLE;
                    end else if (icache_resp_valid_i && stall_i) begin
                        // Wait for stall to clear
                        valid_o <= 0;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
            
            // Handle redirect at any time
            if (redirect_valid_i) begin
                pc_reg <= redirect_pc_i;
                state <= S_IDLE;
                icache_req_valid_o <= 1'b0;
                valid_o <= 0;
            end
        end
    end

endmodule
