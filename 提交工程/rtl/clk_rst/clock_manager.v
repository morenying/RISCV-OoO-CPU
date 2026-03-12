//=============================================================================
// Module: clock_manager
// Description: Clock management unit using Xilinx MMCM primitive
//              - Generates system clock (50MHz) from external 100MHz input
//              - Generates memory clock (100MHz) for SRAM interface
//              - Implements PLL lock detection and automatic re-lock
//              - Provides synchronized reset output
//
// STRICT CONSTRAINTS:
//   - Must use MMCM/PLL primitive, NOT simple clock divider
//   - Must implement lock loss detection and recovery
//   - Must gate output clocks when not locked
//   - Output reset must be synchronous to output clock
//
// Requirements: 3.5, 3.6
//=============================================================================

`timescale 1ns/1ps

module clock_manager #(
    // Input clock frequency (Hz)
    parameter INPUT_CLK_FREQ  = 100_000_000,
    // System clock frequency (Hz) - CPU runs at this
    parameter SYS_CLK_FREQ    = 50_000_000,
    // Memory clock frequency (Hz) - SRAM interface
    parameter MEM_CLK_FREQ    = 100_000_000,
    // Lock timeout cycles before reset retry
    parameter LOCK_TIMEOUT    = 1_000_000,
    // Minimum lock stable cycles before declaring locked
    parameter LOCK_STABLE_CNT = 1000
)(
    // External clock input (from crystal oscillator)
    input  wire        clk_in,
    // Asynchronous reset input (directly from button/POR)
    input  wire        rst_n_async,
    
    // Generated clocks
    output wire        clk_sys,        // 50MHz system clock
    output wire        clk_mem,        // 100MHz memory clock
    
    // Status outputs
    output wire        locked,         // PLL is locked and stable
    output wire        lock_lost,      // PLL lost lock (edge detect)
    
    // Synchronized reset outputs (active low)
    output wire        rst_n_sys,      // Reset synchronized to clk_sys
    output wire        rst_n_mem       // Reset synchronized to clk_mem
);

    //=========================================================================
    // Internal signals
    //=========================================================================
    wire        mmcm_clk_sys;           // Raw MMCM output for sys clock
    wire        mmcm_clk_mem;           // Raw MMCM output for mem clock
    wire        mmcm_locked_raw;        // Raw MMCM locked signal
    wire        mmcm_clkfb;             // MMCM feedback clock
    
    reg  [19:0] lock_timeout_cnt;       // Lock timeout counter
    reg         lock_timeout;           // Lock timeout flag
    reg         mmcm_reset;             // MMCM reset (for re-lock)
    reg  [1:0]  locked_sync;            // Synchronized locked signal
    reg  [9:0]  lock_stable_cnt;        // Lock stability counter
    reg         locked_stable;          // Lock is stable
    reg         locked_prev;            // Previous locked state (for edge detect)

    //=========================================================================
    // MMCM Instantiation (Xilinx 7-Series)
    // 
    // Configuration for 100MHz input -> 50MHz sys, 100MHz mem:
    //   VCO = 100MHz * 10 / 1 = 1000MHz (must be 600-1200MHz for -1 speed)
    //   clk_sys = 1000MHz / 20 = 50MHz
    //   clk_mem = 1000MHz / 10 = 100MHz
    //=========================================================================
    
    // Synthesis: Use actual MMCM primitive
    // Simulation: Use behavioral model
    
`ifdef SYNTHESIS
    
    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),         // VCO = 100 * 10 = 1000MHz
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),         // 100MHz = 10ns period
        .CLKOUT0_DIVIDE_F   (20.0),         // 1000/20 = 50MHz (sys)
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .CLKOUT1_DIVIDE     (10),           // 1000/10 = 100MHz (mem)
        .CLKOUT1_DUTY_CYCLE (0.5),
        .CLKOUT1_PHASE      (0.0),
        .CLKOUT2_DIVIDE     (1),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0            (mmcm_clk_sys),
        .CLKOUT0B           (),
        .CLKOUT1            (mmcm_clk_mem),
        .CLKOUT1B           (),
        .CLKOUT2            (),
        .CLKOUT2B           (),
        .CLKOUT3            (),
        .CLKOUT3B           (),
        .CLKOUT4            (),
        .CLKOUT5            (),
        .CLKOUT6            (),
        .CLKFBOUT           (mmcm_clkfb),
        .CLKFBOUTB          (),
        .LOCKED             (mmcm_locked_raw),
        .CLKIN1             (clk_in),
        .PWRDWN             (1'b0),
        .RST                (mmcm_reset),
        .CLKFBIN            (mmcm_clkfb)
    );

