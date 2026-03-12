# RTL Source Files

本目录包含 RISC-V RV32IM 乱序执行 CPU 的所有 Verilog RTL 源文件。

## 目录结构

```
rtl/
├── common/          # 公共定义和工具模块
│   └── cpu_defines.vh    # 全局参数和宏定义
├── core/            # CPU 核心模块
│   ├── if_stage.v        # 取指阶段
│   ├── id_stage.v        # 译码阶段
│   ├── rn_stage.v        # 重命名阶段
│   ├── is_stage.v        # 发射阶段
│   ├── ex_stage.v        # 执行阶段
│   ├── mem_stage.v       # 访存阶段
│   ├── wb_stage.v        # 写回阶段
│   ├── decoder.v         # 指令译码器
│   ├── alu_unit.v        # ALU 单元
│   ├── mul_unit.v        # 乘法单元
│   ├── div_unit.v        # 除法单元
│   ├── branch_unit.v     # 分支单元
│   ├── agu_unit.v        # 地址生成单元
│   ├── rob.v             # 重排序缓冲区
│   ├── reservation_station.v  # 保留站
│   ├── rat.v             # 寄存器别名表
│   ├── free_list.v       # 空闲列表
│   ├── prf.v             # 物理寄存器文件
│   ├── cdb.v             # 公共数据总线
│   ├── csr_unit.v        # CSR 单元
│   ├── exception_unit.v  # 异常处理单元
│   ├── pipeline_ctrl.v   # 流水线控制
│   ├── perf_counters.v   # 性能计数器 (新增)
│   ├── clock_gate.v      # 时钟门控 (新增)
│   ├── dft_wrapper.v     # DFT 封装 (新增)
│   ├── ecc_unit.v        # ECC 单元 (新增)
│   └── assertions.vh     # 断言宏库 (新增)
├── cache/           # 缓存子系统
│   ├── icache.v          # 指令缓存
│   └── dcache.v          # 数据缓存
├── bpu/             # 分支预测单元
│   ├── bpu.v             # BPU 顶层
│   ├── tage_predictor.v  # TAGE 预测器
│   ├── tage_table.v      # TAGE 表
│   ├── bimodal_predictor.v  # 双模态预测器
│   ├── btb.v             # 分支目标缓冲
│   ├── ras.v             # 返回地址栈
│   └── loop_predictor.v  # 循环预测器
├── mem/             # 内存子系统
│   ├── lsq.v             # Load/Store Queue 顶层
│   ├── load_queue.v      # 加载队列
│   └── store_queue.v     # 存储队列
└── bus/             # 总线接口
    ├── axi_master_ibus.v # AXI 指令总线主机
    └── axi_master_dbus.v # AXI 数据总线主机
```

## 新增生产就绪模块

### 性能计数器 (perf_counters.v)
- 周期计数器、指令计数器
- 分支预测统计
- 缓存命中/缺失统计
- 流水线停顿统计

### 时钟门控 (clock_gate.v)
- Latch-based 时钟门控
- 同步时钟门控
- 功耗域控制器
- 操作数隔离

### DFT 支持 (dft_wrapper.v)
- 扫描链接口
- BIST 控制器
- JTAG TAP 控制器

### ECC 单元 (ecc_unit.v)
- SEC-DED ECC 编码/解码
- 奇偶校验

### 断言宏库 (assertions.vh)
- FIFO 溢出/下溢检查
- 状态机合法性检查
- 数据完整性检查
- 握手协议检查

## 编码规范

- Verilog 2001 标准
- 同步复位设计
- 参数化模块
- 完整的敏感列表 (@*)
