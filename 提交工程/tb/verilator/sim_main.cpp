// Verilator testbench for RISC-V OoO CPU - Comprehensive CPI Measurement
// Production-like benchmarks with 3 decimal places precision
// Supports: ALU, MUL, DIV, Branch, Memory, Cache tests
#include <verilated.h>
#include "Vcpu_core_top.h"
#include "Vcpu_core_top___024root.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

#define MEM_BASE 0x80000000
#define MEM_SIZE (256 * 1024)  // 256KB for larger programs
#define CACHE_LINE_SIZE 32     // 32 bytes = 8 words per cache line
#define CACHE_LINE_WORDS 8

uint32_t memory[MEM_SIZE/4];
uint64_t cycle_count = 0;
double sc_time_stamp() { return cycle_count; }

// ============================================================
// RISC-V Instruction Encoding Macros
// ============================================================
// R-type: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
#define R_TYPE(funct7, rs2, rs1, funct3, rd, opcode) \
    (((funct7) << 25) | ((rs2) << 20) | ((rs1) << 15) | ((funct3) << 12) | ((rd) << 7) | (opcode))

// I-type: imm[31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
#define I_TYPE(imm, rs1, funct3, rd, opcode) \
    ((((imm) & 0xFFF) << 20) | ((rs1) << 15) | ((funct3) << 12) | ((rd) << 7) | (opcode))

// S-type: imm[11:5][31:25] rs2[24:20] rs1[19:15] funct3[14:12] imm[4:0][11:7] opcode[6:0]
#define S_TYPE(imm, rs2, rs1, funct3, opcode) \
    (((((imm) >> 5) & 0x7F) << 25) | ((rs2) << 20) | ((rs1) << 15) | ((funct3) << 12) | (((imm) & 0x1F) << 7) | (opcode))

// B-type: imm[12|10:5][31:25] rs2[24:20] rs1[19:15] funct3[14:12] imm[4:1|11][11:7] opcode[6:0]
#define B_TYPE(imm, rs2, rs1, funct3, opcode) \
    (((((imm) >> 12) & 0x1) << 31) | ((((imm) >> 5) & 0x3F) << 25) | ((rs2) << 20) | ((rs1) << 15) | \
     ((funct3) << 12) | ((((imm) >> 1) & 0xF) << 8) | ((((imm) >> 11) & 0x1) << 7) | (opcode))

// J-type: imm[20|10:1|11|19:12][31:12] rd[11:7] opcode[6:0]
#define J_TYPE(imm, rd, opcode) \
    (((((imm) >> 20) & 0x1) << 31) | ((((imm) >> 1) & 0x3FF) << 21) | ((((imm) >> 11) & 0x1) << 20) | \
     ((((imm) >> 12) & 0xFF) << 12) | ((rd) << 7) | (opcode))

// U-type: imm[31:12] rd[11:7] opcode[6:0]
#define U_TYPE(imm, rd, opcode) (((imm) & 0xFFFFF000) | ((rd) << 7) | (opcode))

// Basic Instructions
#define NOP         0x00000013
#define ADDI(rd, rs1, imm)  I_TYPE(imm, rs1, 0b000, rd, 0b0010011)
#define SLTI(rd, rs1, imm)  I_TYPE(imm, rs1, 0b010, rd, 0b0010011)
#define SLTIU(rd, rs1, imm) I_TYPE(imm, rs1, 0b011, rd, 0b0010011)
#define XORI(rd, rs1, imm)  I_TYPE(imm, rs1, 0b100, rd, 0b0010011)
#define ORI(rd, rs1, imm)   I_TYPE(imm, rs1, 0b110, rd, 0b0010011)
#define ANDI(rd, rs1, imm)  I_TYPE(imm, rs1, 0b111, rd, 0b0010011)
#define SLLI(rd, rs1, shamt) I_TYPE(shamt, rs1, 0b001, rd, 0b0010011)
#define SRLI(rd, rs1, shamt) I_TYPE(shamt, rs1, 0b101, rd, 0b0010011)
#define SRAI(rd, rs1, shamt) I_TYPE((shamt) | 0x400, rs1, 0b101, rd, 0b0010011)

