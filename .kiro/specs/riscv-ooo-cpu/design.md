# Design Document: RISC-V Out-of-Order CPU

## Overview

本设计文档描述了一款基于RISC-V RV32IM架构的高性能乱序执行处理器。该处理器采用七级流水线设计，实现了完整的动态调度、寄存器重命名、TAGE分支预测和精确异常处理机制。

### 设计目标
- 支持完整的RV32IM + Zicsr指令集（51条指令）
- 七级流水线：IF → ID → RN → IS → EX → MEM → WB
- 基于Tomasulo算法的乱序执行
- TAGE高精度分支预测
- 4KB I-Cache + 4KB D-Cache
- 精确异常和中断处理
- AXI4-Lite总线接口
- 可综合的Verilog 2001代码

### 顶层架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CPU_Core Top                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐                      │
│  │   BPU   │──▶│   IF    │──▶│   ID    │──▶│   RN    │                      │
│  │  (TAGE) │   │ Stage   │   │ Stage   │   │ Stage   │                      │
│  └────┬────┘   └────┬────┘   └─────────┘   └────┬────┘                      │
│       │             │                           │                            │
│       │        ┌────┴────┐                 ┌────┴────┐                       │
│       │        │ I-Cache │                 │   RAT   │                       │
│       │        └─────────┘                 │   PRF   │                       │
│       │                                    └────┬────┘                       │
│       │                                         │                            │
│       │   ┌─────────────────────────────────────┴──────────────────────┐    │
│       │   │                    IS Stage                                 │    │
│       │   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │    │
│       │   │  │  ALU RS  │  │  MUL RS  │  │  LSU RS  │  │  BR RS   │   │    │
│       │   │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │    │
│       │   └───────┼─────────────┼─────────────┼─────────────┼─────────┘    │
│       │           │             │             │             │              │
│       │   ┌───────┴─────────────┴─────────────┴─────────────┴───────┐     │
│       │   │                    EX Stage                              │     │
│       │   │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       │     │
│       └───┼──│ALU0 │ │ALU1 │ │ MUL │ │ DIV │ │ AGU │ │ BRU │       │     │
│           │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘       │     │
│           │     └───────┴───────┴───────┴───────┴───────┴───────────┘     │
│           │                          │                                     │
│           │                    ┌─────┴─────┐                               │
│           │                    │    CDB    │                               │
│           │                    └─────┬─────┘                               │
│           │                          │                                     │
│           │   ┌──────────────────────┴──────────────────────┐              │
│           │   │                 MEM Stage                    │              │
│           │   │  ┌─────────┐  ┌─────────┐  ┌─────────┐      │              │
│           │   │  │   LSQ   │──│ D-Cache │──│  Store  │      │              │
│           │   │  │ (LQ+SQ) │  │         │  │ Buffer  │      │              │
│           │   │  └─────────┘  └────┬────┘  └─────────┘      │              │
│           │   └────────────────────┼────────────────────────┘              │
│           │                        │                                       │
│           │   ┌────────────────────┴────────────────────────┐              │
│           │   │                 WB Stage                     │              │
│           │   │  ┌─────────────────────────────────────┐    │              │
│           │   │  │              ROB                     │    │              │
│           │   │  │  (Reorder Buffer - 32 entries)      │    │              │
│           │   │  └─────────────────────────────────────┘    │              │
│           │   └─────────────────────────────────────────────┘              │
│           │                                                                │
│  ┌────────┴────────┐                              ┌─────────────────────┐  │
│  │   CSR Unit      │                              │   Exception Unit    │  │
│  └─────────────────┘                              └─────────────────────┘  │
├─────────────────────────────────────────────────────────────────────────────┤
│                         AXI4-Lite Bus Interface                             │
│  ┌─────────────────────────┐        ┌─────────────────────────┐            │
│  │   I-Bus Master (AXI)    │        │   D-Bus Master (AXI)    │            │
│  └─────────────────────────┘        └─────────────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Architecture

### 模块层次结构

```
cpu_core_top
├── if_stage                    // 指令获取阶段
│   ├── pc_register            // PC寄存器
│   ├── icache                 // 指令缓存
│   └── bpu                    // 分支预测单元
│       ├── tage_predictor     // TAGE预测器
│       ├── btb                // 分支目标缓冲
│       ├── ras                // 返回地址栈
│       └── loop_predictor     // 循环预测器
├── id_stage                    // 指令解码阶段
│   ├── decoder                // 指令解码器
│   └── imm_gen                // 立即数生成器
├── rn_stage                    // 寄存器重命名阶段
│   ├── rat                    // 寄存器别名表
│   ├── free_list              // 空闲物理寄存器列表
│   └── rat_checkpoint         // RAT检查点
├── is_stage                    // 指令调度阶段
│   ├── reservation_station    // 保留站
│   │   ├── alu_rs            // ALU保留站
│   │   ├── mul_rs            // 乘法保留站
│   │   ├── lsu_rs            // 访存保留站
│   │   └── br_rs             // 分支保留站
│   ├── issue_queue            // 发射队列
│   └── rob                    // 重排序缓冲区
├── ex_stage                    // 执行阶段
│   ├── alu_unit (x2)          // ALU单元
│   ├── mul_unit               // 乘法单元
│   ├── div_unit               // 除法单元
│   ├── branch_unit            // 分支单元
│   └── agu_unit               // 地址生成单元
├── mem_stage                   // 内存访问阶段
│   ├── dcache                 // 数据缓存
│   ├── load_queue             // Load队列
│   └── store_queue            // Store队列
├── wb_stage                    // 写回/提交阶段
│   ├── commit_logic           // 提交逻辑
│   └── arf                    // 架构寄存器文件
├── cdb                         // 公共数据总线
├── csr_unit                    // CSR单元
├── exception_unit              // 异常处理单元
└── axi_interface               // AXI总线接口
    ├── axi_master_ibus        // 指令总线主接口
    └── axi_master_dbus        // 数据总线主接口
```

## Components and Interfaces

### 1. IF Stage (指令获取阶段)

#### 1.1 PC Register Module

