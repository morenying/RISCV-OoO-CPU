#==============================================================================
# Vivado Implementation Script for RISC-V OoO CPU
# Runs place & route after synthesis
#==============================================================================

# Project settings
set project_name "riscv_ooo_cpu"
set output_dir "./output"

# Check for synthesis checkpoint
if {![file exists $output_dir/${project_name}_synth.dcp]} {
    puts "ERROR: Synthesis checkpoint not found. Run vivado_synth.tcl first."
    exit 1
}

# Open synthesis checkpoint
open_checkpoint $output_dir/${project_name}_synth.dcp

#------------------------------------------------------------------------------
# Optimization
#------------------------------------------------------------------------------
puts "Running optimization..."
opt_design -directive Explore

# Report post-opt timing
report_timing_summary -file $output_dir/timing_opt.rpt

#------------------------------------------------------------------------------
# Placement
#------------------------------------------------------------------------------
puts "Running placement..."
place_design -directive Explore

# Report post-place timing
report_timing_summary -file $output_dir/timing_place.rpt
report_utilization -file $output_dir/utilization_place.rpt

# Write post-place checkpoint
write_checkpoint -force $output_dir/${project_name}_place.dcp

#------------------------------------------------------------------------------
# Physical Optimization (optional)
#------------------------------------------------------------------------------
puts "Running physical optimization..."
phys_opt_design -directive AggressiveExplore

#------------------------------------------------------------------------------
# Routing
#------------------------------------------------------------------------------
puts "Running routing..."
route_design -directive Explore

# Report post-route timing
report_timing_summary -file $output_dir/timing_route.rpt
report_timing -max_paths 100 -file $output_dir/timing_paths.rpt
report_utilization -file $output_dir/utilization_route.rpt
report_power -file $output_dir/power.rpt
report_drc -file $output_dir/drc_route.rpt

# Write post-route checkpoint
write_checkpoint -force $output_dir/${project_name}_route.dcp

#------------------------------------------------------------------------------
# Bitstream Generation
#------------------------------------------------------------------------------
puts "Generating bitstream..."
write_bitstream -force $output_dir/${project_name}.bit

# Write debug probes (if ILA present)
# write_debug_probes -force $output_dir/${project_name}.ltx

puts "Implementation completed successfully!"
puts "Bitstream: $output_dir/${project_name}.bit"

#------------------------------------------------------------------------------
# Final Timing Check
#------------------------------------------------------------------------------
set timing_slack [get_property SLACK [get_timing_paths -max_paths 1]]
if {$timing_slack < 0} {
    puts "WARNING: Timing not met! Worst slack: $timing_slack ns"
} else {
    puts "Timing met. Worst slack: $timing_slack ns"
}
