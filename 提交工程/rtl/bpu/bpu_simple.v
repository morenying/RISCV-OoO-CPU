//=================================================================
// Module: bpu_simple
// Description: Simplified BPU for fast simulation
//              Always predicts not-taken, no tables
//=================================================================

`timescale 1ns/1ps

module bpu_simple #(
    parameter GHR_WIDTH = 64
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    // Prediction interface
    input  wire                    pred_req_i,
    input  wire [31:0]             pred_pc_i,
    output wire                    pred_valid_o,
    output wire                    pred_taken_o,
    output wire [31:0]             pred_target_o,
    output wire [1:0]              pred_type_o,
    
    // Checkpoint interface
    input  wire                    checkpoint_i,
    input  wire [2:0]              checkpoint_id_i,
    
    // Recovery interface
    input  wire                    recover_i,
    input  wire [2:0]              recover_id_i,
    input  wire [GHR_WIDTH-1:0]    recover_ghr_i,
    
    // Update interface
    input  wire                    update_valid_i,
    input  wire [31:0]             update_pc_i,
    input  wire                    update_taken_i,
    input  wire [31:0]             update_target_i,
    input  wire [1:0]              update_type_i,
    input  wire                    update_mispredict_i,
    
    // GHR output
    output wire [GHR_WIDTH-1:0]    ghr_o
);

    reg [GHR_WIDTH-1:0] ghr;
    
    assign ghr_o = ghr;
    assign pred_valid_o = pred_req_i;
    assign pred_taken_o = 1'b0;  // Always predict not-taken
    assign pred_target_o = pred_pc_i + 4;  // Next sequential
    assign pred_type_o = 2'b00;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ghr <= {GHR_WIDTH{1'b0}};
        else if (recover_i)
            ghr <= recover_ghr_i;
        else if (update_valid_i && update_type_i == 2'b00)
            ghr <= {ghr[GHR_WIDTH-2:0], update_taken_i};
    end

endmodule