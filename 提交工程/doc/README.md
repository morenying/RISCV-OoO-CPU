# RISC-V Out-of-Order CPU Documentation

本目录包含 RISC-V RV32IM 乱序执行 CPU 的完整文档。

## 文档索引

| 文档 | 描述 | 目标读者 |
|------|------|----------|
| [architecture.md](architecture.md) | 整体架构设计，流水线结构，模块框图 | 架构师、设计工程师 |
| [module_interfaces.md](module_interfaces.md) | 所有模块的接口定义和信号描述 | RTL 工程师 |
| [programmer_reference.md](programmer_reference.md) | 指令集、CSR、编程模型 | 软件工程师 |
| [verification_plan.md](verification_plan.md) | 验证策略、测试用例、覆盖率目标 | 验证工程师 |
| [synthesis_guide.md](synthesis_guide.md) | FPGA/ASIC 综合流程和约束 | 后端工程师 |

## 快速开始

1. **了解架构**: 阅读 `architecture.md` 了解 CPU 整体设计
2. **模块接口**: 查阅 `module_interfaces.md` 了解各模块信号
3. **软件开发**: 参考 `programmer_reference.md` 编写测试程序
4. **验证测试**: 按照 `verification_plan.md` 运行测试
5. **综合实现**: 遵循 `synthesis_guide.md` 进行 FPGA 综合

## 设计特性

- 7 级流水线: IF → ID → RN → IS → EX → MEM → WB
- 乱序执行: ROB + 保留站 + 寄存器重命名
- 分支预测: TAGE + BTB + RAS + 循环预测器
- 缓存系统: 4KB I-Cache + 4KB D-Cache (2-way)
- 内存系统: Load/Store Queue + Store-to-Load Forwarding

## 版本信息

- RTL 版本: 1.0
- 文档版本: 1.0
- 最后更新: 2025-01-01
