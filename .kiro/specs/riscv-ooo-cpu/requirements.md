# Requirements Document

## Introduction

本文档定义了一款基于RISC-V架构的高性能乱序执行CPU的需求规格。该CPU采用七级流水线设计，支持动态调度、寄存器重命名、乱序执行和精确异常处理。目标是实现一个功能完整、可综合的Verilog 2001设计。

## Glossary

- **CPU_Core**: RISC-V乱序执行处理器核心
- **IF_Stage**: 指令获取阶段，负责从I-Cache获取指令
- **ID_Stage**: 指令解码与分派阶段，负责解码指令并读取寄存器
- **RN_Stage**: 寄存器重命名阶段，消除WAW和WAR冒险
- **IS_Stage**: 指令调度阶段，管理保留站和指令发射
- **EX_Stage**: 执行阶段，包含ALU、乘除法单元等功能单元
- **MEM_Stage**: 内存访问阶段，处理Load/Store操作
- **WB_Stage**: 结果提交阶段，按序提交结果到架构状态
- **ROB**: Reorder Buffer，重排序缓冲区，支持乱序执行和精确异常
- **RS**: Reservation Station，保留站，用于动态调度
- **RAT**: Register Alias Table，寄存器别名表，用于寄存器重命名
- **PRF**: Physical Register File，物理寄存器文件
- **ARF**: Architectural Register File，架构寄存器文件（x0-x31）
- **BPU**: Branch Prediction Unit，分支预测单元
- **BTB**: Branch Target Buffer，分支目标缓冲区
- **PHT**: Pattern History Table，模式历史表
- **GHR**: Global History Register，全局历史寄存器
- **I_Cache**: Instruction Cache，指令缓存
- **D_Cache**: Data Cache，数据缓存
- **LSQ**: Load Store Queue，访存队列
- **CDB**: Common Data Bus，公共数据总线

## Requirements

### Requirement 1: RV32IM基础指令集支持

**User Story:** As a 软件开发者, I want CPU支持完整的RV32IM指令集, so that 我可以运行标准的RISC-V程序。

#### Acceptance Criteria

1. THE CPU_Core SHALL support all 37 RV32I base integer instructions including:
   - Arithmetic: ADD, ADDI, SUB
   - Logical: AND, ANDI, OR, ORI, XOR, XORI
   - Shift: SLL, SLLI, SRL, SRLI, SRA, SRAI
   - Compare: SLT, SLTI, SLTU, SLTIU
   - Load: LB, LH, LW, LBU, LHU
   - Store: SB, SH, SW
   - Branch: BEQ, BNE, BLT, BGE, BLTU, BGEU
   - Jump: JAL, JALR
   - Upper Immediate: LUI, AUIPC
   - System: ECALL, EBREAK, FENCE

2. THE CPU_Core SHALL support all 8 RV32M multiply/divide extension instructions:
   - Multiply: MUL, MULH, MULHSU, MULHU
   - Divide: DIV, DIVU, REM, REMU

3. THE CPU_Core SHALL support essential Zicsr CSR instructions:
   - CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI

4. WHEN an invalid opcode is encountered, THE ID_Stage SHALL raise an illegal instruction exception

5. THE CPU_Core SHALL implement x0 register as hardwired zero

### Requirement 2: 七级流水线架构

**User Story:** As a CPU架构师, I want 实现七级流水线, so that 可以提高指令吞吐量和时钟频率。

#### Acceptance Criteria

1. THE CPU_Core SHALL implement a 7-stage pipeline with stages: IF, ID, RN, IS, EX, MEM, WB

2. WHEN the IF_Stage fetches an instruction, THE IF_Stage SHALL provide the instruction and PC to ID_Stage within one clock cycle

3. WHEN the ID_Stage decodes an instruction, THE ID_Stage SHALL extract opcode, rd, rs1, rs2, immediate, and control signals

4. WHEN the RN_Stage processes an instruction, THE RN_Stage SHALL map architectural registers to physical registers using RAT