#define ADD(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b000, rd, 0b0110011)
#define SUB(rd, rs1, rs2)   R_TYPE(0b0100000, rs2, rs1, 0b000, rd, 0b0110011)
#define SLL(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b001, rd, 0b0110011)
#define SLT(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b010, rd, 0b0110011)
#define SLTU(rd, rs1, rs2)  R_TYPE(0b0000000, rs2, rs1, 0b011, rd, 0b0110011)
#define XOR(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b100, rd, 0b0110011)
#define SRL(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b101, rd, 0b0110011)
#define SRA(rd, rs1, rs2)   R_TYPE(0b0100000, rs2, rs1, 0b101, rd, 0b0110011)
#define OR(rd, rs1, rs2)    R_TYPE(0b0000000, rs2, rs1, 0b110, rd, 0b0110011)
#define AND(rd, rs1, rs2)   R_TYPE(0b0000000, rs2, rs1, 0b111, rd, 0b0110011)

// M Extension
#define MUL(rd, rs1, rs2)    R_TYPE(0b0000001, rs2, rs1, 0b000, rd, 0b0110011)
#define MULH(rd, rs1, rs2)   R_TYPE(0b0000001, rs2, rs1, 0b001, rd, 0b0110011)
#define MULHSU(rd, rs1, rs2) R_TYPE(0b0000001, rs2, rs1, 0b010, rd, 0b0110011)
#define MULHU(rd, rs1, rs2)  R_TYPE(0b0000001, rs2, rs1, 0b011, rd, 0b0110011)
#define DIV(rd, rs1, rs2)    R_TYPE(0b0000001, rs2, rs1, 0b100, rd, 0b0110011)
#define DIVU(rd, rs1, rs2)   R_TYPE(0b0000001, rs2, rs1, 0b101, rd, 0b0110011)
#define REM(rd, rs1, rs2)    R_TYPE(0b0000001, rs2, rs1, 0b110, rd, 0b0110011)
#define REMU(rd, rs1, rs2)   R_TYPE(0b0000001, rs2, rs1, 0b111, rd, 0b0110011)

// Load/Store
#define LW(rd, rs1, imm)    I_TYPE(imm, rs1, 0b010, rd, 0b0000011)
#define LH(rd, rs1, imm)    I_TYPE(imm, rs1, 0b001, rd, 0b0000011)
#define LB(rd, rs1, imm)    I_TYPE(imm, rs1, 0b000, rd, 0b0000011)
#define LHU(rd, rs1, imm)   I_TYPE(imm, rs1, 0b101, rd, 0b0000011)
#define LBU(rd, rs1, imm)   I_TYPE(imm, rs1, 0b100, rd, 0b0000011)
#define SW(rs2, rs1, imm)   S_TYPE(imm, rs2, rs1, 0b010, 0b0100011)
#define SH(rs2, rs1, imm)   S_TYPE(imm, rs2, rs1, 0b001, 0b0100011)
#define SB(rs2, rs1, imm)   S_TYPE(imm, rs2, rs1, 0b000, 0b0100011)

// Branch
#define BEQ(rs1, rs2, imm)  B_TYPE(imm, rs2, rs1, 0b000, 0b1100011)
#define BNE(rs1, rs2, imm)  B_TYPE(imm, rs2, rs1, 0b001, 0b1100011)
#define BLT(rs1, rs2, imm)  B_TYPE(imm, rs2, rs1, 0b100, 0b1100011)
#define BGE(rs1, rs2, imm)  B_TYPE(imm, rs2, rs1, 0b101, 0b1100011)
#define BLTU(rs1, rs2, imm) B_TYPE(imm, rs2, rs1, 0b110, 0b1100011)
#define BGEU(rs1, rs2, imm) B_TYPE(imm, rs2, rs1, 0b111, 0b1100011)

// Jump
#define JAL(rd, imm)        J_TYPE(imm, rd, 0b1101111)
#define JALR(rd, rs1, imm)  I_TYPE(imm, rs1, 0b000, rd, 0b1100111)

// Upper Immediate
#define LUI(rd, imm)        U_TYPE(imm, rd, 0b0110111)
#define AUIPC(rd, imm)      U_TYPE(imm, rd, 0b0010111)

// Halt (infinite loop)
#define HALT                JAL(0, 0)


// ============================================================
// CPU Simulator with Burst AXI Memory Model
// 
// The CPU's I-Cache expects a full 256-bit cache line. The CPU now has
// a burst accumulator that collects 8 x 32-bit AXI transfers.
// This testbench provides 8 sequential words for each cache line request.
// ============================================================
class CPUSimulator {
public:
    Vcpu_core_top* cpu;
    
