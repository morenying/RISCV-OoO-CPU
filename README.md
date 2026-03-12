# RISC-V 乱序执行 CPU (RV32IM + Zicsr)

> 基于 Verilog 实现的 RISC-V 超标量乱序执行处理器，采用 7 级流水线 + ROB + 保留站 + 寄存器重命名架构，支持 RV32IM 指令集与 Zicsr 扩展。

## 架构概览

```
┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
│  IF  │─▶│  ID  │─▶│  RN  │─▶│  IS  │─▶│  EX  │─▶│ MEM  │─▶│  WB  │
│ 取指 │  │ 译码 │  │ 重命名│  │ 发射 │  │ 执行 │  │ 访存 │  │ 写回 │
└──────┘  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘  └──────┘
                        │          │         │
                      ┌─┴──────────┴─────────┴─┐
                      │    ROB (重排序缓冲)      │
                      │    RAT (寄存器别名表)    │
                      │    PRF (物理寄存器文件)  │
                      │    RS  (保留站)         │
                      └─────────────────────────┘
```

### 核心设计特性

| 特性 | 说明 |
|------|------|
| **流水线** | 7 级：IF → ID → RN → IS → EX → MEM → WB |
| **指令集** | RV32IM + Zicsr 扩展 |
| **乱序执行** | ROB + 保留站 + 寄存器重命名（Tomasulo 算法） |
| **分支预测** | TAGE 预测器 + BTB + RAS + 循环预测器 |
| **缓存** | 4KB I-Cache + 4KB D-Cache（2-way 组相联） |
| **内存系统** | LSQ + Store-to-Load 转发 |
| **CSR** | Zicsr 扩展，支持 CSR 读写指令 |
| **异常处理** | 精确异常，通过 ROB 顺序提交 |
| **FPGA** | Xilinx Artix-7 综合验证通过 |

## 项目结构

```
.
├── rtl/                        # RTL 设计文件（46+ 个模块）
│   ├── common/                     # 公共宏定义 (cpu_defines.vh)
│   ├── core/                       # CPU 核心
│   │   ├── if_stage.v                  # 取指阶段
│   │   ├── id_stage.v                  # 译码阶段
│   │   ├── rn_stage.v                  # 寄存器重命名阶段
│   │   ├── is_stage.v                  # 发射阶段
│   │   ├── ex_stage.v                  # 执行阶段
│   │   ├── mem_stage.v                 # 访存阶段
│   │   ├── wb_stage.v                  # 写回阶段
│   │   ├── rob.v                       # 重排序缓冲 (ROB)
│   │   ├── rat.v                       # 寄存器别名表 (RAT)
│   │   ├── prf.v                       # 物理寄存器文件 (PRF)
│   │   ├── reservation_station.v       # 保留站
│   │   └── ...
│   ├── cache/                      # I-Cache / D-Cache
│   ├── bpu/                        # 分支预测单元
│   │   ├── tage_predictor.v            # TAGE 预测器
│   │   ├── btb.v                       # 分支目标缓冲
│   │   ├── ras.v                       # 返回地址栈
│   │   └── loop_predictor.v            # 循环预测器
│   ├── mem/                        # 内存子系统 / LSQ
│   ├── mmu/                        # 内存管理单元
│   ├── bus/                        # 总线接口
│   ├── periph/                     # 外设接口
│   └── system/                     # 系统级集成
├── tb/                         # 完整验证框架
│   ├── unit/                       # 单元测试
│   ├── integration/                # 集成测试
│   ├── system/                     # 系统级测试
│   ├── property/                   # 属性验证
│   ├── perf/                       # 性能基准测试
│   ├── models/                     # 参考模型
│   └── verilator/                  # Verilator 配置
├── doc/                        # 完整技术文档
│   ├── architecture.md             # 整体架构设计
│   ├── module_interfaces.md        # 模块接口规范
│   ├── programmer_reference.md     # 编程参考手册
│   ├── verification_plan.md        # 验证计划
│   ├── synthesis_guide.md          # 综合指南
│   └── simulation_guide.md         # 仿真指南
├── fpga/                       # FPGA 约束与实现
├── scripts/                    # 构建与自动化脚本
├── sw/                         # 软件测试程序
├── .github/workflows/ci.yml   # CI/CD 自动化
├── Makefile                    # 构建系统
└── README.md
```

## 快速开始

### 环境要求

- [Icarus Verilog](http://iverilog.icarus.com/) — RTL 仿真
- [Verilator](https://www.veripool.org/verilator/) — 高速仿真与 Lint
- [GTKWave](http://gtkwave.sourceforge.net/) — 波形查看
- [Yosys](https://yosyshq.net/yosys/) — 综合（可选）

### 编译与仿真

```bash
# 使用 Makefile
make test_alu          # 运行 ALU 单元测试
make test_mul          # 运行乘法器测试
make test_div          # 运行除法器测试
make test_branch       # 运行分支测试
make test_all          # 运行全部测试
make wave              # 生成波形文件

# 使用 Verilator
make verilate          # Verilator 编译
make sim               # 运行仿真

# Lint 检查
make lint              # Verilator lint
```

## 验证体系

```
12,000+ 测试用例，100% 通过
```

| 测试类别 | 用例数 | 通过率 |
|---------|--------|--------|
| ALU 运算 | 12,007 | 100% |
| 乘法器 (MUL) | 104 | 100% |
| 除法器 (DIV) | 105 | 100% |
| 分支指令 (Branch) | 361 | 100% |
| 集成测试 | 多组 | 100% |

### CI/CD 流水线

项目配置了 GitHub Actions 自动化 CI：

- **Lint**: Verilator -Wall 级别检查
- **单元测试**: 11 项模块测试（ALU、MUL、DIV、Decoder、Branch、BPU、Cache、LSQ、Exception、Pipeline Control、OoO Dependency）
- **集成测试**: 完整指令集测试
- **综合检查**: Yosys 综合验证

## 技术栈

- **HDL**: Verilog
- **仿真**: Icarus Verilog / Verilator
- **综合**: Xilinx Vivado (Artix-7) / Yosys
- **CI/CD**: GitHub Actions
- **波形**: GTKWave

## 作者

**莫仁鹰** — 合肥工业大学 计算机科学与技术

系统硬件综合设计课程项目 · 扩展阶段（2025-2026）
