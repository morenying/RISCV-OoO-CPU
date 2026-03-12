# RISC-V OoO CPU Programmer's Reference Manual

## Overview

This document provides a programmer's reference for the RISC-V Out-of-Order CPU implementing RV32IM with Zicsr extension.

## Instruction Set Summary

### RV32I Base Integer Instructions

#### Arithmetic Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| ADD rd, rs1, rs2 | R | Add | rd = rs1 + rs2 |
| SUB rd, rs1, rs2 | R | Subtract | rd = rs1 - rs2 |
| ADDI rd, rs1, imm | I | Add Immediate | rd = rs1 + sext(imm) |

#### Logical Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| AND rd, rs1, rs2 | R | AND | rd = rs1 & rs2 |
| OR rd, rs1, rs2 | R | OR | rd = rs1 \| rs2 |
| XOR rd, rs1, rs2 | R | XOR | rd = rs1 ^ rs2 |
| ANDI rd, rs1, imm | I | AND Immediate | rd = rs1 & sext(imm) |
| ORI rd, rs1, imm | I | OR Immediate | rd = rs1 \| sext(imm) |
| XORI rd, rs1, imm | I | XOR Immediate | rd = rs1 ^ sext(imm) |

#### Shift Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| SLL rd, rs1, rs2 | R | Shift Left Logical | rd = rs1 << rs2[4:0] |
| SRL rd, rs1, rs2 | R | Shift Right Logical | rd = rs1 >> rs2[4:0] |
| SRA rd, rs1, rs2 | R | Shift Right Arithmetic | rd = rs1 >>> rs2[4:0] |
| SLLI rd, rs1, shamt | I | Shift Left Immediate | rd = rs1 << shamt |
| SRLI rd, rs1, shamt | I | Shift Right Immediate | rd = rs1 >> shamt |
| SRAI rd, rs1, shamt | I | Shift Right Arith Imm | rd = rs1 >>> shamt |

#### Compare Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| SLT rd, rs1, rs2 | R | Set Less Than | rd = (rs1 < rs2) ? 1 : 0 (signed) |
| SLTU rd, rs1, rs2 | R | Set Less Than Unsigned | rd = (rs1 < rs2) ? 1 : 0 (unsigned) |
| SLTI rd, rs1, imm | I | Set Less Than Immediate | rd = (rs1 < sext(imm)) ? 1 : 0 |
| SLTIU rd, rs1, imm | I | Set Less Than Imm Unsigned | rd = (rs1 < sext(imm)) ? 1 : 0 |

#### Upper Immediate Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| LUI rd, imm | U | Load Upper Immediate | rd = imm << 12 |
| AUIPC rd, imm | U | Add Upper Imm to PC | rd = PC + (imm << 12) |

#### Branch Instructions

| Instruction | Format | Description | Condition |
|-------------|--------|-------------|-----------|
| BEQ rs1, rs2, offset | B | Branch if Equal | rs1 == rs2 |
| BNE rs1, rs2, offset | B | Branch if Not Equal | rs1 != rs2 |
| BLT rs1, rs2, offset | B | Branch if Less Than | rs1 < rs2 (signed) |
| BGE rs1, rs2, offset | B | Branch if Greater/Equal | rs1 >= rs2 (signed) |
| BLTU rs1, rs2, offset | B | Branch if Less Than Unsigned | rs1 < rs2 (unsigned) |
| BGEU rs1, rs2, offset | B | Branch if Greater/Equal Unsigned | rs1 >= rs2 (unsigned) |

#### Jump Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| JAL rd, offset | J | Jump and Link | rd = PC+4; PC = PC + sext(offset) |
| JALR rd, rs1, offset | I | Jump and Link Register | rd = PC+4; PC = (rs1 + sext(offset)) & ~1 |