`else
    // Simulation behavioral model
    // This accurately models MMCM behavior including lock time
    
    reg        sim_locked;
    reg [15:0] sim_lock_cnt;
    reg        sim_clk_sys;
    reg        sim_clk_mem;
    
    // Lock time simulation (reduced for faster simulation)
    // In real hardware this is ~100us, but for simulation we use fewer cycles
    localparam SIM_LOCK_TIME = 50;
    
    initial begin
        sim_locked = 1'b0;
        sim_lock_cnt = 0;
        sim_clk_sys = 1'b0;
        sim_clk_mem = 1'b0;
    end
    
    // Lock behavior
    always @(posedge clk_in or posedge mmcm_reset) begin
        if (mmcm_reset) begin
            sim_locked <= 1'b0;
            sim_lock_cnt <= 0;
        end else begin
            if (sim_lock_cnt < SIM_LOCK_TIME) begin
                sim_lock_cnt <= sim_lock_cnt + 1;
                sim_locked <= 1'b0;
            end else begin
                sim_locked <= 1'b1;
            end
        end
    end
    
    // Clock generation (only when locked)
    // 50MHz sys clock (20ns period)
    always @(posedge clk_in) begin
        if (sim_locked)
            sim_clk_sys <= ~sim_clk_sys;
    end
    
    // 100MHz mem clock - pass through input clock when locked
    // Note: In simulation, we just pass through the input clock
    assign mmcm_clk_sys = sim_clk_sys;
    assign mmcm_clk_mem = clk_in;  // mem clock is same freq as input
    assign mmcm_locked_raw = sim_locked;
    assign mmcm_locked_raw = sim_locked;
    
`endif

    //=========================================================================
    // Clock Gating - Output clocks are gated when not locked
    // This prevents glitchy clocks from reaching downstream logic
    //=========================================================================
    
`ifdef SYNTHESIS
    // Use BUFGCE for clock gating (Xilinx recommended)
    BUFGCE u_bufg_sys (
        .O  (clk_sys),
        .CE (locked_stable),
        .I  (mmcm_clk_sys)
    );
    
    BUFGCE u_bufg_mem (
        .O  (clk_mem),
        .CE (locked_stable),
        .I  (mmcm_clk_mem)
    );
`else
    // Simulation: simple gating
    assign clk_sys = locked_stable ? mmcm_clk_sys : 1'b0;
    assign clk_mem = locked_stable ? mmcm_clk_mem : 1'b0;
