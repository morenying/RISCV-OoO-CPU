//==============================================================================
// RISC-V Out-of-Order CPU - Global Definitions
// File: cpu_defines.vh
// Description: Global parameters, constants, and type definitions
//==============================================================================

`ifndef CPU_DEFINES_VH
`define CPU_DEFINES_VH

//==============================================================================
// Basic Parameters
//==============================================================================

// Data widths
`define XLEN                32          // Register width
`define ILEN                32          // Instruction length
`define ADDR_WIDTH          32          // Address width

// Register file
`define NUM_ARCH_REGS       32          // Architectural registers (x0-x31)
`define NUM_PHYS_REGS       64          // Physical registers
`define ARCH_REG_BITS       5           // Bits to address arch regs
`define PHYS_REG_BITS       6           // Bits to address phys regs

// ROB
`define ROB_ENTRIES         32          // Reorder buffer entries
`define ROB_IDX_BITS        5           // Bits to index ROB

// Reservation Stations
`define ALU_RS_ENTRIES      4           // ALU reservation station entries
`define MUL_RS_ENTRIES      2           // Multiplier RS entries
`define LSU_RS_ENTRIES      4           // Load/Store RS entries
`define BR_RS_ENTRIES       2           // Branch RS entries

// Load/Store Queue
`define LQ_ENTRIES          8           // Load queue entries
`define SQ_ENTRIES          8           // Store queue entries
`define LSQ_IDX_BITS        3           // Bits to index LSQ

// Cache parameters
`define ICACHE_SIZE         4096        // I-Cache size in bytes (4KB)
`define DCACHE_SIZE         4096        // D-Cache size in bytes (4KB)
`define CACHE_LINE_SIZE     32          // Cache line size in bytes
`define DCACHE_WAYS         2           // D-Cache associativity

// Branch Prediction
`define GHR_WIDTH           64          // Global history register width
`define BIMODAL_SIZE        2048        // Bimodal predictor entries
`define TAGE_TABLE_SIZE     256         // TAGE tagged table entries
`define BTB_ENTRIES         512         // BTB entries
`define BTB_WAYS            2           // BTB associativity
`define RAS_DEPTH           16          // Return address stack depth
`define LOOP_PRED_ENTRIES   32          // Loop predictor entries

// Reset vector
`define RESET_VECTOR        32'h8000_0000

//==============================================================================
// RISC-V Opcodes (inst[6:0])
//==============================================================================

`define OPCODE_LOAD         7'b0000011  // Load instructions
`define OPCODE_LOAD_FP      7'b0000111  // Load floating-point
`define OPCODE_MISC_MEM     7'b0001111  // FENCE, FENCE.I
`define OPCODE_OP_IMM       7'b0010011  // I-type ALU
`define OPCODE_AUIPC        7'b0010111  // AUIPC
`define OPCODE_OP_IMM_32    7'b0011011  // I-type ALU (RV64)
`define OPCODE_STORE        7'b0100011  // Store instructions
`define OPCODE_STORE_FP     7'b0100111  // Store floating-point
`define OPCODE_AMO          7'b0101111  // Atomic operations
`define OPCODE_OP           7'b0110011  // R-type ALU
`define OPCODE_LUI          7'b0110111  // LUI
`define OPCODE_OP_32        7'b0111011  // R-type ALU (RV64)
`define OPCODE_MADD         7'b1000011  // Fused multiply-add
`define OPCODE_MSUB         7'b1000111  // Fused multiply-sub
`define OPCODE_NMSUB        7'b1001011  // Negated fused multiply-sub
`define OPCODE_NMADD        7'b1001111  // Negated fused multiply-add
`define OPCODE_OP_FP        7'b1010011  // Floating-point operations
`define OPCODE_BRANCH       7'b1100011  // Branch instructions
`define OPCODE_JALR         7'b1100111  // JALR
`define OPCODE_JAL          7'b1101111  // JAL
`define OPCODE_SYSTEM       7'b1110011  // System instructions (CSR, ECALL, EBREAK)

//==============================================================================
// Funct3 Codes
//==============================================================================

// Branch funct3
`define FUNCT3_BEQ          3'b000
`define FUNCT3_BNE          3'b001
`define FUNCT3_BLT          3'b100
`define FUNCT3_BGE          3'b101
`define FUNCT3_BLTU         3'b110
`define FUNCT3_BGEU         3'b111

// Load funct3
`define FUNCT3_LB           3'b000
`define FUNCT3_LH           3'b001
`define FUNCT3_LW           3'b010
`define FUNCT3_LBU          3'b100
`define FUNCT3_LHU          3'b101

