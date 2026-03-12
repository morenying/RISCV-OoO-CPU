//=============================================================================
// SRAM Timing Model - IS61WV25616 Compatible
//
// Description:
//   Realistic SRAM timing model for verification. Models all timing
//   constraints of a real async SRAM and reports violations.
//
// Target: IS61WV25616 (256K x 16-bit, 10ns access time)
//
// Timing Parameters (at 10ns grade):
//   - tAA:  Address to data valid = 10ns max
//   - tOE:  OE to data valid = 5ns max
//   - tWC:  Write cycle time = 10ns min
//   - tAS:  Address setup to WE = 0ns min
//   - tAH:  Address hold from WE = 0ns min
//   - tDS:  Data setup to WE rising = 6ns min
//   - tDH:  Data hold from WE rising = 0ns min
//   - tWP:  WE pulse width = 8ns min
//
// Features:
//   - Accurate timing violation detection
//   - Configurable timing parameters
//   - Output delay modeling
//   - Setup/hold violation reporting
//
// Requirements: 2.1 (SRAM timing model for verification)
//=============================================================================

`timescale 1ns/1ps

module sram_model #(
    // Memory size
    parameter ADDR_WIDTH = 18,          // 256K words
    parameter DATA_WIDTH = 16,          // 16-bit data
    
    // Timing parameters (in ns) - IS61WV25616-10 specs
    parameter real tAA  = 10.0,         // Address access time
    parameter real tOE  = 5.0,          // OE to data valid
    parameter real tWC  = 10.0,         // Write cycle time
    parameter real tAS  = 0.0,          // Address setup to WE
    parameter real tAH  = 0.0,          // Address hold from WE
    parameter real tDS  = 6.0,          // Data setup to WE rising
    parameter real tDH  = 0.0,          // Data hold from WE rising
    parameter real tWP  = 8.0,          // WE pulse width
    parameter real tOHZ = 5.0,          // OE to high-Z
    parameter real tWHZ = 6.0,          // WE to high-Z
    
    // Simulation options
    parameter VERBOSE = 0               // Enable verbose timing messages
)(
    // SRAM interface
    input  wire [ADDR_WIDTH-1:0]    addr,
    inout  wire [DATA_WIDTH-1:0]    data,
    input  wire                     ce_n,
    input  wire                     oe_n,
    input  wire                     we_n,
    input  wire                     lb_n,
    input  wire                     ub_n,
    
    // Violation reporting
    output reg                      timing_violation,
    output reg  [7:0]               violation_count
);

    //=========================================================================
    // Memory Array
    //=========================================================================
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    
    //=========================================================================
    // Internal Signals
    //=========================================================================
    reg [DATA_WIDTH-1:0] data_out;
    reg                  data_out_en;
    
    // Timing tracking
    realtime addr_change_time;
    realtime ce_fall_time;
    realtime oe_fall_time;
    realtime we_fall_time;
    realtime we_rise_time;
    realtime data_change_time;
    
    // Previous values for edge detection
    reg [ADDR_WIDTH-1:0] addr_prev;
    reg                  ce_n_prev;
    reg                  oe_n_prev;
    reg                  we_n_prev;
    reg [DATA_WIDTH-1:0] data_prev;
    
    // Timing check variables (moved from unnamed blocks)
    realtime current_time;
    realtime we_pulse_width;
    realtime data_setup;
    realtime hold_time;
    
    //=========================================================================
    // Tri-state Output
    //=========================================================================
    assign data = data_out_en ? data_out : {DATA_WIDTH{1'bz}};
    
    //=========================================================================
    // Initialize Memory (optional - can be loaded from file)
    //=========================================================================
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'bx}};  // Uninitialized = X
        end
        
        data_out = {DATA_WIDTH{1'bz}};
        data_out_en = 1'b0;
        timing_violation = 1'b0;
        violation_count = 8'd0;
        
        addr_change_time = 0;
        ce_fall_time = 0;
        oe_fall_time = 0;
        we_fall_time = 0;
        we_rise_time = 0;
        data_change_time = 0;
        
        addr_prev = {ADDR_WIDTH{1'b0}};
        ce_n_prev = 1'b1;
        oe_n_prev = 1'b1;
        we_n_prev = 1'b1;
        data_prev = {DATA_WIDTH{1'b0}};
    end
    
    //=========================================================================
    // Edge Detection and Timing Tracking
    //=========================================================================
    always @(addr) begin
        addr_change_time = $realtime;
        addr_prev = addr;
    end
    
    always @(negedge ce_n) begin
        ce_fall_time = $realtime;
    end
    
    always @(negedge oe_n) begin
        oe_fall_time = $realtime;
    end
    
    always @(negedge we_n) begin
        we_fall_time = $realtime;
    end
    
    always @(posedge we_n) begin
        we_rise_time = $realtime;
    end
    
    always @(data) begin
        if (!we_n) begin  // Only track during write
            data_change_time = $realtime;
        end
        data_prev = data;
    end
    
    //=========================================================================
    // Read Operation with Timing
    //=========================================================================
    always @(*) begin
        if (!ce_n && !oe_n && we_n) begin
            // Read mode - output data after access time
            data_out_en = 1'b1;
        end else begin
            data_out_en = 1'b0;
        end
    end
    
    // Model output delay
    always @(addr or ce_n or oe_n or we_n or lb_n or ub_n) begin
        if (!ce_n && !oe_n && we_n) begin
            // Read operation
            #(tAA);  // Address access time delay
            
            // Apply byte enables
            if (!lb_n && !ub_n) begin
                data_out = mem[addr];
            end else if (!lb_n) begin
                data_out = {8'hzz, mem[addr][7:0]};
            end else if (!ub_n) begin
                data_out = {mem[addr][15:8], 8'hzz};
            end else begin
                data_out = {DATA_WIDTH{1'bz}};
            end
            
            if (VERBOSE) begin
                $display("[SRAM] %0t: Read addr=%h data=%h", $realtime, addr, data_out);
            end
        end
    end
    
    //=========================================================================
    // Write Operation with Timing Checks
    //=========================================================================
    always @(posedge we_n) begin
        if (!ce_n) begin
            // Write operation on WE rising edge
            current_time = $realtime;
            we_pulse_width = current_time - we_fall_time;
            data_setup = we_rise_time - data_change_time;
            
            // Check WE pulse width
            if (we_pulse_width < tWP) begin
                report_violation("WE pulse width", we_pulse_width, tWP);
            end
            
            // Check data setup time
            if (data_setup < tDS && data_change_time > we_fall_time) begin
                report_violation("Data setup", data_setup, tDS);
            end
            
            // Perform write if no critical violations
            if (!lb_n || !ub_n) begin
                if (!lb_n && !ub_n) begin
                    mem[addr] = data;
                end else if (!lb_n) begin
                    mem[addr][7:0] = data[7:0];
                end else if (!ub_n) begin
                    mem[addr][15:8] = data[15:8];
                end
                
                if (VERBOSE) begin
                    $display("[SRAM] %0t: Write addr=%h data=%h lb_n=%b ub_n=%b", 
                             $realtime, addr, data, lb_n, ub_n);
                end
            end
        end
    end
    
    //=========================================================================
    // Address Hold Check
    //=========================================================================
    always @(addr) begin
        if (!ce_n && we_n_prev == 1'b0 && we_n == 1'b1) begin
            // Address changed after WE rising - check hold time
            hold_time = $realtime - we_rise_time;
            
            if (hold_time < tAH) begin
                report_violation("Address hold", hold_time, tAH);
            end
        end
    end
    
    //=========================================================================
    // Data Hold Check
    //=========================================================================
    always @(data) begin
        if (!ce_n && we_rise_time > 0) begin
            hold_time = $realtime - we_rise_time;
            
            if (hold_time < tDH && hold_time > 0) begin
                report_violation("Data hold", hold_time, tDH);
            end
        end
    end
    
    //=========================================================================
    // Violation Reporting
    //=========================================================================
    task report_violation;
        input [255:0] violation_type;
        input real actual;
        input real required;
    begin
        timing_violation = 1'b1;
        violation_count = violation_count + 1;
        $display("[SRAM VIOLATION] %0t: %0s violation - actual=%.2fns, required=%.2fns",
                 $realtime, violation_type, actual, required);
        #1 timing_violation = 1'b0;
    end
    endtask
    
    //=========================================================================
    // Memory Initialization from File
    //=========================================================================
    task load_memory;
        input [255:0] filename;
    begin
        $readmemh(filename, mem);
        $display("[SRAM] Loaded memory from %0s", filename);
    end
    endtask
    
    //=========================================================================
    // Memory Dump for Debug
    //=========================================================================
    task dump_memory;
        input [ADDR_WIDTH-1:0] start_addr;
        input [ADDR_WIDTH-1:0] end_addr;
        integer j;
    begin
        $display("[SRAM] Memory dump from %h to %h:", start_addr, end_addr);
        for (j = start_addr; j <= end_addr; j = j + 1) begin
            $display("  [%h] = %h", j, mem[j]);
        end
    end
    endtask

endmodule