    // I-Bus AXI state machine - burst transfers (8 beats)
    enum IBusState { IBUS_IDLE, IBUS_BURST };
    IBusState ibus_state;
    uint32_t ibus_base_addr;
    int ibus_beat;
    
    // D-Bus AXI state machine - burst transfers
    enum DBusState { DBUS_IDLE, DBUS_READ_BURST, DBUS_WRITE_DATA, DBUS_WRITE_RESP };
    DBusState dbus_state;
    uint32_t dbus_base_addr;
    int dbus_beat;
    
    // Statistics
    uint64_t total_commits;
    uint64_t branch_commits;
    uint64_t branch_mispredicts;
    uint64_t icache_misses;
    uint64_t dcache_misses;
    
    CPUSimulator() {
        cpu = new Vcpu_core_top;
        reset();
    }
    
    ~CPUSimulator() { 
        delete cpu; 
    }
    
    void reset() {
        cycle_count = 0;
        total_commits = 0;
        branch_commits = 0;
        branch_mispredicts = 0;
        icache_misses = 0;
        dcache_misses = 0;
        
        // Reset CPU
        cpu->rst_n = 0;
        cpu->clk = 0;
        
        // I-Bus defaults
        cpu->m_axi_ibus_arready = 1;
        cpu->m_axi_ibus_rvalid = 0;
        cpu->m_axi_ibus_rdata = NOP;
        cpu->m_axi_ibus_rresp = 0;
        
        // D-Bus defaults
        cpu->m_axi_dbus_awready = 1;
        cpu->m_axi_dbus_wready = 1;
        cpu->m_axi_dbus_arready = 1;
        cpu->m_axi_dbus_bvalid = 0;
        cpu->m_axi_dbus_rvalid = 0;
        cpu->m_axi_dbus_bresp = 0;
        cpu->m_axi_dbus_rresp = 0;
        cpu->m_axi_dbus_rdata = 0;
        
        // No interrupts
        cpu->ext_irq_i = 0;
        cpu->timer_irq_i = 0;
        cpu->sw_irq_i = 0;
        
        // Reset cycles
        for (int i = 0; i < 10; i++) {
            cpu->clk = 0; cpu->eval();
            cpu->clk = 1; cpu->eval();
        }
        cpu->rst_n = 1;
        
        ibus_state = IBUS_IDLE;
        ibus_beat = 0;
        dbus_state = DBUS_IDLE;
        dbus_beat = 0;
    }
    
