//=================================================================
// Module: clock_gate
// Description: Clock Gating Cell for Power Optimization
//              Provides glitch-free clock gating using latch
//              Synthesis tool will map to ICG cell if available
// Requirements: 11.1, 10.4
//=================================================================

`timescale 1ns/1ps

module clock_gate (
    input  wire clk_i,      // Input clock
    input  wire en_i,       // Enable signal (active high)
    input  wire test_en_i,  // Test mode enable (bypass gating)
    output wire clk_o       // Gated clock output
);

    //=========================================================
    // Latch-based Clock Gating
    //=========================================================
    // The enable is latched on the negative edge of clock
    // to prevent glitches on the gated clock
    
    reg en_latch;
    
    // Latch enable on falling edge (transparent when clk low)
    always @(*) begin
        if (!clk_i) begin
            en_latch = en_i | test_en_i;
        end
    end
    
    // AND gate for clock gating
    assign clk_o = clk_i & en_latch;

endmodule

//=================================================================
// Module: clock_gate_sync
// Description: Synchronous Clock Gating Cell
//              Uses flip-flop for enable synchronization
//              More timing-friendly but uses more power
//=================================================================

module clock_gate_sync (
    input  wire clk_i,
    input  wire rst_n,
    input  wire en_i,
    input  wire test_en_i,
    output wire clk_o
);

    reg en_sync;
    
    always @(posedge clk_i or negedge rst_n) begin
        if (!rst_n)
            en_sync <= 1'b0;
        else
            en_sync <= en_i;
    end
    
    assign clk_o = clk_i & (en_sync | test_en_i);

endmodule

//=================================================================
// Module: operand_isolation
// Description: Operand Isolation for Power Reduction
//              Gates data inputs when unit is idle
// Requirements: 11.2
//=================================================================

module operand_isolation #(
    parameter WIDTH = 32
) (
    input  wire             en_i,       // Enable (1 = pass data)
    input  wire [WIDTH-1:0] data_i,     // Input data
    output wire [WIDTH-1:0] data_o      // Isolated output
);

    // When disabled, output zeros to reduce switching activity
    assign data_o = en_i ? data_i : {WIDTH{1'b0}};

endmodule

//=================================================================
// Module: power_domain_ctrl
// Description: Power Domain Controller
//              Manages clock gating for functional units
// Requirements: 11.1
//=================================================================

module power_domain_ctrl (
    input  wire clk,
    input  wire rst_n,
    
    // Unit activity signals
    input  wire alu_active_i,
    input  wire mul_active_i,
    input  wire div_active_i,
    input  wire lsu_active_i,
    input  wire bpu_active_i,
    
    // Test mode
    input  wire test_mode_i,
    
    // Gated clock enables
    output reg  alu_clk_en_o,
    output reg  mul_clk_en_o,
    output reg  div_clk_en_o,
    output reg  lsu_clk_en_o,
    output reg  bpu_clk_en_o
);

    //=========================================================
    // Idle Detection with Hysteresis
    //=========================================================
    // Keep clock enabled for a few cycles after activity
    // to avoid frequent clock toggling
    
    localparam IDLE_THRESHOLD = 4;
    
    reg [2:0] alu_idle_cnt;
    reg [2:0] mul_idle_cnt;
    reg [2:0] div_idle_cnt;
    reg [2:0] lsu_idle_cnt;
    reg [2:0] bpu_idle_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_idle_cnt <= 0;
            mul_idle_cnt <= 0;
            div_idle_cnt <= 0;
            lsu_idle_cnt <= 0;
            bpu_idle_cnt <= 0;
            alu_clk_en_o <= 1'b1;
            mul_clk_en_o <= 1'b1;
            div_clk_en_o <= 1'b1;
            lsu_clk_en_o <= 1'b1;
            bpu_clk_en_o <= 1'b1;
        end else if (test_mode_i) begin
            // In test mode, all clocks enabled
            alu_clk_en_o <= 1'b1;
            mul_clk_en_o <= 1'b1;
            div_clk_en_o <= 1'b1;
            lsu_clk_en_o <= 1'b1;
            bpu_clk_en_o <= 1'b1;
        end else begin
            // ALU clock gating
            if (alu_active_i) begin
                alu_idle_cnt <= 0;
                alu_clk_en_o <= 1'b1;
            end else if (alu_idle_cnt < IDLE_THRESHOLD) begin
                alu_idle_cnt <= alu_idle_cnt + 1;
            end else begin
                alu_clk_en_o <= 1'b0;
            end
            
            // MUL clock gating
            if (mul_active_i) begin
                mul_idle_cnt <= 0;
                mul_clk_en_o <= 1'b1;
            end else if (mul_idle_cnt < IDLE_THRESHOLD) begin
                mul_idle_cnt <= mul_idle_cnt + 1;
            end else begin
                mul_clk_en_o <= 1'b0;
            end
            
            // DIV clock gating
            if (div_active_i) begin
                div_idle_cnt <= 0;
                div_clk_en_o <= 1'b1;
            end else if (div_idle_cnt < IDLE_THRESHOLD) begin
                div_idle_cnt <= div_idle_cnt + 1;
            end else begin
                div_clk_en_o <= 1'b0;
            end
            
            // LSU clock gating
            if (lsu_active_i) begin
                lsu_idle_cnt <= 0;
                lsu_clk_en_o <= 1'b1;
            end else if (lsu_idle_cnt < IDLE_THRESHOLD) begin
                lsu_idle_cnt <= lsu_idle_cnt + 1;
            end else begin
                lsu_clk_en_o <= 1'b0;
            end
            
            // BPU clock gating
            if (bpu_active_i) begin
                bpu_idle_cnt <= 0;
                bpu_clk_en_o <= 1'b1;
            end else if (bpu_idle_cnt < IDLE_THRESHOLD) begin
                bpu_idle_cnt <= bpu_idle_cnt + 1;
            end else begin
                bpu_clk_en_o <= 1'b0;
            end
        end
    end

endmodule
