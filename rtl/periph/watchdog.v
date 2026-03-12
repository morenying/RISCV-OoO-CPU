//=============================================================================
// Module: watchdog
// Description: Watchdog Timer
//              Detects CPU hang and triggers system reset
//              Records last PC value before timeout
//
// Features:
//   - Configurable timeout period
//   - Atomic kick operation
//   - Last PC capture on timeout
//   - Enable/disable control
//   - Timeout counter status
//
// Requirements: 5.5, 7.4
//=============================================================================

`timescale 1ns/1ps

module watchdog #(
    parameter XLEN = 32,
    parameter DEFAULT_TIMEOUT = 50_000_000,  // 1 second at 50MHz
    parameter COUNTER_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================================
    // Control Interface
    //=========================================================================
    input  wire                    enable,         // Enable watchdog
    input  wire                    kick,           // Kick (reset counter)
    input  wire [COUNTER_WIDTH-1:0] timeout_val,   // Configurable timeout
    input  wire                    timeout_load,   // Load new timeout value
    
    //=========================================================================
    // CPU Interface
    //=========================================================================
    input  wire [XLEN-1:0]         cpu_pc,         // Current PC for capture
    input  wire                    cpu_valid,      // PC is valid (instruction committed)
    
    //=========================================================================
    // Status and Reset Output
    //=========================================================================
    output reg                     timeout,        // Timeout occurred
    output reg                     wdt_reset,      // Reset signal to reset_manager
    output reg  [XLEN-1:0]         last_pc,        // Last valid PC before timeout
    output wire [COUNTER_WIDTH-1:0] counter_val,   // Current counter value (for debug)
    output wire                    running         // Watchdog is running
);

    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [COUNTER_WIDTH-1:0] counter;
    reg [COUNTER_WIDTH-1:0] timeout_reg;
    reg [XLEN-1:0]          last_valid_pc;
    reg                     enabled_reg;
    reg                     kick_sync_1, kick_sync_2;
    reg                     kick_edge;
    
    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [1:0]
        ST_IDLE     = 2'd0,
        ST_RUNNING  = 2'd1,
        ST_TIMEOUT  = 2'd2,
        ST_RESET    = 2'd3;
    
    reg [1:0] state;
    reg [1:0] next_state;
    
    // Reset pulse counter (hold reset for multiple cycles)
    reg [3:0] reset_pulse_cnt;
    localparam RESET_PULSE_WIDTH = 4'd8;
    
    //=========================================================================
    // Output Assignments
    //=========================================================================
    assign counter_val = counter;
    assign running = (state == ST_RUNNING);
    
    //=========================================================================
    // Kick Synchronization (for cross-domain safety)
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            kick_sync_1 <= 1'b0;
            kick_sync_2 <= 1'b0;
            kick_edge <= 1'b0;
        end else begin
            kick_sync_1 <= kick;
            kick_sync_2 <= kick_sync_1;
            kick_edge <= kick_sync_1 && !kick_sync_2;  // Rising edge detect
        end
    end
    
    //=========================================================================
    // Last Valid PC Capture
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_valid_pc <= 32'h0;
        end else begin
            if (cpu_valid) begin
                last_valid_pc <= cpu_pc;
            end
        end
    end
    
    //=========================================================================
    // Timeout Value Register
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_reg <= DEFAULT_TIMEOUT;
        end else begin
            if (timeout_load) begin
                timeout_reg <= timeout_val;
            end
        end
    end
    
    //=========================================================================
    // Enable Register
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enabled_reg <= 1'b0;
        end else begin
            enabled_reg <= enable;
        end
    end
    
    //=========================================================================
    // State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //=========================================================================
    // State Machine - Combinational
    //=========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (enabled_reg) begin
                    next_state = ST_RUNNING;
                end
            end
            
            ST_RUNNING: begin
                if (!enabled_reg) begin
                    next_state = ST_IDLE;
                end else if (counter >= timeout_reg) begin
                    next_state = ST_TIMEOUT;
                end
            end
            
            ST_TIMEOUT: begin
                next_state = ST_RESET;
            end
            
            ST_RESET: begin
                if (reset_pulse_cnt == 0) begin
                    next_state = ST_IDLE;
                end
            end
            
            default: next_state = ST_IDLE;
        endcase
    end
    
    //=========================================================================
    // Counter Logic
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    counter <= 0;
                end
                
                ST_RUNNING: begin
                    if (kick_edge || kick) begin
                        // Kick resets counter (atomic operation)
                        counter <= 0;
                    end else begin
                        // Increment counter
                        counter <= counter + 1;
                    end
                end
                
                ST_TIMEOUT, ST_RESET: begin
                    // Hold counter value
                end
                
                default: counter <= 0;
            endcase
        end
    end
    
    //=========================================================================
    // Timeout and Reset Output
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout <= 1'b0;
            wdt_reset <= 1'b0;
            last_pc <= 32'h0;
            reset_pulse_cnt <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    timeout <= 1'b0;
                    wdt_reset <= 1'b0;
                    reset_pulse_cnt <= RESET_PULSE_WIDTH;
                end
                
                ST_RUNNING: begin
                    timeout <= 1'b0;
                    wdt_reset <= 1'b0;
                    reset_pulse_cnt <= RESET_PULSE_WIDTH;
                end
                
                ST_TIMEOUT: begin
                    // Capture last PC and assert timeout
                    timeout <= 1'b1;
                    last_pc <= last_valid_pc;
                end
                
                ST_RESET: begin
                    // Assert reset pulse
                    wdt_reset <= 1'b1;
                    if (reset_pulse_cnt > 0) begin
                        reset_pulse_cnt <= reset_pulse_cnt - 1;
                    end else begin
                        wdt_reset <= 1'b0;
                    end
                end
                
                default: begin
                    timeout <= 1'b0;
                    wdt_reset <= 1'b0;
                end
            endcase
        end
    end

endmodule
