# CPI Performance Benchmarks

## 概述

本目录包含 RISC-V OoO CPU 的性能测量 testbench。

## 文件说明

### 1. tb_cpi_benchmark.v (概念演示)
- **类型**: 硬编码模拟
- **用途**: 展示各种微架构优化的理论效果
- **特点**: 
  - 没有实例化真实 CPU 核心
  - 惩罚值是硬编码的 (cache miss +10, 分支错误 +4)
  - 数据是确定性的，用于教学演示

### 2. tb_cpi_nocache.v (IF Stage 测试)
- **类型**: 真实硬件测试
- **用途**: 测量 IF stage 的取指性能
- **特点**:
  - 实例化真实的 if_stage 模块
  - 使用简单的 1-cycle 内存模型
  - 测量真实的取指 CPI

### 3. tb_cpi_pipeline.v (IF+ID 流水线测试)
- **类型**: 真实硬件测试
- **用途**: 测量 IF+ID 流水线性能
- **特点**:
  - 实例化 if_stage 和 id_stage
  - 测量取指和译码的 CPI

## 运行方法

```bash
# 概念演示 (硬编码数据)
iverilog -g2001 -Irtl/common -o sim/cpi_benchmark.vvp rtl/common/cpu_defines.vh tb/perf/tb_cpi_benchmark.v
vvp sim/cpi_benchmark.vvp

# IF Stage 真实测试
iverilog -g2001 -Irtl/common -Irtl -o sim/cpi_nocache.vvp rtl/common/cpu_defines.vh rtl/core/if_stage.v tb/perf/tb_cpi_nocache.v
vvp sim/cpi_nocache.vvp

# IF+ID 流水线测试
iverilog -g2001 -Irtl/common -Irtl -o sim/cpi_pipeline.vvp rtl/common/cpu_defines.vh rtl/core/if_stage.v rtl/core/id_stage.v rtl/core/decoder.v rtl/core/imm_gen.v tb/perf/tb_cpi_pipeline.v
vvp sim/cpi_pipeline.vvp
```

## 测试结果示例

### IF Stage (tb_cpi_nocache.v)
```
Test 1: ALU Sequence (11 instructions)
  Cycles: 55, Instructions: 13, CPI: 4.231
```

### IF+ID Pipeline (tb_cpi_pipeline.v)
```
Test 1: Independent ALU (11 instr)
  Cycles: 56, Fetched: 13, Decoded: 13
  Fetch CPI: 4.308, Decode CPI: 4.308
```

## CPI 分析

### IF Stage CPI ≈ 4 的原因
IF stage 状态机需要 4 个周期完成一次取指:
1. IDLE: 准备发送请求
2. FETCH: 发送取指请求
3. WAIT: 等待内存响应
4. (返回 IDLE): 更新 PC，输出指令

### 完整 CPU 核心测试的限制
当前 `cpu_core_top` 的 AXI 接口存在问题:
- I-Cache 的 `mem_req_valid_o` 没有连接到 AXI 总线
- `m_axi_ibus_arvalid` 被硬编码为 0

要进行完整的 CPU 核心 CPI 测试，需要:
1. 修复 cpu_core_top 的 AXI 接口连接
2. 或者绕过 cache，直接连接 IF stage 到内存

## 性能计数器

CPU 核心包含 `perf_counters` 模块，可以收集:
- mcycle: 周期计数
- minstret: 指令退休计数
- 分支预测统计
- Cache 命中/未命中统计
- 流水线 stall 统计