// Store funct3
`define FUNCT3_SB           3'b000
`define FUNCT3_SH           3'b001
`define FUNCT3_SW           3'b010

// ALU funct3
`define FUNCT3_ADD_SUB      3'b000      // ADD/SUB
`define FUNCT3_SLL          3'b001      // SLL
`define FUNCT3_SLT          3'b010      // SLT
`define FUNCT3_SLTU         3'b011      // SLTU
`define FUNCT3_XOR          3'b100      // XOR
`define FUNCT3_SRL_SRA      3'b101      // SRL/SRA
`define FUNCT3_OR           3'b110      // OR
`define FUNCT3_AND          3'b111      // AND

// M-extension funct3
`define FUNCT3_MUL          3'b000
`define FUNCT3_MULH         3'b001
`define FUNCT3_MULHSU       3'b010
`define FUNCT3_MULHU        3'b011
`define FUNCT3_DIV          3'b100
`define FUNCT3_DIVU         3'b101
`define FUNCT3_REM          3'b110
`define FUNCT3_REMU         3'b111

// CSR funct3
`define FUNCT3_CSRRW        3'b001
`define FUNCT3_CSRRS        3'b010
`define FUNCT3_CSRRC        3'b011
`define FUNCT3_CSRRWI       3'b101
`define FUNCT3_CSRRSI       3'b110
`define FUNCT3_CSRRCI       3'b111

// FENCE funct3
`define FUNCT3_FENCE        3'b000
`define FUNCT3_FENCE_I      3'b001

//==============================================================================
// Funct7 Codes
//==============================================================================

`define FUNCT7_NORMAL       7'b0000000  // Normal operations
`define FUNCT7_ALT          7'b0100000  // SUB, SRA
`define FUNCT7_MULDIV       7'b0000001  // M-extension

//==============================================================================
// ALU Operation Codes
//==============================================================================

`define ALU_OP_WIDTH        4

`define ALU_OP_ADD          4'b0000
`define ALU_OP_SUB          4'b0001
`define ALU_OP_SLL          4'b0010
`define ALU_OP_SLT          4'b0011
`define ALU_OP_SLTU         4'b0100
`define ALU_OP_XOR          4'b0101
`define ALU_OP_SRL          4'b0110
`define ALU_OP_SRA          4'b0111
`define ALU_OP_OR           4'b1000
`define ALU_OP_AND          4'b1001
`define ALU_OP_LUI          4'b1010     // Pass src2 (for LUI)
`define ALU_OP_AUIPC        4'b1011     // PC + src2 (for AUIPC)
`define ALU_OP_NOP          4'b1111     // No operation

//==============================================================================
// Multiplier Operation Codes
//==============================================================================

`define MUL_OP_WIDTH        2

`define MUL_OP_MUL          2'b00       // Lower 32 bits
`define MUL_OP_MULH         2'b01       // Upper 32 bits (signed x signed)
`define MUL_OP_MULHSU       2'b10       // Upper 32 bits (signed x unsigned)
`define MUL_OP_MULHU        2'b11       // Upper 32 bits (unsigned x unsigned)

//==============================================================================
// Divider Operation Codes
//==============================================================================

`define DIV_OP_WIDTH        2

`define DIV_OP_DIV          2'b00       // Signed division
`define DIV_OP_DIVU         2'b01       // Unsigned division
`define DIV_OP_REM          2'b10       // Signed remainder
`define DIV_OP_REMU         2'b11       // Unsigned remainder

//==============================================================================
// Branch Operation Codes
//==============================================================================

`define BR_OP_WIDTH         3

`define BR_OP_BEQ           3'b000
`define BR_OP_BNE           3'b001
`define BR_OP_BLT           3'b100
`define BR_OP_BGE           3'b101
`define BR_OP_BLTU          3'b110
`define BR_OP_BGEU          3'b111

//==============================================================================
// Memory Access Size
//==============================================================================

`define MEM_SIZE_WIDTH      2

`define MEM_SIZE_BYTE       2'b00
`define MEM_SIZE_HALF       2'b01
`define MEM_SIZE_WORD       2'b10

//==============================================================================
// Functional Unit Types
//==============================================================================

`define FU_TYPE_WIDTH       3

`define FU_TYPE_ALU         3'b000
`define FU_TYPE_MUL         3'b001
`define FU_TYPE_DIV         3'b010
`define FU_TYPE_BRANCH      3'b011
`define FU_TYPE_LOAD        3'b100
`define FU_TYPE_STORE       3'b101
`define FU_TYPE_CSR         3'b110
`define FU_TYPE_NONE        3'b111

//==============================================================================
// Instruction Types (for ROB)
//==============================================================================

