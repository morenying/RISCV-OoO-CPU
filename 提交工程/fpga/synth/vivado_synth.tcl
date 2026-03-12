#==============================================================================
# Vivado Synthesis Script for RISC-V OoO CPU
# Target: Xilinx Artix-7 (xc7a100tcsg324-1)
#==============================================================================

# Project settings
set project_name "riscv_ooo_cpu"
set part_name "xc7a100tcsg324-1"
set top_module "cpu_core_top"

# Directories
set rtl_dir "../rtl"
set output_dir "./output"

# Create output directory
file mkdir $output_dir

# Create project in memory
create_project -in_memory -part $part_name

# Set target language
set_property target_language Verilog [current_project]

# Add RTL source files
add_files -norecurse [glob $rtl_dir/common/*.vh]
add_files -norecurse [glob $rtl_dir/core/*.v]
add_files -norecurse [glob $rtl_dir/cache/*.v]
add_files -norecurse [glob $rtl_dir/bpu/*.v]
add_files -norecurse [glob $rtl_dir/mem/*.v]
add_files -norecurse [glob $rtl_dir/bus/*.v]

# Set top module
set_property top $top_module [current_fileset]

# Add constraints
if {[file exists "./constraints/timing.xdc"]} {
    add_files -fileset constrs_1 -norecurse ./constraints/timing.xdc
}

# Synthesis settings
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value {rebuilt} -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.RETIMING} -value {true} -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION} -value {one_hot} -objects [get_runs synth_1]

# Run synthesis
puts "Starting synthesis..."
synth_design -top $top_module -part $part_name

# Generate reports
puts "Generating reports..."
report_utilization -file $output_dir/utilization_synth.rpt
report_timing_summary -file $output_dir/timing_synth.rpt
report_drc -file $output_dir/drc_synth.rpt
report_methodology -file $output_dir/methodology_synth.rpt

# Write checkpoint
write_checkpoint -force $output_dir/${project_name}_synth.dcp

# Write netlist
write_verilog -force $output_dir/${project_name}_synth.v

puts "Synthesis completed successfully!"
puts "Reports saved to: $output_dir"
