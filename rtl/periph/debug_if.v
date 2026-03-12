//=============================================================================
// Module: debug_if
// Description: Debug Interface Module
//              Provides external debug access via UART
//              Implements complete debug command protocol
//
// Commands:
//   'H' - Halt CPU
//   'R' - Resume CPU
//   'S' - Single Step
//   'P' - Read PC
//   'G' nn - Read GPR register nn (00-31)
//   'C' nn - Read CSR register nnnn
//   'M' aaaa - Read memory at address aaaa
//   'W' aaaa dddd - Write memory at address aaaa with data dddd
//   'B' aaaa - Set breakpoint at address aaaa
//   'D' aaaa - Delete breakpoint at address aaaa
//   'L' - List breakpoints
//   'I' - Get CPU info/status
//   '?' - Help
//
// Response Format:
//   OK: '+' followed by data (if any)
//   Error: '-' followed by error code
//
// Requirements: 5.1, 5.2, 5.3, 5.4
//=============================================================================

`timescale 1ns/1ps

module debug_if #(
    parameter XLEN = 32,
    parameter NUM_BREAKPOINTS = 4,
    parameter TIMEOUT_CYCLES = 1000000  // ~20ms at 50MHz
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================================
    // UART Interface
    //=========================================================================
    input  wire [7:0]              uart_rx_data,
    input  wire                    uart_rx_valid,
    output reg  [7:0]              uart_tx_data,
    output reg                     uart_tx_valid,
    input  wire                    uart_tx_ready,
    
    //=========================================================================
    // CPU Debug Interface
    //=========================================================================
    output reg                     cpu_halt_req,
    output reg                     cpu_resume_req,
    output reg                     cpu_step_req,
    input  wire                    cpu_halted,
    input  wire                    cpu_running,
    input  wire [XLEN-1:0]         cpu_pc,
    input  wire [XLEN-1:0]         cpu_instr,
    
    //=========================================================================
    // Register Read Interface
    //=========================================================================
    output reg  [4:0]              gpr_addr,
    output reg                     gpr_read_req,
    input  wire [XLEN-1:0]         gpr_rdata,
    input  wire                    gpr_rdata_valid,
    
    output reg  [11:0]             csr_addr,
    output reg                     csr_read_req,
    input  wire [XLEN-1:0]         csr_rdata,
    input  wire                    csr_rdata_valid,
    
    //=========================================================================
    // Memory Debug Interface
    //=========================================================================
    output reg  [XLEN-1:0]         dbg_mem_addr,
    output reg  [XLEN-1:0]         dbg_mem_wdata,
    output reg                     dbg_mem_read,
    output reg                     dbg_mem_write,
    output reg  [1:0]              dbg_mem_size,  // 0=byte, 1=half, 2=word
    input  wire [XLEN-1:0]         dbg_mem_rdata,
    input  wire                    dbg_mem_done,
    input  wire                    dbg_mem_error,
    
    //=========================================================================
    // Breakpoint Interface
    //=========================================================================
    output reg  [NUM_BREAKPOINTS-1:0]        bp_enable,
    output reg  [XLEN-1:0]                   bp_addr_0,
    output reg  [XLEN-1:0]                   bp_addr_1,
    output reg  [XLEN-1:0]                   bp_addr_2,
    output reg  [XLEN-1:0]                   bp_addr_3,
    input  wire                              bp_hit,
    input  wire [$clog2(NUM_BREAKPOINTS)-1:0] bp_hit_idx,
    
    //=========================================================================
    // Status
    //=========================================================================
    output wire                    debug_active,
    output reg  [7:0]              error_code
);

    //=========================================================================
    // State Machine
    //=========================================================================
    localparam [4:0]
        ST_IDLE           = 5'd0,
        ST_RECV_CMD       = 5'd1,
        ST_RECV_ADDR_0    = 5'd2,
        ST_RECV_ADDR_1    = 5'd3,
        ST_RECV_ADDR_2    = 5'd4,
        ST_RECV_ADDR_3    = 5'd5,
        ST_RECV_ADDR_4    = 5'd6,
        ST_RECV_ADDR_5    = 5'd7,
        ST_RECV_ADDR_6    = 5'd8,
        ST_RECV_ADDR_7    = 5'd9,
        ST_RECV_DATA_0    = 5'd10,
        ST_RECV_DATA_1    = 5'd11,
        ST_RECV_DATA_2    = 5'd12,
        ST_RECV_DATA_3    = 5'd13,
        ST_RECV_DATA_4    = 5'd14,
        ST_RECV_DATA_5    = 5'd15,
        ST_RECV_DATA_6    = 5'd16,
        ST_RECV_DATA_7    = 5'd17,
        ST_EXEC_CMD       = 5'd18,
        ST_WAIT_HALT      = 5'd19,
        ST_WAIT_RESUME    = 5'd20,
        ST_WAIT_STEP      = 5'd21,
        ST_WAIT_MEM       = 5'd22,
        ST_WAIT_REG       = 5'd23,
        ST_SEND_RESP      = 5'd24,
        ST_SEND_DATA      = 5'd25,
        ST_ERROR          = 5'd26;
    
    reg [4:0] state;
    reg [4:0] next_state;
    
    //=========================================================================
    // Command Codes
    //=========================================================================
    localparam [7:0]
        CMD_HALT      = "H",
        CMD_RESUME    = "R",
        CMD_STEP      = "S",
        CMD_READ_PC   = "P",
        CMD_READ_GPR  = "G",
        CMD_READ_CSR  = "C",
        CMD_READ_MEM  = "M",
        CMD_WRITE_MEM = "W",
        CMD_SET_BP    = "B",
        CMD_DEL_BP    = "D",
        CMD_LIST_BP   = "L",
        CMD_INFO      = "I",
        CMD_HELP      = "?";
    
    //=========================================================================
    // Error Codes
    //=========================================================================
    localparam [7:0]
        ERR_NONE          = 8'h00,
        ERR_INVALID_CMD   = 8'h01,
        ERR_TIMEOUT       = 8'h02,
        ERR_NOT_HALTED    = 8'h03,
        ERR_MEM_ERROR     = 8'h04,
        ERR_INVALID_ADDR  = 8'h05,
        ERR_BP_FULL       = 8'h06,
        ERR_BP_NOT_FOUND  = 8'h07,
        ERR_INVALID_REG   = 8'h08;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [7:0]  cmd_reg;
    reg [31:0] addr_reg;
    reg [31:0] data_reg;
    reg [31:0] resp_data;
    reg [3:0]  resp_len;
    reg [3:0]  resp_idx;
    reg [31:0] timeout_cnt;
    reg        cmd_valid;
    
    // Breakpoint management - internal storage
    reg [XLEN-1:0] bp_addr_int [0:NUM_BREAKPOINTS-1];
    integer bp_idx;
    reg [$clog2(NUM_BREAKPOINTS)-1:0] bp_slot;
    reg bp_found;
    
    //=========================================================================
    // ASCII Hex Conversion Functions
    //=========================================================================
    function [3:0] hex_to_nibble;
        input [7:0] ascii;
        begin
            if (ascii >= "0" && ascii <= "9")
                hex_to_nibble = ascii - "0";
            else if (ascii >= "A" && ascii <= "F")
                hex_to_nibble = ascii - "A" + 10;
            else if (ascii >= "a" && ascii <= "f")
                hex_to_nibble = ascii - "a" + 10;
            else
                hex_to_nibble = 4'h0;
        end
    endfunction
    
    function [7:0] nibble_to_hex;
        input [3:0] nibble;
        begin
            if (nibble < 10)
                nibble_to_hex = "0" + nibble;
            else
                nibble_to_hex = "A" + nibble - 10;
        end
    endfunction
    
    //=========================================================================
    // Debug Active Signal
    //=========================================================================
    assign debug_active = (state != ST_IDLE);
    
    //=========================================================================
    // Timeout Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 32'd0;
        end else begin
            if (state == ST_IDLE || state == ST_RECV_CMD) begin
                timeout_cnt <= 32'd0;
            end else if (timeout_cnt < TIMEOUT_CYCLES) begin
                timeout_cnt <= timeout_cnt + 1;
            end
        end
    end
    
    wire timeout = (timeout_cnt >= TIMEOUT_CYCLES);


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
                if (uart_rx_valid) begin
                    // Use uart_rx_data directly for immediate command decode
                    case (uart_rx_data)
                        CMD_HALT, CMD_RESUME, CMD_STEP, CMD_READ_PC, CMD_INFO, CMD_HELP, CMD_LIST_BP:
                            next_state = ST_EXEC_CMD;
                        CMD_READ_GPR, CMD_READ_CSR, CMD_READ_MEM, CMD_SET_BP, CMD_DEL_BP, CMD_WRITE_MEM:
                            next_state = ST_RECV_ADDR_0;
                        default:
                            next_state = ST_ERROR;
                    endcase
                end
            end
            
            ST_RECV_CMD: begin
                // This state is no longer used for simple commands
                // Keep for compatibility but should not be reached
                next_state = ST_EXEC_CMD;
            end
            
            // Address reception (8 hex digits = 32 bits)
            ST_RECV_ADDR_0: if (uart_rx_valid) next_state = ST_RECV_ADDR_1;
            ST_RECV_ADDR_1: if (uart_rx_valid) next_state = ST_RECV_ADDR_2;
            ST_RECV_ADDR_2: if (uart_rx_valid) next_state = ST_RECV_ADDR_3;
            ST_RECV_ADDR_3: if (uart_rx_valid) next_state = ST_RECV_ADDR_4;
            ST_RECV_ADDR_4: if (uart_rx_valid) next_state = ST_RECV_ADDR_5;
            ST_RECV_ADDR_5: if (uart_rx_valid) next_state = ST_RECV_ADDR_6;
            ST_RECV_ADDR_6: if (uart_rx_valid) next_state = ST_RECV_ADDR_7;
            ST_RECV_ADDR_7: begin
                if (uart_rx_valid) begin
                    if (cmd_reg == CMD_WRITE_MEM)
                        next_state = ST_RECV_DATA_0;
                    else if (cmd_reg == CMD_READ_GPR || cmd_reg == CMD_READ_CSR)
                        next_state = ST_EXEC_CMD;  // Only need 2 digits for reg
                    else
                        next_state = ST_EXEC_CMD;
                end
            end
            
            // Data reception for write (8 hex digits = 32 bits)
            ST_RECV_DATA_0: if (uart_rx_valid) next_state = ST_RECV_DATA_1;
            ST_RECV_DATA_1: if (uart_rx_valid) next_state = ST_RECV_DATA_2;
            ST_RECV_DATA_2: if (uart_rx_valid) next_state = ST_RECV_DATA_3;
            ST_RECV_DATA_3: if (uart_rx_valid) next_state = ST_RECV_DATA_4;
            ST_RECV_DATA_4: if (uart_rx_valid) next_state = ST_RECV_DATA_5;
            ST_RECV_DATA_5: if (uart_rx_valid) next_state = ST_RECV_DATA_6;
            ST_RECV_DATA_6: if (uart_rx_valid) next_state = ST_RECV_DATA_7;
            ST_RECV_DATA_7: if (uart_rx_valid) next_state = ST_EXEC_CMD;
            
            ST_EXEC_CMD: begin
                case (cmd_reg)
                    CMD_HALT:     next_state = ST_WAIT_HALT;
                    CMD_RESUME:   next_state = ST_WAIT_RESUME;
                    CMD_STEP:     next_state = ST_WAIT_STEP;
                    CMD_READ_PC:  next_state = ST_SEND_RESP;
                    CMD_READ_GPR: next_state = ST_WAIT_REG;
                    CMD_READ_CSR: next_state = ST_WAIT_REG;
                    CMD_READ_MEM: next_state = ST_WAIT_MEM;
                    CMD_WRITE_MEM: next_state = ST_WAIT_MEM;
                    CMD_SET_BP, CMD_DEL_BP, CMD_LIST_BP, CMD_INFO, CMD_HELP:
                        next_state = ST_SEND_RESP;
                    default:      next_state = ST_ERROR;
                endcase
            end
            
            ST_WAIT_HALT: begin
                if (cpu_halted)
                    next_state = ST_SEND_RESP;
                else if (timeout)
                    next_state = ST_ERROR;
            end
            
            ST_WAIT_RESUME: begin
                if (cpu_running)
                    next_state = ST_SEND_RESP;
                else if (timeout)
                    next_state = ST_ERROR;
            end
            
            ST_WAIT_STEP: begin
                if (cpu_halted)  // Step completes when CPU halts again
                    next_state = ST_SEND_RESP;
                else if (timeout)
                    next_state = ST_ERROR;
            end
            
            ST_WAIT_MEM: begin
                if (dbg_mem_done)
                    next_state = ST_SEND_RESP;
                else if (dbg_mem_error)
                    next_state = ST_ERROR;
                else if (timeout)
                    next_state = ST_ERROR;
            end
            
            ST_WAIT_REG: begin
                if (gpr_rdata_valid || csr_rdata_valid)
                    next_state = ST_SEND_RESP;
                else if (timeout)
                    next_state = ST_ERROR;
            end
            
            ST_SEND_RESP: begin
                if (uart_tx_ready && uart_tx_valid) begin
                    if (resp_idx + 1 >= resp_len)
                        next_state = ST_IDLE;
                    else
                        next_state = ST_SEND_DATA;
                end
            end
            
            ST_SEND_DATA: begin
                if (uart_tx_ready && uart_tx_valid) begin
                    if (resp_idx + 1 >= resp_len)
                        next_state = ST_IDLE;
                end
            end
            
            ST_ERROR: begin
                if (uart_tx_ready && uart_tx_valid)
                    next_state = ST_IDLE;
            end
            
            default: next_state = ST_IDLE;
        endcase
        
        // Timeout override
        if (timeout && state != ST_IDLE && state != ST_ERROR && 
            state != ST_SEND_RESP && state != ST_SEND_DATA) begin
            next_state = ST_ERROR;
        end
    end


    //=========================================================================
    // Command and Address/Data Reception
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_reg <= 8'd0;
            addr_reg <= 32'd0;
            data_reg <= 32'd0;
            cmd_valid <= 1'b0;
        end else begin
            cmd_valid <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    if (uart_rx_valid) begin
                        cmd_reg <= uart_rx_data;
                        addr_reg <= 32'd0;
                        data_reg <= 32'd0;
                    end
                end
                
                // Address reception
                ST_RECV_ADDR_0: if (uart_rx_valid) addr_reg[31:28] <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_1: if (uart_rx_valid) addr_reg[27:24] <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_2: if (uart_rx_valid) addr_reg[23:20] <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_3: if (uart_rx_valid) addr_reg[19:16] <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_4: if (uart_rx_valid) addr_reg[15:12] <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_5: if (uart_rx_valid) addr_reg[11:8]  <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_6: if (uart_rx_valid) addr_reg[7:4]   <= hex_to_nibble(uart_rx_data);
                ST_RECV_ADDR_7: if (uart_rx_valid) begin
                    addr_reg[3:0] <= hex_to_nibble(uart_rx_data);
                    cmd_valid <= 1'b1;
                end
                
                // Data reception
                ST_RECV_DATA_0: if (uart_rx_valid) data_reg[31:28] <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_1: if (uart_rx_valid) data_reg[27:24] <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_2: if (uart_rx_valid) data_reg[23:20] <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_3: if (uart_rx_valid) data_reg[19:16] <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_4: if (uart_rx_valid) data_reg[15:12] <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_5: if (uart_rx_valid) data_reg[11:8]  <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_6: if (uart_rx_valid) data_reg[7:4]   <= hex_to_nibble(uart_rx_data);
                ST_RECV_DATA_7: if (uart_rx_valid) begin
                    data_reg[3:0] <= hex_to_nibble(uart_rx_data);
                    cmd_valid <= 1'b1;
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // CPU Control Signals
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_halt_req <= 1'b0;
            cpu_resume_req <= 1'b0;
            cpu_step_req <= 1'b0;
        end else begin
            // Default: deassert all requests
            cpu_halt_req <= 1'b0;
            cpu_resume_req <= 1'b0;
            cpu_step_req <= 1'b0;
            
            if (state == ST_EXEC_CMD) begin
                case (cmd_reg)
                    CMD_HALT:   cpu_halt_req <= 1'b1;
                    CMD_RESUME: cpu_resume_req <= 1'b1;
                    CMD_STEP:   cpu_step_req <= 1'b1;
                    default: ;
                endcase
            end
        end
    end
    
    //=========================================================================
    // Register Read Interface
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpr_addr <= 5'd0;
            gpr_read_req <= 1'b0;
            csr_addr <= 12'd0;
            csr_read_req <= 1'b0;
        end else begin
            gpr_read_req <= 1'b0;
            csr_read_req <= 1'b0;
            
            if (state == ST_EXEC_CMD) begin
                if (cmd_reg == CMD_READ_GPR) begin
                    gpr_addr <= addr_reg[4:0];
                    gpr_read_req <= 1'b1;
                end else if (cmd_reg == CMD_READ_CSR) begin
                    csr_addr <= addr_reg[11:0];
                    csr_read_req <= 1'b1;
                end
            end
        end
    end
    
    //=========================================================================
    // Memory Debug Interface
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_mem_addr <= 32'd0;
            dbg_mem_wdata <= 32'd0;
            dbg_mem_read <= 1'b0;
            dbg_mem_write <= 1'b0;
            dbg_mem_size <= 2'd2;  // Default word access
        end else begin
            dbg_mem_read <= 1'b0;
            dbg_mem_write <= 1'b0;
            
            if (state == ST_EXEC_CMD) begin
                dbg_mem_addr <= addr_reg;
                dbg_mem_size <= 2'd2;  // Word access
                
                if (cmd_reg == CMD_READ_MEM) begin
                    dbg_mem_read <= 1'b1;
                end else if (cmd_reg == CMD_WRITE_MEM) begin
                    dbg_mem_wdata <= data_reg;
                    dbg_mem_write <= 1'b1;
                end
            end
        end
    end


    //=========================================================================
    // Breakpoint Management
    //=========================================================================
    integer i;
    
    // Output breakpoint addresses from internal storage
    always @(*) begin
        bp_addr_0 = bp_addr_int[0];
        bp_addr_1 = bp_addr_int[1];
        bp_addr_2 = bp_addr_int[2];
        bp_addr_3 = bp_addr_int[3];
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bp_enable <= {NUM_BREAKPOINTS{1'b0}};
            for (i = 0; i < NUM_BREAKPOINTS; i = i + 1) begin
                bp_addr_int[i] <= 32'd0;
            end
            bp_slot <= 0;
            bp_found <= 1'b0;
        end else begin
            bp_found <= 1'b0;
            
            if (state == ST_EXEC_CMD) begin
                if (cmd_reg == CMD_SET_BP) begin
                    // Find empty slot - use local variable for immediate check
                    if (!bp_enable[0]) begin
                        bp_enable[0] <= 1'b1;
                        bp_addr_int[0] <= addr_reg;
                        bp_slot <= 2'd0;
                        bp_found <= 1'b1;
                    end else if (!bp_enable[1]) begin
                        bp_enable[1] <= 1'b1;
                        bp_addr_int[1] <= addr_reg;
                        bp_slot <= 2'd1;
                        bp_found <= 1'b1;
                    end else if (!bp_enable[2]) begin
                        bp_enable[2] <= 1'b1;
                        bp_addr_int[2] <= addr_reg;
                        bp_slot <= 2'd2;
                        bp_found <= 1'b1;
                    end else if (!bp_enable[3]) begin
                        bp_enable[3] <= 1'b1;
                        bp_addr_int[3] <= addr_reg;
                        bp_slot <= 2'd3;
                        bp_found <= 1'b1;
                    end
                end else if (cmd_reg == CMD_DEL_BP) begin
                    // Find and delete breakpoint
                    for (i = 0; i < NUM_BREAKPOINTS; i = i + 1) begin
                        if (bp_enable[i] && bp_addr_int[i] == addr_reg) begin
                            bp_enable[i] <= 1'b0;
                            bp_found <= 1'b1;
                        end
                    end
                end
            end
        end
    end
    
    //=========================================================================
    // Response Generation
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_data <= 32'd0;
            resp_len <= 4'd0;
            resp_idx <= 4'd0;
            error_code <= ERR_NONE;
        end else begin
            case (state)
                ST_EXEC_CMD: begin
                    resp_idx <= 4'd0;
                    error_code <= ERR_NONE;
                    
                    case (cmd_reg)
                        CMD_HALT, CMD_RESUME, CMD_STEP: begin
                            resp_len <= 4'd1;  // Just '+' or '-'
                        end
                        
                        CMD_READ_PC: begin
                            resp_data <= cpu_pc;
                            resp_len <= 4'd9;  // '+' + 8 hex digits
                        end
                        
                        CMD_READ_GPR, CMD_READ_CSR: begin
                            resp_len <= 4'd9;  // '+' + 8 hex digits
                        end
                        
                        CMD_READ_MEM: begin
                            resp_len <= 4'd9;  // '+' + 8 hex digits
                        end
                        
                        CMD_WRITE_MEM: begin
                            resp_len <= 4'd1;  // Just '+'
                        end
                        
                        CMD_SET_BP, CMD_DEL_BP: begin
                            resp_len <= 4'd1;
                        end
                        
                        CMD_LIST_BP: begin
                            resp_len <= 4'd1;  // Simplified: just acknowledge
                        end
                        
                        CMD_INFO: begin
                            resp_data <= {cpu_halted, cpu_running, 30'd0};
                            resp_len <= 4'd9;
                        end
                        
                        CMD_HELP: begin
                            resp_len <= 4'd1;
                        end
                        
                        default: begin
                            error_code <= ERR_INVALID_CMD;
                            resp_len <= 4'd2;  // '-' + error code
                        end
                    endcase
                end
                
                ST_WAIT_MEM: begin
                    if (dbg_mem_done) begin
                        if (cmd_reg == CMD_READ_MEM) begin
                            resp_data <= dbg_mem_rdata;
                        end
                    end else if (dbg_mem_error) begin
                        error_code <= ERR_MEM_ERROR;
                    end
                end
                
                ST_WAIT_REG: begin
                    if (gpr_rdata_valid) begin
                        resp_data <= gpr_rdata;
                    end else if (csr_rdata_valid) begin
                        resp_data <= csr_rdata;
                    end
                end
                
                ST_SEND_RESP, ST_SEND_DATA: begin
                    if (uart_tx_ready && uart_tx_valid) begin
                        resp_idx <= resp_idx + 1;
                    end
                end
                
                ST_ERROR: begin
                    // Set error code if not already set
                    if (error_code == ERR_NONE) begin
                        if (timeout) begin
                            error_code <= ERR_TIMEOUT;
                        end else begin
                            error_code <= ERR_INVALID_CMD;
                        end
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // UART TX Output
    //=========================================================================
    always @(*) begin
        uart_tx_data = 8'd0;
        uart_tx_valid = 1'b0;
        
        case (state)
            ST_SEND_RESP: begin
                uart_tx_valid = 1'b1;
                if (error_code != ERR_NONE) begin
                    uart_tx_data = "-";
                end else begin
                    uart_tx_data = "+";
                end
            end
            
            ST_SEND_DATA: begin
                uart_tx_valid = 1'b1;
                if (error_code != ERR_NONE) begin
                    // Send error code as hex
                    case (resp_idx)
                        4'd1: uart_tx_data = nibble_to_hex(error_code[7:4]);
                        4'd2: uart_tx_data = nibble_to_hex(error_code[3:0]);
                        default: uart_tx_data = 8'd0;
                    endcase
                end else begin
                    // Send response data as hex
                    case (resp_idx)
                        4'd1: uart_tx_data = nibble_to_hex(resp_data[31:28]);
                        4'd2: uart_tx_data = nibble_to_hex(resp_data[27:24]);
                        4'd3: uart_tx_data = nibble_to_hex(resp_data[23:20]);
                        4'd4: uart_tx_data = nibble_to_hex(resp_data[19:16]);
                        4'd5: uart_tx_data = nibble_to_hex(resp_data[15:12]);
                        4'd6: uart_tx_data = nibble_to_hex(resp_data[11:8]);
                        4'd7: uart_tx_data = nibble_to_hex(resp_data[7:4]);
                        4'd8: uart_tx_data = nibble_to_hex(resp_data[3:0]);
                        default: uart_tx_data = 8'd0;
                    endcase
                end
            end
            
            ST_ERROR: begin
                uart_tx_valid = 1'b1;
                uart_tx_data = "-";
            end
            
            default: ;
        endcase
    end

endmodule
