//=============================================================================
// SRAM Controller for External Async SRAM
// 
// Description:
//   Complete asynchronous SRAM controller with proper timing state machine.
//   Supports 16-bit SRAM with 32-bit CPU interface (two accesses per word).
//   Implements configurable timing parameters for real hardware compatibility.
//
// Target SRAM: IS61WV25616 (256K x 16-bit, 10ns access time)
//
// Features:
//   - Full state machine: IDLE → ADDR_SETUP → ACCESS → DATA_HOLD
//   - Configurable timing: tAA (address access), tWC (write cycle), tOE (output enable)
//   - 32-bit to 16-bit access conversion (two cycles per word)
//   - Proper tri-state bus control
//   - Bus timeout detection
//   - Byte/halfword/word access support
//
// Timing Parameters (in clock cycles at 50MHz = 20ns period):
//   - tAA: Address to data valid (typ 10ns = 1 cycle)
//   - tWC: Write cycle time (typ 10ns = 1 cycle)
//   - tOE: Output enable to data valid (typ 5ns = 1 cycle)
//   - tAS: Address setup time (typ 0ns = 1 cycle for safety)
//   - tAH: Address hold time (typ 0ns = 1 cycle for safety)
//
// Requirements: 2.1, 2.2, 2.6
//=============================================================================

