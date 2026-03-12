# Production Readiness - Remaining Tasks Guide

本文档说明如何完成需要外部工具的生产就绪任务。

## 已完成的任务

所有可在当前环境中完成的任务已完成：
- ✅ Lint 检查和代码质量修复
- ✅ FPGA 综合脚本和时序约束
- ✅ 断言宏库 (rtl/core/assertions.vh)
- ✅ 性能计数器 (rtl/core/perf_counters.v)
- ✅ FPGA 模块 (fpga/rtl/*.v)
- ✅ DFT 支持 (rtl/core/dft_wrapper.v, ecc_unit.v)
- ✅ 时钟门控 (rtl/core/clock_gate.v)
- ✅ CI/CD 自动化 (.github/workflows/ci.yml)
- ✅ 完整文档 (doc/*.md)

## 待完成任务

### 1. 代码覆盖率分析 (需要 Verilator)

```bash
# 安装 Verilator
# Ubuntu: sudo apt install verilator
# macOS: brew install verilator

# 运行覆盖率收集
verilator --coverage --cc --exe --build -Wall \
    -Irtl/common -Irtl \
    rtl/core/*.v rtl/cache/*.v rtl/bpu/*.v rtl/mem/*.v

# 运行测试并收集覆盖率
./obj_dir/Vcpu_core_top

# 生成覆盖率报告
verilator_coverage --annotate coverage_annotate coverage/*.dat
```

### 2. RISC-V 合规性测试 (需要 riscv-tests)

```bash
# 克隆 riscv-tests
git clone https://github.com/riscv/riscv-tests.git
cd riscv-tests
git submodule update --init --recursive

# 安装 RISC-V 工具链
# 参考: https://github.com/riscv-collab/riscv-gnu-toolchain

# 编译测试
./configure --prefix=$RISCV
make

# 运行测试 (需要修改测试框架以适配本 CPU)
# RV32I 测试
./isa/rv32ui-p-*
# RV32M 测试
./isa/rv32um-p-*
```

### 3. 性能基准测试 (需要 RISC-V 工具链)

```bash
# Dhrystone
git clone https://github.com/riscv/riscv-tests.git
cd benchmarks/dhrystone
riscv32-unknown-elf-gcc -O2 -o dhrystone dhrystone.c dhrystone_main.c

# CoreMark
git clone https://github.com/eembc/coremark.git
cd coremark
# 修改 core_portme.h 和 core_portme.c 以适配本 CPU
make PORT_DIR=riscv
```

### 4. FPGA 综合和验证 (需要 Vivado)

```bash
# 打开 Vivado
vivado &

# 或使用批处理模式
cd fpga/synth
vivado -mode batch -source vivado_synth.tcl
vivado -mode batch -source vivado_impl.tcl

# 查看报告
cat output/timing_synth.rpt
cat output/utilization_synth.rpt
```

### 5. 功耗分析 (需要综合工具)

```tcl
# 在 Vivado 中运行功耗分析
# 综合后执行:
report_power -file output/power_report.rpt

# 或使用 Synopsys Design Compiler:
# read_verilog rtl/core/*.v
# compile
# report_power
```

## 验证清单

完成所有任务后，请验证：

- [ ] Verilator 覆盖率 >= 95% 行覆盖率, >= 90% 分支覆盖率
- [ ] 所有 riscv-tests RV32I 测试通过
- [ ] 所有 riscv-tests RV32M 测试通过
- [ ] Dhrystone DMIPS 分数记录
- [ ] CoreMark/MHz 分数记录
- [ ] FPGA 综合成功，时序收敛
- [ ] 功耗报告生成

## 联系方式

如有问题，请参考：
- doc/architecture.md - 架构文档
- doc/synthesis_guide.md - 综合指南
- doc/verification_plan.md - 验证计划
