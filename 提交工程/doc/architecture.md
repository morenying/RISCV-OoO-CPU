# RISC-V Out-of-Order CPU Architecture

## Overview

This document describes the architecture of a 7-stage out-of-order RISC-V CPU implementing the RV32IM instruction set with Zicsr extension.

## Pipeline Stages

```
┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐   ┌─────┐
│ IF  │──▶│ ID  │──▶│ RN  │──▶│ IS  │──▶│ EX  │──▶│ MEM │──▶│ WB  │
└─────┘   └─────┘   └─────┘   └─────┘   └─────┘   └─────┘   └─────┘
```

### Stage Descriptions

1. **IF (Instruction Fetch)**: Fetches instructions from I-Cache, interfaces with BPU
2. **ID (Instruction Decode)**: Decodes instructions, generates immediates
3. **RN (Rename)**: Register renaming using RAT and Free List
4. **IS (Issue)**: Instruction scheduling from Reservation Stations
5. **EX (Execute)**: ALU, MUL, DIV, Branch execution
6. **MEM (Memory)**: Load/Store Queue management, D-Cache access
7. **WB (Writeback)**: ROB commit, architectural state update

## Key Components

### Out-of-Order Execution Engine

- **ROB (Reorder Buffer)**: 32 entries, maintains program order for commit
- **RAT (Register Alias Table)**: Maps architectural to physical registers
- **Free List**: Manages 64 physical registers
- **PRF (Physical Register File)**: 64 x 32-bit registers
- **Reservation Stations**: 4 entries per functional unit

### Functional Units

- **ALU**: Single-cycle integer operations
- **MUL**: 3-cycle pipelined multiplier
- **DIV**: 34-cycle iterative divider
- **Branch Unit**: Branch resolution and target calculation
- **AGU**: Address generation for load/store

### Memory Subsystem

- **I-Cache**: 4KB, 4-way set associative
- **D-Cache**: 4KB, 4-way set associative, write-back
- **Load Queue**: 8 entries
- **Store Queue**: 8 entries
- **AXI Master**: Bus interface for cache misses

### Branch Prediction Unit

- **BTB**: 256 entries branch target buffer
- **TAGE Predictor**: Tagged geometric history predictor
- **Bimodal Predictor**: Base predictor
- **RAS**: 8-entry return address stack
- **Loop Predictor**: Loop iteration prediction

## Block Diagram

```
                    ┌─────────────────────────────────────────────────────┐
                    │                    CPU Core                          │
                    │  ┌─────────────────────────────────────────────────┐│
                    │  │              Frontend                            ││
                    │  │  ┌─────┐  ┌─────┐  ┌─────┐                      ││
                    │  │  │ BPU │  │I-$  │  │ IF  │──▶ ID ──▶ RN        ││
                    │  │  └─────┘  └─────┘  └─────┘                      ││
                    │  └─────────────────────────────────────────────────┘│
                    │  ┌─────────────────────────────────────────────────┐│
                    │  │              Backend                             ││
                    │  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐            ││
                    │  │  │ RAT │  │ ROB │  │ PRF │  │ CDB │            ││
                    │  │  └─────┘  └─────┘  └─────┘  └─────┘            ││
                    │  │  ┌─────────────────────────────────┐            ││
                    │  │  │      Reservation Stations       │            ││
                    │  │  │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ │            ││
                    │  │  │  │ALU│ │MUL│ │DIV│ │BRU│ │LSU│ │            ││
                    │  │  │  └───┘ └───┘ └───┘ └───┘ └───┘ │            ││
                    │  │  └─────────────────────────────────┘            ││
                    │  └─────────────────────────────────────────────────┘│
                    │  ┌─────────────────────────────────────────────────┐│
                    │  │              Memory Subsystem                    ││
                    │  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐            ││
                    │  │  │D-$  │  │ LQ  │  │ SQ  │  │ LSQ │            ││
                    │  │  └─────┘  └─────┘  └─────┘  └─────┘            ││
                    │  └─────────────────────────────────────────────────┘│
                    └─────────────────────────────────────────────────────┘
                                          │
                                    ┌─────┴─────┐
                                    │ AXI Bus   │
                                    └───────────┘
```

## Performance Targets

| Metric | Target |
|--------|--------|
| Clock Frequency | 100 MHz (Artix-7) |
| IPC | > 0.8 |
| Branch Prediction | > 90% accuracy |
| I-Cache Hit Rate | > 95% |
| D-Cache Hit Rate | > 90% |

## Supported Instructions

### RV32I Base
- Integer arithmetic: ADD, SUB, AND, OR, XOR, SLT, SLTU
- Shifts: SLL, SRL, SRA
- Immediate: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
- Upper immediate: LUI, AUIPC
- Branches: BEQ, BNE, BLT, BGE, BLTU, BGEU
- Jumps: JAL, JALR
- Loads: LB, LH, LW, LBU, LHU
- Stores: SB, SH, SW

### RV32M Extension
- Multiply: MUL, MULH, MULHSU, MULHU
- Divide: DIV, DIVU, REM, REMU

### Zicsr Extension
- CSR access: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI

## Exception Handling

Supported exceptions:
- Instruction address misaligned
- Illegal instruction
- Load/Store address misaligned
- Environment call (ECALL)
- Breakpoint (EBREAK)

## CSR Registers

| Address | Name | Description |
|---------|------|-------------|
| 0x300 | mstatus | Machine status |
| 0x304 | mie | Machine interrupt enable |
| 0x305 | mtvec | Machine trap vector |
| 0x340 | mscratch | Machine scratch |
| 0x341 | mepc | Machine exception PC |
| 0x342 | mcause | Machine cause |
| 0x343 | mtval | Machine trap value |
| 0x344 | mip | Machine interrupt pending |
| 0xB00 | mcycle | Cycle counter |
| 0xB02 | minstret | Instructions retired |
