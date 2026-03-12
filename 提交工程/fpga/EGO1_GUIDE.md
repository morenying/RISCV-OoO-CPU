# EGO1 开发板 FPGA 使用指南

本指南说明如何在 Ubuntu 虚拟机中使用 Vivado 对 RISC-V OoO CPU 进行综合、实现和烧录到 EGO1 开发板。

## 开发板信息

- **开发板**: EGO1
- **FPGA 芯片**: Xilinx Artix-7 xc7a35tcsg324-1
- **系统时钟**: 100MHz
- **资源**: 33,280 LUTs, 41,600 FFs, 90 BRAMs

## 前置条件

### 1. 安装 Vivado

```bash
# 下载 Vivado (推荐 2020.2 或更新版本)
# 从 Xilinx 官网下载: https://www.xilinx.com/support/download.html

# 安装 (假设下载到 ~/Downloads)
cd ~/Downloads
chmod +x Xilinx_Unified_*_Lin64.bin
sudo ./Xilinx_Unified_*_Lin64.bin

# 安装完成后，添加到 PATH
echo 'source /tools/Xilinx/Vivado/2020.2/settings64.sh' >> ~/.bashrc
source ~/.bashrc

# 验证安装
vivado -version
```

### 2. 安装 USB 驱动 (用于烧录)

```bash
# 安装 Digilent 驱动
cd /tools/Xilinx/Vivado/2020.2/data/xicom/cable_drivers/lin64/install_script/install_drivers
sudo ./install_drivers

# 添加 udev 规则
sudo cp /tools/Xilinx/Vivado/2020.2/data/xicom/cable_drivers/lin64/install_script/52-xilinx-digilent-usb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

# 将用户添加到 dialout 组
sudo usermod -a -G dialout $USER
# 重新登录使更改生效
```

### 3. 虚拟机 USB 直通设置

如果使用 VMware 或 VirtualBox:

**VMware:**
1. 虚拟机 → 设置 → USB 控制器 → USB 兼容性选择 USB 3.0
2. 连接 EGO1 后，虚拟机 → 可移动设备 → 选择 Digilent USB Device → 连接

**VirtualBox:**
1. 设置 → USB → 启用 USB 控制器 → USB 3.0
2. 添加 USB 设备过滤器: Digilent
3. 启动虚拟机后连接 EGO1

## 快速开始

### 方法一: 使用 TCL 脚本 (推荐)

```bash
# 进入项目目录
cd /path/to/riscv-ooo-cpu

# 运行综合和实现脚本
cd fpga/synth
vivado -mode batch -source vivado_ego1.tcl

# 完成后，比特流文件位于:
# fpga/synth/output/riscv_cpu_ego1.bit
```

### 方法二: 使用 Vivado GUI

```bash
# 启动 Vivado GUI
vivado &
```

然后按照以下步骤操作:

1. **创建项目**
   - File → New Project
   - Project Name: `riscv_ooo_cpu_ego1`
   - Project Location: 选择一个目录
   - Project Type: RTL Project
   - Part: `xc7a35tcsg324-1`

2. **添加源文件**
   - Add Sources → Add or create design sources
   - 添加以下目录的所有 .v 文件:
     - `rtl/common/`
     - `rtl/core/`
     - `rtl/cache/`
     - `rtl/bpu/`
     - `rtl/mem/`
     - `rtl/bus/`
     - `fpga/rtl/`

3. **添加约束文件**
   - Add Sources → Add or create constraints
   - 添加 `fpga/synth/constraints/ego1.xdc`

4. **设置顶层模块**
   - 在 Sources 窗口右键 `fpga_top` → Set as Top

5. **运行综合**
   - Flow Navigator → Run Synthesis
   - 等待完成 (约 5-15 分钟)

6. **运行实现**
   - Flow Navigator → Run Implementation
   - 等待完成 (约 10-30 分钟)

7. **生成比特流**
   - Flow Navigator → Generate Bitstream
   - 等待完成 (约 5-10 分钟)

## 烧录到 EGO1

### 方法一: 使用 Hardware Manager (GUI)