    void tick() {
        cpu->clk = 0;
        cpu->eval();
        
        // ========================================
        // I-Bus AXI - Burst transfer (8 beats per cache line)
        // ========================================
        switch (ibus_state) {
            case IBUS_IDLE:
                cpu->m_axi_ibus_arready = 1;
                cpu->m_axi_ibus_rvalid = 0;
                if (cpu->m_axi_ibus_arvalid) {
                    // Cache line aligned address
                    ibus_base_addr = cpu->m_axi_ibus_araddr & ~0x1F;
                    ibus_beat = 0;
                    ibus_state = IBUS_BURST;
                    icache_misses++;
                }
                break;
                
            case IBUS_BURST:
                cpu->m_axi_ibus_arready = 0;
                cpu->m_axi_ibus_rvalid = 1;
                {
                    uint32_t word_addr = ibus_base_addr + ibus_beat * 4;
                    if (word_addr >= MEM_BASE && word_addr < MEM_BASE + MEM_SIZE) {
                        cpu->m_axi_ibus_rdata = memory[(word_addr - MEM_BASE) >> 2];
                    } else {
                        cpu->m_axi_ibus_rdata = NOP;
                    }
                }
                cpu->m_axi_ibus_rresp = 0;  // OKAY
                
                if (cpu->m_axi_ibus_rready) {
                    ibus_beat++;
                    if (ibus_beat >= 8) {
                        ibus_state = IBUS_IDLE;
                    }
                }
                break;
        }
        
        // ========================================
        // D-Bus AXI - Burst transfer (8 beats per cache line)
        // ========================================
        switch (dbus_state) {
            case DBUS_IDLE:
                cpu->m_axi_dbus_arready = 1;
                cpu->m_axi_dbus_awready = 1;
                cpu->m_axi_dbus_wready = 0;
                cpu->m_axi_dbus_rvalid = 0;
                cpu->m_axi_dbus_bvalid = 0;
                
                if (cpu->m_axi_dbus_arvalid) {
                    // Read request - cache line aligned
                    dbus_base_addr = cpu->m_axi_dbus_araddr & ~0x1F;
                    dbus_beat = 0;
                    dbus_state = DBUS_READ_BURST;
                    dcache_misses++;
                } else if (cpu->m_axi_dbus_awvalid) {
                    // Write request
                    dbus_base_addr = cpu->m_axi_dbus_awaddr;
                    dbus_beat = 0;
                    dbus_state = DBUS_WRITE_DATA;
                }
                break;
                
            case DBUS_READ_BURST:
                cpu->m_axi_dbus_arready = 0;
                cpu->m_axi_dbus_awready = 0;
                cpu->m_axi_dbus_rvalid = 1;
                {
                    uint32_t word_addr = dbus_base_addr + dbus_beat * 4;
                    if (word_addr >= MEM_BASE && word_addr < MEM_BASE + MEM_SIZE) {
                        cpu->m_axi_dbus_rdata = memory[(word_addr - MEM_BASE) >> 2];
                    } else {
                        cpu->m_axi_dbus_rdata = 0;
                    }
                }
                cpu->m_axi_dbus_rresp = 0;
                
                if (cpu->m_axi_dbus_rready) {
                    dbus_beat++;
                    if (dbus_beat >= 8) {
                        dbus_state = DBUS_IDLE;
                    }
                }
                break;
                
            case DBUS_WRITE_DATA:
                cpu->m_axi_dbus_arready = 0;
                cpu->m_axi_dbus_awready = 0;
                cpu->m_axi_dbus_wready = 1;
                
                if (cpu->m_axi_dbus_wvalid) {
                    // Write data to memory
                    uint32_t word_addr = dbus_base_addr + dbus_beat * 4;
                    if (word_addr >= MEM_BASE && word_addr < MEM_BASE + MEM_SIZE) {
                        uint32_t strb = cpu->m_axi_dbus_wstrb;
                        uint32_t old_data = memory[(word_addr - MEM_BASE) >> 2];
                        uint32_t new_data = cpu->m_axi_dbus_wdata;
                        uint32_t mask = 0;
                        if (strb & 1) mask |= 0x000000FF;
                        if (strb & 2) mask |= 0x0000FF00;
                        if (strb & 4) mask |= 0x00FF0000;
                        if (strb & 8) mask |= 0xFF000000;
                        memory[(word_addr - MEM_BASE) >> 2] = (old_data & ~mask) | (new_data & mask);
                    }
                    dbus_beat++;
                    if (dbus_beat >= 8) {
                        dbus_state = DBUS_WRITE_RESP;
                    }
                }
                break;
                
            case DBUS_WRITE_RESP:
                cpu->m_axi_dbus_wready = 0;
                cpu->m_axi_dbus_bvalid = 1;
                cpu->m_axi_dbus_bresp = 0;
                
                if (cpu->m_axi_dbus_bready) {
                    dbus_state = DBUS_IDLE;
                }
                break;
        }
        
        cpu->clk = 1;
        cpu->eval();
        cycle_count++;
        
        // Track statistics
        if (committed()) {
            total_commits++;
        }
    }
    
    bool committed() { 
        return cpu->rootp->cpu_core_top__DOT__rob_commit_valid; 
    }
    
    uint32_t getPC() {
        return cpu->rootp->cpu_core_top__DOT__u_if_stage__DOT__pc_reg;
    }
    
    bool isBranchMispredict() {
        return cpu->rootp->cpu_core_top__DOT__u_ex_stage__DOT__br_mispredict_out &&
               cpu->rootp->cpu_core_top__DOT__u_ex_stage__DOT__br_done;
    }
};


// ============================================================
// Test Result Structure
// ============================================================
struct TestResult {
    const char* name;
    uint64_t total_cycles;
    uint64_t total_commits;
    uint64_t steady_cycles;
    uint64_t steady_commits;
    double cpi;
    double ipc;
    uint64_t icache_misses;
    uint64_t dcache_misses;
};

