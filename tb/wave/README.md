# Wave Tests - 精简波形测试套件

## 概述

本目录包含针对RISC-V OoO CPU各模块的精简波形测试。每个测试设计为：
- **周期数**: 15-30个周期（便于GTKWave分析）
- **覆盖面**: 覆盖模块的核心功能
- **预配置**: 每个测试都有对应的`.gtkw`文件，信号已分组配置好

## 测试文件列表

| 模块 | 测试文件 | GTKWave配置 | 周期数 | 覆盖内容 |
|------|----------|-------------|--------|----------|
| ALU | tb_alu_wave.v | alu.gtkw | ~15 | 12种ALU操作 |
| MUL | tb_mul_wave.v | mul.gtkw | ~20 | 4种乘法操作 |
| DIV | tb_div_wave.v | div.gtkw | ~150 | 4种除法+除零 |
| Decoder | tb_decoder_wave.v | decoder.gtkw | ~20 | 12种指令类型 |
| Branch | tb_branch_wave.v | branch.gtkw | ~15 | 6种分支+JAL/JALR |
| RAT | tb_rat_wave.v | rat.gtkw | ~25 | 重命名/CDB/检查点 |
| ROB | tb_rob_wave.v | rob.gtkw | ~30 | 分配/完成/提交 |
| RS | tb_rs_wave.v | rs.gtkw | ~25 | 分配/唤醒/发射 |
| BPU | tb_bpu_wave.v | bpu.gtkw | ~25 | 预测/更新/恢复 |
| LSQ | tb_lsq_wave.v | lsq.gtkw | ~30 | Load/Store/转发 |
| Pipeline | tb_pipeline_wave.v | pipeline.gtkw | ~20 | Stall/Flush/重定向 |
| Exception | tb_exception_wave.v | exception.gtkw | ~20 | 各种异常类型 |
| CSR | tb_csr_wave.v | csr.gtkw | ~25 | CSR读写/异常处理 |
| CDB | tb_cdb_wave.v | cdb.gtkw | ~15 | 优先级仲裁 |
| AGU | tb_agu_wave.v | agu.gtkw | ~15 | 地址计算/对齐检测 |

## 使用方法

### 运行单个测试
```bash
make wave_alu      # 运行ALU波形测试
make wave_decoder  # 运行Decoder波形测试
# ... 其他模块类似
```

### 运行所有波形测试
```bash
make wave_all
```

### 查看波形
```bash
# 运行测试后，使用GTKWave打开波形
gtkwave sim/waves/alu_wave.vcd tb/wave/alu.gtkw
```

GTKWave配置文件已预设好：
- 信号分组显示
- 合适的时间缩放
- 关键信号高亮

## 波形文件位置

- VCD波形文件: `sim/waves/<module>_wave.vcd`
- GTKWave配置: `tb/wave/<module>.gtkw`
- 测试日志: 直接输出到终端

## 测试覆盖说明

### 执行单元
- **ALU**: ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU/LUI/AUIPC
- **MUL**: MUL/MULH/MULHSU/MULHU (3周期流水线)
- **DIV**: DIV/DIVU/REM/REMU + 除零处理
- **Branch**: BEQ/BNE/BLT/BGE/BLTU/BGEU/JAL/JALR
- **AGU**: 地址计算、字节/半字/字对齐检测

### 前端
- **Decoder**: R/I/S/B/U/J型指令、M扩展、非法指令检测
- **BPU**: TAGE预测、BTB、RAS、GHR管理、检查点恢复

### OoO核心
- **RAT**: 寄存器重命名、CDB广播、检查点创建/恢复
- **ROB**: 指令分配、完成标记、顺序提交
- **RS**: 操作数捕获、CDB唤醒、最老优先发射
- **CDB**: 6源固定优先级仲裁

### 存储系统
- **LSQ**: Load/Store分配、地址计算、Store-to-Load转发

### 控制
- **Pipeline**: 资源满stall、cache miss stall、分支误预测flush
- **Exception**: 异常优先级、MRET、重定向
- **CSR**: CSRRW/CSRRS/CSRRC、异常处理、中断

## 与原有测试的区别

| 特性 | 原有测试 | Wave测试 |
|------|----------|----------|
| 测试用例数 | 数千个 | 5-15个 |
| 周期数 | 数百-数千 | 15-30 |
| 波形分析 | 困难 | 容易 |
| GTKWave配置 | 无 | 预配置 |
| 用途 | 回归测试 | 调试/学习 |