```verilog
module pc_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,           // 流水线停顿
    input  wire        flush,           // 流水线冲刷
    input  wire        branch_taken,    // 分支跳转
    input  wire [31:0] branch_target,   // 分支目标地址
    input  wire        exception,       // 异常发生
    input  wire [31:0] exception_pc,    // 异常处理地址
    output reg  [31:0] pc,              // 当前PC
    output wire [31:0] pc_next          // 下一PC
);
```

**功能描述**：
- 维护当前程序计数器
- 支持顺序执行（PC+4）
- 支持分支跳转（来自BPU预测或EX阶段解析）
- 支持异常跳转（跳转到mtvec）

#### 1.2 I-Cache Module

```verilog
module icache #(
    parameter CACHE_SIZE   = 4096,      // 4KB
    parameter LINE_SIZE    = 32,        // 32字节行
    parameter ADDR_WIDTH   = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // CPU接口
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire                  req,
    output wire [31:0]           rdata,
    output wire                  hit,
    output wire                  ready,
    // 内存接口
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire                  mem_req,
    input  wire [255:0]          mem_rdata,  // 32字节 = 256位
    input  wire                  mem_valid,
    // 控制
    input  wire                  invalidate   // FENCE.I
);
```

**Cache组织**：
- 容量：4KB
- 行大小：32字节（8条指令）
- 组织：直接映射
- 索引位：[11:5]（128行）
- 标签位：[31:12]
- 块内偏移：[4:0]

#### 1.3 TAGE Branch Predictor

```verilog
module tage_predictor #(
    parameter GHR_WIDTH     = 64,       // 全局历史长度
    parameter BIMODAL_SIZE  = 2048,     // 基础预测器大小
    parameter TAGGED_SIZE   = 256,      // 每个标签表大小
    parameter NUM_TAGGED    = 4         // 标签表数量
) (
    input  wire        clk,
    input  wire        rst_n,
    // 预测接口
    input  wire [31:0] pc,
    output wire        pred_taken,
    output wire [31:0] pred_target,
    output wire        pred_valid,
    // 更新接口
    input  wire        update_valid,
    input  wire [31:0] update_pc,
    input  wire        update_taken,
    input  wire        update_mispredict,
    input  wire [GHR_WIDTH-1:0] update_ghr,
    // GHR管理
    output wire [GHR_WIDTH-1:0] ghr,
    input  wire        ghr_restore,
    input  wire [GHR_WIDTH-1:0] ghr_restore_val
);
```

**TAGE结构**：
```
                    ┌─────────────────────────────────────────┐
                    │              TAGE Predictor              │
                    ├─────────────────────────────────────────┤
     PC ───────────▶│  ┌─────────────────────────────────┐   │
                    │  │     Bimodal Base Predictor      │   │
     GHR[63:0] ────▶│  │     (2048 x 2-bit counters)     │   │
                    │  └─────────────────────────────────┘   │
                    │                  │                      │
                    │  ┌───────────────┼───────────────┐     │
                    │  │               ▼               │     │
                    │  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │
                    │  │  │ T1  │ │ T2  │ │ T3  │ │ T4  │   │
                    │  │  │H=8  │ │H=16 │ │H=32 │ │H=64 │   │
                    │  │  │256  │ │256  │ │256  │ │256  │   │
                    │  │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘   │
                    │  │     │       │       │       │      │
                    │  │     ▼       ▼       ▼       ▼      │
                    │  │  ┌─────────────────────────────┐   │
                    │  │  │      Tag Match Logic        │   │
                    │  │  └─────────────────────────────┘   │
                    │  │               │                    │
                    │  │               ▼                    │
                    │  │  ┌─────────────────────────────┐   │
                    │  │  │   Provider Selection MUX    │   │
                    │  │  └─────────────────────────────┘   │
                    │  └───────────────┼───────────────┘    │
                    │                  ▼                     │
                    │           pred_taken                   │
                    └─────────────────────────────────────────┘
```

**标签表项结构**：
```
┌─────────────────────────────────────────────────┐
│              Tagged Table Entry                  │
├──────────┬──────────┬──────────┬────────────────┤
│  Tag     │  Pred    │  Useful  │   Reserved     │
│ (10-bit) │ (3-bit)  │ (2-bit)  │                │
└──────────┴──────────┴──────────┴────────────────┘
```

#### 1.4 BTB (Branch Target Buffer)

```verilog
module btb #(
    parameter NUM_ENTRIES = 512,
    parameter NUM_WAYS    = 2
) (
    input  wire        clk,
    input  wire        rst_n,
    // 查询接口
    input  wire [31:0] pc,
    output wire        hit,
    output wire [31:0] target,
    output wire [1:0]  branch_type,  // 00:cond, 01:uncond, 10:call, 11:ret
    // 更新接口
    input  wire        update_valid,
    input  wire [31:0] update_pc,
    input  wire [31:0] update_target,
    input  wire [1:0]  update_type
);
```

#### 1.5 RAS (Return Address Stack)

```verilog
module ras #(
    parameter DEPTH = 16
) (
    input  wire        clk,
    input  wire        rst_n,
    // 操作接口
    input  wire        push,
    input  wire        pop,
    input  wire [31:0] push_addr,
    output wire [31:0] pop_addr,
    output wire        empty,
    // 检查点恢复
    input  wire        checkpoint,
    input  wire        restore,
    input  wire [3:0]  restore_ptr
);
```

#### 1.6 Loop Predictor

```verilog
module loop_predictor #(
    parameter NUM_ENTRIES = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] pc,
    output wire        loop_pred_valid,
    output wire        loop_pred_taken,
    input  wire        update_valid,
    input  wire [31:0] update_pc,
    input  wire        update_taken
);
```

### 2. ID Stage (指令解码阶段)

#### 2.1 Decoder Module

```verilog
module decoder (
    input  wire [31:0] instr,
    input  wire [31:0] pc,
    // 解码输出
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [31:0] imm,
    output wire [6:0]  opcode,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    // 控制信号
    output wire        reg_write,
    output wire        mem_read,
    output wire        mem_write,
    output wire        branch,
    output wire        jump,
    output wire [3:0]  alu_op,
    output wire [1:0]  alu_src,
    output wire        csr_op,
    output wire [2:0]  csr_type,
    // 异常
    output wire        illegal_instr
);
```

