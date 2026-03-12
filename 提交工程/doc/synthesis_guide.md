# RISC-V OoO CPU Synthesis and Implementation Guide

## Overview

This guide describes the synthesis and implementation flow for the RISC-V Out-of-Order CPU targeting Xilinx FPGAs.

## Target Device

- **Family**: Xilinx Artix-7
- **Part**: xc7a100tcsg324-1
- **Speed Grade**: -1
- **Package**: CSG324

## Prerequisites

### Software Requirements
- Vivado Design Suite 2020.2 or later
- Icarus Verilog (for simulation)
- Git (for version control)

### Hardware Requirements
- Minimum 16GB RAM
- 50GB free disk space
- Multi-core CPU recommended

## Directory Structure

```
fpga/
├── rtl/
│   ├── fpga_top.v          # FPGA top-level wrapper
│   ├── bram_imem.v         # Instruction memory
│   ├── bram_dmem.v         # Data memory
│   └── uart_debug.v        # Debug interface
├── synth/
│   ├── vivado_synth.tcl    # Synthesis script
│   ├── vivado_impl.tcl     # Implementation script
│   └── constraints/
│       └── timing.xdc      # Timing constraints
└── output/                  # Generated files
```

## Synthesis Flow

### Step 1: Prepare Environment

```bash
# Set Vivado environment
source /opt/Xilinx/Vivado/2020.2/settings64.sh

# Navigate to synthesis directory
cd fpga/synth
```

### Step 2: Run Synthesis

```bash
vivado -mode batch -source vivado_synth.tcl
```

This will:
1. Read all RTL source files
2. Run synthesis with optimization
3. Generate utilization report
4. Generate timing report
5. Write synthesis checkpoint

### Step 3: Run Implementation

```bash
vivado -mode batch -source vivado_impl.tcl
```

This will:
1. Open synthesis checkpoint
2. Run optimization
3. Run placement
4. Run physical optimization
5. Run routing
6. Generate bitstream

## Timing Constraints

### Clock Definition

```tcl
# 100MHz system clock (10ns period)
create_clock -period 10.000 -name sys_clk [get_ports clk]
```

### Input/Output Delays

```tcl
# Input delays (2ns max, 0.5ns min)
set_input_delay -clock sys_clk -max 2.0 [get_ports rst_n]
set_input_delay -clock sys_clk -min 0.5 [get_ports rst_n]

# Output delays (2ns max, 0.5ns min)
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_*}]
```

### False Paths

```tcl
# Reset is asynchronous
set_false_path -from [get_ports rst_n]
```

## Resource Utilization

### Expected Utilization (Artix-7 100T)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUT | ~15,000 | 63,400 | ~24% |
| FF | ~8,000 | 126,800 | ~6% |
| BRAM | 16 | 135 | ~12% |
| DSP | 4 | 240 | ~2% |

### Critical Modules

| Module | LUTs | FFs | Notes |
|--------|------|-----|-------|
| ROB | ~2,000 | ~1,500 | 32 entries |
| RAT | ~1,000 | ~500 | 32 arch regs |
| RS | ~1,500 | ~800 | 4 entries x 4 |
| I-Cache | ~1,000 | ~500 | 4KB |
| D-Cache | ~1,500 | ~800 | 4KB |
| BPU | ~2,000 | ~1,000 | TAGE predictor |

## Timing Analysis

### Critical Paths

1. **ROB to RAT**: Register rename lookup
2. **RS to Execute**: Operand selection
3. **Cache Tag Compare**: Hit/miss detection
4. **BPU Prediction**: Branch target calculation

### Timing Optimization Techniques

1. **Pipeline Registers**: Add registers on critical paths
2. **Logic Restructuring**: Balance combinational depth
3. **Resource Sharing**: Reduce parallel logic
4. **Retiming**: Move registers for better timing

## Power Optimization

### Clock Gating

The design includes clock gating for:
- Idle functional units (ALU, MUL, DIV)
- Inactive cache banks
- Unused BPU components

### Operand Isolation

Data paths are isolated when units are idle to reduce switching activity.

## FPGA Board Setup

### Nexys A7 Board (Example)

| Signal | FPGA Pin | Board Connection |
|--------|----------|------------------|
| clk | E3 | 100MHz oscillator |
| rst_n | C12 | CPU_RESETN button |
| uart_rx | C4 | USB-UART RX |
| uart_tx | D4 | USB-UART TX |
| led[0] | H17 | LED0 |
| led[1] | K15 | LED1 |

### Pin Constraints

```tcl
# Clock
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]

# Reset
set_property PACKAGE_PIN C12 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# UART
set_property PACKAGE_PIN C4 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
set_property PACKAGE_PIN D4 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]
```

## Programming the FPGA

### Generate Bitstream

```bash
# After implementation completes
# Bitstream is at: fpga/synth/output/riscv_ooo_cpu.bit
```

### Program via Vivado Hardware Manager

1. Open Vivado Hardware Manager
2. Connect to target board
3. Program device with bitstream
4. Verify programming success

### Program via Command Line

```bash
vivado -mode batch -source program.tcl
```

## Debug Interface

### UART Commands

| Command | Description | Response |
|---------|-------------|----------|
| R + addr[4] | Read memory | data[4] |
| W + addr[4] + data[4] | Write memory | K (ACK) |
| H | Halt CPU | K |
| G | Resume CPU | K |
| X | Reset CPU | K |
| S | Status query | H/R |

### Example Usage

```python
# Python example for UART debug
import serial

ser = serial.Serial('/dev/ttyUSB0', 115200)

# Read memory at 0x00001000
ser.write(b'R\x00\x00\x10\x00')
data = ser.read(4)

# Write 0xDEADBEEF to 0x00001000
ser.write(b'W\x00\x00\x10\x00\xDE\xAD\xBE\xEF')
ack = ser.read(1)  # Should be 'K'
```

## Troubleshooting

### Timing Failures

1. Check critical path in timing report
2. Add pipeline registers if needed
3. Reduce clock frequency target
4. Enable retiming in synthesis

### Resource Overflow

1. Reduce cache size
2. Reduce ROB/RS entries
3. Simplify BPU (use bimodal only)
4. Target larger FPGA

### Simulation Mismatch

1. Check for uninitialized signals
2. Verify reset behavior
3. Check clock domain crossings
4. Review synthesis warnings

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial release |
| 1.1 | 2024-06 | Added clock gating |
| 1.2 | 2024-12 | Added UART debug |