5. WHEN the IS_Stage receives an instruction, THE IS_Stage SHALL allocate a reservation station entry and ROB entry

6. WHEN all operands are ready in a reservation station, THE IS_Stage SHALL issue the instruction to the appropriate functional unit

7. WHEN the EX_Stage completes execution, THE EX_Stage SHALL broadcast the result on CDB

8. WHEN the MEM_Stage processes a load instruction, THE MEM_Stage SHALL access D_Cache and return data

9. WHEN the WB_Stage commits an instruction, THE WB_Stage SHALL update ARF only if the instruction is at ROB head and completed without exception

### Requirement 3: 寄存器重命名

**User Story:** As a CPU架构师, I want 实现寄存器重命名, so that 可以消除WAW和WAR数据冒险，支持更多并行执行。

#### Acceptance Criteria

1. THE RN_Stage SHALL maintain a RAT with 32 entries mapping architectural registers to physical registers

2. THE PRF SHALL contain at least 64 physical registers to support sufficient in-flight instructions

3. WHEN a destination register is renamed, THE RN_Stage SHALL allocate a free physical register from the free list

4. WHEN an instruction commits, THE WB_Stage SHALL return the old physical register mapping to the free list

5. WHEN a branch misprediction occurs, THE RN_Stage SHALL restore RAT to the checkpoint state

6. THE RN_Stage SHALL maintain RAT checkpoints for each in-flight branch instruction

### Requirement 4: 动态调度与乱序执行

**User Story:** As a CPU架构师, I want 实现基于Tomasulo算法的动态调度, so that 指令可以乱序执行以提高性能。

#### Acceptance Criteria

1. THE IS_Stage SHALL implement reservation stations for each functional unit type:
   - At least 4 entries for ALU operations
   - At least 2 entries for multiply/divide operations
   - At least 4 entries for load/store operations

2. WHEN an instruction enters a reservation station, THE IS_Stage SHALL record source operand values or ROB tags

3. WHEN a result is broadcast on CDB, THE IS_Stage SHALL update all waiting reservation station entries with matching tags

4. WHEN multiple instructions are ready to issue, THE IS_Stage SHALL use oldest-first priority for issue selection

5. THE ROB SHALL support at least 32 entries for in-flight instructions

6. WHEN an instruction completes out-of-order, THE ROB SHALL hold the result until in-order commit

### Requirement 5: 数据前推（Forwarding/Bypassing）

**User Story:** As a CPU架构师, I want 实现数据前推, so that 可以减少数据冒险导致的流水线停顿。

#### Acceptance Criteria

1. WHEN a result is produced by EX_Stage, THE CDB SHALL broadcast the result to all reservation stations in the same cycle

2. WHEN a reservation station entry is waiting for an operand, THE IS_Stage SHALL capture the value from CDB when the tag matches

3. WHEN a load instruction completes in MEM_Stage, THE MEM_Stage SHALL broadcast the result on CDB

4. THE CPU_Core SHALL support forwarding from EX_Stage to IS_Stage within one cycle

### Requirement 6: 精确异常处理

**User Story:** As a 系统程序员, I want CPU支持精确异常, so that 异常处理程序可以正确恢复执行。

#### Acceptance Criteria

1. WHEN an exception occurs during execution, THE EX_Stage SHALL mark the exception in the corresponding ROB entry

2. WHEN an instruction with exception reaches ROB head, THE WB_Stage SHALL:
   - Flush all younger instructions from pipeline
   - Restore architectural state to the excepting instruction
   - Transfer control to exception handler

3. THE CPU_Core SHALL support the following exceptions:
   - Illegal instruction exception
   - Load/Store address misaligned exception
   - Load/Store access fault
   - Environment call (ECALL)
   - Breakpoint (EBREAK)

4. WHEN an exception is taken, THE CPU_Core SHALL save PC to mepc CSR and cause to mcause CSR

5. THE CPU_Core SHALL implement mtvec, mepc, mcause, mstatus CSR registers for exception handling