**指令格式解码**：
```
R-type: [funct7][rs2][rs1][funct3][rd][opcode]
I-type: [imm[11:0]][rs1][funct3][rd][opcode]
S-type: [imm[11:5]][rs2][rs1][funct3][imm[4:0]][opcode]
B-type: [imm[12|10:5]][rs2][rs1][funct3][imm[4:1|11]][opcode]
U-type: [imm[31:12]][rd][opcode]
J-type: [imm[20|10:1|11|19:12]][rd][opcode]
```

**支持的指令编码**：

| 指令类型 | Opcode | 指令列表 |
|---------|--------|---------|
| R-type ALU | 0110011 | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| I-type ALU | 0010011 | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Load | 0000011 | LB, LH, LW, LBU, LHU |
| Store | 0100011 | SB, SH, SW |
| Branch | 1100011 | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| JAL | 1101111 | JAL |
| JALR | 1100111 | JALR |
| LUI | 0110111 | LUI |
| AUIPC | 0010111 | AUIPC |
| M-ext | 0110011 | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| System | 1110011 | ECALL, EBREAK, CSRxx |
| FENCE | 0001111 | FENCE, FENCE.I |

### 3. RN Stage (寄存器重命名阶段)

#### 3.1 RAT (Register Alias Table)

```verilog
module rat #(
    parameter NUM_ARCH_REGS = 32,
    parameter NUM_PHYS_REGS = 64,
    parameter PHYS_REG_BITS = 6
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // 读取映射
    input  wire [4:0]              rs1,
    input  wire [4:0]              rs2,
    output wire [PHYS_REG_BITS-1:0] prs1,
    output wire [PHYS_REG_BITS-1:0] prs2,
    output wire                    prs1_ready,
    output wire                    prs2_ready,
    // 写入映射
    input  wire                    rename_valid,
    input  wire [4:0]              rd,
    input  wire [PHYS_REG_BITS-1:0] prd_new,
    output wire [PHYS_REG_BITS-1:0] prd_old,
    // 检查点
    input  wire                    checkpoint,
    input  wire [4:0]              checkpoint_id,
    input  wire                    restore,
    input  wire [4:0]              restore_id,
    // 提交
    input  wire                    commit_valid,
    input  wire [4:0]              commit_rd,
    input  wire [PHYS_REG_BITS-1:0] commit_prd
);
```

**RAT结构**：
```
┌─────────────────────────────────────────────────────────────┐
│                    Register Alias Table                      │
├─────────────────────────────────────────────────────────────┤
│  Arch Reg │ Phys Reg │ Ready │     Checkpoint Storage       │
│    (x0)   │   P0     │   1   │  [CP0][CP1][CP2]...[CP7]    │
│    (x1)   │   P5     │   1   │  [CP0][CP1][CP2]...[CP7]    │
│    (x2)   │   P12    │   0   │  [CP0][CP1][CP2]...[CP7]    │
│    ...    │   ...    │  ...  │           ...                │
│   (x31)   │   P47    │   1   │  [CP0][CP1][CP2]...[CP7]    │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2 Free List

```verilog
module free_list #(
    parameter NUM_PHYS_REGS = 64,
    parameter PHYS_REG_BITS = 6
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // 分配
    input  wire                    alloc_req,
    output wire [PHYS_REG_BITS-1:0] alloc_preg,
    output wire                    alloc_valid,
    // 释放
    input  wire                    free_req,
    input  wire [PHYS_REG_BITS-1:0] free_preg,
    // 状态
    output wire                    empty,
    output wire [5:0]              count
);
```

#### 3.3 Physical Register File

```verilog
module prf #(
    parameter NUM_REGS     = 64,
    parameter DATA_WIDTH   = 32,
    parameter NUM_RD_PORTS = 4,
    parameter NUM_WR_PORTS = 2
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // 读端口
    input  wire [5:0]            rd_addr [NUM_RD_PORTS-1:0],
    output wire [DATA_WIDTH-1:0] rd_data [NUM_RD_PORTS-1:0],
    // 写端口
    input  wire                  wr_en   [NUM_WR_PORTS-1:0],
    input  wire [5:0]            wr_addr [NUM_WR_PORTS-1:0],
    input  wire [DATA_WIDTH-1:0] wr_data [NUM_WR_PORTS-1:0]
);
```

### 4. IS Stage (指令调度阶段)

#### 4.1 Reservation Station

```verilog
module reservation_station #(
    parameter NUM_ENTRIES   = 4,
    parameter DATA_WIDTH    = 32,
    parameter TAG_WIDTH     = 6,
    parameter ROB_IDX_WIDTH = 5
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // 分配接口
    input  wire                    alloc_valid,
    input  wire [3:0]              alloc_op,
    input  wire [TAG_WIDTH-1:0]    alloc_prs1,
    input  wire [TAG_WIDTH-1:0]    alloc_prs2,
    input  wire [DATA_WIDTH-1:0]   alloc_val1,
    input  wire [DATA_WIDTH-1:0]   alloc_val2,
    input  wire                    alloc_rdy1,
    input  wire                    alloc_rdy2,
    input  wire [TAG_WIDTH-1:0]    alloc_prd,
    input  wire [ROB_IDX_WIDTH-1:0] alloc_rob_idx,
    input  wire [31:0]             alloc_imm,
    input  wire [31:0]             alloc_pc,
    output wire                    alloc_ready,
    // CDB监听
    input  wire                    cdb_valid,
    input  wire [TAG_WIDTH-1:0]    cdb_tag,
    input  wire [DATA_WIDTH-1:0]   cdb_data,
    // 发射接口
    output wire                    issue_valid,
    output wire [3:0]              issue_op,
    output wire [DATA_WIDTH-1:0]   issue_val1,
    output wire [DATA_WIDTH-1:0]   issue_val2,
    output wire [TAG_WIDTH-1:0]    issue_prd,
    output wire [ROB_IDX_WIDTH-1:0] issue_rob_idx,
    output wire [31:0]             issue_imm,
    output wire [31:0]             issue_pc,
    input  wire                    issue_ack,
    // 冲刷
    input  wire                    flush
);
```

**保留站项结构**：
```
┌────────────────────────────────────────────────────────────────────────┐
│                    Reservation Station Entry                            │
├──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬────────┤
│ Valid│  Op  │ Src1 │ Rdy1 │ Src2 │ Rdy2 │  Dst │ ROB  │ Imm  │   PC   │
│(1-bit)│(4-bit)│(32/6)│(1-bit)│(32/6)│(1-bit)│(6-bit)│(5-bit)│(32-bit)│(32-bit)│
└──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴────────┘
```

#### 4.2 ROB (Reorder Buffer)

```verilog
module rob #(
    parameter NUM_ENTRIES   = 32,
    parameter DATA_WIDTH    = 32,
    parameter PHYS_REG_BITS = 6
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // 分配接口
    input  wire                    alloc_valid,
    input  wire [4:0]              alloc_rd,
    input  wire [PHYS_REG_BITS-1:0] alloc_prd,
    input  wire [PHYS_REG_BITS-1:0] alloc_prd_old,
    input  wire [31:0]             alloc_pc,
    input  wire [3:0]              alloc_type,
    output wire [4:0]              alloc_idx,
    output wire                    alloc_ready,
    // 完成接口
    input  wire                    complete_valid,
    input  wire [4:0]              complete_idx,
    input  wire [DATA_WIDTH-1:0]   complete_data,
    input  wire                    complete_exception,
    input  wire [3:0]              complete_exc_code,
    // 提交接口
    output wire                    commit_valid,
    output wire [4:0]              commit_rd,
    output wire [PHYS_REG_BITS-1:0] commit_prd,
    output wire [PHYS_REG_BITS-1:0] commit_prd_old,
    output wire [DATA_WIDTH-1:0]   commit_data,
    output wire                    commit_exception,
    output wire [3:0]              commit_exc_code,
    output wire [31:0]             commit_pc,
    // 状态
    output wire                    full,
    output wire                    empty,
    // 冲刷
    input  wire                    flush
);
```

**ROB项结构**：
```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           ROB Entry                                           │
├──────┬──────┬──────┬────────┬──────┬──────┬──────┬──────┬──────┬────────────┤
│Valid │ Done │  Rd  │  PRd   │PRdOld│ Data │ Exc  │ExcCode│  PC  │   Type     │
│(1-bit)│(1-bit)│(5-bit)│(6-bit)│(6-bit)│(32-bit)│(1-bit)│(4-bit)│(32-bit)│(4-bit)│
└──────┴──────┴──────┴────────┴──────┴──────┴──────┴──────┴──────┴────────────┘
```

**ROB操作流程**：
```
1. 分配 (Allocate): 指令进入RN阶段时分配ROB项
   - 记录目标寄存器、物理寄存器映射、PC等
   - 返回ROB索引用于后续追踪

