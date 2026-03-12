//==============================================================================
// Branch Unit 精简波形测试 - 覆盖6种分支+JAL/JALR
//==============================================================================
`timescale 1ns/1ps

module tb_branch_wave;
    reg clk, rst_n, valid_i;
    reg [3:0] op_i;
    reg [31:0] src1_i, src2_i, pc_i, imm_i, pred_target_i;
    reg pred_taken_i;
    reg [5:0] prd_i;
    reg [4:0] rob_idx_i;
    wire done_o, taken_o, mispredict_o;
    wire [31:0] target_o, link_addr_o;
    wire [5:0] result_prd_o;
    wire [4:0] result_rob_idx_o;

    branch_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/branch_wave.vcd");
        $dumpvars(0, tb_branch_wave);
    end

    integer pass = 0, fail = 0;
    reg exp_taken;
    reg [63:0] test_name;

    // 发送测试激励并检查结果
    task send_test(input [3:0] op, input [31:0] s1, s2, imm, input expected, input [63:0] name);
        begin
            exp_taken = expected;
            test_name = name;
            op_i = op; src1_i = s1; src2_i = s2; imm_i = imm;
            pc_i = 32'h1000; pred_taken_i = 0; pred_target_i = 32'h1000 + imm;
            prd_i = 1; rob_idx_i = 0;
            valid_i = 1;
            #10; // 等待一个时钟周期 (clk周期=10ns)
            valid_i = 0;
            #10; // 再等待一个时钟周期，此时done_o应该为1
            #2;  // 额外延时确保稳定
            // 检查结果
            if (taken_o === exp_taken) begin 
                pass = pass + 1; 
                $display("PASS: %s taken=%b done=%b", test_name, taken_o, done_o); 
            end else begin 
                fail = fail + 1; 
                $display("FAIL: %s exp=%b got=%b done=%b", test_name, exp_taken, taken_o, done_o); 
            end
            #10; // 等待done_o清零
        end
    endtask

    // 保留空任务以兼容现有调用
    task check_result;
        begin
            // 检查已在send_test中完成
        end
    endtask

    initial begin
        $display("=== Branch Wave Test ===");
        rst_n = 0; valid_i = 0; op_i = 0; src1_i = 0; src2_i = 0; pc_i = 0; imm_i = 0;
        pred_taken_i = 0; pred_target_i = 0; prd_i = 0; rob_idx_i = 0;
        exp_taken = 0; test_name = "";
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // BEQ: 5 == 5 -> taken
        send_test(4'b0000, 32'd5, 32'd5, 32'd8, 1, "BEQ_T");
        check_result;
        
        // BEQ: 5 != 6 -> not taken
        send_test(4'b0000, 32'd5, 32'd6, 32'd8, 0, "BEQ_NT");
        check_result;
        
        // BNE: 5 != 6 -> taken
        send_test(4'b0001, 32'd5, 32'd6, 32'd8, 1, "BNE_T");
        check_result;
        
        // BLT: -1 < 1 -> taken (signed)
        send_test(4'b0100, 32'hFFFFFFFF, 32'd1, 32'd8, 1, "BLT_T");
        check_result;
        
        // BGE: 5 >= 3 -> taken
        send_test(4'b0101, 32'd5, 32'd3, 32'd8, 1, "BGE_T");
        check_result;
        
        // BLTU: 1 < 0xFFFFFFFF -> taken (unsigned)
        send_test(4'b0110, 32'd1, 32'hFFFFFFFF, 32'd8, 1, "BLTU_T");
        check_result;
        
        // BGEU: 0xFFFFFFFF >= 1 -> taken (unsigned)
        send_test(4'b0111, 32'hFFFFFFFF, 32'd1, 32'd8, 1, "BGEU_T");
        check_result;
        
        // JAL: always taken
        send_test(4'b1000, 32'd0, 32'd0, 32'd100, 1, "JAL");
        check_result;
        
        // JALR: always taken
        send_test(4'b1001, 32'h2000, 32'd0, 32'd4, 1, "JALR");
        check_result;

        repeat(3) @(posedge clk);
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