#### Load Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| LB rd, offset(rs1) | I | Load Byte | rd = sext(M[rs1+offset][7:0]) |
| LH rd, offset(rs1) | I | Load Halfword | rd = sext(M[rs1+offset][15:0]) |
| LW rd, offset(rs1) | I | Load Word | rd = M[rs1+offset][31:0] |
| LBU rd, offset(rs1) | I | Load Byte Unsigned | rd = zext(M[rs1+offset][7:0]) |
| LHU rd, offset(rs1) | I | Load Halfword Unsigned | rd = zext(M[rs1+offset][15:0]) |

#### Store Instructions

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| SB rs2, offset(rs1) | S | Store Byte | M[rs1+offset][7:0] = rs2[7:0] |
| SH rs2, offset(rs1) | S | Store Halfword | M[rs1+offset][15:0] = rs2[15:0] |
| SW rs2, offset(rs1) | S | Store Word | M[rs1+offset][31:0] = rs2[31:0] |

#### System Instructions

| Instruction | Format | Description |
|-------------|--------|-------------|
| ECALL | I | Environment Call |
| EBREAK | I | Breakpoint |
| FENCE | I | Memory Fence |

### RV32M Multiply/Divide Extension

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| MUL rd, rs1, rs2 | R | Multiply | rd = (rs1 * rs2)[31:0] |
| MULH rd, rs1, rs2 | R | Multiply High Signed | rd = (rs1 * rs2)[63:32] (signed) |
| MULHSU rd, rs1, rs2 | R | Multiply High Signed-Unsigned | rd = (rs1 * rs2)[63:32] |
| MULHU rd, rs1, rs2 | R | Multiply High Unsigned | rd = (rs1 * rs2)[63:32] (unsigned) |
| DIV rd, rs1, rs2 | R | Divide | rd = rs1 / rs2 (signed) |
| DIVU rd, rs1, rs2 | R | Divide Unsigned | rd = rs1 / rs2 (unsigned) |
| REM rd, rs1, rs2 | R | Remainder | rd = rs1 % rs2 (signed) |
| REMU rd, rs1, rs2 | R | Remainder Unsigned | rd = rs1 % rs2 (unsigned) |

### Zicsr Extension

| Instruction | Format | Description | Operation |
|-------------|--------|-------------|-----------|
| CSRRW rd, csr, rs1 | I | CSR Read/Write | t=CSR[csr]; CSR[csr]=rs1; rd=t |
| CSRRS rd, csr, rs1 | I | CSR Read/Set | t=CSR[csr]; CSR[csr]=t\|rs1; rd=t |
| CSRRC rd, csr, rs1 | I | CSR Read/Clear | t=CSR[csr]; CSR[csr]=t&~rs1; rd=t |
| CSRRWI rd, csr, imm | I | CSR Read/Write Immediate | t=CSR[csr]; CSR[csr]=zext(imm); rd=t |
| CSRRSI rd, csr, imm | I | CSR Read/Set Immediate | t=CSR[csr]; CSR[csr]=t\|zext(imm); rd=t |
| CSRRCI rd, csr, imm | I | CSR Read/Clear Immediate | t=CSR[csr]; CSR[csr]=t&~zext(imm); rd=t |

## Control and Status Registers (CSRs)

### Machine-Level CSRs

| Address | Name | Description | Access |
|---------|------|-------------|--------|
| 0x300 | mstatus | Machine Status | RW |
| 0x301 | misa | ISA and Extensions | RO |
| 0x304 | mie | Machine Interrupt Enable | RW |
| 0x305 | mtvec | Machine Trap Vector | RW |
| 0x340 | mscratch | Machine Scratch | RW |
| 0x341 | mepc | Machine Exception PC | RW |
| 0x342 | mcause | Machine Cause | RW |
| 0x343 | mtval | Machine Trap Value | RW |
| 0x344 | mip | Machine Interrupt Pending | RW |

### Machine Counter CSRs

