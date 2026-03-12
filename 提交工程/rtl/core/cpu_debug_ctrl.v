//=============================================================================
// Module: cpu_debug_ctrl
// Description: CPU Debug Controller
//              Bridges debug interface with CPU core
//              Handles halt/resume/step control
//              Provides register and memory access during debug
//
// Features:
//   - Halt CPU at instruction boundary
//   - Single-step execution
//   - GPR register read access
//   - CSR register read access
//   - Debug memory access (bypasses cache)
//   - Breakpoint hit detection
//
// Requirements: 5.1, 5.2, 5.3, 5.4
//=============================================================================

`timescale 1ns/1ps

module cpu_debug_ctrl #(
    parameter XLEN = 32,
    parameter PHYS_REG_BITS = 6,
    parameter NUM_BREAKPOINTS = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,
    
    //=========================================================================
    // Debug Interface Signals (from debug_if)
    //=========================================================================
    input  wire                    dbg_halt_req,
    input  wire                    dbg_resume_req,
    input  wire                    dbg_step_req,
    output reg                     dbg_halted,
    output reg                     dbg_running,
    output wire [XLEN-1:0]         dbg_pc,
    output wire [XLEN-1:0]         dbg_instr,
    
    // GPR Read Interface
    input  wire [4:0]              dbg_gpr_addr,
    input  wire                    dbg_gpr_read_req,
    output reg  [XLEN-1:0]         dbg_gpr_rdata,
    output reg                     dbg_gpr_rdata_valid,
    
    // CSR Read Interface
    input  wire [11:0]             dbg_csr_addr,
    input  wire                    dbg_csr_read_req,
    output reg  [XLEN-1:0]         dbg_csr_rdata,
    output reg                     dbg_csr_rdata_valid,
    
    // Debug Memory Interface
    input  wire [XLEN-1:0]         dbg_mem_addr,
    input  wire [XLEN-1:0]         dbg_mem_wdata,
    input  wire                    dbg_mem_read,
    input  wire                    dbg_mem_write,
    input  wire [1:0]              dbg_mem_size,
    output reg  [XLEN-1:0]         dbg_mem_rdata,
    output reg                     dbg_mem_done,
    output reg                     dbg_mem_error,
    
    // Breakpoint Interface
    input  wire [NUM_BREAKPOINTS-1:0] bp_enable,
    input  wire [XLEN-1:0]         bp_addr_0,
    input  wire [XLEN-1:0]         bp_addr_1,
    input  wire [XLEN-1:0]         bp_addr_2,
    input  wire [XLEN-1:0]         bp_addr_3,
    output reg                     bp_hit,
    output reg  [$clog2(NUM_BREAKPOINTS)-1:0] bp_hit_idx,
    
    //=========================================================================
    // CPU Pipeline Control
    //=========================================================================
    output reg                     cpu_halt,        // Halt pipeline
    output reg                     cpu_step_en,     // Enable single step
    input  wire                    cpu_commit_valid, // Instruction committed
    input  wire [XLEN-1:0]         cpu_commit_pc,   // Committed PC
    input  wire [XLEN-1:0]         cpu_commit_instr, // Committed instruction
    
    //=========================================================================
    // GPR Read Interface (to PRF)
    //=========================================================================
    output reg  [PHYS_REG_BITS-1:0] prf_dbg_addr,
    output reg                     prf_dbg_read,
    input  wire [XLEN-1:0]         prf_dbg_rdata,
    input  wire                    prf_dbg_rdata_valid,
    
    // Architectural to Physical mapping (from RAT)
    output reg  [4:0]              rat_dbg_arch_addr,
    input  wire [PHYS_REG_BITS-1:0] rat_dbg_phys_addr,
    
    //=========================================================================
    // CSR Read Interface (to CSR unit)
    //=========================================================================
    output reg  [11:0]             csr_dbg_addr,
    output reg                     csr_dbg_read,
    input  wire [XLEN-1:0]         csr_dbg_rdata,
    input  wire                    csr_dbg_illegal,
    
    //=========================================================================
    // Debug Memory Interface (to AXI)
    //=========================================================================
    output reg                     dbg_axi_awvalid,
    input  wire                    dbg_axi_awready,
    output reg  [XLEN-1:0]         dbg_axi_awaddr,
    output reg                     dbg_axi_wvalid,
    input  wire                    dbg_axi_wready,
    output reg  [XLEN-1:0]         dbg_axi_wdata,
    output reg  [3:0]              dbg_axi_wstrb,
    input  wire                    dbg_axi_bvalid,
    output reg                     dbg_axi_bready,
    input  wire [1:0]              dbg_axi_bresp,
    output reg                     dbg_axi_arvalid,
    input  wire                    dbg_axi_arready,
    output reg  [XLEN-1:0]         dbg_axi_araddr,
    input  wire                    dbg_axi_rvalid,
    output reg                     dbg_axi_rready,
    input  wire [XLEN-1:0]         dbg_axi_rdata,
    input  wire [1:0]              dbg_axi_rresp
);

    //=========================================================================
    // Debug State Machine
    //=========================================================================
    localparam [2:0]
        DBG_RUNNING     = 3'd0,
        DBG_HALT_WAIT   = 3'd1,
        DBG_HALTED      = 3'd2,
        DBG_STEP_EXEC   = 3'd3,
        DBG_STEP_WAIT   = 3'd4,
        DBG_RESUME_WAIT = 3'd5;
    
    reg [2:0] dbg_state;
    reg [2:0] dbg_next_state;
    
    //=========================================================================
    // Memory Access State Machine
    //=========================================================================
    localparam [2:0]
        MEM_IDLE        = 3'd0,
        MEM_READ_ADDR   = 3'd1,
        MEM_READ_DATA   = 3'd2,
        MEM_WRITE_ADDR  = 3'd3,
        MEM_WRITE_DATA  = 3'd4,
        MEM_WRITE_RESP  = 3'd5;
    
    reg [2:0] mem_state;
    reg [2:0] mem_next_state;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [XLEN-1:0] last_commit_pc;
    reg [XLEN-1:0] last_commit_instr;
    reg            step_pending;
    reg [3:0]      halt_delay_cnt;
    
    // GPR read pipeline
    reg            gpr_read_pending;
    reg [1:0]      gpr_read_stage;
    
    // CSR read pipeline
    reg            csr_read_pending;
    
    //=========================================================================
    // Debug PC and Instruction Output
    //=========================================================================
    assign dbg_pc = last_commit_pc;
    assign dbg_instr = last_commit_instr;
    
    //=========================================================================
    // Breakpoint Detection
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bp_hit <= 1'b0;
            bp_hit_idx <= 0;
        end else begin
            bp_hit <= 1'b0;
            
            if (cpu_commit_valid && !dbg_halted) begin
                // Check each breakpoint
                if (bp_enable[0] && cpu_commit_pc == bp_addr_0) begin
                    bp_hit <= 1'b1;
                    bp_hit_idx <= 2'd0;
                end else if (bp_enable[1] && cpu_commit_pc == bp_addr_1) begin
                    bp_hit <= 1'b1;
                    bp_hit_idx <= 2'd1;
                end else if (bp_enable[2] && cpu_commit_pc == bp_addr_2) begin
                    bp_hit <= 1'b1;
                    bp_hit_idx <= 2'd2;
                end else if (bp_enable[3] && cpu_commit_pc == bp_addr_3) begin
                    bp_hit <= 1'b1;
                    bp_hit_idx <= 2'd3;
                end
            end
        end
    end
    
    //=========================================================================
    // Track Last Committed Instruction
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_commit_pc <= 32'h0;
            last_commit_instr <= 32'h0;
        end else begin
            if (cpu_commit_valid) begin
                last_commit_pc <= cpu_commit_pc;
                last_commit_instr <= cpu_commit_instr;
            end
        end
    end

    //=========================================================================
    // Debug State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_state <= DBG_RUNNING;
        end else begin
            dbg_state <= dbg_next_state;
        end
    end
    
    //=========================================================================
    // Debug State Machine - Combinational
    //=========================================================================
    always @(*) begin
        dbg_next_state = dbg_state;
        
        case (dbg_state)
            DBG_RUNNING: begin
                if (dbg_halt_req || bp_hit) begin
                    dbg_next_state = DBG_HALT_WAIT;
                end
            end
            
            DBG_HALT_WAIT: begin
                // Wait for pipeline to drain (instruction boundary)
                if (halt_delay_cnt == 4'd0) begin
                    dbg_next_state = DBG_HALTED;
                end
            end
            
            DBG_HALTED: begin
                if (dbg_resume_req) begin
                    dbg_next_state = DBG_RESUME_WAIT;
                end else if (dbg_step_req) begin
                    dbg_next_state = DBG_STEP_EXEC;
                end
            end
            
            DBG_STEP_EXEC: begin
                // Enable pipeline for one instruction
                dbg_next_state = DBG_STEP_WAIT;
            end
            
            DBG_STEP_WAIT: begin
                // Wait for instruction to commit
                if (cpu_commit_valid) begin
                    dbg_next_state = DBG_HALTED;
                end
            end
            
            DBG_RESUME_WAIT: begin
                // Small delay before full resume
                dbg_next_state = DBG_RUNNING;
            end
            
            default: dbg_next_state = DBG_RUNNING;
        endcase
    end
    
    //=========================================================================
    // Debug Control Outputs
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_halted <= 1'b0;
            dbg_running <= 1'b1;
            cpu_halt <= 1'b0;
            cpu_step_en <= 1'b0;
            halt_delay_cnt <= 4'd0;
        end else begin
            case (dbg_state)
                DBG_RUNNING: begin
                    dbg_halted <= 1'b0;
                    dbg_running <= 1'b1;
                    cpu_halt <= 1'b0;
                    cpu_step_en <= 1'b0;
                    halt_delay_cnt <= 4'd4;  // Pipeline drain delay
                end
                
                DBG_HALT_WAIT: begin
                    cpu_halt <= 1'b1;  // Assert halt
                    dbg_running <= 1'b0;
                    if (halt_delay_cnt > 0) begin
                        halt_delay_cnt <= halt_delay_cnt - 1;
                    end
                end
                
                DBG_HALTED: begin
                    dbg_halted <= 1'b1;
                    dbg_running <= 1'b0;
                    cpu_halt <= 1'b1;
                    cpu_step_en <= 1'b0;
                end
                
                DBG_STEP_EXEC: begin
                    cpu_step_en <= 1'b1;  // Enable single step
                    cpu_halt <= 1'b0;     // Release halt briefly
                end
                
                DBG_STEP_WAIT: begin
                    cpu_step_en <= 1'b0;
                    cpu_halt <= 1'b1;     // Re-halt after step
                end
                
                DBG_RESUME_WAIT: begin
                    dbg_halted <= 1'b0;
                    cpu_halt <= 1'b0;
                end
                
                default: ;
            endcase
        end
    end
    
    //=========================================================================
    // GPR Read Logic
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpr_read_pending <= 1'b0;
            gpr_read_stage <= 2'd0;
            dbg_gpr_rdata <= 32'd0;
            dbg_gpr_rdata_valid <= 1'b0;
            rat_dbg_arch_addr <= 5'd0;
            prf_dbg_addr <= 6'd0;
            prf_dbg_read <= 1'b0;
        end else begin
            dbg_gpr_rdata_valid <= 1'b0;
            prf_dbg_read <= 1'b0;
            
            if (dbg_gpr_read_req && dbg_halted && !gpr_read_pending) begin
                // Start GPR read - first get physical register from RAT
                gpr_read_pending <= 1'b1;
                gpr_read_stage <= 2'd0;
                rat_dbg_arch_addr <= dbg_gpr_addr;
            end else if (gpr_read_pending) begin
                case (gpr_read_stage)
                    2'd0: begin
                        // RAT lookup cycle - get physical register
                        prf_dbg_addr <= rat_dbg_phys_addr;
                        prf_dbg_read <= 1'b1;
                        gpr_read_stage <= 2'd1;
                    end
                    
                    2'd1: begin
                        // Wait for PRF read
                        gpr_read_stage <= 2'd2;
                    end
                    
                    2'd2: begin
                        // PRF data ready
                        if (prf_dbg_rdata_valid) begin
                            dbg_gpr_rdata <= prf_dbg_rdata;
                            dbg_gpr_rdata_valid <= 1'b1;
                            gpr_read_pending <= 1'b0;
                        end else begin
                            // Fallback: use data directly
                            dbg_gpr_rdata <= prf_dbg_rdata;
                            dbg_gpr_rdata_valid <= 1'b1;
                            gpr_read_pending <= 1'b0;
                        end
                    end
                    
                    default: begin
                        gpr_read_pending <= 1'b0;
                    end
                endcase
            end
        end
    end
    
    //=========================================================================
    // CSR Read Logic
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_read_pending <= 1'b0;
            dbg_csr_rdata <= 32'd0;
            dbg_csr_rdata_valid <= 1'b0;
            csr_dbg_addr <= 12'd0;
            csr_dbg_read <= 1'b0;
        end else begin
            dbg_csr_rdata_valid <= 1'b0;
            csr_dbg_read <= 1'b0;
            
            if (dbg_csr_read_req && dbg_halted && !csr_read_pending) begin
                // Start CSR read
                csr_read_pending <= 1'b1;
                csr_dbg_addr <= dbg_csr_addr;
                csr_dbg_read <= 1'b1;
            end else if (csr_read_pending) begin
                // CSR read completes in one cycle
                dbg_csr_rdata <= csr_dbg_rdata;
                dbg_csr_rdata_valid <= 1'b1;
                csr_read_pending <= 1'b0;
            end
        end
    end

    //=========================================================================
    // Memory Access State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state <= MEM_IDLE;
        end else begin
            mem_state <= mem_next_state;
        end
    end
    
    //=========================================================================
    // Memory Access State Machine - Combinational
    //=========================================================================
    always @(*) begin
        mem_next_state = mem_state;
        
        case (mem_state)
            MEM_IDLE: begin
                if (dbg_halted) begin
                    if (dbg_mem_read) begin
                        mem_next_state = MEM_READ_ADDR;
                    end else if (dbg_mem_write) begin
                        mem_next_state = MEM_WRITE_ADDR;
                    end
                end
            end
            
            MEM_READ_ADDR: begin
                if (dbg_axi_arready) begin
                    mem_next_state = MEM_READ_DATA;
                end
            end
            
            MEM_READ_DATA: begin
                if (dbg_axi_rvalid) begin
                    mem_next_state = MEM_IDLE;
                end
            end
            
            MEM_WRITE_ADDR: begin
                if (dbg_axi_awready) begin
                    mem_next_state = MEM_WRITE_DATA;
                end
            end
            
            MEM_WRITE_DATA: begin
                if (dbg_axi_wready) begin
                    mem_next_state = MEM_WRITE_RESP;
                end
            end
            
            MEM_WRITE_RESP: begin
                if (dbg_axi_bvalid) begin
                    mem_next_state = MEM_IDLE;
                end
            end
            
            default: mem_next_state = MEM_IDLE;
        endcase
    end
    
    //=========================================================================
    // Memory Access Control
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_mem_rdata <= 32'd0;
            dbg_mem_done <= 1'b0;
            dbg_mem_error <= 1'b0;
            dbg_axi_awvalid <= 1'b0;
            dbg_axi_awaddr <= 32'd0;
            dbg_axi_wvalid <= 1'b0;
            dbg_axi_wdata <= 32'd0;
            dbg_axi_wstrb <= 4'b0;
            dbg_axi_bready <= 1'b0;
            dbg_axi_arvalid <= 1'b0;
            dbg_axi_araddr <= 32'd0;
            dbg_axi_rready <= 1'b0;
        end else begin
            // Default: deassert done/error
            dbg_mem_done <= 1'b0;
            dbg_mem_error <= 1'b0;
            
            case (mem_state)
                MEM_IDLE: begin
                    dbg_axi_awvalid <= 1'b0;
                    dbg_axi_wvalid <= 1'b0;
                    dbg_axi_arvalid <= 1'b0;
                    dbg_axi_bready <= 1'b0;
                    dbg_axi_rready <= 1'b0;
                    
                    if (dbg_halted && dbg_mem_read) begin
                        // Setup read address
                        dbg_axi_araddr <= dbg_mem_addr;
                        dbg_axi_arvalid <= 1'b1;
                    end else if (dbg_halted && dbg_mem_write) begin
                        // Setup write address and data
                        dbg_axi_awaddr <= dbg_mem_addr;
                        dbg_axi_awvalid <= 1'b1;
                        dbg_axi_wdata <= dbg_mem_wdata;
                        // Generate write strobe based on size
                        case (dbg_mem_size)
                            2'd0: dbg_axi_wstrb <= 4'b0001 << dbg_mem_addr[1:0];  // Byte
                            2'd1: dbg_axi_wstrb <= 4'b0011 << {dbg_mem_addr[1], 1'b0};  // Half
                            2'd2: dbg_axi_wstrb <= 4'b1111;  // Word
                            default: dbg_axi_wstrb <= 4'b1111;
                        endcase
                    end
                end
                
                MEM_READ_ADDR: begin
                    if (dbg_axi_arready) begin
                        dbg_axi_arvalid <= 1'b0;
                        dbg_axi_rready <= 1'b1;
                    end
                end
                
                MEM_READ_DATA: begin
                    if (dbg_axi_rvalid) begin
                        dbg_axi_rready <= 1'b0;
                        dbg_mem_rdata <= dbg_axi_rdata;
                        dbg_mem_done <= 1'b1;
                        // Check for error response
                        if (dbg_axi_rresp != 2'b00) begin
                            dbg_mem_error <= 1'b1;
                        end
                    end
                end
                
                MEM_WRITE_ADDR: begin
                    if (dbg_axi_awready) begin
                        dbg_axi_awvalid <= 1'b0;
                        dbg_axi_wvalid <= 1'b1;
                    end
                end
                
                MEM_WRITE_DATA: begin
                    if (dbg_axi_wready) begin
                        dbg_axi_wvalid <= 1'b0;
                        dbg_axi_bready <= 1'b1;
                    end
                end
                
                MEM_WRITE_RESP: begin
                    if (dbg_axi_bvalid) begin
                        dbg_axi_bready <= 1'b0;
                        dbg_mem_done <= 1'b1;
                        // Check for error response
                        if (dbg_axi_bresp != 2'b00) begin
                            dbg_mem_error <= 1'b1;
                        end
                    end
                end
                
                default: ;
            endcase
        end
    end

endmodule