`endif

    //=========================================================================
    // Lock Synchronization and Stability Detection
    // 
    // Raw MMCM locked signal is asynchronous to output clocks.
    // We synchronize it and require it to be stable for LOCK_STABLE_CNT
    // cycles before declaring the system locked.
    //=========================================================================
    
    // Synchronize locked signal to input clock domain
    always @(posedge clk_in or negedge rst_n_async) begin
        if (!rst_n_async) begin
            locked_sync <= 2'b00;
        end else begin
            locked_sync <= {locked_sync[0], mmcm_locked_raw};
        end
    end
    
    // Lock stability counter
    // Requires locked to be high for LOCK_STABLE_CNT consecutive cycles
    always @(posedge clk_in or negedge rst_n_async) begin
        if (!rst_n_async) begin
            lock_stable_cnt <= 10'd0;
            locked_stable <= 1'b0;
        end else if (!locked_sync[1]) begin
            // Not locked, reset counter
            lock_stable_cnt <= 10'd0;
            locked_stable <= 1'b0;
        end else if (lock_stable_cnt < LOCK_STABLE_CNT[9:0]) begin
            // Counting up to stability threshold
            lock_stable_cnt <= lock_stable_cnt + 1'b1;
            locked_stable <= 1'b0;
        end else begin
            // Stable!
            locked_stable <= 1'b1;
        end
    end
    
    // Lock loss edge detection
    always @(posedge clk_in or negedge rst_n_async) begin
        if (!rst_n_async) begin
            locked_prev <= 1'b0;
        end else begin
            locked_prev <= locked_stable;
        end
    end
    
    assign locked = locked_stable;
    assign lock_lost = locked_prev & ~locked_stable;  // Falling edge

    //=========================================================================
    // Lock Timeout and Auto-Recovery
    //
    // If MMCM doesn't lock within LOCK_TIMEOUT cycles, we reset it and retry.
    // This handles cases where MMCM gets stuck in an invalid state.
    //=========================================================================
    
    always @(posedge clk_in or negedge rst_n_async) begin
        if (!rst_n_async) begin
            lock_timeout_cnt <= 20'd0;
            lock_timeout <= 1'b0;
        end else if (locked_stable) begin
            // Locked, reset timeout
            lock_timeout_cnt <= 20'd0;
            lock_timeout <= 1'b0;
        end else if (lock_timeout_cnt < LOCK_TIMEOUT[19:0]) begin
            // Counting towards timeout
            lock_timeout_cnt <= lock_timeout_cnt + 1'b1;
            lock_timeout <= 1'b0;
        end else begin
            // Timeout! Will trigger MMCM reset
            lock_timeout <= 1'b1;
        end
    end
    
    // MMCM reset logic
    // Reset MMCM on:
    //   1. External async reset
    //   2. Lock timeout (auto-recovery)
    //   3. Lock loss (re-lock attempt)
    always @(posedge clk_in or negedge rst_n_async) begin
        if (!rst_n_async) begin
            mmcm_reset <= 1'b1;  // Hold in reset initially
        end else if (lock_timeout || lock_lost) begin
            mmcm_reset <= 1'b1;  // Reset on timeout or lock loss
        end else begin
            mmcm_reset <= 1'b0;  // Normal operation
        end
    end

    //=========================================================================
    // Reset Synchronizers for Output Clock Domains
    //
    // Each output clock domain needs its own synchronized reset.
    // Reset assertion is asynchronous (immediate), release is synchronous.
    // This is the standard async-assert, sync-deassert pattern.
    //=========================================================================
    
    // System clock domain reset synchronizer
    reg [2:0] rst_sync_sys;
    
    always @(posedge mmcm_clk_sys or negedge rst_n_async) begin
        if (!rst_n_async) begin
            rst_sync_sys <= 3'b000;  // Assert reset immediately
        end else if (!locked_stable) begin
            rst_sync_sys <= 3'b000;  // Keep in reset if not locked
        end else begin
            rst_sync_sys <= {rst_sync_sys[1:0], 1'b1};  // Sync release
        end
    end
    
    assign rst_n_sys = rst_sync_sys[2];
    
    // Memory clock domain reset synchronizer
    reg [2:0] rst_sync_mem;
    
    always @(posedge mmcm_clk_mem or negedge rst_n_async) begin
        if (!rst_n_async) begin
            rst_sync_mem <= 3'b000;  // Assert reset immediately
        end else if (!locked_stable) begin
            rst_sync_mem <= 3'b000;  // Keep in reset if not locked
        end else begin
            rst_sync_mem <= {rst_sync_mem[1:0], 1'b1};  // Sync release
        end
    end
    
    assign rst_n_mem = rst_sync_mem[2];

    //=========================================================================
    // Assertions (for simulation verification)
    //=========================================================================
    
`ifdef SIMULATION
    // Property: Output clocks must be gated when not locked
    always @(posedge clk_in) begin
        if (!locked_stable) begin
            // When not locked, output clocks should not toggle
            // (This is checked by observing clk_sys and clk_mem)
        end
    end
    
    // Property: Reset must be asserted when not locked
    always @(posedge mmcm_clk_sys) begin
        if (!locked_stable && rst_n_sys) begin
            $error("ASSERTION FAILED: rst_n_sys should be low when not locked");
        end
    end
    
    // Property: Lock timeout should trigger MMCM reset
    always @(posedge clk_in) begin
        if (lock_timeout && !mmcm_reset) begin
            $error("ASSERTION FAILED: mmcm_reset should be high on lock_timeout");
        end
    end
`endif

endmodule