`timescale 1ns/1ps

module sram_controller #(
    // Timing parameters (in clock cycles)
    parameter ADDR_SETUP_CYCLES  = 1,    // Address setup before CE/WE
    parameter ACCESS_CYCLES      = 2,    // Read access time (tAA)
    parameter WRITE_CYCLES       = 2,    // Write cycle time (tWC)
    parameter DATA_HOLD_CYCLES   = 1,    // Data hold after WE deassert
    parameter OE_DELAY_CYCLES    = 1,    // Output enable delay (tOE)
    
    // Bus timeout (in clock cycles)
    parameter TIMEOUT_CYCLES     = 256,  // Bus timeout for error detection
    
    // Address width (for 256K x 16 SRAM = 18-bit address)
    parameter SRAM_ADDR_WIDTH    = 18,
    parameter SRAM_DATA_WIDTH    = 16,
    
    // CPU interface width
    parameter CPU_ADDR_WIDTH     = 32,
    parameter CPU_DATA_WIDTH     = 32
)(
    input  wire                         clk,
    input  wire                         rst_n,
    
    //=========================================================================
    // CPU Interface (Simple valid/ready handshake)
    //=========================================================================
    input  wire                         cpu_req,        // Request valid
    output reg                          cpu_ack,        // Request acknowledged
    output reg                          cpu_done,       // Operation complete
    input  wire                         cpu_wr,         // 1=write, 0=read
    input  wire [CPU_ADDR_WIDTH-1:0]    cpu_addr,       // Byte address
    input  wire [CPU_DATA_WIDTH-1:0]    cpu_wdata,      // Write data
    input  wire [3:0]                   cpu_be,         // Byte enables
    output reg  [CPU_DATA_WIDTH-1:0]    cpu_rdata,      // Read data
    output reg                          cpu_error,      // Bus error (timeout)
    
    //=========================================================================
    // SRAM Interface (directly to FPGA pins)
    //=========================================================================
    output reg  [SRAM_ADDR_WIDTH-1:0]   sram_addr,      // Address bus
    inout  wire [SRAM_DATA_WIDTH-1:0]   sram_data,      // Bidirectional data
    output reg                          sram_ce_n,      // Chip enable (active low)
    output reg                          sram_oe_n,      // Output enable (active low)
    output reg                          sram_we_n,      // Write enable (active low)
    output reg                          sram_lb_n,      // Lower byte enable (active low)
    output reg                          sram_ub_n       // Upper byte enable (active low)
);

    //=========================================================================
    // State Machine Definition
    //=========================================================================
    localparam [3:0] ST_IDLE       = 4'd0;   // Idle, waiting for request
    localparam [3:0] ST_ADDR_SETUP = 4'd1;   // Address setup phase
    localparam [3:0] ST_READ_OE    = 4'd2;   // Output enable delay for read
    localparam [3:0] ST_READ_ACC   = 4'd3;   // Read access time
    localparam [3:0] ST_READ_DONE  = 4'd4;   // Read complete, latch data
    localparam [3:0] ST_WRITE_ACC  = 4'd5;   // Write access time
    localparam [3:0] ST_WRITE_HOLD = 4'd6;   // Write data hold
    localparam [3:0] ST_NEXT_HALF  = 4'd7;   // Prepare for second 16-bit access
    localparam [3:0] ST_COMPLETE   = 4'd8;   // Operation complete
    localparam [3:0] ST_ERROR      = 4'd9;   // Bus error state
    
    reg [3:0] state, next_state;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0]  cycle_cnt;           // Cycle counter for timing
    reg [15:0] timeout_cnt;         // Timeout counter
    reg        half_select;         // 0=lower 16 bits, 1=upper 16 bits
    reg        current_half;        // Current half being accessed (registered)
    reg [15:0] read_data_lo;        // Latched lower 16 bits
    reg [15:0] read_data_hi;        // Latched upper 16 bits
    reg [15:0] write_data_reg;      // Current write data
    reg        data_out_en;         // Tri-state control
    reg [15:0] data_out_reg;        // Output data register
    
    // Latched request parameters
    reg [CPU_ADDR_WIDTH-1:0] addr_reg;
    reg [CPU_DATA_WIDTH-1:0] wdata_reg;
    reg [3:0]                be_reg;
    reg                      wr_reg;
    
    //=========================================================================
    // Tri-state Bus Control
    //=========================================================================
    assign sram_data = data_out_en ? data_out_reg : {SRAM_DATA_WIDTH{1'bz}};
    
    //=========================================================================
    // Address Calculation
    // CPU uses byte addressing, SRAM uses 16-bit word addressing
    //=========================================================================
    wire [SRAM_ADDR_WIDTH-1:0] sram_addr_lo = addr_reg[SRAM_ADDR_WIDTH:1];
    wire [SRAM_ADDR_WIDTH-1:0] sram_addr_hi = addr_reg[SRAM_ADDR_WIDTH:1] + 1'b1;
    
    // Combinational versions for initial decision (based on cpu_addr input)
    wire [SRAM_ADDR_WIDTH-1:0] sram_addr_lo_in = cpu_addr[SRAM_ADDR_WIDTH:1];
    wire [SRAM_ADDR_WIDTH-1:0] sram_addr_hi_in = cpu_addr[SRAM_ADDR_WIDTH:1] + 1'b1;
    
    //=========================================================================
    // Byte Enable Calculation for 16-bit SRAM
    //=========================================================================
    wire lb_en_lo = be_reg[0];  // Byte 0 → lower byte of first access
    wire ub_en_lo = be_reg[1];  // Byte 1 → upper byte of first access
    wire lb_en_hi = be_reg[2];  // Byte 2 → lower byte of second access
    wire ub_en_hi = be_reg[3];  // Byte 3 → upper byte of second access
    
    // Determine if we need second access (based on latched be_reg)
    wire need_second_access = (be_reg[3:2] != 2'b00);
    wire need_first_access  = (be_reg[1:0] != 2'b00);
    
    // Combinational versions for initial decision (based on cpu_be input)
    wire need_second_access_in = (cpu_be[3:2] != 2'b00);
    wire need_first_access_in  = (cpu_be[1:0] != 2'b00);
    
    //=========================================================================
    // State Machine - Sequential Logic
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //=========================================================================
    // State Machine - Combinational Logic
    //=========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            ST_IDLE: begin
                if (cpu_req) begin
                    // Use cpu_be directly since be_reg hasn't been latched yet
                    if (need_first_access_in || need_second_access_in) begin
                        next_state = ST_ADDR_SETUP;
                    end else begin
                        // No bytes enabled - complete immediately
                        next_state = ST_COMPLETE;
                    end
                end
            end
            
            ST_ADDR_SETUP: begin
                if (cycle_cnt >= ADDR_SETUP_CYCLES - 1) begin
                    if (wr_reg) begin
                        next_state = ST_WRITE_ACC;
                    end else begin
                        next_state = ST_READ_OE;
                    end
                end
            end
            
            ST_READ_OE: begin
                if (cycle_cnt >= OE_DELAY_CYCLES - 1) begin
                    next_state = ST_READ_ACC;
                end
            end
            
            ST_READ_ACC: begin
                if (timeout_cnt >= TIMEOUT_CYCLES) begin
                    next_state = ST_ERROR;
                end else if (cycle_cnt >= ACCESS_CYCLES - 1) begin
                    next_state = ST_READ_DONE;
                end
            end
            
            ST_READ_DONE: begin
                if (!half_select && need_second_access) begin
                    next_state = ST_NEXT_HALF;
                end else begin
                    next_state = ST_COMPLETE;
                end
            end
            
            ST_WRITE_ACC: begin
                if (timeout_cnt >= TIMEOUT_CYCLES) begin
                    next_state = ST_ERROR;
                end else if (cycle_cnt >= WRITE_CYCLES - 1) begin
                    next_state = ST_WRITE_HOLD;
                end
            end
            
            ST_WRITE_HOLD: begin
                if (cycle_cnt >= DATA_HOLD_CYCLES - 1) begin
                    if (!half_select && need_second_access) begin
                        next_state = ST_NEXT_HALF;
                    end else begin
                        next_state = ST_COMPLETE;
                    end
                end
            end
            
            ST_NEXT_HALF: begin
                next_state = ST_ADDR_SETUP;
            end
            
            ST_COMPLETE: begin
                next_state = ST_IDLE;
            end
            
            ST_ERROR: begin
                next_state = ST_IDLE;
            end
            
            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    //=========================================================================
    // Cycle Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt <= 8'd0;
        end else begin
            if (state != next_state) begin
                // Reset counter on state transition
                cycle_cnt <= 8'd0;
            end else begin
                // Increment counter within state
                cycle_cnt <= cycle_cnt + 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Timeout Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 16'd0;
        end else begin
            if (state == ST_IDLE) begin
                timeout_cnt <= 16'd0;
            end else begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Half Select (for 32-bit to 16-bit conversion)
    // half_select: determines which half to access next
    // current_half: tracks which half is currently being accessed
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            half_select <= 1'b0;
            current_half <= 1'b0;
        end else begin
            if (state == ST_IDLE && cpu_req) begin
                // Start with lower half, unless only upper bytes needed
                // Use cpu_be directly since be_reg hasn't been latched yet
                if (!need_first_access_in && need_second_access_in) begin
                    half_select <= 1'b1;
                    current_half <= 1'b1;
                end else begin
                    half_select <= 1'b0;
                    current_half <= 1'b0;
                end
            end else if (state == ST_NEXT_HALF) begin
                half_select <= 1'b1;
                current_half <= 1'b1;
            end
        end
    end
    
    //=========================================================================
    // Latch Request Parameters
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_reg  <= {CPU_ADDR_WIDTH{1'b0}};
            wdata_reg <= {CPU_DATA_WIDTH{1'b0}};
            be_reg    <= 4'b0000;
            wr_reg    <= 1'b0;
        end else begin
            if (state == ST_IDLE && cpu_req) begin
                addr_reg  <= cpu_addr;
                wdata_reg <= cpu_wdata;
                be_reg    <= cpu_be;
                wr_reg    <= cpu_wr;
            end
        end
    end
    
    //=========================================================================
    // SRAM Address Output
    // Note: Address is updated when entering ADDR_SETUP state
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_addr <= {SRAM_ADDR_WIDTH{1'b0}};
        end else begin
            // Update address when transitioning to ADDR_SETUP
            if (next_state == ST_ADDR_SETUP) begin
                if (state == ST_IDLE) begin
                    // First access - check if we should skip to upper half
                    // Use cpu_addr and cpu_be directly since addr_reg/be_reg haven't been latched yet
                    if (!need_first_access_in && need_second_access_in) begin
                        sram_addr <= sram_addr_hi_in;
                    end else begin
                        sram_addr <= sram_addr_lo_in;
                    end
                end else if (state == ST_NEXT_HALF) begin
                    // Second access - always upper half (use latched addr_reg)
                    sram_addr <= sram_addr_hi;
                end
            end
        end
    end
    
    //=========================================================================
    // SRAM Control Signals
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_ce_n <= 1'b1;
            sram_oe_n <= 1'b1;
            sram_we_n <= 1'b1;
            sram_lb_n <= 1'b1;
            sram_ub_n <= 1'b1;
        end else begin
            case (next_state)
                ST_IDLE, ST_COMPLETE, ST_ERROR: begin
                    // All signals inactive
                    sram_ce_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    sram_lb_n <= 1'b1;
                    sram_ub_n <= 1'b1;
                end
                
                ST_ADDR_SETUP: begin
                    // Assert CE, set byte enables
                    sram_ce_n <= 1'b0;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    // Determine byte enables based on current access
                    if (state == ST_NEXT_HALF) begin
                        // Second access - use upper byte enables
                        sram_lb_n <= ~lb_en_hi;
                        sram_ub_n <= ~ub_en_hi;
                    end else if (state == ST_IDLE && !need_first_access_in && need_second_access_in) begin
                        // First access but skipping to upper half
                        // Use cpu_be directly since be_reg hasn't been latched yet
                        sram_lb_n <= ~cpu_be[2];
                        sram_ub_n <= ~cpu_be[3];
                    end else begin
                        // Normal first access - use lower byte enables
                        // Use cpu_be directly since be_reg hasn't been latched yet
                        if (state == ST_IDLE) begin
                            sram_lb_n <= ~cpu_be[0];
                            sram_ub_n <= ~cpu_be[1];
                        end else begin
                            sram_lb_n <= ~lb_en_lo;
                            sram_ub_n <= ~ub_en_lo;
                        end
                    end
                end
                
                ST_READ_OE, ST_READ_ACC, ST_READ_DONE: begin
                    // Read: CE and OE active
                    sram_ce_n <= 1'b0;
                    sram_oe_n <= 1'b0;
                    sram_we_n <= 1'b1;
                    // Keep byte enables
                end
                
                ST_WRITE_ACC: begin
                    // Write: CE and WE active
                    sram_ce_n <= 1'b0;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b0;
                    // Keep byte enables
                end
                
                ST_WRITE_HOLD: begin
                    // Write hold: WE deasserted, data held
                    sram_ce_n <= 1'b0;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                end
                
                ST_NEXT_HALF: begin
                    // Transition state - deassert all
                    sram_ce_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    sram_lb_n <= 1'b1;
                    sram_ub_n <= 1'b1;
                end
                
                default: begin
                    sram_ce_n <= 1'b1;
                    sram_oe_n <= 1'b1;
                    sram_we_n <= 1'b1;
                    sram_lb_n <= 1'b1;
                    sram_ub_n <= 1'b1;
                end
            endcase
        end
    end
    
    //=========================================================================
    // Write Data Output
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out_en  <= 1'b0;
            data_out_reg <= {SRAM_DATA_WIDTH{1'b0}};
        end else begin
            // Determine if we're in a write state
            if (next_state == ST_WRITE_ACC || next_state == ST_WRITE_HOLD) begin
                // Check if this is a write operation
                // Use cpu_wr for first cycle, wr_reg for subsequent cycles
                if ((state == ST_ADDR_SETUP && cpu_wr) || (state != ST_ADDR_SETUP && wr_reg)) begin
                    data_out_en <= 1'b1;
                    if (current_half) begin
                        data_out_reg <= wdata_reg[31:16];
                    end else begin
                        data_out_reg <= wdata_reg[15:0];
                    end
                end else begin
                    data_out_en  <= 1'b0;
                    data_out_reg <= {SRAM_DATA_WIDTH{1'b0}};
                end
            end else begin
                data_out_en  <= 1'b0;
                data_out_reg <= {SRAM_DATA_WIDTH{1'b0}};
            end
        end
    end
    
    //=========================================================================
    // Read Data Latching
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_data_lo <= 16'd0;
            read_data_hi <= 16'd0;
        end else begin
            if (state == ST_READ_DONE) begin
                if (current_half) begin
                    read_data_hi <= sram_data;
                end else begin
                    read_data_lo <= sram_data;
                end
            end else if (state == ST_IDLE) begin
                read_data_lo <= 16'd0;
                read_data_hi <= 16'd0;
            end
        end
    end
    
    //=========================================================================
    // CPU Interface Outputs
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_ack   <= 1'b0;
            cpu_done  <= 1'b0;
            cpu_rdata <= {CPU_DATA_WIDTH{1'b0}};
            cpu_error <= 1'b0;
        end else begin
            // Default: clear pulse signals
            cpu_ack  <= 1'b0;
            cpu_done <= 1'b0;
            
            // Acknowledge request
            if (state == ST_IDLE && cpu_req) begin
                cpu_ack <= 1'b1;
            end
            
            // Complete operation
            if (state == ST_COMPLETE) begin
                cpu_done  <= 1'b1;
                cpu_error <= 1'b0;
                // Assemble 32-bit read data
                if (!wr_reg) begin
                    cpu_rdata <= {read_data_hi, read_data_lo};
                end
            end
            
            // Error condition
            if (state == ST_ERROR) begin
                cpu_done  <= 1'b1;
                cpu_error <= 1'b1;
                cpu_rdata <= {CPU_DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
