#=================================================================
# Vivado TCL Script for CPU Simulation
# Usage: vivado -mode batch -source run_sim.tcl
#=================================================================

# Set project parameters
set project_name "cpu_4way_sim"
set project_dir "../sim/vivado"
set rtl_dir "../rtl"
set tb_dir "../tb"
set part "xc7a200tfbg676-2"

# Create project directory
file mkdir $project_dir

# Create project
create_project $project_name $project_dir -part $part -force

# Add RTL sources
add_files -fileset sources_1 [glob $rtl_dir/core/*.v]
add_files -fileset sources_1 [glob $rtl_dir/bpu/*.v]
add_files -fileset sources_1 [glob $rtl_dir/cache/*.v]
add_files -fileset sources_1 [glob $rtl_dir/mmu/*.v]
add_files -fileset sources_1 [glob $rtl_dir/mem/*.v]

# Add testbench
add_files -fileset sim_1 $tb_dir/tb_cpu_core_4way.v
set_property top tb_cpu_core_4way [get_filesets sim_1]

# Set simulation runtime
set_property -name {xsim.simulate.runtime} -value {1000us} -objects [get_filesets sim_1]

# Add include directories
set_property include_dirs [list $rtl_dir/core $rtl_dir/bpu] [get_filesets sources_1]
set_property include_dirs [list $rtl_dir/core $rtl_dir/bpu] [get_filesets sim_1]

# Set Verilog define for simulation
set_property verilog_define {SIMULATION=1} [get_filesets sim_1]

# Run elaboration to check for syntax errors
puts "Running elaboration..."
synth_design -top cpu_core_4way -part $part -rtl

# Launch simulation
puts "Launching simulation..."
launch_simulation

# Run simulation
run 100us

# Print summary
puts "================================"
puts "Simulation completed"
puts "================================"

# Close project
close_project
