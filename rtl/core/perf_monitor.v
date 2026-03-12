//=================================================================
// Module: perf_monitor
// Description: Hardware Performance Counters
//              Tracks IPC, branch prediction, cache performance
//              Accessible via CSR for software profiling
//=================================================================

`timescale 1ns/1ps

module perf_monitor #(
    parameter XLEN         = 32,
    parameter COMMIT_WIDTH = 4,
    parameter CDB_WIDTH    = 4
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    //=========================================================
    // Event Inputs
    //=========================================================
    // Commit events
    input  wire [COMMIT_WIDTH-1:0]  commit_valid_i,
    input  wire [COMMIT_WIDTH-1:0]  commit_is_branch_i,
    input  wire [COMMIT_WIDTH-1:0]  commit_is_load_i,
    input  wire [COMMIT_WIDTH-1:0]  commit_is_store_i,
    input  wire [COMMIT_WIDTH-1:0]  commit_is_mul_i,
    input  wire [COMMIT_WIDTH-1:0]  commit_is_div_i,
    
    // Branch prediction events
    input  wire                     br_resolve_valid_i,
    input  wire                     br_mispredict_i,
    
    // Cache events
    input  wire                     icache_access_i,
    input  wire                     icache_miss_i,
    input  wire                     dcache_access_i,
    input  wire                     dcache_miss_i,
    
    // TLB events
    input  wire                     itlb_access_i,
    input  wire                     itlb_miss_i,
    input  wire                     dtlb_access_i,
    input  wire                     dtlb_miss_i,
    
    // Stall events
    input  wire                     frontend_stall_i,
    input  wire                     backend_stall_i,
    input  wire                     rob_full_i,
    input  wire                     iq_full_i,
    input  wire                     lq_full_i,
    input  wire                     sq_full_i,
    
    // Flush events
    input  wire                     flush_i,
    
    //=========================================================
    // CSR Interface
    //=========================================================
    input  wire [11:0]              csr_addr_i,
    input  wire                     csr_read_i,
    output reg  [XLEN-1:0]          csr_data_o,
    input  wire                     csr_write_i,
    input  wire [XLEN-1:0]          csr_wdata_i,
    
    //=========================================================
    // Real-time Metrics Output
    //=========================================================
    output wire [31:0]              ipc_x1000_o,       // IPC * 1000
    output wire [31:0]              br_accuracy_x1000_o, // Accuracy * 1000
    output wire [31:0]              icache_hitrate_x1000_o,
    output wire [31:0]              dcache_hitrate_x1000_o
);

    //=========================================================
    // CSR Addresses (mhpmcounterX)
    //=========================================================
    localparam CSR_MCYCLE       = 12'hB00;
    localparam CSR_MINSTRET     = 12'hB02;
    localparam CSR_MHPMCOUNTER3 = 12'hB03;  // Branch count
    localparam CSR_MHPMCOUNTER4 = 12'hB04;  // Branch mispredict
    localparam CSR_MHPMCOUNTER5 = 12'hB05;  // I-Cache access
    localparam CSR_MHPMCOUNTER6 = 12'hB06;  // I-Cache miss
    localparam CSR_MHPMCOUNTER7 = 12'hB07;  // D-Cache access
    localparam CSR_MHPMCOUNTER8 = 12'hB08;  // D-Cache miss
    localparam CSR_MHPMCOUNTER9 = 12'hB09;  // Load count
    localparam CSR_MHPMCOUNTER10= 12'hB0A;  // Store count
    localparam CSR_MHPMCOUNTER11= 12'hB0B;  // Frontend stall
    localparam CSR_MHPMCOUNTER12= 12'hB0C;  // Backend stall
    localparam CSR_MHPMCOUNTER13= 12'hB0D;  // Flush count
    localparam CSR_MHPMCOUNTER14= 12'hB0E;  // MUL count
    localparam CSR_MHPMCOUNTER15= 12'hB0F;  // DIV count
    
    //=========================================================
    // Counter Registers (64-bit for long runs)
    //=========================================================
    reg [63:0] cycle_count;
    reg [63:0] instret_count;
    reg [63:0] branch_count;
    reg [63:0] branch_mispredict_count;
    reg [63:0] icache_access_count;
    reg [63:0] icache_miss_count;
    reg [63:0] dcache_access_count;
    reg [63:0] dcache_miss_count;
    reg [63:0] load_count;
    reg [63:0] store_count;
    reg [63:0] frontend_stall_count;
    reg [63:0] backend_stall_count;
    reg [63:0] flush_count;
    reg [63:0] mul_count;
    reg [63:0] div_count;
    
    //=========================================================
    // Count Commit Events
    //=========================================================
    wire [2:0] commit_count;
    wire [2:0] branch_commit_count;
    wire [2:0] load_commit_count;
    wire [2:0] store_commit_count;
    wire [2:0] mul_commit_count;
    wire [2:0] div_commit_count;
    
    // Population count for commit valid
    assign commit_count = commit_valid_i[0] + commit_valid_i[1] + 
                          commit_valid_i[2] + commit_valid_i[3];
    
    assign branch_commit_count = (commit_valid_i[0] & commit_is_branch_i[0]) +
                                 (commit_valid_i[1] & commit_is_branch_i[1]) +
                                 (commit_valid_i[2] & commit_is_branch_i[2]) +
                                 (commit_valid_i[3] & commit_is_branch_i[3]);
    
    assign load_commit_count = (commit_valid_i[0] & commit_is_load_i[0]) +
                               (commit_valid_i[1] & commit_is_load_i[1]) +
                               (commit_valid_i[2] & commit_is_load_i[2]) +
                               (commit_valid_i[3] & commit_is_load_i[3]);
    
    assign store_commit_count = (commit_valid_i[0] & commit_is_store_i[0]) +
                                (commit_valid_i[1] & commit_is_store_i[1]) +
                                (commit_valid_i[2] & commit_is_store_i[2]) +
                                (commit_valid_i[3] & commit_is_store_i[3]);
    
    assign mul_commit_count = (commit_valid_i[0] & commit_is_mul_i[0]) +
                              (commit_valid_i[1] & commit_is_mul_i[1]) +
                              (commit_valid_i[2] & commit_is_mul_i[2]) +
                              (commit_valid_i[3] & commit_is_mul_i[3]);
    
    assign div_commit_count = (commit_valid_i[0] & commit_is_div_i[0]) +
                              (commit_valid_i[1] & commit_is_div_i[1]) +
                              (commit_valid_i[2] & commit_is_div_i[2]) +
                              (commit_valid_i[3] & commit_is_div_i[3]);
    
    //=========================================================
    // Update Counters
    //=========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            instret_count <= 0;
            branch_count <= 0;
            branch_mispredict_count <= 0;
            icache_access_count <= 0;
            icache_miss_count <= 0;
            dcache_access_count <= 0;
            dcache_miss_count <= 0;
            load_count <= 0;
            store_count <= 0;
            frontend_stall_count <= 0;
            backend_stall_count <= 0;
            flush_count <= 0;
            mul_count <= 0;
            div_count <= 0;
        end else begin
            // Always increment cycle count
            cycle_count <= cycle_count + 1;
            
            // Commit events
            instret_count <= instret_count + {61'd0, commit_count};
            branch_count <= branch_count + {61'd0, branch_commit_count};
            load_count <= load_count + {61'd0, load_commit_count};
            store_count <= store_count + {61'd0, store_commit_count};
            mul_count <= mul_count + {61'd0, mul_commit_count};
            div_count <= div_count + {61'd0, div_commit_count};
            
            // Branch misprediction
            if (br_resolve_valid_i && br_mispredict_i)
                branch_mispredict_count <= branch_mispredict_count + 1;
            
            // Cache events
            if (icache_access_i)
                icache_access_count <= icache_access_count + 1;
            if (icache_miss_i)
                icache_miss_count <= icache_miss_count + 1;
            if (dcache_access_i)
                dcache_access_count <= dcache_access_count + 1;
            if (dcache_miss_i)
                dcache_miss_count <= dcache_miss_count + 1;
            
            // Stall events
            if (frontend_stall_i)
                frontend_stall_count <= frontend_stall_count + 1;
            if (backend_stall_i)
                backend_stall_count <= backend_stall_count + 1;
            
            // Flush events
            if (flush_i)
                flush_count <= flush_count + 1;
        end
    end
    
    //=========================================================
    // CSR Read
    //=========================================================
    always @(*) begin
        csr_data_o = 32'd0;
        
        case (csr_addr_i)
            CSR_MCYCLE:        csr_data_o = cycle_count[31:0];
            CSR_MINSTRET:      csr_data_o = instret_count[31:0];
            CSR_MHPMCOUNTER3:  csr_data_o = branch_count[31:0];
            CSR_MHPMCOUNTER4:  csr_data_o = branch_mispredict_count[31:0];
            CSR_MHPMCOUNTER5:  csr_data_o = icache_access_count[31:0];
            CSR_MHPMCOUNTER6:  csr_data_o = icache_miss_count[31:0];
            CSR_MHPMCOUNTER7:  csr_data_o = dcache_access_count[31:0];
            CSR_MHPMCOUNTER8:  csr_data_o = dcache_miss_count[31:0];
            CSR_MHPMCOUNTER9:  csr_data_o = load_count[31:0];
            CSR_MHPMCOUNTER10: csr_data_o = store_count[31:0];
            CSR_MHPMCOUNTER11: csr_data_o = frontend_stall_count[31:0];
            CSR_MHPMCOUNTER12: csr_data_o = backend_stall_count[31:0];
            CSR_MHPMCOUNTER13: csr_data_o = flush_count[31:0];
            CSR_MHPMCOUNTER14: csr_data_o = mul_count[31:0];
            CSR_MHPMCOUNTER15: csr_data_o = div_count[31:0];
            
            // High 32 bits
            12'hB80: csr_data_o = cycle_count[63:32];
            12'hB82: csr_data_o = instret_count[63:32];
            default: csr_data_o = 32'd0;
        endcase
    end
    
    //=========================================================
    // Real-time Metrics Calculation
    //=========================================================
    // IPC = instret / cycle * 1000
    // Use a sliding window for smooth output
    reg [31:0] window_cycles;
    reg [31:0] window_instret;
    reg [31:0] window_branches;
    reg [31:0] window_mispredicts;
    reg [31:0] window_icache_access;
    reg [31:0] window_icache_miss;
    reg [31:0] window_dcache_access;
    reg [31:0] window_dcache_miss;
    
    localparam WINDOW_SIZE = 1024;  // Update every 1K cycles
    reg [9:0] window_counter;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_counter <= 0;
            window_cycles <= 0;
            window_instret <= 0;
            window_branches <= 0;
            window_mispredicts <= 0;
            window_icache_access <= 0;
            window_icache_miss <= 0;
            window_dcache_access <= 0;
            window_dcache_miss <= 0;
        end else begin
            window_counter <= window_counter + 1;
            
            if (window_counter == 0) begin
                // Capture current values
                window_cycles <= cycle_count[31:0];
                window_instret <= instret_count[31:0];
                window_branches <= branch_count[31:0];
                window_mispredicts <= branch_mispredict_count[31:0];
                window_icache_access <= icache_access_count[31:0];
                window_icache_miss <= icache_miss_count[31:0];
                window_dcache_access <= dcache_access_count[31:0];
                window_dcache_miss <= dcache_miss_count[31:0];
            end
        end
    end
    
    // Calculate metrics (avoid division, use approximation)
    // IPC * 1000 ≈ (instret_diff * 1000) / cycle_diff
    wire [31:0] instret_diff = instret_count[31:0] - window_instret;
    wire [31:0] cycle_diff = cycle_count[31:0] - window_cycles;
    
    // Simple approximation: IPC * 1024 ≈ instret << 10 / cycles
    // Then scale: (x * 1000) >> 10 ≈ x * 0.976 ≈ x
    assign ipc_x1000_o = (cycle_diff > 0) ? 
                         ((instret_diff << 10) / cycle_diff) : 32'd0;
    
    // Branch accuracy = (1 - mispredicts/branches) * 1000
    wire [31:0] branch_diff = branch_count[31:0] - window_branches;
    wire [31:0] mispredict_diff = branch_mispredict_count[31:0] - window_mispredicts;
    assign br_accuracy_x1000_o = (branch_diff > 0) ?
                                 (1000 - (mispredict_diff * 1000) / branch_diff) : 32'd1000;
    
    // Cache hit rate = (1 - misses/accesses) * 1000
    wire [31:0] icache_access_diff = icache_access_count[31:0] - window_icache_access;
    wire [31:0] icache_miss_diff = icache_miss_count[31:0] - window_icache_miss;
    assign icache_hitrate_x1000_o = (icache_access_diff > 0) ?
                                    (1000 - (icache_miss_diff * 1000) / icache_access_diff) : 32'd1000;
    
    wire [31:0] dcache_access_diff = dcache_access_count[31:0] - window_dcache_access;
    wire [31:0] dcache_miss_diff = dcache_miss_count[31:0] - window_dcache_miss;
    assign dcache_hitrate_x1000_o = (dcache_access_diff > 0) ?
                                    (1000 - (dcache_miss_diff * 1000) / dcache_access_diff) : 32'd1000;

endmodule
