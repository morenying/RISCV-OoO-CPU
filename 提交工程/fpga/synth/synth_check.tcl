# =============================================================================
# Vivado Synthesis Check Script for RISC-V OoO CPU
# 
# Usage: vivado -mode batch -source synth_check.tcl
# =============================================================================

# Create project
create_project -force synth_check ./synth_check -part xc7a35tcsg324-1

# Add RTL sources
add_files -fileset sources_1 [glob ../../rtl/core/*.v]
add_files -fileset sources_1 [glob ../../rtl/bus/*.v]
add_files -fileset sources_1 [glob ../../rtl/mem/*.v]
add_files -fileset sources_1 [glob ../../rtl/periph/*.v]
add_files -fileset sources_1 [glob ../../rtl/clk_rst/*.v]
add_files -fileset sources_1 [glob ../../rtl/system/*.v]
add_files -fileset sources_1 [glob ../../rtl/bpu/*.v]
add_files -fileset sources_1 ../rtl/fpga_top.v

# Add constraints
add_files -fileset constrs_1 constraints.xdc

# Set top module
set_property top fpga_top [current_fileset]

# Run synthesis
synth_design -top fpga_top -part xc7a35tcsg324-1

# Report utilization
report_utilization -file synth_utilization.rpt

# Report timing
report_timing_summary -file synth_timing.rpt

# Check for critical warnings
set warnings [get_msg_config -count -severity {CRITICAL WARNING}]
puts "Critical Warnings: $warnings"

# Check for errors
set errors [get_msg_config -count -severity {ERROR}]
puts "Errors: $errors"

# Close project
close_project

puts "Synthesis check complete!"
puts "Check synth_utilization.rpt and synth_timing.rpt for details"