### Requirement 7: TAGE动态分支预测

**User Story:** As a CPU架构师, I want 实现TAGE高端动态分支预测, so that 可以获得最高的分支预测准确率并减少流水线停顿。

#### Acceptance Criteria

1. THE BPU SHALL implement a TAGE (TAgged GEometric history length) predictor with:
   - 1 bimodal base predictor with 2048 entries and 2-bit saturating counters
   - 4 tagged predictor tables (T1, T2, T3, T4) with geometric history lengths
   - History lengths: T1=8, T2=16, T3=32, T4=64 bits
   - Each tagged table with 256 entries containing: 3-bit prediction counter, 2-bit useful counter, partial tag

2. THE BPU SHALL implement tag computation using:
   - Folded global history XORed with PC for tag generation
   - Partial tags of 8-10 bits per tagged table entry

3. WHEN predicting a branch, THE BPU SHALL:
   - Query all 5 tables (bimodal + 4 tagged) in parallel
   - Select prediction from the table with longest matching history
   - Use bimodal as default when no tagged table matches

4. WHEN a branch is resolved, THE BPU SHALL update TAGE tables:
   - Update the provider table's prediction counter
   - Allocate new entry in longer history table on misprediction
   - Manage useful counters for replacement policy

5. THE BPU SHALL implement a BTB with at least 512 entries for branch target prediction with:
   - 2-way set associative organization
   - Branch type field (conditional, unconditional, call, return)

6. WHEN a branch misprediction is detected, THE CPU_Core SHALL:
   - Flush all instructions fetched after the mispredicted branch
   - Restore global history register to the correct state
   - Redirect fetch to correct target within 2 cycles

7. THE BPU SHALL implement a Return Address Stack (RAS) with:
   - At least 16 entries for function return prediction
   - Speculative and committed stack pointers for recovery

8. THE BPU SHALL implement a Loop Predictor with:
   - 32 entries for detecting and predicting loop branches
   - Loop iteration counter and trip count fields

9. THE BPU SHALL maintain a global history register (GHR) of at least 64 bits

10. THE BPU SHALL support speculative history update with checkpoint/restore capability

### Requirement 8: 指令缓存（I-Cache）

**User Story:** As a CPU架构师, I want 实现指令缓存, so that 可以减少指令获取延迟。

#### Acceptance Criteria

1. THE I_Cache SHALL implement a direct-mapped cache with:
   - At least 4KB capacity
   - 32-byte cache line size
   - Valid bit per cache line

2. WHEN a cache hit occurs, THE I_Cache SHALL return the instruction within one clock cycle

3. WHEN a cache miss occurs, THE I_Cache SHALL:
   - Stall the IF_Stage
   - Fetch the cache line from memory
   - Update the cache line and resume fetch

4. THE I_Cache SHALL support cache invalidation for self-modifying code (via FENCE.I)

### Requirement 9: 数据缓存（D-Cache）

**User Story:** As a CPU架构师, I want 实现数据缓存, so that 可以减少数据访问延迟。

#### Acceptance Criteria

1. THE D_Cache SHALL implement a 2-way set-associative cache with:
   - At least 4KB capacity
   - 32-byte cache line size
   - LRU replacement policy
   - Write-back, write-allocate policy

2. WHEN a cache hit occurs on load, THE D_Cache SHALL return data within one clock cycle

3. WHEN a cache miss occurs, THE D_Cache SHALL:
   - Stall the MEM_Stage
   - Write back dirty line if necessary
   - Fetch the cache line from memory
   - Update cache and return data

4. WHEN a store instruction executes, THE D_Cache SHALL update the cache line and mark it dirty

5. THE D_Cache SHALL support byte, halfword, and word access with proper alignment

### Requirement 10: Load/Store队列

**User Story:** As a CPU架构师, I want 实现Load/Store队列, so that 可以支持访存指令的乱序执行同时保证内存一致性。

#### Acceptance Criteria