`define INSTR_TYPE_WIDTH    4

`define INSTR_TYPE_ALU      4'b0000
`define INSTR_TYPE_MUL      4'b0001
`define INSTR_TYPE_DIV      4'b0010
`define INSTR_TYPE_BRANCH   4'b0011
`define INSTR_TYPE_JAL      4'b0100
`define INSTR_TYPE_JALR     4'b0101
`define INSTR_TYPE_LOAD     4'b0110
`define INSTR_TYPE_STORE    4'b0111
`define INSTR_TYPE_CSR      4'b1000
`define INSTR_TYPE_FENCE    4'b1001
`define INSTR_TYPE_SYSTEM   4'b1010     // ECALL, EBREAK
`define INSTR_TYPE_NOP      4'b1111

//==============================================================================
// Exception Codes (mcause values)
//==============================================================================

`define EXC_CODE_WIDTH      4

`define EXC_INSTR_MISALIGN  4'd0        // Instruction address misaligned
`define EXC_INSTR_FAULT     4'd1        // Instruction access fault
`define EXC_ILLEGAL_INSTR   4'd2        // Illegal instruction
`define EXC_BREAKPOINT      4'd3        // Breakpoint
`define EXC_LOAD_MISALIGN   4'd4        // Load address misaligned
`define EXC_LOAD_FAULT      4'd5        // Load access fault
`define EXC_STORE_MISALIGN  4'd6        // Store address misaligned
`define EXC_STORE_FAULT     4'd7        // Store access fault
`define EXC_ECALL_U         4'd8        // Environment call from U-mode
`define EXC_ECALL_S         4'd9        // Environment call from S-mode
`define EXC_ECALL_M         4'd11       // Environment call from M-mode
`define EXC_INSTR_PAGE      4'd12       // Instruction page fault
`define EXC_LOAD_PAGE       4'd13       // Load page fault
`define EXC_STORE_PAGE      4'd15       // Store page fault

`define EXC_NONE            4'd0        // No exception

//==============================================================================
// CSR Addresses
//==============================================================================

// Machine Information Registers
`define CSR_MVENDORID       12'hF11
`define CSR_MARCHID         12'hF12
`define CSR_MIMPID          12'hF13
`define CSR_MHARTID         12'hF14

// Machine Trap Setup
`define CSR_MSTATUS         12'h300
`define CSR_MISA            12'h301
`define CSR_MIE             12'h304
`define CSR_MTVEC           12'h305

// Machine Trap Handling
`define CSR_MSCRATCH        12'h340
`define CSR_MEPC            12'h341
`define CSR_MCAUSE          12'h342
`define CSR_MTVAL           12'h343
`define CSR_MIP             12'h344

// Machine Counter/Timers
`define CSR_MCYCLE          12'hB00
`define CSR_MINSTRET        12'hB02
`define CSR_MCYCLEH         12'hB80
`define CSR_MINSTRETH       12'hB82

// Debug CSRs
`define CSR_DCSR            12'h7B0
`define CSR_DPC             12'h7B1
`define CSR_DSCRATCH0       12'h7B2
`define CSR_DSCRATCH1       12'h7B3

//==============================================================================
// Branch Type (for BTB)
//==============================================================================

`define BR_TYPE_WIDTH       2

`define BR_TYPE_COND        2'b00       // Conditional branch
`define BR_TYPE_UNCOND      2'b01       // Unconditional jump (JAL)
`define BR_TYPE_CALL        2'b10       // Function call
`define BR_TYPE_RET         2'b11       // Function return

//==============================================================================
// CDB Source IDs
//==============================================================================

`define CDB_SRC_WIDTH       3

`define CDB_SRC_ALU0        3'd0
`define CDB_SRC_ALU1        3'd1
`define CDB_SRC_MUL         3'd2
`define CDB_SRC_DIV         3'd3
`define CDB_SRC_LSU         3'd4
`define CDB_SRC_BRU         3'd5

`define CDB_NUM_SOURCES     6

//==============================================================================
// Pipeline Stage IDs
//==============================================================================

`define STAGE_IF            3'd0
`define STAGE_ID            3'd1
`define STAGE_RN            3'd2
`define STAGE_IS            3'd3
`define STAGE_EX            3'd4
`define STAGE_MEM           3'd5
`define STAGE_WB            3'd6

//==============================================================================
// Utility Macros
//==============================================================================

// Sign extension
`define SIGN_EXT_8(x)       {{24{x[7]}}, x[7:0]}
`define SIGN_EXT_16(x)      {{16{x[15]}}, x[15:0]}
`define SIGN_EXT_12(x)      {{20{x[11]}}, x[11:0]}
`define SIGN_EXT_20(x)      {{12{x[19]}}, x[19:0]}

// Zero extension
`define ZERO_EXT_8(x)       {24'b0, x[7:0]}
`define ZERO_EXT_16(x)      {16'b0, x[15:0]}

`endif // CPU_DEFINES_VH
