//=================================================================
// Module: perf_counters
// Description: Performance Counters for CPU profiling
//              Tracks cycles, instructions, cache hits/misses,
//              branch predictions, stalls, etc.
// Requirements: 6.3, 6.4, 6.5
//=================================================================

`timescale 1ns/1ps

module perf_counters #(
    parameter XLEN = 32,
    parameter COUNTER_WIDTH = 64
) (
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control Interface
    input  wire                     enable_i,           // Global enable
    input  wire                     clear_i,            // Clear all counters
    
    // Event Inputs
    input  wire                     cycle_i,            // Always 1 when enabled
    input  wire                     instr_retire_i,     // Instruction retired
    input  wire                     branch_i,           // Branch instruction
    input  wire                     branch_miss_i,      // Branch misprediction
    input  wire                     icache_access_i,    // I-cache access
    input  wire                     icache_miss_i,      // I-cache miss
    input  wire                     dcache_access_i,    // D-cache access
    input  wire                     dcache_miss_i,      // D-cache miss
    input  wire                     load_i,             // Load instruction
    input  wire                     store_i,            // Store instruction
    input  wire                     stall_frontend_i,   // Frontend stall
    input  wire                     stall_backend_i,    // Backend stall
    input  wire                     exception_i,        // Exception taken
    input  wire                     interrupt_i,        // Interrupt taken
    
    // CSR Read Interface
    input  wire [11:0]              csr_addr_i,
    input  wire                     csr_read_i,
    output reg  [XLEN-1:0]          csr_rdata_o,
    
    // CSR Write Interface
    input  wire                     csr_write_i,
    input  wire [XLEN-1:0]          csr_wdata_i
);

    //=========================================================
    // Counter Registers (64-bit)
    //=========================================================
    reg [COUNTER_WIDTH-1:0] cycle_cnt;          // mcycle
    reg [COUNTER_WIDTH-1:0] instret_cnt;        // minstret
    reg [COUNTER_WIDTH-1:0] branch_cnt;         // Branch count
    reg [COUNTER_WIDTH-1:0] branch_miss_cnt;    // Branch miss count
    reg [COUNTER_WIDTH-1:0] icache_access_cnt;  // I-cache accesses
    reg [COUNTER_WIDTH-1:0] icache_miss_cnt;    // I-cache misses
    reg [COUNTER_WIDTH-1:0] dcache_access_cnt;  // D-cache accesses
    reg [COUNTER_WIDTH-1:0] dcache_miss_cnt;    // D-cache misses
    reg [COUNTER_WIDTH-1:0] load_cnt;           // Load count
    reg [COUNTER_WIDTH-1:0] store_cnt;          // Store count
    reg [COUNTER_WIDTH-1:0] stall_frontend_cnt; // Frontend stall cycles
    reg [COUNTER_WIDTH-1:0] stall_backend_cnt;  // Backend stall cycles
    reg [COUNTER_WIDTH-1:0] exception_cnt;      // Exception count
    reg [COUNTER_WIDTH-1:0] interrupt_cnt;      // Interrupt count

    //=========================================================
    // CSR Addresses (Machine Performance Counters)
    //=========================================================
    localparam CSR_MCYCLE        = 12'hB00;
    localparam CSR_MINSTRET      = 12'hB02;
    localparam CSR_MCYCLEH       = 12'hB80;
    localparam CSR_MINSTRETH     = 12'hB82;
    
    // Hardware Performance Counters (mhpmcounter3-31)
    localparam CSR_MHPMCOUNTER3  = 12'hB03;  // Branch count
    localparam CSR_MHPMCOUNTER4  = 12'hB04;  // Branch miss
    localparam CSR_MHPMCOUNTER5  = 12'hB05;  // I-cache access
    localparam CSR_MHPMCOUNTER6  = 12'hB06;  // I-cache miss
    localparam CSR_MHPMCOUNTER7  = 12'hB07;  // D-cache access
    localparam CSR_MHPMCOUNTER8  = 12'hB08;  // D-cache miss
    localparam CSR_MHPMCOUNTER9  = 12'hB09;  // Load count
    localparam CSR_MHPMCOUNTER10 = 12'hB0A;  // Store count
    localparam CSR_MHPMCOUNTER11 = 12'hB0B;  // Frontend stall
    localparam CSR_MHPMCOUNTER12 = 12'hB0C;  // Backend stall
    localparam CSR_MHPMCOUNTER13 = 12'hB0D;  // Exception count
    localparam CSR_MHPMCOUNTER14 = 12'hB0E;  // Interrupt count
    
    // High bits (mhpmcounter3h-31h)
    localparam CSR_MHPMCOUNTER3H  = 12'hB83;
    localparam CSR_MHPMCOUNTER4H  = 12'hB84;
    localparam CSR_MHPMCOUNTER5H  = 12'hB85;
    localparam CSR_MHPMCOUNTER6H  = 12'hB86;
    localparam CSR_MHPMCOUNTER7H  = 12'hB87;
    localparam CSR_MHPMCOUNTER8H  = 12'hB88;
    localparam CSR_MHPMCOUNTER9H  = 12'hB89;
    localparam CSR_MHPMCOUNTER10H = 12'hB8A;
    localparam CSR_MHPMCOUNTER11H = 12'hB8B;
    localparam CSR_MHPMCOUNTER12H = 12'hB8C;
    localparam CSR_MHPMCOUNTER13H = 12'hB8D;
    localparam CSR_MHPMCOUNTER14H = 12'hB8E;

    //=========================================================
    // Counter Update Logic
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt          <= 64'h0;
            instret_cnt        <= 64'h0;
            branch_cnt         <= 64'h0;
            branch_miss_cnt    <= 64'h0;
            icache_access_cnt  <= 64'h0;
            icache_miss_cnt    <= 64'h0;
            dcache_access_cnt  <= 64'h0;
            dcache_miss_cnt    <= 64'h0;
            load_cnt           <= 64'h0;
            store_cnt          <= 64'h0;
            stall_frontend_cnt <= 64'h0;
            stall_backend_cnt  <= 64'h0;
            exception_cnt      <= 64'h0;
            interrupt_cnt      <= 64'h0;
        end else if (clear_i) begin
            cycle_cnt          <= 64'h0;
            instret_cnt        <= 64'h0;
            branch_cnt         <= 64'h0;
            branch_miss_cnt    <= 64'h0;
            icache_access_cnt  <= 64'h0;
            icache_miss_cnt    <= 64'h0;
            dcache_access_cnt  <= 64'h0;
            dcache_miss_cnt    <= 64'h0;
            load_cnt           <= 64'h0;
            store_cnt          <= 64'h0;
            stall_frontend_cnt <= 64'h0;
            stall_backend_cnt  <= 64'h0;
            exception_cnt      <= 64'h0;
            interrupt_cnt      <= 64'h0;
        end else if (enable_i) begin
            // Cycle counter always increments
            cycle_cnt <= cycle_cnt + 1;
            
            // Event counters
            if (instr_retire_i)    instret_cnt        <= instret_cnt + 1;
            if (branch_i)          branch_cnt         <= branch_cnt + 1;
            if (branch_miss_i)     branch_miss_cnt    <= branch_miss_cnt + 1;
            if (icache_access_i)   icache_access_cnt  <= icache_access_cnt + 1;
            if (icache_miss_i)     icache_miss_cnt    <= icache_miss_cnt + 1;
            if (dcache_access_i)   dcache_access_cnt  <= dcache_access_cnt + 1;
            if (dcache_miss_i)     dcache_miss_cnt    <= dcache_miss_cnt + 1;
            if (load_i)            load_cnt           <= load_cnt + 1;
            if (store_i)           store_cnt          <= store_cnt + 1;
            if (stall_frontend_i)  stall_frontend_cnt <= stall_frontend_cnt + 1;
            if (stall_backend_i)   stall_backend_cnt  <= stall_backend_cnt + 1;
            if (exception_i)       exception_cnt      <= exception_cnt + 1;
            if (interrupt_i)       interrupt_cnt      <= interrupt_cnt + 1;
        end
    end

    //=========================================================
    // CSR Read Logic
    //=========================================================
    always @(*) begin
        csr_rdata_o = {XLEN{1'b0}};
        
        if (csr_read_i) begin
            case (csr_addr_i)
                // Low 32 bits
                CSR_MCYCLE:        csr_rdata_o = cycle_cnt[31:0];
                CSR_MINSTRET:      csr_rdata_o = instret_cnt[31:0];
                CSR_MHPMCOUNTER3:  csr_rdata_o = branch_cnt[31:0];
                CSR_MHPMCOUNTER4:  csr_rdata_o = branch_miss_cnt[31:0];
                CSR_MHPMCOUNTER5:  csr_rdata_o = icache_access_cnt[31:0];
                CSR_MHPMCOUNTER6:  csr_rdata_o = icache_miss_cnt[31:0];
                CSR_MHPMCOUNTER7:  csr_rdata_o = dcache_access_cnt[31:0];
                CSR_MHPMCOUNTER8:  csr_rdata_o = dcache_miss_cnt[31:0];
                CSR_MHPMCOUNTER9:  csr_rdata_o = load_cnt[31:0];
                CSR_MHPMCOUNTER10: csr_rdata_o = store_cnt[31:0];
                CSR_MHPMCOUNTER11: csr_rdata_o = stall_frontend_cnt[31:0];
                CSR_MHPMCOUNTER12: csr_rdata_o = stall_backend_cnt[31:0];
                CSR_MHPMCOUNTER13: csr_rdata_o = exception_cnt[31:0];
                CSR_MHPMCOUNTER14: csr_rdata_o = interrupt_cnt[31:0];
                
                // High 32 bits
                CSR_MCYCLEH:        csr_rdata_o = cycle_cnt[63:32];
                CSR_MINSTRETH:      csr_rdata_o = instret_cnt[63:32];
                CSR_MHPMCOUNTER3H:  csr_rdata_o = branch_cnt[63:32];
                CSR_MHPMCOUNTER4H:  csr_rdata_o = branch_miss_cnt[63:32];
                CSR_MHPMCOUNTER5H:  csr_rdata_o = icache_access_cnt[63:32];
                CSR_MHPMCOUNTER6H:  csr_rdata_o = icache_miss_cnt[63:32];
                CSR_MHPMCOUNTER7H:  csr_rdata_o = dcache_access_cnt[63:32];
                CSR_MHPMCOUNTER8H:  csr_rdata_o = dcache_miss_cnt[63:32];
                CSR_MHPMCOUNTER9H:  csr_rdata_o = load_cnt[63:32];
                CSR_MHPMCOUNTER10H: csr_rdata_o = store_cnt[63:32];
                CSR_MHPMCOUNTER11H: csr_rdata_o = stall_frontend_cnt[63:32];
                CSR_MHPMCOUNTER12H: csr_rdata_o = stall_backend_cnt[63:32];
                CSR_MHPMCOUNTER13H: csr_rdata_o = exception_cnt[63:32];
                CSR_MHPMCOUNTER14H: csr_rdata_o = interrupt_cnt[63:32];
                
                default: csr_rdata_o = {XLEN{1'b0}};
            endcase
        end
    end

    //=========================================================
    // Derived Metrics (for debug/monitoring)
    //=========================================================
    // IPC = instret_cnt / cycle_cnt (calculated externally)
    // Cache hit rate = (access - miss) / access (calculated externally)
    // Branch prediction accuracy = (branch - miss) / branch (calculated externally)

endmodule