TestResult runTest(CPUSimulator& sim, const char* name, int target_commits, int max_cycles = 500000) {
    sim.reset();
    
    uint64_t commits = 0;
    uint64_t first_commit_cycle = 0;
    uint64_t last_commit_cycle = 0;
    
    for (cycle_count = 0; cycle_count < (uint64_t)max_cycles && commits < (uint64_t)target_commits; ) {
        sim.tick();
        if (sim.committed()) {
            commits++;
            if (first_commit_cycle == 0) first_commit_cycle = cycle_count;
            last_commit_cycle = cycle_count;
        }
    }
    
    TestResult r;
    r.name = name;
    r.total_cycles = cycle_count;
    r.total_commits = commits;
    r.icache_misses = sim.icache_misses;
    r.dcache_misses = sim.dcache_misses;
    
    if (commits > 1) {
        r.steady_cycles = last_commit_cycle - first_commit_cycle;
        r.steady_commits = commits - 1;
    } else {
        r.steady_cycles = last_commit_cycle;
        r.steady_commits = commits;
    }
    
    r.cpi = r.steady_commits > 0 ? (double)r.steady_cycles / r.steady_commits : 0;
    r.ipc = r.cpi > 0 ? 1.0 / r.cpi : 0;
    
    return r;
}

// ============================================================
// Benchmark Generators
// ============================================================

// 1. Independent ALU operations (no dependencies)
int gen_independent_alu(uint32_t* prog, int count) {
    int i = 0;
    for (int j = 0; j < count; j++) {
        int rd = (j % 31) + 1;
        prog[i++] = ADDI(rd, 0, j + 1);
    }
    prog[i++] = HALT;
    return i;
}

// 2. Dependent ALU chain (RAW hazards)
int gen_dependent_alu(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, 1);
    for (int j = 0; j < count - 1; j++) {
        prog[i++] = ADD(1, 1, 1);
    }
    prog[i++] = HALT;
    return i;
}

// 3. Mixed ALU operations
int gen_mixed_alu(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, 100);
    prog[i++] = ADDI(2, 0, 50);
    for (int j = 0; j < count - 2; j++) {
        int rd = (j % 28) + 3;
        switch (j % 8) {
            case 0: prog[i++] = ADD(rd, 1, 2); break;
            case 1: prog[i++] = SUB(rd, 1, 2); break;
            case 2: prog[i++] = AND(rd, 1, 2); break;
            case 3: prog[i++] = OR(rd, 1, 2); break;
            case 4: prog[i++] = XOR(rd, 1, 2); break;
            case 5: prog[i++] = SLL(rd, 1, 2); break;
            case 6: prog[i++] = SRL(rd, 1, 2); break;
            case 7: prog[i++] = SRA(rd, 1, 2); break;
        }
    }
    prog[i++] = HALT;
    return i;
}

// 4. MUL operations (independent)
int gen_mul_independent(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, 7);
    prog[i++] = ADDI(2, 0, 11);
    for (int j = 0; j < count - 2; j++) {
        int rd = (j % 28) + 3;
        prog[i++] = MUL(rd, 1, 2);
    }
    prog[i++] = HALT;
    return i;
}

// 5. MUL operations (dependent chain)
int gen_mul_dependent(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, 2);
    prog[i++] = ADDI(2, 0, 1);
    for (int j = 0; j < count - 2; j++) {
        prog[i++] = MUL(1, 1, 2);  // x1 = x1 * x2
    }
    prog[i++] = HALT;
    return i;
}

// 6. DIV operations (independent)
int gen_div_independent(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, 1000);
    prog[i++] = ADDI(2, 0, 7);
    for (int j = 0; j < count - 2; j++) {
        int rd = (j % 28) + 3;
        prog[i++] = DIV(rd, 1, 2);
    }
    prog[i++] = HALT;
    return i;
}

// 7. DIV operations (dependent chain)
int gen_div_dependent(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = LUI(1, 0x10000);  // x1 = 0x10000000
    prog[i++] = ADDI(2, 0, 2);
    for (int j = 0; j < count - 2; j++) {
        prog[i++] = DIV(1, 1, 2);  // x1 = x1 / 2
    }
    prog[i++] = HALT;
    return i;
}

