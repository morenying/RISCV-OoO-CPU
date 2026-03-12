#==============================================================================
# Timing Constraints for RISC-V OoO CPU
# Target: 100MHz operation
#==============================================================================

#------------------------------------------------------------------------------
# Clock Definition
#------------------------------------------------------------------------------
# Primary system clock - 100MHz (10ns period)
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Clock uncertainty for setup/hold analysis
set_clock_uncertainty -setup 0.5 [get_clocks sys_clk]
set_clock_uncertainty -hold 0.1 [get_clocks sys_clk]

#------------------------------------------------------------------------------
# Input Delays
#------------------------------------------------------------------------------
# All inputs relative to clock (assume 2ns external delay)
set_input_delay -clock sys_clk -max 2.0 [get_ports rst_n]

# AXI interface inputs
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_rdata*}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_rvalid}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_rresp*}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_rlast}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_arready}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_awready}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_wready}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_bvalid}]
set_input_delay -clock sys_clk -max 3.0 [get_ports {axi_*_bresp*}]

# Minimum input delays
set_input_delay -clock sys_clk -min 0.5 [get_ports rst_n]
set_input_delay -clock sys_clk -min 0.5 [get_ports {axi_*}]

#------------------------------------------------------------------------------
# Output Delays
#------------------------------------------------------------------------------
# AXI interface outputs (assume 2ns external setup requirement)
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_araddr*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_arvalid}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_arlen*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_arsize*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_arburst*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_rready}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_awaddr*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_awvalid}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_awlen*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_awsize*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_awburst*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_wdata*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_wstrb*}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_wvalid}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_wlast}]
set_output_delay -clock sys_clk -max 2.0 [get_ports {axi_*_bready}]

# Minimum output delays
set_output_delay -clock sys_clk -min 0.5 [get_ports {axi_*}]

#------------------------------------------------------------------------------
# False Paths
#------------------------------------------------------------------------------
# Reset is asynchronous
set_false_path -from [get_ports rst_n]

# Debug interface (if present) - async to main clock domain
# set_false_path -from [get_ports {debug_*}]

#------------------------------------------------------------------------------
# Multicycle Paths
#------------------------------------------------------------------------------
# Divider unit - multi-cycle operation (34 cycles)
# These paths are handled internally by valid/ready handshaking
# set_multicycle_path 2 -setup -from [get_cells -hier *div_unit*] -to [get_cells -hier *div_unit*]
# set_multicycle_path 1 -hold -from [get_cells -hier *div_unit*] -to [get_cells -hier *div_unit*]

#------------------------------------------------------------------------------
# Max Delay Constraints
#------------------------------------------------------------------------------
# Critical paths - ensure they meet timing
# set_max_delay 8.0 -from [get_cells -hier *rob*] -to [get_cells -hier *rat*]

#------------------------------------------------------------------------------
# Clock Groups (for future multi-clock designs)
#------------------------------------------------------------------------------
# set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks debug_clk]

#------------------------------------------------------------------------------
# Physical Constraints (optional - for specific FPGA board)
#------------------------------------------------------------------------------
# Example for Nexys A7 board:
# set_property PACKAGE_PIN E3 [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]
# set_property PACKAGE_PIN C12 [get_ports rst_n]
# set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
