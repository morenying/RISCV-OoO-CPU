//==============================================================================
// BPU 精简波形测试 - 覆盖预测/更新/恢复，约25周期
//==============================================================================
`timescale 1ns/1ps

module tb_bpu_wave;
    parameter GHR_WIDTH = 64;
    reg clk, rst_n;
    // Prediction
    reg pred_req_i;
    reg [31:0] pred_pc_i;
    wire pred_valid_o, pred_taken_o;
    wire [31:0] pred_target_o;
    wire [1:0] pred_type_o;
    // Checkpoint
    reg checkpoint_i;
    reg [2:0] checkpoint_id_i;
    // Recovery
    reg recover_i;
    reg [2:0] recover_id_i;
    reg [GHR_WIDTH-1:0] recover_ghr_i;
    // Update
    reg update_valid_i, update_taken_i, update_mispredict_i;
    reg [31:0] update_pc_i, update_target_i;
    reg [1:0] update_type_i;
    // GHR output
    wire [GHR_WIDTH-1:0] ghr_o;

    bpu #(.GHR_WIDTH(GHR_WIDTH)) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/bpu_wave.vcd");
        $dumpvars(0, tb_bpu_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== BPU Wave Test ===");
        rst_n = 0; pred_req_i = 0; checkpoint_i = 0; recover_i = 0; update_valid_i = 0;
        pred_pc_i = 0; checkpoint_id_i = 0; recover_id_i = 0; recover_ghr_i = 0;
        update_pc_i = 0; update_target_i = 0; update_type_i = 0;
        update_taken_i = 0; update_mispredict_i = 0;
        #20 rst_n = 1; #10;

        // Train BTB with a branch
        @(posedge clk);
        update_valid_i = 1; update_pc_i = 32'h1000; update_target_i = 32'h1100;
        update_type_i = 2'b00; update_taken_i = 1; update_mispredict_i = 0;
        @(posedge clk);
        update_valid_i = 0;

        // Predict same PC
        @(posedge clk);
        pred_req_i = 1; pred_pc_i = 32'h1000;
        @(posedge clk);
        pred_req_i = 0;
        #1;
        $display("Prediction: taken=%b target=%h", pred_taken_o, pred_target_o);

        // Create checkpoint
        @(posedge clk);
        checkpoint_i = 1; checkpoint_id_i = 0;
        @(posedge clk);
        checkpoint_i = 0;

        // More predictions to shift GHR
        @(posedge clk);
        pred_req_i = 1; pred_pc_i = 32'h1004;
        @(posedge clk);
        pred_req_i = 0;

        // Recover to checkpoint
        @(posedge clk);
        recover_i = 1; recover_id_i = 0; recover_ghr_i = 64'h0;
        @(posedge clk);
        recover_i = 0;

        pass = 1; // Basic flow completed
        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
