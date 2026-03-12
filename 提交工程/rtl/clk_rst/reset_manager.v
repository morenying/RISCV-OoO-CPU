//=============================================================================
// Module: reset_manager
// Description: System reset manager with sequenced reset release
//              
// Implements a strict reset release sequence:
//   1. Wait for PLL lock
//   2. Wait for stability period
//   3. Release memory controller reset (first)
//   4. Wait RELEASE_DELAY cycles
//   5. Release cache reset
//   6. Wait RELEASE_DELAY cycles
//   7. Release CPU reset (last)
//   8. Release peripheral reset
//
// STRICT CONSTRAINTS:
//   - Reset release order MUST be: memory → cache → cpu → periph
//   - Each release must be separated by at least RELEASE_DELAY cycles
//   - Must wait for PLL lock before starting sequence
//   - All resets must re-assert on any reset source
//
// Requirements: 3.3, 3.4
//=============================================================================

`timescale 1ns/1ps

module reset_manager #(
    // Delay between each reset release (in clock cycles)
    parameter RELEASE_DELAY = 16,
    // Stability wait after PLL lock (in clock cycles)
    parameter STABILITY_WAIT = 100
)(
    // System clock (from clock_manager, already stable)
    input  wire        clk,
    
    // Reset sources
    input  wire        pll_locked,        // PLL is locked and stable
    input  wire        rst_btn_n,         // External reset button (active low)
    input  wire        wdt_reset,         // Watchdog timeout reset
    input  wire        sw_reset,          // Software-triggered reset
    
    // Sequenced reset outputs (active low)
    output reg         rst_mem_n,         // Memory controller reset (released first)
    output reg         rst_cache_n,       // Cache reset
    output reg         rst_cpu_n,         // CPU reset (released last)
    output reg         rst_periph_n,      // Peripheral reset
    
    // Status outputs
    output wire        reset_active,      // Any reset is active
    output wire [2:0]  reset_state        // Current state for debug
);

    //=========================================================================
    // Reset source combination
    //=========================================================================
    wire any_reset_source;
    
    // Combine all reset sources
    // Reset is active if:
    //   - PLL not locked, OR
    //   - Reset button pressed (active low), OR
    //   - Watchdog timeout, OR
    //   - Software reset
    assign any_reset_source = !pll_locked || !rst_btn_n || wdt_reset || sw_reset;
    
    //=========================================================================
    // Synchronize external reset button
    //=========================================================================
    reg [2:0] rst_btn_sync;
    
    always @(posedge clk) begin
        rst_btn_sync <= {rst_btn_sync[1:0], rst_btn_n};
    end
    
    wire rst_btn_synced = rst_btn_sync[2];

    //=========================================================================
    // State Machine for Reset Sequence
    //=========================================================================
    localparam [2:0] ST_RESET       = 3'd0;  // All in reset
    localparam [2:0] ST_WAIT_LOCK   = 3'd1;  // Waiting for PLL lock
    localparam [2:0] ST_WAIT_STABLE = 3'd2;  // Waiting for stability
    localparam [2:0] ST_REL_MEM     = 3'd3;  // Release memory reset
    localparam [2:0] ST_REL_CACHE   = 3'd4;  // Release cache reset
    localparam [2:0] ST_REL_CPU     = 3'd5;  // Release CPU reset
    localparam [2:0] ST_REL_PERIPH  = 3'd6;  // Release peripheral reset
    localparam [2:0] ST_RUNNING     = 3'd7;  // Normal operation
    
    reg [2:0] state;
    reg [15:0] delay_counter;
    
    assign reset_state = state;
    assign reset_active = (state != ST_RUNNING);
    
    //=========================================================================
    // State Machine
    //=========================================================================
    always @(posedge clk) begin
        if (any_reset_source) begin
            // Any reset source asserts all resets immediately
            state <= ST_RESET;
            delay_counter <= 16'd0;
            rst_mem_n <= 1'b0;
            rst_cache_n <= 1'b0;
            rst_cpu_n <= 1'b0;
            rst_periph_n <= 1'b0;
        end else begin
            case (state)
                ST_RESET: begin
                    // All resets asserted, wait for PLL
                    rst_mem_n <= 1'b0;
                    rst_cache_n <= 1'b0;
                    rst_cpu_n <= 1'b0;
                    rst_periph_n <= 1'b0;
                    delay_counter <= 16'd0;
                    
                    if (pll_locked) begin
                        state <= ST_WAIT_LOCK;
                    end
                end
                
                ST_WAIT_LOCK: begin
                    // PLL just locked, start stability wait
                    delay_counter <= 16'd0;
                    state <= ST_WAIT_STABLE;
                end
                
                ST_WAIT_STABLE: begin
                    // Wait for stability period
                    if (delay_counter < STABILITY_WAIT) begin
                        delay_counter <= delay_counter + 1'b1;
                    end else begin
                        delay_counter <= 16'd0;
                        state <= ST_REL_MEM;
                    end
                end
                
                ST_REL_MEM: begin
                    // Release memory reset (first)
                    rst_mem_n <= 1'b1;
                    
                    if (delay_counter < RELEASE_DELAY) begin
                        delay_counter <= delay_counter + 1'b1;
                    end else begin
                        delay_counter <= 16'd0;
                        state <= ST_REL_CACHE;
                    end
                end
                
                ST_REL_CACHE: begin
                    // Release cache reset
                    rst_cache_n <= 1'b1;
                    
                    if (delay_counter < RELEASE_DELAY) begin
                        delay_counter <= delay_counter + 1'b1;
                    end else begin
                        delay_counter <= 16'd0;
                        state <= ST_REL_CPU;
                    end
                end
                
                ST_REL_CPU: begin
                    // Release CPU reset (last critical component)
                    rst_cpu_n <= 1'b1;
                    
                    if (delay_counter < RELEASE_DELAY) begin
                        delay_counter <= delay_counter + 1'b1;
                    end else begin
                        delay_counter <= 16'd0;
                        state <= ST_REL_PERIPH;
                    end
                end
                
                ST_REL_PERIPH: begin
                    // Release peripheral reset
                    rst_periph_n <= 1'b1;
                    state <= ST_RUNNING;
                end
                
                ST_RUNNING: begin
                    // Normal operation, all resets released
                    // Stay here until a reset source activates
                end
                
                default: begin
                    state <= ST_RESET;
                end
            endcase
        end
    end

    //=========================================================================
    // Assertions for verification
    //=========================================================================
    
`ifdef SIMULATION
    // Track reset release times for sequence verification
    reg [31:0] mem_release_time;
    reg [31:0] cache_release_time;
    reg [31:0] cpu_release_time;
    reg [31:0] periph_release_time;
    reg        mem_released, cache_released, cpu_released, periph_released;
    
    initial begin
        mem_release_time = 0;
        cache_release_time = 0;
        cpu_release_time = 0;
        periph_release_time = 0;
        mem_released = 0;
        cache_released = 0;
        cpu_released = 0;
        periph_released = 0;
    end
    
    always @(posedge clk) begin
        // Track release times
        if (rst_mem_n && !mem_released) begin
            mem_release_time <= $time;
            mem_released <= 1'b1;
        end
        if (rst_cache_n && !cache_released) begin
            cache_release_time <= $time;
            cache_released <= 1'b1;
        end
        if (rst_cpu_n && !cpu_released) begin
            cpu_release_time <= $time;
            cpu_released <= 1'b1;
        end
        if (rst_periph_n && !periph_released) begin
            periph_release_time <= $time;
            periph_released <= 1'b1;
        end
        
        // Reset tracking on reset
        if (any_reset_source) begin
            mem_released <= 1'b0;
            cache_released <= 1'b0;
            cpu_released <= 1'b0;
            periph_released <= 1'b0;
        end
    end
    
    // Property: Memory must be released before cache
    always @(posedge clk) begin
        if (rst_cache_n && !rst_mem_n) begin
            $error("ASSERTION FAILED: Cache released before memory!");
        end
    end
    
    // Property: Cache must be released before CPU
    always @(posedge clk) begin
        if (rst_cpu_n && !rst_cache_n) begin
            $error("ASSERTION FAILED: CPU released before cache!");
        end
    end
    
    // Property: CPU must be released before peripherals
    always @(posedge clk) begin
        if (rst_periph_n && !rst_cpu_n) begin
            $error("ASSERTION FAILED: Peripherals released before CPU!");
        end
    end
    
    // Property: All resets must assert when any reset source is active
    always @(posedge clk) begin
        if (any_reset_source) begin
            // Give one cycle for state machine to respond
            @(posedge clk);
            if (rst_mem_n || rst_cache_n || rst_cpu_n || rst_periph_n) begin
                $error("ASSERTION FAILED: Not all resets asserted on reset source!");
            end
        end
    end
`endif

endmodule
