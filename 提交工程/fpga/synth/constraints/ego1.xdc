#==============================================================================
# EGO1 开发板约束文件
# FPGA: Xilinx Artix-7 xc7a35tcsg324-1
# 晶振: 100MHz
#==============================================================================

#------------------------------------------------------------------------------
# 时钟约束
#------------------------------------------------------------------------------
# 100MHz 系统时钟 (Y18 引脚)
set_property PACKAGE_PIN Y18 [get_ports sys_clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk_i]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk_i]

#------------------------------------------------------------------------------
# 复位按钮 (active-low)
#------------------------------------------------------------------------------
# S1 按钮作为复位 (active-low)
set_property PACKAGE_PIN U4 [get_ports sys_rst_n_i]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n_i]

#------------------------------------------------------------------------------
# LED 输出 (active-high)
#------------------------------------------------------------------------------
# LED0-LED7
set_property PACKAGE_PIN F6  [get_ports {led_o[0]}]
set_property PACKAGE_PIN G4  [get_ports {led_o[1]}]
set_property PACKAGE_PIN G3  [get_ports {led_o[2]}]
set_property PACKAGE_PIN J4  [get_ports {led_o[3]}]
set_property PACKAGE_PIN H4  [get_ports {led_o[4]}]
set_property PACKAGE_PIN J3  [get_ports {led_o[5]}]
set_property PACKAGE_PIN J2  [get_ports {led_o[6]}]
set_property PACKAGE_PIN K2  [get_ports {led_o[7]}]

set_property IOSTANDARD LVCMOS33 [get_ports {led_o[*]}]

#------------------------------------------------------------------------------
# UART 接口 (通过 USB-UART 芯片)
#------------------------------------------------------------------------------
# UART TX (FPGA -> PC)
set_property PACKAGE_PIN T4 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_o]

# UART RX (PC -> FPGA)
set_property PACKAGE_PIN N5 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]

#------------------------------------------------------------------------------
# 调试接口 (可选，使用按钮)
#------------------------------------------------------------------------------
# S2 按钮作为调试请求 (active-low)
set_property PACKAGE_PIN V2 [get_ports debug_req_i]
set_property IOSTANDARD LVCMOS33 [get_ports debug_req_i]
set_property PULLUP true [get_ports debug_req_i]

#------------------------------------------------------------------------------
# 时序约束
#------------------------------------------------------------------------------
# 时钟不确定性
set_clock_uncertainty -setup 0.5 [get_clocks sys_clk]
set_clock_uncertainty -hold 0.1 [get_clocks sys_clk]

# 复位是异步的
set_false_path -from [get_ports sys_rst_n_i]

# UART 输入延迟
set_input_delay -clock sys_clk -max 3.0 [get_ports uart_rx_i]
set_input_delay -clock sys_clk -min 0.5 [get_ports uart_rx_i]

# UART 输出延迟
set_output_delay -clock sys_clk -max 2.0 [get_ports uart_tx_o]
set_output_delay -clock sys_clk -min 0.5 [get_ports uart_tx_o]

# LED 输出延迟
set_output_delay -clock sys_clk -max 2.0 [get_ports {led_o[*]}]
set_output_delay -clock sys_clk -min 0.5 [get_ports {led_o[*]}]

#------------------------------------------------------------------------------
# 配置设置
#------------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

#------------------------------------------------------------------------------
# 可选: 七段数码管 (EGO1 有 8 个数码管)
#------------------------------------------------------------------------------
# 段选信号 (active-low)
# set_property PACKAGE_PIN B4 [get_ports {seg[0]}]  # a
# set_property PACKAGE_PIN A4 [get_ports {seg[1]}]  # b
# set_property PACKAGE_PIN A3 [get_ports {seg[2]}]  # c
# set_property PACKAGE_PIN B1 [get_ports {seg[3]}]  # d
# set_property PACKAGE_PIN A1 [get_ports {seg[4]}]  # e
# set_property PACKAGE_PIN B3 [get_ports {seg[5]}]  # f
# set_property PACKAGE_PIN B2 [get_ports {seg[6]}]  # g
# set_property PACKAGE_PIN D5 [get_ports {seg[7]}]  # dp

# 位选信号 (active-low)
# set_property PACKAGE_PIN G2 [get_ports {an[0]}]
# set_property PACKAGE_PIN C2 [get_ports {an[1]}]
# set_property PACKAGE_PIN C1 [get_ports {an[2]}]
# set_property PACKAGE_PIN H1 [get_ports {an[3]}]
# set_property PACKAGE_PIN G1 [get_ports {an[4]}]
# set_property PACKAGE_PIN F1 [get_ports {an[5]}]
# set_property PACKAGE_PIN E1 [get_ports {an[6]}]
# set_property PACKAGE_PIN G6 [get_ports {an[7]}]