1. THE LSQ SHALL maintain separate Load Queue and Store Queue with at least 8 entries each

2. WHEN a load instruction is issued, THE LSQ SHALL check Store Queue for address conflicts

3. IF a load address matches a pending store address, THEN THE LSQ SHALL forward the store data to the load

4. WHEN a store instruction commits, THE LSQ SHALL write data to D_Cache in program order

5. THE LSQ SHALL support speculative load execution before older stores are resolved

6. WHEN a memory ordering violation is detected, THE LSQ SHALL flush and re-execute the violating load

### Requirement 11: 功能单元

**User Story:** As a CPU架构师, I want 实现多个功能单元, so that 可以支持多条指令并行执行。

#### Acceptance Criteria

1. THE EX_Stage SHALL implement at least 2 ALU units for integer arithmetic and logical operations

2. THE EX_Stage SHALL implement 1 multiplier unit with 3-cycle latency for MUL instructions

3. THE EX_Stage SHALL implement 1 divider unit with variable latency (up to 32 cycles) for DIV instructions

4. THE EX_Stage SHALL implement 1 branch unit for branch resolution and target calculation

5. THE EX_Stage SHALL implement 1 address generation unit for load/store address calculation

6. WHEN multiple functional units complete in the same cycle, THE CDB SHALL arbitrate and serialize broadcasts

### Requirement 12: 流水线控制

**User Story:** As a CPU架构师, I want 实现完整的流水线控制逻辑, so that 可以正确处理各种冒险和异常情况。

#### Acceptance Criteria

1. WHEN a structural hazard occurs (e.g., CDB conflict), THE CPU_Core SHALL stall the appropriate pipeline stages

2. WHEN ROB is full, THE RN_Stage SHALL stall until an entry becomes available

3. WHEN reservation stations are full, THE IS_Stage SHALL stall dispatch

4. WHEN a branch misprediction occurs, THE CPU_Core SHALL flush IF, ID, RN stages and redirect fetch

5. WHEN an interrupt is pending, THE CPU_Core SHALL take the interrupt at the next instruction boundary

6. THE CPU_Core SHALL implement pipeline flush on exception with correct state restoration

### Requirement 13: 总线接口

**User Story:** As a 系统集成工程师, I want CPU提供标准总线接口, so that 可以连接外部存储器和外设。

#### Acceptance Criteria

1. THE CPU_Core SHALL implement an AXI4-Lite master interface for instruction fetch

2. THE CPU_Core SHALL implement an AXI4-Lite master interface for data access

3. WHEN a cache miss occurs, THE Cache SHALL generate appropriate AXI transactions

4. THE CPU_Core SHALL support burst transfers for cache line fills

5. THE CPU_Core SHALL handle bus errors and propagate them as exceptions

### Requirement 14: 调试支持

**User Story:** As a 硬件调试工程师, I want CPU支持基本调试功能, so that 可以进行硬件调试和验证。

#### Acceptance Criteria

1. THE CPU_Core SHALL implement debug CSR registers (dcsr, dpc, dscratch)

2. WHEN EBREAK is executed in debug mode, THE CPU_Core SHALL halt and enter debug state

3. THE CPU_Core SHALL support single-step execution via debug CSR

4. THE CPU_Core SHALL provide internal signal visibility for simulation and verification

### Requirement 15: 复位与时钟

**User Story:** As a 硬件工程师, I want CPU支持标准复位和时钟接口, so that 可以正确初始化和运行。

#### Acceptance Criteria

1. WHEN reset is asserted, THE CPU_Core SHALL:
   - Clear all pipeline registers
   - Initialize PC to reset vector (configurable, default 0x80000000)
   - Clear all CSRs to default values
   - Invalidate all cache lines
   - Clear ROB, reservation stations, and LSQ

2. THE CPU_Core SHALL operate on a single clock domain

3. THE CPU_Core SHALL support synchronous reset

4. WHEN reset is deasserted, THE CPU_Core SHALL begin fetching from reset vector
