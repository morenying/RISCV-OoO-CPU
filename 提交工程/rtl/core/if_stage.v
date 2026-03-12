//=================================================================
// Module: if_stage
// Description: Instruction Fetch Stage
//              PC register management
//              I-Cache interface
//              BPU interface
//              IF/ID pipeline register
// Requirements: 2.1, 2.2
//=================================================================

`timescale 1ns/1ps

module if_stage #(
    parameter XLEN = 32,
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Pipeline control
    input  wire                    stall_i,
    input  wire                    flush_i,
    
    // PC redirect
    input  wire                    redirect_valid_i,
    input  wire [XLEN-1:0]         redirect_pc_i,
    
    // I-Cache interface
    output wire                    icache_req_valid_o,
    output wire [XLEN-1:0]         icache_req_addr_o,
    input  wire                    icache_req_ready_i,
    input  wire                    icache_resp_valid_i,
    input  wire [XLEN-1:0]         icache_resp_data_i,
    
    // BPU interface
    output wire                    bpu_req_o,
    output wire [XLEN-1:0]         bpu_pc_o,
    input  wire                    bpu_pred_taken_i,
    input  wire [XLEN-1:0]         bpu_pred_target_i,
    input  wire [1:0]              bpu_pred_type_i,
    
    // Output to ID stage
    output reg                     id_valid_o,
    output reg  [XLEN-1:0]         id_pc_o,
    output reg  [XLEN-1:0]         id_instr_o,
    output reg                     id_pred_taken_o,
    output reg  [XLEN-1:0]         id_pred_target_o,
    output reg  [1:0]              id_pred_type_o,
    output reg  [GHR_WIDTH-1:0]    id_ghr_o,
    
    // GHR for checkpoint
    input  wire [GHR_WIDTH-1:0]    ghr_i
);

    //=========================================================
    // PC Register
    //=========================================================
    reg [XLEN-1:0] pc_reg;
    reg [XLEN-1:0] pc_next;
    
    // Reset vector
    localparam RESET_VECTOR = 32'h8000_0000;
    
    //=========================================================
    // State Machine
    //=========================================================
    localparam IDLE    = 2'b00;
    localparam FETCH   = 2'b01;
    localparam WAIT    = 2'b10;
    
    reg [1:0] state;
    reg [XLEN-1:0] fetch_pc;
    
    //=========================================================
    // Next PC Logic
    //=========================================================
    always @(*) begin
        if (redirect_valid_i) begin
            pc_next = redirect_pc_i;
        end else if (bpu_pred_taken_i) begin
            pc_next = bpu_pred_target_i;
        end else begin
            pc_next = pc_reg + 4;
        end
    end
    
    //=========================================================
    // I-Cache Request
    //=========================================================
    assign icache_req_valid_o = (state == FETCH) && !stall_i;
    assign icache_req_addr_o = fetch_pc;
    
    //=========================================================
    // BPU Request
    //=========================================================
    assign bpu_req_o = (state == IDLE) && !stall_i && !flush_i;
    assign bpu_pc_o = pc_reg;
    
    //=========================================================
    // State Machine Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pc_reg <= RESET_VECTOR;
            fetch_pc <= RESET_VECTOR;
            
            id_valid_o <= 1'b0;
            id_pc_o <= 0;
            id_instr_o <= 32'h0000_0013;  // NOP (addi x0, x0, 0)
            id_pred_taken_o <= 1'b0;
            id_pred_target_o <= 0;
            id_pred_type_o <= 2'b00;
            id_ghr_o <= 0;
        end else if (flush_i) begin
            state <= IDLE;
            pc_reg <= redirect_valid_i ? redirect_pc_i : pc_reg;
            id_valid_o <= 1'b0;
            id_instr_o <= 32'h0000_0013;  // NOP
        end else if (!stall_i) begin
            case (state)
                IDLE: begin
                    // Start fetch
                    state <= FETCH;
                    fetch_pc <= pc_reg;
                end
                
                FETCH: begin
                    if (icache_req_ready_i) begin
                        state <= WAIT;
                    end
                end
                
                WAIT: begin
                    if (icache_resp_valid_i) begin
                        // Instruction fetched
                        id_valid_o <= 1'b1;
                        id_pc_o <= fetch_pc;
                        id_instr_o <= icache_resp_data_i;
                        id_pred_taken_o <= bpu_pred_taken_i;
                        id_pred_target_o <= bpu_pred_target_i;
                        id_pred_type_o <= bpu_pred_type_i;
                        id_ghr_o <= ghr_i;
                        
                        // Update PC
                        pc_reg <= pc_next;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
