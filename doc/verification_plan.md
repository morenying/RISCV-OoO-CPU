# RISC-V OoO CPU Verification Plan

## Overview

This document describes the verification strategy and test plan for the RISC-V Out-of-Order CPU.

## Verification Goals

1. **Functional Correctness**: Verify all instructions execute correctly
2. **Architectural Compliance**: Pass RISC-V compliance tests
3. **Performance Validation**: Meet IPC and timing targets
4. **Coverage Targets**: Achieve >95% line coverage, >90% branch coverage

## Verification Methodology

### Simulation-Based Verification

- **Unit Tests**: Individual module testing
- **Integration Tests**: Multi-module interaction testing
- **System Tests**: Full CPU execution testing
- **Property-Based Tests**: Formal property verification

### Tools

| Tool | Purpose |
|------|---------|
| Icarus Verilog | RTL simulation |
| Verilator | Lint and coverage |
| Vivado | FPGA synthesis and STA |
| riscv-tests | Compliance testing |

## Test Categories

### 1. Unit Tests

#### ALU Unit (tb_alu_unit.v)
- **Test Count**: 12,007 tests
- **Coverage**: All ALU operations
- **Properties Tested**:
  - ADD/SUB correctness
  - Logical operations (AND, OR, XOR)
  - Shift operations (SLL, SRL, SRA)
  - Compare operations (SLT, SLTU)
  - LUI/AUIPC

#### Multiplier Unit (tb_mul_unit.v)
- **Test Count**: 104 tests
- **Coverage**: MUL, MULH, MULHSU, MULHU
- **Properties Tested**:
  - Signed multiplication
  - Unsigned multiplication
  - Mixed sign multiplication
  - Pipeline latency

#### Divider Unit (tb_div_unit.v)
- **Test Count**: 105 tests
- **Coverage**: DIV, DIVU, REM, REMU
- **Properties Tested**:
  - Signed division
  - Unsigned division
  - Division by zero handling
  - Overflow handling

#### Branch Unit (tb_branch_unit.v)
- **Test Count**: 361 tests
- **Coverage**: All branch types
- **Properties Tested**:
  - BEQ/BNE correctness
  - BLT/BGE signed comparison
  - BLTU/BGEU unsigned comparison
  - Target address calculation

#### Decoder (tb_decoder.v)
- **Test Count**: 76 tests
- **Coverage**: All instruction formats
- **Properties Tested**:
  - R-type decoding
  - I-type decoding
  - S-type decoding
  - B-type decoding
  - U-type decoding
  - J-type decoding

### 2. Microarchitecture Tests

#### ROB (tb_rob.v)
- **Properties Tested**:
  - Allocation/deallocation
  - In-order commit
  - Flush handling
  - Full/empty detection

#### Reservation Station (tb_reservation_station.v)
- **Properties Tested**:
  - Operand capture from CDB
  - Oldest-first issue
  - Flush handling

#### RAT (tb_rat.v)
- **Properties Tested**:
  - Register mapping
  - Speculative state
  - Commit/rollback

#### Free List (tb_free_list.v)
- **Properties Tested**:
  - Allocation
  - Deallocation
  - Overflow/underflow prevention

### 3. Memory Subsystem Tests

#### I-Cache (tb_icache.v)
- **Properties Tested**:
  - Hit/miss detection
  - Line fill
  - Tag matching

#### D-Cache (tb_dcache.v)
- **Properties Tested**:
  - Read hit/miss
  - Write hit/miss
  - Write-back on eviction
  - Byte/halfword/word access

#### LSQ (tb_lsq.v)
- **Test Count**: 12 tests
- **Properties Tested**:
  - Load queue management
  - Store queue management
  - Store-to-load forwarding
  - Memory ordering

### 4. Branch Prediction Tests

#### BPU (tb_bpu.v)
- **Test Count**: 6 tests
- **Properties Tested**:
  - BTB hit/miss
  - TAGE prediction
  - RAS push/pop
  - Update mechanism

### 5. Exception Tests

#### Exception Unit (tb_exception.v)
- **Test Count**: 10 tests
- **Properties Tested**:
  - Exception detection
  - Priority handling
  - CSR updates
  - PC redirection

### 6. Pipeline Control Tests

#### Pipeline Control (tb_pipeline_ctrl.v)
- **Properties Tested**:
  - Stall propagation
  - Flush handling
  - Hazard detection

### 7. Integration Tests

#### Instruction Tests (tb_instr_tests.v)
- **Test Count**: 6 tests
- **Coverage**: End-to-end instruction execution
- **Properties Tested**:
  - Instruction fetch
  - Decode
  - Execute
  - Memory access
  - Writeback

#### OoO Dependency Tests (tb_ooo_deps.v)
- **Test Count**: 6 tests
- **Properties Tested**:
  - RAW hazard handling
  - WAW hazard handling
  - WAR hazard handling
  - Register renaming

## Coverage Metrics

### Line Coverage Target: ≥95%

| Module | Target | Method |
|--------|--------|--------|
| ALU | 100% | Unit tests |
| MUL | 100% | Unit tests |
| DIV | 100% | Unit tests |
| Decoder | 100% | Unit tests |
| ROB | 95% | Unit + integration |
| RS | 95% | Unit + integration |
| Cache | 95% | Unit + integration |
| BPU | 90% | Unit + integration |

### Branch Coverage Target: ≥90%

Focus areas:
- FSM state transitions
- Error handling paths
- Edge cases

### Functional Coverage

#### Instruction Coverage
- All RV32I instructions executed
- All RV32M instructions executed
- All Zicsr instructions executed

#### Pipeline State Coverage
- All pipeline stages active
- Stall conditions
- Flush conditions

#### Exception Coverage
- All exception types triggered
- Nested exceptions
- Exception during branch

## Test Execution

### Running Unit Tests

```bash
# Run all unit tests
make test_all

# Run specific test
make test_alu
make test_mul
make test_div
make test_decoder
make test_branch
make test_bpu
make test_cache
make test_lsq
make test_exception
make test_pipeline_ctrl
make test_ooo_deps
```

### Running Integration Tests

```bash
make test_instr
```

### Running Regression

```bash
make regression
```

## Pass/Fail Criteria

### Unit Tests
- All assertions pass
- No X/Z propagation in outputs
- Expected vs actual match

### Integration Tests
- Correct instruction execution
- Proper exception handling
- Memory consistency

### Compliance Tests
- All riscv-tests pass
- Correct CSR behavior
- Proper privilege handling

## Known Limitations

1. No floating-point support (RV32F/D)
2. No compressed instructions (RV32C)
3. Machine mode only (no S/U modes)
4. No virtual memory (no MMU)

## Test Schedule

| Phase | Duration | Tests |
|-------|----------|-------|
| Unit Testing | Week 1-2 | All unit tests |
| Integration | Week 3 | Integration tests |
| Compliance | Week 4 | riscv-tests |
| Coverage | Week 5 | Coverage analysis |
| Regression | Ongoing | Full regression |

## Defect Tracking

All defects tracked in GitHub Issues with labels:
- `bug`: Functional defect
- `performance`: Performance issue
- `compliance`: RISC-V compliance issue
- `coverage`: Coverage gap