// 8. Simple loop (branch always taken)
int gen_simple_loop(uint32_t* prog, int iterations) {
    int i = 0;
    prog[i++] = ADDI(1, 0, iterations);  // x1 = iterations (counter)
    prog[i++] = ADDI(2, 0, 0);           // x2 = 0 (accumulator)
    // Loop start (offset 8 bytes = 2 instructions from here)
    prog[i++] = ADDI(2, 2, 1);           // x2 = x2 + 1
    prog[i++] = ADDI(1, 1, -1);          // x1 = x1 - 1
    prog[i++] = BNE(1, 0, -8);           // if x1 != 0, branch back 8 bytes
    prog[i++] = HALT;
    return i;
}

// 9. Nested loop
int gen_nested_loop(uint32_t* prog, int outer, int inner) {
    int i = 0;
    prog[i++] = ADDI(1, 0, outer);       // x1 = outer counter
    prog[i++] = ADDI(3, 0, 0);           // x3 = result
    // Outer loop
    prog[i++] = ADDI(2, 0, inner);       // x2 = inner counter
    // Inner loop
    prog[i++] = ADDI(3, 3, 1);           // x3++
    prog[i++] = ADDI(2, 2, -1);          // x2--
    prog[i++] = BNE(2, 0, -8);           // inner loop back
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -20);          // outer loop back (5 instructions = 20 bytes)
    prog[i++] = HALT;
    return i;
}

// 10. Branch alternating (50% taken)
int gen_branch_alternating(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, count);       // x1 = counter
    prog[i++] = ADDI(2, 0, 0);           // x2 = 0
    prog[i++] = ADDI(3, 0, 1);           // x3 = 1
    // Loop
    prog[i++] = ANDI(4, 1, 1);           // x4 = x1 & 1 (odd/even)
    prog[i++] = BEQ(4, 0, 8);            // if even, skip next
    prog[i++] = ADDI(2, 2, 1);           // x2++ (only if odd)
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -16);          // loop back
    prog[i++] = HALT;
    return i;
}

// 11. Branch random pattern (hard to predict)
int gen_branch_random(uint32_t* prog, int count) {
    int i = 0;
    prog[i++] = ADDI(1, 0, count);       // x1 = counter
    prog[i++] = ADDI(2, 0, 0);           // x2 = accumulator
    prog[i++] = ADDI(3, 0, 0x5A5A);      // x3 = pseudo-random seed
    // Loop
    prog[i++] = SRLI(4, 3, 3);           // x4 = x3 >> 3
    prog[i++] = XOR(3, 3, 4);            // x3 ^= x4 (LFSR-like)
    prog[i++] = ANDI(4, 3, 1);           // x4 = x3 & 1
    prog[i++] = BEQ(4, 0, 8);            // branch based on LSB
    prog[i++] = ADDI(2, 2, 1);           // x2++
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -24);          // loop back
    prog[i++] = HALT;
    return i;
}

// 12. Function call pattern (JAL/JALR)
int gen_function_calls(uint32_t* prog, int calls) {
    int i = 0;
    prog[i++] = ADDI(1, 0, calls);       // x1 = call counter
    prog[i++] = ADDI(2, 0, 0);           // x2 = result
    // Main loop
    int loop_start = i;
    prog[i++] = JAL(5, 12);              // call function (3 instructions ahead)
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -8);           // loop back
    prog[i++] = JAL(0, 16);              // jump to end (skip function)
    // Function body
    prog[i++] = ADDI(2, 2, 1);           // x2++
    prog[i++] = ADDI(2, 2, 1);           // x2++
    prog[i++] = JALR(0, 5, 0);           // return
    // End
    prog[i++] = HALT;
    return i;
}

// 13. Mixed workload (realistic)
int gen_mixed_workload(uint32_t* prog, int iterations) {
    int i = 0;
    prog[i++] = ADDI(1, 0, iterations);  // x1 = counter
    prog[i++] = ADDI(10, 0, 0);          // x10 = sum
    prog[i++] = ADDI(11, 0, 3);          // x11 = multiplier
    prog[i++] = ADDI(12, 0, 7);          // x12 = divisor
    // Loop
    prog[i++] = ADD(2, 1, 10);           // x2 = x1 + x10
    prog[i++] = MUL(3, 2, 11);           // x3 = x2 * 3
    prog[i++] = ANDI(4, 3, 0xF);         // x4 = x3 & 0xF
    prog[i++] = BEQ(4, 0, 8);            // skip if zero
    prog[i++] = ADD(10, 10, 4);          // x10 += x4
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -24);          // loop back
    prog[i++] = HALT;
    return i;
}

