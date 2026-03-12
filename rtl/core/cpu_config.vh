//=================================================================
// CPU Configuration Parameters
// Description: Optimized parameters for championship-level IPC
// Target: IPC > 1.5, Branch Prediction > 97%
//=================================================================

`ifndef CPU_CONFIG_VH
`define CPU_CONFIG_VH

//=========================================================
// General Parameters
//=========================================================
`define XLEN                    32
`define RESET_VECTOR            32'h8000_0000
`define MHART_ID                32'h0

//=========================================================
// Superscalar Width - CRITICAL FOR IPC
//=========================================================
// 4-way gives good balance between IPC and complexity
`define FETCH_WIDTH             4       // Instructions fetched per cycle
`define DECODE_WIDTH            4       // Instructions decoded per cycle
`define RENAME_WIDTH            4       // Instructions renamed per cycle
`define DISPATCH_WIDTH          4       // Instructions dispatched per cycle
`define ISSUE_WIDTH             4       // Instructions issued per cycle
`define COMMIT_WIDTH            4       // Instructions committed per cycle
`define CDB_WIDTH               4       // CDB writeback ports

//=========================================================
// Register File - Sized for 4-way + speculation
//=========================================================
// Formula: PRF_SIZE = ARCH_REGS + ROB_SIZE + margin
// 128 = 32 + 64 + 32 margin for deep speculation
`define ARCH_REG_BITS           5       // 32 architectural registers
`define PHYS_REG_BITS           7       // 128 physical registers
`define NUM_PHYS_REGS           128
`define PRF_READ_PORTS          8       // 2 per issue slot
`define PRF_WRITE_PORTS         4       // 1 per CDB port

//=========================================================
// ROB - Large enough to hide memory latency
//=========================================================
// 64 entries allows ~16 cache miss hiding at 4-way
`define ROB_ENTRIES             64
`define ROB_IDX_BITS            6

//=========================================================
// Issue Queue - Key for ILP extraction
//=========================================================
// Larger IQ = more parallelism extraction
// 32 entries is sweet spot for area/performance
`define IQ_ENTRIES              32
`define IQ_IDX_BITS             5

//=========================================================
// Load/Store Queue - Critical for memory ILP
//=========================================================
// 16 entries each allows overlapping of multiple loads
`define LQ_ENTRIES              16
`define LQ_IDX_BITS             4
`define SQ_ENTRIES              16
`define SQ_IDX_BITS             4

//=========================================================
// Branch Predictor - Target 97%+ accuracy
//=========================================================
// TAGE-SC-L configuration
`define GHR_WIDTH               256     // Long history for loops
`define TAGE_TABLES             8       // 8 tagged tables
`define TAGE_TAG_BITS           12      // 12-bit tags
`define TAGE_CTR_BITS           3       // 3-bit counters
`define TAGE_TABLE_SIZE         1024    // 1K entries per table
`define BTB_ENTRIES             512     // Branch target buffer
`define BTB_TAG_BITS            20
`define RAS_ENTRIES             16      // Return address stack
`define LOOP_ENTRIES            32      // Loop predictor

//=========================================================
// I-Cache - Sized for 4-way fetch
//=========================================================
// 16KB 4-way provides good hit rate
`define ICACHE_SIZE             16384   // 16KB
`define ICACHE_WAYS             4
`define ICACHE_LINE_SIZE        32      // 32 bytes = 8 instructions
`define ICACHE_SETS             128     // 16KB / (4 * 32)
`define ICACHE_TAG_BITS         18      // 32 - log2(32) - log2(128)

//=========================================================
// D-Cache - Sized for memory-intensive workloads
//=========================================================
// 8KB 4-way with 4-entry MSHR for miss handling
`define DCACHE_SIZE             8192    // 8KB
`define DCACHE_WAYS             4
`define DCACHE_LINE_SIZE        32      // 32 bytes
`define DCACHE_SETS             64      // 8KB / (4 * 32)
`define DCACHE_TAG_BITS         19
`define DCACHE_MSHR_ENTRIES     4       // Outstanding misses

//=========================================================
// MMU/TLB - Sized for Linux
//=========================================================
`define TLB_ENTRIES             32      // 32-entry fully-associative
`define ITLB_ENTRIES            16
`define DTLB_ENTRIES            16
`define TLB_TAG_BITS            20      // VPN bits
`define PAGE_SIZE               4096    // 4KB pages

//=========================================================
// Execution Units - Balanced for workload mix
//=========================================================
`define NUM_ALU                 2       // 2 ALUs for arithmetic
`define NUM_MUL                 1       // 1 multiplier (3-cycle)
`define NUM_DIV                 1       // 1 divider (32-cycle)
`define NUM_BRU                 1       // 1 branch unit
`define NUM_LSU                 1       // 1 load/store unit

// Latencies
`define ALU_LATENCY             1       // Single cycle
`define MUL_LATENCY             3       // 3-stage pipelined
`define DIV_LATENCY             32      // 32-cycle iterative
`define BRU_LATENCY             1       // Single cycle
`define LOAD_LATENCY            2       // D-Cache hit

//=========================================================
// Prefetcher - Reduce cache misses
//=========================================================
`define PREFETCH_ENABLE         1
`define STRIDE_TABLE_SIZE       16      // Stride prefetcher entries
`define STREAM_TABLE_SIZE       8       // Stream prefetcher entries
`define PREFETCH_DEGREE         4       // Prefetch 4 lines ahead
`define PREFETCH_DISTANCE       64      // Bytes ahead to prefetch

//=========================================================
// Power Optimization
//=========================================================
`define USE_CLOCK_GATING        1       // Enable clock gating
`define USE_POWER_GATING        0       // Disable power gating (complex)

//=========================================================
// Debug Features
//=========================================================
`define DEBUG_ENABLE            1
`define PERF_COUNTERS           1       // Performance counters
`define TRACE_ENABLE            0       // Instruction trace (off for perf)

//=========================================================
// Performance Tuning Notes
//=========================================================
// IPC bottlenecks analysis:
// 1. Branch misprediction: ~15 cycle penalty
//    - Solution: TAGE-SC-L with 256-bit GHR
// 2. Cache miss: ~100 cycle penalty  
//    - Solution: Larger caches, MSHR, prefetcher
// 3. Structural hazards: 
//    - Solution: 2 ALUs, 4-wide CDB
// 4. Data dependencies:
//    - Solution: Large IQ (32), register renaming (128 PRF)
// 5. Control dependencies:
//    - Solution: Speculative execution, 64-entry ROB
//
// Expected IPC breakdown:
// - Base IPC (no stalls): 4.0
// - Branch penalty: -0.5 (12% branches, 3% mispredict, 15 cycle)
// - Cache penalty: -0.3 (5% miss rate, 100 cycle)
// - Structural: -0.2 (MUL/DIV contention)
// - Dependencies: -0.8 (RAW hazards, limited ILP)
// - Net IPC target: ~2.2
//
// For Linux boot, expect lower IPC (~1.2-1.5) due to:
// - More cache misses (cold start)
// - More branches (kernel code)
// - I/O waiting
//=========================================================

`endif // CPU_CONFIG_VH
