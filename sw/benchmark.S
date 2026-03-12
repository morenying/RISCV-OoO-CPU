#=================================================================
# RISC-V Performance Benchmark
# Tests: ALU throughput, Branch prediction, Memory bandwidth
# Target: Measure IPC under various workloads
#=================================================================

.section .text
.global _start

#-----------------------------------------------------------------
# Constants
#-----------------------------------------------------------------
.equ TOHOST,      0x10000000    # Test completion address
.equ DATA_BASE,   0x80010000    # Data area base
.equ LOOP_COUNT,  1000          # Iterations for each test

#-----------------------------------------------------------------
# Entry Point
#-----------------------------------------------------------------
_start:
    # Initialize stack pointer
    li      sp, 0x80020000
    
    # Run all benchmarks
    jal     ra, bench_alu_throughput
    jal     ra, bench_branch_prediction
    jal     ra, bench_memory_bandwidth
    jal     ra, bench_dependency_chain
    jal     ra, bench_mixed_workload
    
    # Signal success
    li      t0, TOHOST
    li      t1, 1
    sw      t1, 0(t0)
    
    # Infinite loop
1:  j       1b

#-----------------------------------------------------------------
# Benchmark 1: ALU Throughput
# Tests: Maximum ALU operations per cycle
# Expected IPC: ~2.0 (2 ALUs)
#-----------------------------------------------------------------
bench_alu_throughput:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    
    li      t0, LOOP_COUNT
    li      a0, 0
    li      a1, 1
    li      a2, 2
    li      a3, 3
    li      a4, 4
    li      a5, 5

alu_loop:
    # Independent ALU operations (can execute in parallel)
    add     a0, a0, a1      # ALU0
    add     a2, a2, a3      # ALU1
    sub     a4, a4, a5      # ALU0
    xor     a1, a1, a0      # ALU1
    or      a3, a3, a2      # ALU0
    and     a5, a5, a4      # ALU1
    sll     a0, a0, a1      # ALU0
    srl     a2, a2, a3      # ALU1
    
    addi    t0, t0, -1
    bnez    t0, alu_loop
    
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

#-----------------------------------------------------------------
# Benchmark 2: Branch Prediction
# Tests: Predictable loop, alternating pattern, random-ish
# Expected accuracy: >97%
#-----------------------------------------------------------------
bench_branch_prediction:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    
    # Test 2a: Simple counted loop (very predictable)
    li      t0, LOOP_COUNT
    li      a0, 0
loop_simple:
    addi    a0, a0, 1
    addi    t0, t0, -1
    bnez    t0, loop_simple
    
    # Test 2b: Nested loop (tests loop predictor)
    li      t0, 100         # Outer loop
outer_loop:
    li      t1, 10          # Inner loop
inner_loop:
    addi    a0, a0, 1
    addi    t1, t1, -1
    bnez    t1, inner_loop
    addi    t0, t0, -1
    bnez    t0, outer_loop
    
    # Test 2c: Alternating branch (TNTNTN pattern)
    li      t0, LOOP_COUNT
    li      t2, 0
alt_loop:
    andi    t3, t2, 1
    beqz    t3, alt_taken
    addi    a0, a0, 1
    j       alt_next
alt_taken:
    addi    a0, a0, 2
alt_next:
    addi    t2, t2, 1
    addi    t0, t0, -1
    bnez    t0, alt_loop
    
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

#-----------------------------------------------------------------
# Benchmark 3: Memory Bandwidth
# Tests: Sequential load/store, stride access
# Expected: ~1 IPC (memory bound)
#-----------------------------------------------------------------
bench_memory_bandwidth:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    
    li      t0, DATA_BASE
    li      t1, 256         # Array size (words)
    
    # Initialize array
    li      t2, 0
init_loop:
    sw      t2, 0(t0)
    addi    t0, t0, 4
    addi    t2, t2, 1
    blt     t2, t1, init_loop
    
    # Sequential read
    li      t0, DATA_BASE
    li      t1, 256
    li      a0, 0
read_loop:
    lw      t2, 0(t0)
    add     a0, a0, t2
    addi    t0, t0, 4
    addi    t1, t1, -1
    bnez    t1, read_loop
    
    # Sequential write
    li      t0, DATA_BASE
    li      t1, 256
write_loop:
    sw      a0, 0(t0)
    addi    a0, a0, 1
    addi    t0, t0, 4
    addi    t1, t1, -1
    bnez    t1, write_loop
    
    # Load-store forwarding test
    li      t0, DATA_BASE
    li      t1, 256
forward_loop:
    lw      t2, 0(t0)
    addi    t2, t2, 1
    sw      t2, 0(t0)
    addi    t0, t0, 4
    addi    t1, t1, -1
    bnez    t1, forward_loop
    
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

#-----------------------------------------------------------------
# Benchmark 4: Dependency Chain
# Tests: Long RAW dependency chains
# Expected IPC: ~1.0 (serialized by dependencies)
#-----------------------------------------------------------------
bench_dependency_chain:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    
    li      t0, LOOP_COUNT
    li      a0, 1
    
dep_loop:
    # Long dependency chain - cannot parallelize
    add     a0, a0, a0      # a0 depends on prev
    add     a0, a0, a0      # a0 depends on prev
    add     a0, a0, a0      # a0 depends on prev
    add     a0, a0, a0      # a0 depends on prev
    addi    a0, a0, 1       # Reset to prevent overflow
    andi    a0, a0, 0xFF    
    
    addi    t0, t0, -1
    bnez    t0, dep_loop
    
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

#-----------------------------------------------------------------
# Benchmark 5: Mixed Workload (CoreMark-like)
# Tests: Realistic mix of operations
# Target IPC: 1.5+
#-----------------------------------------------------------------
bench_mixed_workload:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    
    li      t0, 100         # Outer iterations
    li      s0, DATA_BASE   # Data pointer
    li      s1, 0           # Checksum
    
mixed_outer:
    li      t1, 10          # Inner iterations
    
mixed_inner:
    # Load data
    lw      a0, 0(s0)
    lw      a1, 4(s0)
    
    # Compute
    add     a2, a0, a1
    sub     a3, a0, a1
    xor     a4, a2, a3
    sll     a5, a4, 2
    srl     a6, a4, 2
    or      a7, a5, a6
    
    # Conditional
    bge     a0, a1, mixed_ge
    add     s1, s1, a2
    j       mixed_cont
mixed_ge:
    add     s1, s1, a3
mixed_cont:
    
    # Store result
    sw      a7, 8(s0)
    
    # Multiply (if available)
    mul     t2, a0, a1
    add     s1, s1, t2
    
    # Advance pointer
    addi    s0, s0, 12
    andi    s0, s0, 0xFFF   # Wrap around
    addi    s0, s0, DATA_BASE
    
    addi    t1, t1, -1
    bnez    t1, mixed_inner
    
    addi    t0, t0, -1
    bnez    t0, mixed_outer
    
    # Store final checksum
    sw      s1, 0(s0)
    
    lw      s2, 16(sp)
    lw      s1, 20(sp)
    lw      s0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    ret

#-----------------------------------------------------------------
# Data Section
#-----------------------------------------------------------------
.section .data
.align 4
test_data:
    .word 0x12345678
    .word 0x9ABCDEF0
    .word 0x55AA55AA
    .word 0xDEADBEEF