// 14. Fibonacci sequence
int gen_fibonacci(uint32_t* prog, int n) {
    int i = 0;
    prog[i++] = ADDI(1, 0, n);           // x1 = n (counter)
    prog[i++] = ADDI(2, 0, 0);           // x2 = fib(0) = 0
    prog[i++] = ADDI(3, 0, 1);           // x3 = fib(1) = 1
    // Loop
    prog[i++] = ADD(4, 2, 3);            // x4 = x2 + x3
    prog[i++] = ADD(2, 0, 3);            // x2 = x3
    prog[i++] = ADD(3, 0, 4);            // x3 = x4
    prog[i++] = ADDI(1, 1, -1);          // x1--
    prog[i++] = BNE(1, 0, -16);          // loop back
    prog[i++] = HALT;
    return i;
}

// 15. Prime sieve (compute intensive)
int gen_prime_check(uint32_t* prog, int num) {
    int i = 0;
    prog[i++] = ADDI(1, 0, num);         // x1 = number to check
    prog[i++] = ADDI(2, 0, 2);           // x2 = divisor starting at 2
    prog[i++] = ADDI(10, 0, 1);          // x10 = is_prime (assume true)
    // Loop: check divisibility
    prog[i++] = MUL(3, 2, 2);            // x3 = x2 * x2
    prog[i++] = BGE(3, 1, 24);           // if x2*x2 >= num, done (6 instr ahead)
    prog[i++] = REM(4, 1, 2);            // x4 = num % divisor
    prog[i++] = BNE(4, 0, 8);            // if remainder != 0, skip
    prog[i++] = ADDI(10, 0, 0);          // x10 = 0 (not prime)
    prog[i++] = ADDI(2, 2, 1);           // x2++
    prog[i++] = JAL(0, -24);             // loop back
    // Done
    prog[i++] = HALT;
    return i;
}