2. 完成 (Complete): 指令执行完成时更新ROB
   - 写入结果数据
   - 标记完成状态
   - 记录异常信息（如有）

3. 提交 (Commit): ROB头部指令按序提交
   - 检查是否完成且无异常
   - 更新架构状态（ARF）
   - 释放旧物理寄存器
   - 处理异常（如有）
```

### 5. EX Stage (执行阶段)

#### 5.1 ALU Unit

```verilog
module alu_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 输入
    input  wire        valid,
    input  wire [3:0]  op,
    input  wire [31:0] src1,
    input  wire [31:0] src2,
    input  wire [5:0]  prd,
    input  wire [4:0]  rob_idx,
    // 输出
    output wire        done,
    output wire [31:0] result,
    output wire [5:0]  result_prd,
    output wire [4:0]  result_rob_idx
);
```

**ALU操作编码**：
| Op Code | 操作 | 描述 |
|---------|------|------|
| 4'b0000 | ADD  | 加法 |
| 4'b0001 | SUB  | 减法 |
| 4'b0010 | SLL  | 逻辑左移 |
| 4'b0011 | SLT  | 有符号比较 |
| 4'b0100 | SLTU | 无符号比较 |
| 4'b0101 | XOR  | 异或 |
| 4'b0110 | SRL  | 逻辑右移 |
| 4'b0111 | SRA  | 算术右移 |
| 4'b1000 | OR   | 或 |
| 4'b1001 | AND  | 与 |
| 4'b1010 | LUI  | 高位立即数 |
| 4'b1011 | AUIPC| PC+高位立即数 |

#### 5.2 Multiplier Unit

```verilog
module mul_unit #(
    parameter LATENCY = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    // 输入
    input  wire        valid,
    input  wire [1:0]  op,        // 00:MUL, 01:MULH, 10:MULHSU, 11:MULHU
    input  wire [31:0] src1,
    input  wire [31:0] src2,
    input  wire [5:0]  prd,
    input  wire [4:0]  rob_idx,
    // 输出
    output wire        done,
    output wire [31:0] result,
    output wire [5:0]  result_prd,
    output wire [4:0]  result_rob_idx,
    // 状态
    output wire        busy
);
```

**乘法器流水线**：
```
Stage 1: 部分积生成 (Booth编码)
Stage 2: 部分积压缩 (Wallace树)
Stage 3: 最终加法 (CLA加法器)
```

#### 5.3 Divider Unit

```verilog
module div_unit #(
    parameter MAX_LATENCY = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    // 输入
    input  wire        valid,
    input  wire [1:0]  op,        // 00:DIV, 01:DIVU, 10:REM, 11:REMU
    input  wire [31:0] src1,      // 被除数
    input  wire [31:0] src2,      // 除数
    input  wire [5:0]  prd,
    input  wire [4:0]  rob_idx,
    // 输出
    output wire        done,
    output wire [31:0] result,
    output wire [5:0]  result_prd,
    output wire [4:0]  result_rob_idx,
    // 状态
    output wire        busy
);
```

**除法算法**：采用非恢复余数除法（Non-Restoring Division），每周期处理1位，最多32周期完成。

#### 5.4 Branch Unit

```verilog
module branch_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 输入
    input  wire        valid,
    input  wire [2:0]  op,        // 分支类型
    input  wire [31:0] src1,
    input  wire [31:0] src2,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire        pred_taken,
    input  wire [31:0] pred_target,
    input  wire [5:0]  prd,
    input  wire [4:0]  rob_idx,
    // 输出
    output wire        done,
    output wire        taken,
    output wire [31:0] target,
    output wire        mispredict,
    output wire [31:0] link_addr,  // JAL/JALR返回地址
    output wire [5:0]  result_prd,
    output wire [4:0]  result_rob_idx
);
```

**分支操作编码**：
| Op Code | 操作 | 条件 |
|---------|------|------|
| 3'b000 | BEQ  | rs1 == rs2 |
| 3'b001 | BNE  | rs1 != rs2 |
| 3'b100 | BLT  | rs1 < rs2 (signed) |
| 3'b101 | BGE  | rs1 >= rs2 (signed) |
| 3'b110 | BLTU | rs1 < rs2 (unsigned) |
| 3'b111 | BGEU | rs1 >= rs2 (unsigned) |

#### 5.5 AGU (Address Generation Unit)

```verilog
module agu_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 输入
    input  wire        valid,
    input  wire        is_store,
    input  wire [31:0] base,
    input  wire [31:0] offset,
    input  wire [31:0] store_data,
    input  wire [1:0]  size,       // 00:byte, 01:half, 10:word
    input  wire        sign_ext,
    input  wire [5:0]  prd,
    input  wire [4:0]  rob_idx,
    // 输出
    output wire        done,
    output wire [31:0] addr,
    output wire [31:0] data,
    output wire        misaligned,
    output wire [5:0]  result_prd,
    output wire [4:0]  result_rob_idx
);
```

### 6. MEM Stage (内存访问阶段)

#### 6.1 D-Cache

```verilog
module dcache #(
    parameter CACHE_SIZE = 4096,      // 4KB
    parameter LINE_SIZE  = 32,        // 32字节
    parameter NUM_WAYS   = 2,         // 2路组相联
    parameter ADDR_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // CPU读接口
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  rd_req,
    input  wire [1:0]            rd_size,
    input  wire                  rd_sign_ext,
    output wire [31:0]           rd_data,
    output wire                  rd_hit,
    output wire                  rd_ready,
    // CPU写接口
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire                  wr_req,
    input  wire [1:0]            wr_size,
    input  wire [31:0]           wr_data,
    output wire                  wr_hit,
    output wire                  wr_ready,
    // 内存接口
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire                  mem_rd_req,
    output wire                  mem_wr_req,
    output wire [255:0]          mem_wr_data,
    input  wire [255:0]          mem_rd_data,
    input  wire                  mem_valid
);
```

**D-Cache组织**：
```
┌─────────────────────────────────────────────────────────────────┐
│                    D-Cache (4KB, 2-way)                          │
├─────────────────────────────────────────────────────────────────┤
│  Set │     Way 0                    │     Way 1                 │
│      │ V│D│LRU│Tag  │Data(32B)     │ V│D│LRU│Tag  │Data(32B)  │
├──────┼──┼─┼───┼─────┼──────────────┼──┼─┼───┼─────┼───────────┤
│   0  │1 │0│ 0 │0x800│xxxxxxxx...  │1 │1│ 1 │0x801│xxxxxxxx...│
│   1  │1 │1│ 1 │0x802│xxxxxxxx...  │0 │0│ 0 │     │           │
│  ... │  │ │   │     │              │  │ │   │     │           │
│  63  │1 │0│ 0 │0x8FF│xxxxxxxx...  │1 │0│ 1 │0x900│xxxxxxxx...│
└──────┴──┴─┴───┴─────┴──────────────┴──┴─┴───┴─────┴───────────┘