| Address | Name | Description | Access |
|---------|------|-------------|--------|
| 0xB00 | mcycle | Cycle Counter (low) | RW |
| 0xB02 | minstret | Instructions Retired (low) | RW |
| 0xB80 | mcycleh | Cycle Counter (high) | RW |
| 0xB82 | minstreth | Instructions Retired (high) | RW |

### Hardware Performance Counters

| Address | Name | Description |
|---------|------|-------------|
| 0xB03 | mhpmcounter3 | Branch Count |
| 0xB04 | mhpmcounter4 | Branch Misprediction Count |
| 0xB05 | mhpmcounter5 | I-Cache Access Count |
| 0xB06 | mhpmcounter6 | I-Cache Miss Count |
| 0xB07 | mhpmcounter7 | D-Cache Access Count |
| 0xB08 | mhpmcounter8 | D-Cache Miss Count |
| 0xB09 | mhpmcounter9 | Load Count |
| 0xB0A | mhpmcounter10 | Store Count |
| 0xB0B | mhpmcounter11 | Frontend Stall Cycles |
| 0xB0C | mhpmcounter12 | Backend Stall Cycles |

### mstatus Register Fields

| Bits | Field | Description |
|------|-------|-------------|
| 3 | MIE | Machine Interrupt Enable |
| 7 | MPIE | Previous MIE |
| 12:11 | MPP | Previous Privilege Mode |

### mcause Register Values

| Value | Description |
|-------|-------------|
| 0 | Instruction address misaligned |
| 1 | Instruction access fault |
| 2 | Illegal instruction |
| 3 | Breakpoint |
| 4 | Load address misaligned |
| 5 | Load access fault |
| 6 | Store address misaligned |
| 7 | Store access fault |
| 11 | Environment call from M-mode |

## Memory Map

| Address Range | Description |
|---------------|-------------|
| 0x0000_0000 - 0x0000_3FFF | Instruction Memory (16KB) |
| 0x0001_0000 - 0x0001_3FFF | Data Memory (16KB) |
| 0x1000_0000 - 0x1000_00FF | Peripheral Registers |

## Exception Handling

### Exception Entry
1. `mepc` ← PC of faulting instruction
2. `mcause` ← Exception cause code
3. `mtval` ← Exception-specific value
4. `mstatus.MPIE` ← `mstatus.MIE`
5. `mstatus.MIE` ← 0
6. PC ← `mtvec`

### Exception Return (MRET)
1. PC ← `mepc`
2. `mstatus.MIE` ← `mstatus.MPIE`
3. `mstatus.MPIE` ← 1

## Programming Notes

### Register Usage Convention (RISC-V ABI)

| Register | ABI Name | Description | Saver |
|----------|----------|-------------|-------|
| x0 | zero | Hard-wired zero | - |
| x1 | ra | Return address | Caller |
| x2 | sp | Stack pointer | Callee |
| x3 | gp | Global pointer | - |
| x4 | tp | Thread pointer | - |
| x5-x7 | t0-t2 | Temporaries | Caller |
| x8 | s0/fp | Saved/Frame pointer | Callee |
| x9 | s1 | Saved register | Callee |
| x10-x11 | a0-a1 | Arguments/Return values | Caller |
| x12-x17 | a2-a7 | Arguments | Caller |
| x18-x27 | s2-s11 | Saved registers | Callee |
| x28-x31 | t3-t6 | Temporaries | Caller |

### Alignment Requirements

- Instructions: 4-byte aligned
- Halfword access: 2-byte aligned
- Word access: 4-byte aligned
- Misaligned access generates exception

### Division Special Cases

| Operation | Dividend | Divisor | Result |
|-----------|----------|---------|--------|
| DIV | Any | 0 | -1 (0xFFFFFFFF) |
| DIVU | Any | 0 | 0xFFFFFFFF |
| REM | Any | 0 | Dividend |
| REMU | Any | 0 | Dividend |
| DIV | -2^31 | -1 | -2^31 (overflow) |
| REM | -2^31 | -1 | 0 |