```bash
# 启动 Vivado
vivado &
```

1. Flow Navigator → Open Hardware Manager
2. Open Target → Auto Connect
3. 右键 xc7a35t → Program Device
4. 选择比特流文件: `fpga/synth/output/riscv_cpu_ego1.bit`
5. 点击 Program

### 方法二: 使用命令行

```bash
# 创建烧录脚本
cat > fpga/synth/program_ego1.tcl << 'EOF'
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

# 获取设备
set device [get_hw_devices xc7a35t_0]
current_hw_device $device

# 设置比特流
set_property PROGRAM.FILE {output/riscv_cpu_ego1.bit} $device

# 烧录
program_hw_devices $device

# 关闭
close_hw_target
disconnect_hw_server
close_hw_manager
EOF

# 运行烧录
cd fpga/synth
vivado -mode batch -source program_ego1.tcl
```

## 验证运行

烧录成功后:

1. **LED 状态**:
   - LED0: 亮 = 复位完成
   - LED1: 亮 = PLL 锁定
   - 其他 LED: 保留

2. **UART 通信** (115200 baud):
   ```bash
   # 安装串口工具
   sudo apt install minicom
   
   # 连接串口 (通常是 /dev/ttyUSB0 或 /dev/ttyUSB1)
   minicom -D /dev/ttyUSB0 -b 115200
   ```

3. **复位**:
   - 按下 S1 按钮进行复位

## 常见问题

### Q1: 综合失败，资源不足

EGO1 的 xc7a35t 资源有限。如果资源不足:

1. 减小 ROB 大小 (修改 `cpu_defines.vh`):
   ```verilog
   `define ROB_DEPTH 16  // 从 32 减小到 16
   ```

2. 减小缓存大小:
   ```verilog
   `define ICACHE_SIZE 2048  // 2KB
   `define DCACHE_SIZE 2048  // 2KB
   ```

### Q2: 时序不满足

如果时序违例:

1. 降低时钟频率 (修改 `ego1.xdc`):
   ```tcl
   # 改为 50MHz
   create_clock -period 20.000 -name sys_clk [get_ports sys_clk_i]
   ```

2. 修改 MMCM 配置 (修改 `fpga_top.v`):
   ```verilog
   .CLKOUT0_DIVIDE_F(20.0),  // 50MHz output
   ```

### Q3: USB 设备未识别

```bash
# 检查 USB 设备
lsusb | grep -i digilent

# 检查权限
ls -la /dev/ttyUSB*

# 如果权限不足
sudo chmod 666 /dev/ttyUSB0
```

### Q4: Vivado 许可证问题

EGO1 使用的 xc7a35t 支持免费的 Vivado WebPACK 许可证，无需购买。

## 资源使用估算

| 资源 | 估计使用 | 可用 | 使用率 |
|------|----------|------|--------|
| LUT | ~15,000 | 20,800 | ~72% |
| FF | ~8,000 | 41,600 | ~19% |
| BRAM | ~20 | 50 | ~40% |
| DSP | ~4 | 90 | ~4% |

## 文件结构

```
fpga/
├── rtl/
│   ├── fpga_top.v       # FPGA 顶层模块
│   ├── bram_imem.v      # 指令存储器
│   ├── bram_dmem.v      # 数据存储器
│   └── uart_debug.v     # UART 调试接口
├── synth/
│   ├── constraints/
│   │   ├── ego1.xdc     # EGO1 约束文件
│   │   └── timing.xdc   # 通用时序约束
│   ├── vivado_ego1.tcl  # EGO1 综合脚本
│   ├── program_ego1.tcl # 烧录脚本
│   └── output/          # 输出目录
│       ├── riscv_cpu_ego1.bit  # 比特流
│       └── *.rpt        # 报告文件
└── EGO1_GUIDE.md        # 本指南
```

## 下一步

1. 加载测试程序到 BRAM
2. 通过 UART 进行调试
3. 运行 RISC-V 测试程序

如有问题，请参考 `doc/synthesis_guide.md` 获取更多信息。