// ============================================================
// Main Function - Run All Benchmarks
// ============================================================
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════════════════════╗\n");
    printf("║     RISC-V OoO CPU - Comprehensive CPI Measurement Results                   ║\n");
    printf("║     精确到小数点后三位 (3 decimal places precision)                          ║\n");
    printf("╚══════════════════════════════════════════════════════════════════════════════╝\n");
    printf("\n");
    
    uint32_t prog[8192];
    int size;
    CPUSimulator sim;
    std::vector<TestResult> results;
    
    // ========================================
    // Section 1: Basic ALU Tests
    // ========================================
    printf("┌──────────────────────────────────────────────────────────────────────────────┐\n");
    printf("│ 【基础ALU测试 / Basic ALU Tests】                                            │\n");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    printf("│ %-44s │ %8s │ %8s │ %8s │\n", "Benchmark", "CPI", "IPC", "Commits");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    
    size = gen_independent_alu(prog, 200);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    auto r = runTest(sim, "Independent ADDI (200)", 200);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_dependent_alu(prog, 200);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Dependent ADD chain (200)", 200);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_mixed_alu(prog, 200);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Mixed ALU ops (200)", 200);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    printf("└──────────────────────────────────────────────────────────────────────────────┘\n\n");
    
    // ========================================
    // Section 2: Multiply/Divide Tests
    // ========================================
    printf("┌──────────────────────────────────────────────────────────────────────────────┐\n");
    printf("│ 【乘除法测试 / Multiply/Divide Tests】                                       │\n");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    printf("│ %-44s │ %8s │ %8s │ %8s │\n", "Benchmark", "CPI", "IPC", "Commits");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    
    size = gen_mul_independent(prog, 100);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "MUL independent (100)", 100);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_mul_dependent(prog, 50);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "MUL dependent chain (50)", 50);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_div_independent(prog, 30);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "DIV independent (30)", 30);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_div_dependent(prog, 20);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "DIV dependent chain (20)", 20);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    printf("└──────────────────────────────────────────────────────────────────────────────┘\n\n");
    
    // ========================================
    // Section 3: Branch Tests
    // ========================================
    printf("┌──────────────────────────────────────────────────────────────────────────────┐\n");
    printf("│ 【分支测试 / Branch Tests】                                                  │\n");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    printf("│ %-44s │ %8s │ %8s │ %8s │\n", "Benchmark", "CPI", "IPC", "Commits");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    
    size = gen_simple_loop(prog, 100);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Simple loop (100 iter)", 100 * 3 + 2);  // 3 instr per iter + setup
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_nested_loop(prog, 10, 10);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Nested loop (10x10)", 10 * 10 * 3 + 10 * 3 + 2);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_branch_alternating(prog, 100);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Branch alternating (100)", 100 * 4 + 3);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_branch_random(prog, 100);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Branch random pattern (100)", 100 * 6 + 3);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_function_calls(prog, 50);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Function calls (50)", 50 * 5 + 3);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    printf("└──────────────────────────────────────────────────────────────────────────────┘\n\n");
    
    // ========================================
    // Section 4: Complex Workloads
    // ========================================
    printf("┌──────────────────────────────────────────────────────────────────────────────┐\n");
    printf("│ 【综合测试 / Complex Workloads】                                             │\n");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    printf("│ %-44s │ %8s │ %8s │ %8s │\n", "Benchmark", "CPI", "IPC", "Commits");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    
    size = gen_mixed_workload(prog, 50);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Mixed workload (50 iter)", 50 * 7 + 4);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_fibonacci(prog, 50);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Fibonacci (50)", 50 * 4 + 3);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_prime_check(prog, 97);  // Check if 97 is prime
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Prime check (97)", 200);  // Approximate
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    printf("└──────────────────────────────────────────────────────────────────────────────┘\n\n");
    
    // ========================================
    // Section 5: Long Running Tests
    // ========================================
    printf("┌──────────────────────────────────────────────────────────────────────────────┐\n");
    printf("│ 【长时间运行测试 / Long Running Tests】                                      │\n");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    printf("│ %-44s │ %8s │ %8s │ %8s │\n", "Benchmark", "CPI", "IPC", "Commits");
    printf("├──────────────────────────────────────────────────────────────────────────────┤\n");
    
    size = gen_independent_alu(prog, 1000);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Independent ADDI (1000)", 1000);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_simple_loop(prog, 500);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Simple loop (500 iter)", 500 * 3 + 2);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    size = gen_fibonacci(prog, 200);
    memset(memory, 0, sizeof(memory));
    for (int i = 0; i < size; i++) memory[i] = prog[i];
    r = runTest(sim, "Fibonacci (200)", 200 * 4 + 3);
    printf("│ %-44s │ %8.3f │ %8.3f │ %8lu │\n", r.name, r.cpi, r.ipc, r.total_commits);
    results.push_back(r);
    
    printf("└──────────────────────────────────────────────────────────────────────────────┘\n\n");
    
    // ========================================
    // Summary Statistics
    // ========================================
    double total_cpi = 0;
    double min_cpi = 999, max_cpi = 0;
    const char* min_name = "";
    const char* max_name = "";
    
    for (const auto& res : results) {
        total_cpi += res.cpi;
        if (res.cpi < min_cpi && res.cpi > 0) { min_cpi = res.cpi; min_name = res.name; }
        if (res.cpi > max_cpi) { max_cpi = res.cpi; max_name = res.name; }
    }
    double avg_cpi = total_cpi / results.size();
    
    printf("╔══════════════════════════════════════════════════════════════════════════════╗\n");
    printf("║                              Summary / 总结                                  ║\n");
    printf("╠══════════════════════════════════════════════════════════════════════════════╣\n");
    printf("║  Total tests:     %3lu                                                       ║\n", results.size());
    printf("║  Average CPI:     %.3f                                                       ║\n", avg_cpi);
    printf("║  Best CPI:        %.3f  (%s)                                  ║\n", min_cpi, min_name);
    printf("║  Worst CPI:       %.3f  (%s)                                  ║\n", max_cpi, max_name);
    printf("╚══════════════════════════════════════════════════════════════════════════════╝\n");
    
    printf("\n");
    printf("说明 / Notes:\n");
    printf("  • CPI = Cycles Per Instruction (稳态测量，排除流水线预热)\n");
    printf("  • IPC = Instructions Per Cycle = 1/CPI\n");
    printf("  • 单发射CPU理想CPI = 1.000\n");
    printf("  • CPI > 1.000 表示存在停顿 (分支误预测、数据依赖、Cache Miss等)\n");
    printf("  • CPI < 1.000 需要超标量架构 (本设计不支持)\n");
    printf("\n");
    
    return 0;
}