地址分解: [Tag:20bit][Index:6bit][Offset:5bit][Byte:1bit]
```

#### 6.2 Load Queue

```verilog
module load_queue #(
    parameter NUM_ENTRIES = 8,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // 分配接口
    input  wire                  alloc_valid,
    input  wire [ADDR_WIDTH-1:0] alloc_addr,
    input  wire [1:0]            alloc_size,
    input  wire                  alloc_sign_ext,
    input  wire [5:0]            alloc_prd,
    input  wire [4:0]            alloc_rob_idx,
    output wire [2:0]            alloc_lq_idx,
    output wire                  alloc_ready,
    // Store Queue检查
    input  wire                  sq_check_valid,
    input  wire [ADDR_WIDTH-1:0] sq_check_addr,
    input  wire [DATA_WIDTH-1:0] sq_forward_data,
    input  wire                  sq_forward_valid,
    // 执行接口
    output wire                  exec_valid,
    output wire [ADDR_WIDTH-1:0] exec_addr,
    output wire [1:0]            exec_size,
    output wire                  exec_sign_ext,
    output wire [5:0]            exec_prd,
    output wire [4:0]            exec_rob_idx,
    input  wire                  exec_done,
    input  wire [DATA_WIDTH-1:0] exec_data,
    // 提交
    input  wire                  commit_valid,
    input  wire [2:0]            commit_lq_idx,
    // 冲刷
    input  wire                  flush
);
```

#### 6.3 Store Queue

```verilog
module store_queue #(
    parameter NUM_ENTRIES = 8,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // 分配接口
    input  wire                  alloc_valid,
    input  wire [ADDR_WIDTH-1:0] alloc_addr,
    input  wire [DATA_WIDTH-1:0] alloc_data,
    input  wire [1:0]            alloc_size,
    input  wire [4:0]            alloc_rob_idx,
    output wire [2:0]            alloc_sq_idx,
    output wire                  alloc_ready,
    // 地址转发检查
    input  wire [ADDR_WIDTH-1:0] forward_check_addr,
    output wire                  forward_hit,
    output wire [DATA_WIDTH-1:0] forward_data,
    // 提交写入
    input  wire                  commit_valid,
    output wire                  commit_ready,
    output wire [ADDR_WIDTH-1:0] commit_addr,
    output wire [DATA_WIDTH-1:0] commit_data,
    output wire [1:0]            commit_size,
    // 冲刷
    input  wire                  flush
);
```

**LSQ操作流程**：
```
Load操作:
1. 地址计算完成后进入Load Queue
2. 检查Store Queue是否有地址冲突
   - 如有匹配且数据就绪：Store-to-Load转发
   - 如有匹配但数据未就绪：等待
   - 如无匹配：访问D-Cache
