//==============================================================================
// CSR Unit 精简波形测试 - 覆盖CSR读写/异常处理，约25周期
//==============================================================================
`timescale 1ns/1ps

module tb_csr_wave;
    reg clk, rst_n;
    // CSR access
    reg csr_valid_i;
    reg [11:0] csr_addr_i;
    reg [2:0] csr_op_i;
    reg [31:0] csr_wdata_i;
    wire [31:0] csr_rdata_o;
    wire csr_illegal_o;
    // Exception
    reg exception_i;
    reg [3:0] exc_code_i;
    reg [31:0] exc_pc_i, exc_tval_i;
    // MRET
    reg mret_i;
    // Interrupt
    reg ext_irq_i, timer_irq_i, sw_irq_i;
    wire irq_pending_o;
    // Outputs
    wire [31:0] mtvec_o, mepc_o;
    wire mie_o;
    // Hart ID
    reg [31:0] hart_id_i;

    csr_unit dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/waves/csr_wave.vcd");
        $dumpvars(0, tb_csr_wave);
    end

    integer pass = 0, fail = 0;

    initial begin
        $display("=== CSR Unit Wave Test ===");
        rst_n = 0; csr_valid_i = 0; exception_i = 0; mret_i = 0;
        csr_addr_i = 0; csr_op_i = 0; csr_wdata_i = 0;
        exc_code_i = 0; exc_pc_i = 0; exc_tval_i = 0;
        ext_irq_i = 0; timer_irq_i = 0; sw_irq_i = 0;
        hart_id_i = 32'd0;
        #20 rst_n = 1; #10;

        // Write mtvec (CSRRW = 3'b001)
        csr_valid_i = 1; csr_addr_i = 12'h305; csr_op_i = 3'b001; csr_wdata_i = 32'h100;
        #10; // Wait for write to be captured
        csr_valid_i = 0;
        #10; // Wait for register to update
        #2;  // Extra delay for stability
        if (mtvec_o == 32'h100) begin
            pass = pass + 1; $display("PASS: mtvec = %h", mtvec_o);
        end else begin
            fail = fail + 1; $display("FAIL: mtvec write (got %h)", mtvec_o);
        end

        // Read misa
        #10;
        csr_valid_i = 1; csr_addr_i = 12'h301; csr_op_i = 3'b010; csr_wdata_i = 0;
        #2; // Combinational read delay
        $display("misa = %h", csr_rdata_o);
        #8;
        csr_valid_i = 0;

        // Test exception handling
        #10;
        exception_i = 1; exc_code_i = 4'd2; exc_pc_i = 32'h1000; exc_tval_i = 32'hDEAD;
        #10; // Wait for exception to be captured
        exception_i = 0;
        #10; // Wait for registers to update
        #2;
        if (mepc_o == 32'h1000) begin
            pass = pass + 1; $display("PASS: mepc saved = %h", mepc_o);
        end else begin
            fail = fail + 1; $display("FAIL: mepc save (got %h)", mepc_o);
        end

        // Read mcause
        #10;
        csr_valid_i = 1; csr_addr_i = 12'h342; csr_op_i = 3'b010; csr_wdata_i = 0;
        #2; // Combinational read delay
        if (csr_rdata_o[3:0] == 4'd2) begin
            pass = pass + 1; $display("PASS: mcause = %h", csr_rdata_o);
        end else begin
            fail = fail + 1; $display("FAIL: mcause (got %h)", csr_rdata_o);
        end
        #8;
        csr_valid_i = 0;

        // Test MRET
        #10;
        mret_i = 1;
        #10;
        mret_i = 0;

        // Test illegal CSR
        #10;
        csr_valid_i = 1; csr_addr_i = 12'hFFF; csr_op_i = 3'b001; csr_wdata_i = 0;
        #2; // Combinational delay
        if (csr_illegal_o) begin
            pass = pass + 1; $display("PASS: Illegal CSR detected");
        end else begin
            fail = fail + 1; $display("FAIL: Illegal CSR");
        end
        #8;
        csr_valid_i = 0;

        #20;
        $display("=== Results: %0d PASS, %0d FAIL ===", pass, fail);
        $finish;
    end
endmodule