3. 数据返回后广播到CDB
4. 提交时释放LQ项

Store操作:
1. 地址和数据计算完成后进入Store Queue
2. 等待ROB提交
3. 提交时按序写入D-Cache
4. 写入完成后释放SQ项
```

### 7. WB Stage (写回/提交阶段)

#### 7.1 Commit Logic

```verilog
module commit_logic #(
    parameter ROB_ENTRIES = 32
) (
    input  wire        clk,
    input  wire        rst_n,
    // ROB接口
    input  wire        rob_head_valid,
    input  wire        rob_head_done,
    input  wire        rob_head_exception,
    input  wire [3:0]  rob_head_exc_code,
    input  wire [4:0]  rob_head_rd,
    input  wire [5:0]  rob_head_prd,
    input  wire [5:0]  rob_head_prd_old,
    input  wire [31:0] rob_head_data,
    input  wire [31:0] rob_head_pc,
    input  wire [3:0]  rob_head_type,
    output wire        rob_commit,
    // ARF更新
    output wire        arf_wr_en,
    output wire [4:0]  arf_wr_addr,
    output wire [31:0] arf_wr_data,
    // Free List释放
    output wire        free_valid,
    output wire [5:0]  free_preg,
    // 异常处理
    output wire        exception_valid,
    output wire [3:0]  exception_code,
    output wire [31:0] exception_pc,
    // 分支提交
    output wire        branch_commit,
    output wire        branch_taken,
    // 流水线控制
    output wire        flush_pipeline
);
```

#### 7.2 ARF (Architectural Register File)

```verilog
module arf #(
    parameter NUM_REGS   = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // 读端口（用于调试）
    input  wire [4:0]            rd_addr,
    output wire [DATA_WIDTH-1:0] rd_data,
    // 写端口
    input  wire                  wr_en,
    input  wire [4:0]            wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data
);
```

### 8. CDB (Common Data Bus)

```verilog
module cdb #(
    parameter NUM_SOURCES = 6,    // ALU0, ALU1, MUL, DIV, LSU, BRU
    parameter DATA_WIDTH  = 32,
    parameter TAG_WIDTH   = 6
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // 输入源
    input  wire [NUM_SOURCES-1:0]     src_valid,
    input  wire [TAG_WIDTH-1:0]       src_tag   [NUM_SOURCES-1:0],
    input  wire [DATA_WIDTH-1:0]      src_data  [NUM_SOURCES-1:0],
    input  wire [4:0]                 src_rob_idx [NUM_SOURCES-1:0],
    output wire [NUM_SOURCES-1:0]     src_grant,
    // 广播输出
    output wire                  broadcast_valid,
    output wire [TAG_WIDTH-1:0]  broadcast_tag,
    output wire [DATA_WIDTH-1:0] broadcast_data,
    output wire [4:0]            broadcast_rob_idx
);
```

**CDB仲裁策略**：
- 固定优先级：ALU0 > ALU1 > MUL > DIV > LSU > BRU
- 每周期最多广播一个结果
- 未获得授权的源需要保持结果直到下一周期

### 9. CSR Unit

```verilog
module csr_unit (
    input  wire        clk,
    input  wire        rst_n,
    // CSR操作
    input  wire        csr_valid,
    input  wire [2:0]  csr_op,      // CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI
    input  wire [11:0] csr_addr,
    input  wire [31:0] csr_wdata,
    output wire [31:0] csr_rdata,
    output wire        csr_illegal,
    // 异常接口
    input  wire        exception_valid,
    input  wire [3:0]  exception_code,
    input  wire [31:0] exception_pc,
    input  wire [31:0] exception_tval,
    output wire [31:0] mtvec,
    // 中断
    input  wire        ext_interrupt,
    input  wire        timer_interrupt,
    input  wire        sw_interrupt,
    output wire        interrupt_pending,
    // MRET
    input  wire        mret,
    output wire [31:0] mepc
);
```

**支持的CSR寄存器**：
| 地址 | 名称 | 描述 |
|------|------|------|
| 0x300 | mstatus | 机器状态寄存器 |
| 0x301 | misa | ISA描述寄存器 |
| 0x304 | mie | 中断使能寄存器 |
| 0x305 | mtvec | 异常向量基址 |
| 0x340 | mscratch | 临时寄存器 |
| 0x341 | mepc | 异常PC |
| 0x342 | mcause | 异常原因 |
| 0x343 | mtval | 异常值 |
| 0x344 | mip | 中断挂起 |
| 0xF11 | mvendorid | 厂商ID |
| 0xF12 | marchid | 架构ID |
| 0xF13 | mimpid | 实现ID |
| 0xF14 | mhartid | 硬件线程ID |

### 10. Exception Unit

```verilog
module exception_unit (
    input  wire        clk,
    input  wire        rst_n,
    // 异常输入
    input  wire        commit_exception,
    input  wire [3:0]  commit_exc_code,
    input  wire [31:0] commit_pc,
    input  wire [31:0] commit_tval,
    // CSR接口
    output wire        csr_exception_valid,
    output wire [3:0]  csr_exception_code,
    output wire [31:0] csr_exception_pc,
    output wire [31:0] csr_exception_tval,
    input  wire [31:0] csr_mtvec,
    // 流水线控制
    output wire        flush_pipeline,
    output wire [31:0] redirect_pc,
    // 中断
    input  wire        interrupt_pending,
    input  wire        commit_valid
);
```

**异常代码**：
| Code | 异常类型 |
|------|---------|
| 0 | Instruction address misaligned |
| 1 | Instruction access fault |
| 2 | Illegal instruction |
| 3 | Breakpoint |
| 4 | Load address misaligned |
| 5 | Load access fault |
| 6 | Store address misaligned |
| 7 | Store access fault |
| 11 | Environment call from M-mode |

### 11. AXI Interface

#### 11.1 AXI Master (Instruction Bus)

```verilog
module axi_master_ibus (
    input  wire        clk,
    input  wire        rst_n,
    // Cache接口
    input  wire [31:0] cache_addr,
    input  wire        cache_req,
    output wire [255:0] cache_rdata,
    output wire        cache_valid,
    // AXI读通道
    output wire [31:0] axi_araddr,
    output wire [7:0]  axi_arlen,
    output wire [2:0]  axi_arsize,
    output wire [1:0]  axi_arburst,
    output wire        axi_arvalid,
    input  wire        axi_arready,
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rlast,
    input  wire        axi_rvalid,
    output wire        axi_rready
);
```

#### 11.2 AXI Master (Data Bus)

```verilog
module axi_master_dbus (
    input  wire        clk,
    input  wire        rst_n,
    // Cache读接口
    input  wire [31:0] cache_rd_addr,
    input  wire        cache_rd_req,
    output wire [255:0] cache_rd_data,
    output wire        cache_rd_valid,
    // Cache写接口
    input  wire [31:0] cache_wr_addr,
    input  wire        cache_wr_req,
    input  wire [255:0] cache_wr_data,
    output wire        cache_wr_done,
    // AXI读通道
    output wire [31:0] axi_araddr,
    output wire [7:0]  axi_arlen,
    output wire [2:0]  axi_arsize,
    output wire [1:0]  axi_arburst,
    output wire        axi_arvalid,
    input  wire        axi_arready,
    input  wire [31:0] axi_rdata,
    input  wire [1:0]  axi_rresp,
    input  wire        axi_rlast,
    input  wire        axi_rvalid,
    output wire        axi_rready,
    // AXI写通道
    output wire [31:0] axi_awaddr,
    output wire [7:0]  axi_awlen,
    output wire [2:0]  axi_awsize,
    output wire [1:0]  axi_awburst,
    output wire        axi_awvalid,
    input  wire        axi_awready,
    output wire [31:0] axi_wdata,
    output wire [3:0]  axi_wstrb,
    output wire        axi_wlast,
    output wire        axi_wvalid,
    input  wire        axi_wready,
    input  wire [1:0]  axi_bresp,
    input  wire        axi_bvalid,
    output wire        axi_bready
);
```

## Data Models

### 指令编码格式

```
R-type (寄存器-寄存器操作):
31        25 24    20 19    15 14  12 11     7 6      0
┌──────────┬────────┬────────┬──────┬────────┬────────┐
│  funct7  │   rs2  │   rs1  │funct3│   rd   │ opcode │
└──────────┴────────┴────────┴──────┴────────┴────────┘

I-type (立即数操作):
31                  20 19    15 14  12 11     7 6      0
┌─────────────────────┬────────┬──────┬────────┬────────┐
│      imm[11:0]      │   rs1  │funct3│   rd   │ opcode │
└─────────────────────┴────────┴──────┴────────┴────────┘

S-type (存储操作):
31        25 24    20 19    15 14  12 11     7 6      0
┌──────────┬────────┬────────┬──────┬────────┬────────┐
│imm[11:5] │   rs2  │   rs1  │funct3│imm[4:0]│ opcode │
└──────────┴────────┴────────┴──────┴────────┴────────┘

B-type (分支操作):
31   30      25 24    20 19    15 14  12 11    8  7   6      0
┌───┬──────────┬────────┬────────┬──────┬───────┬───┬────────┐
│[12]│ imm[10:5]│   rs2  │   rs1  │funct3│[4:1]  │[11]│ opcode │
└───┴──────────┴────────┴────────┴──────┴───────┴───┴────────┘

U-type (高位立即数):
31                                  12 11     7 6      0
┌──────────────────────────────────────┬────────┬────────┐
│            imm[31:12]                │   rd   │ opcode │
└──────────────────────────────────────┴────────┴────────┘

J-type (跳转):
31   30        21  20  19          12 11     7 6      0
┌───┬────────────┬───┬───────────────┬────────┬────────┐
│[20]│ imm[10:1]  │[11]│  imm[19:12]   │   rd   │ opcode │
└───┴────────────┴───┴───────────────┴────────┴────────┘
```

### 内部数据结构

#### 流水线寄存器

```verilog
// IF/ID流水线寄存器
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instr;
    logic        pred_taken;
    logic [31:0] pred_target;
    logic [63:0] ghr_snapshot;
    logic        valid;
} if_id_reg_t;

// ID/RN流水线寄存器
typedef struct packed {
    logic [31:0] pc;
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [31:0] imm;
    logic [3:0]  alu_op;
    logic [2:0]  fu_type;      // 功能单元类型
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic        branch;
    logic        pred_taken;
    logic [31:0] pred_target;
    logic [63:0] ghr_snapshot;
    logic        valid;
} id_rn_reg_t;

// RN/IS流水线寄存器
typedef struct packed {
    logic [31:0] pc;
    logic [5:0]  prd;
    logic [5:0]  prd_old;
    logic [5:0]  prs1;
    logic [5:0]  prs2;
    logic        prs1_ready;
    logic        prs2_ready;
    logic [31:0] imm;
    logic [3:0]  alu_op;
    logic [2:0]  fu_type;
    logic        reg_write;
    logic        mem_read;
    logic        mem_write;
    logic        branch;
    logic        pred_taken;
    logic [31:0] pred_target;
    logic [4:0]  rob_idx;
    logic        valid;
} rn_is_reg_t;
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Instruction Execution Correctness

*For any* valid RV32IM instruction with valid operands, executing the instruction SHALL produce the mathematically correct result as defined by the RISC-V specification.

**Validates: Requirements 1.1, 1.2, 1.3**

**Test Strategy**: Generate random valid instructions with random operand values, execute them, and compare results against a reference model (software ISA simulator).

### Property 2: x0 Hardwired Zero Invariant

*For any* instruction sequence that writes to register x0, reading x0 SHALL always return zero.

**Validates: Requirements 1.5**

**Test Strategy**: Generate random instructions targeting x0, execute them, then verify x0 reads as zero.

### Property 3: Invalid Opcode Exception

*For any* instruction with an invalid opcode encoding, the CPU SHALL raise an illegal instruction exception.

**Validates: Requirements 1.4**

**Test Strategy**: Generate random invalid opcodes and verify exception is raised with correct mcause value.

### Property 4: Register Rename Round-Trip

*For any* instruction that writes to a destination register, allocating a physical register and then committing the instruction SHALL correctly free the old physical register mapping.

**Validates: Requirements 3.3, 3.4**

**Test Strategy**: Track physical register allocation/deallocation across instruction sequences and verify free list consistency.

### Property 5: RAT Checkpoint Recovery

*For any* branch misprediction, restoring the RAT from checkpoint SHALL produce a RAT state identical to the state at the branch instruction.

**Validates: Requirements 3.5**

**Test Strategy**: Create checkpoints at branches, simulate misprediction, restore, and compare RAT states.

### Property 6: Data Forwarding Correctness

*For any* instruction sequence with data dependencies, the dependent instruction SHALL receive the correct operand value either from the register file, CDB forwarding, or reservation station capture.

**Validates: Requirements 4.2, 4.3, 5.1, 5.2, 5.3, 5.4**

**Test Strategy**: Generate instruction sequences with RAW dependencies and verify correct values are forwarded.

### Property 7: In-Order Commit

*For any* sequence of instructions executed out-of-order, the ROB SHALL commit instructions in program order, and the architectural state SHALL reflect in-order execution.

**Validates: Requirements 4.6**

**Test Strategy**: Execute instruction sequences with varying latencies and verify commit order matches program order.

### Property 8: Precise Exception

*For any* instruction that causes an exception, when the exception is taken: (1) all older instructions SHALL have committed, (2) no younger instructions SHALL have modified architectural state, (3) mepc SHALL contain the excepting instruction's PC, (4) mcause SHALL contain the correct exception code.

**Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5**

**Test Strategy**: Inject exceptions at various pipeline stages and verify architectural state consistency.

### Property 9: Branch Prediction Recovery

*For any* branch misprediction, the CPU SHALL: (1) flush all instructions fetched after the mispredicted branch, (2) restore the global history register to the correct state, (3) redirect fetch to the correct target.

**Validates: Requirements 7.6**

**Test Strategy**: Create branch misprediction scenarios and verify correct recovery.

### Property 10: Cache Coherence

*For any* memory address, a load following a store to the same address SHALL return the stored value (assuming no intervening stores from other sources).

**Validates: Requirements 8.1, 8.2, 8.3, 9.1, 9.2, 9.3, 9.4**

**Test Strategy**: Generate store-load sequences to same addresses and verify data consistency.

### Property 11: Store-to-Load Forwarding

*For any* load instruction with address matching a pending store in the Store Queue, the load SHALL receive the store's data through forwarding.

**Validates: Requirements 10.2, 10.3**

**Test Strategy**: Generate store-load pairs with matching addresses and verify forwarding occurs.

### Property 12: Memory Ordering

*For any* sequence of memory operations, stores SHALL be written to memory in program order.

**Validates: Requirements 10.4**

**Test Strategy**: Generate store sequences and verify memory write order matches program order.

### Property 13: Functional Unit Correctness

*For any* ALU operation, the result SHALL match the expected mathematical result:
- ADD: result = src1 + src2
- SUB: result = src1 - src2
- MUL: result = (src1 * src2)[31:0]
- DIV: result = src1 / src2 (with division by zero handling)
- etc.

**Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**

**Test Strategy**: Generate random operands for each operation type and verify results.

### Property 14: Pipeline Stall Correctness

*For any* structural hazard (ROB full, RS full, CDB conflict), the pipeline SHALL stall the appropriate stages without losing or corrupting instructions.

**Validates: Requirements 12.1, 12.2, 12.3**

**Test Strategy**: Create resource exhaustion scenarios and verify no instruction loss.

### Property 15: Reset State

*For any* reset assertion, after reset deassertion the CPU SHALL: (1) have PC set to reset vector, (2) have all CSRs at default values, (3) have empty ROB, RS, and LSQ, (4) have invalidated caches.

**Validates: Requirements 15.1, 15.2, 15.3, 15.4**

**Test Strategy**: Assert reset and verify all state is correctly initialized.

## Error Handling

### Exception Handling Flow

```
1. 异常检测 (EX/MEM Stage)
   ├── 非法指令 → ID Stage检测
   ├── 地址未对齐 → AGU检测
   ├── 访问错误 → Cache/Bus检测
   └── 环境调用 → ID Stage检测

2. 异常记录 (ROB)
   └── 在对应ROB项中标记异常类型和相关信息

3. 异常提交 (WB Stage)
   ├── 等待异常指令到达ROB头部
   ├── 确保所有更老指令已提交
   └── 触发异常处理

4. 异常处理 (Exception Unit)
   ├── 保存mepc = 异常指令PC
   ├── 保存mcause = 异常代码
   ├── 保存mtval = 异常相关值
   ├── 更新mstatus
   ├── 冲刷流水线
   └── 跳转到mtvec

5. 状态恢复
   ├── 清空ROB、RS、LSQ
   ├── 恢复RAT到提交状态
   └── 从mtvec开始取指
```

### 分支误预测恢复流程

```
1. 误预测检测 (Branch Unit)
   └── 比较预测方向/目标与实际结果

2. 恢复触发
   ├── 标记ROB中该分支之后的所有指令为无效
   ├── 恢复RAT到分支检查点
   └── 恢复GHR到分支时状态

3. 流水线冲刷
   ├── 清空IF、ID、RN阶段
   ├── 清空该分支之后的RS项
   └── 清空该分支之后的LSQ项

4. 重定向取指
   └── 设置PC为正确的分支目标
```

## Testing Strategy

### 单元测试

每个模块应有独立的单元测试，验证：
- 基本功能正确性
- 边界条件处理
- 错误输入处理

### 属性测试

使用属性测试框架（如Cocotb + Hypothesis）验证上述正确性属性：
- 最少100次随机迭代
- 覆盖边界情况
- 使用约束随机生成有效输入

### 集成测试

1. **ISA合规性测试**：运行riscv-tests官方测试套件
2. **随机指令测试**：使用RISC-V DV生成随机指令序列
3. **性能基准测试**：运行Dhrystone、CoreMark等基准

### 形式验证

对关键模块进行形式验证：
- ROB的FIFO属性
- RAT的一致性
- Cache的一致性协议

### 测试配置

```verilog
// 测试参数
parameter TEST_ITERATIONS = 100;      // 属性测试迭代次数
parameter RANDOM_SEED     = 42;       // 随机种子
parameter TIMEOUT_CYCLES  = 100000;   // 超时周期数
```
