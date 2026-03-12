#==============================================================================
# Vivado 综合脚本 - EGO1 开发板
# FPGA: Xilinx Artix-7 xc7a35tcsg324-1
#==============================================================================

# 项目设置
set project_name "riscv_ooo_cpu_ego1"
set part_name "xc7a35tcsg324-1"
set top_module "fpga_top"

# 目录设置 (相对于脚本所在目录)
set script_dir [file dirname [info script]]
set rtl_dir [file normalize "$script_dir/../../rtl"]
set fpga_rtl_dir [file normalize "$script_dir/../rtl"]
set output_dir [file normalize "$script_dir/output"]

# 创建输出目录
file mkdir $output_dir

puts "=============================================="
puts "  RISC-V OoO CPU - EGO1 FPGA Build"
puts "=============================================="
puts "Project: $project_name"
puts "Part: $part_name"
puts "Top Module: $top_module"
puts "RTL Dir: $rtl_dir"
puts "FPGA RTL Dir: $fpga_rtl_dir"
puts "Output Dir: $output_dir"
puts "=============================================="

#==============================================================================
# 创建项目
#==============================================================================
create_project -force $project_name $output_dir -part $part_name

# 设置目标语言
set_property target_language Verilog [current_project]

#==============================================================================
# 添加源文件
#==============================================================================
puts "Adding RTL source files..."

# 添加公共定义
add_files -norecurse [glob -nocomplain $rtl_dir/common/*.vh]

# 添加核心模块 (排除 assertions.vh，它是头文件)
foreach f [glob -nocomplain $rtl_dir/core/*.v] {
    add_files -norecurse $f
}

# 添加缓存模块
add_files -norecurse [glob -nocomplain $rtl_dir/cache/*.v]

# 添加 BPU 模块
add_files -norecurse [glob -nocomplain $rtl_dir/bpu/*.v]

# 添加内存模块
add_files -norecurse [glob -nocomplain $rtl_dir/mem/*.v]

# 添加总线模块
add_files -norecurse [glob -nocomplain $rtl_dir/bus/*.v]

# 添加 FPGA 专用模块
add_files -norecurse [glob -nocomplain $fpga_rtl_dir/*.v]

# 设置顶层模块
set_property top $top_module [current_fileset]

#==============================================================================
# 添加约束文件
#==============================================================================
puts "Adding constraint files..."
add_files -fileset constrs_1 -norecurse $script_dir/constraints/ego1.xdc

#==============================================================================
# 综合设置
#==============================================================================
puts "Configuring synthesis settings..."

# 综合策略
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

# 综合选项
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value {rebuilt} -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.RETIMING} -value {true} -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION} -value {one_hot} -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING} -value {auto} -objects [get_runs synth_1]

#==============================================================================
# 运行综合
#==============================================================================
puts "Starting synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# 检查综合结果
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts "Synthesis completed successfully!"

#==============================================================================
# 生成综合报告
#==============================================================================
puts "Generating synthesis reports..."
open_run synth_1

report_utilization -file $output_dir/utilization_synth.rpt
report_timing_summary -file $output_dir/timing_synth.rpt
report_drc -file $output_dir/drc_synth.rpt
report_methodology -file $output_dir/methodology_synth.rpt

#==============================================================================
# 实现设置
#==============================================================================
puts "Configuring implementation settings..."

# 实现策略
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

#==============================================================================
# 运行实现
#==============================================================================
puts "Starting implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# 检查实现结果
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

puts "Implementation completed successfully!"

#==============================================================================
# 生成实现报告
#==============================================================================
puts "Generating implementation reports..."
open_run impl_1

report_utilization -file $output_dir/utilization_impl.rpt
report_timing_summary -file $output_dir/timing_impl.rpt
report_power -file $output_dir/power_impl.rpt
report_drc -file $output_dir/drc_impl.rpt

#==============================================================================
# 生成比特流
#==============================================================================
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# 复制比特流到输出目录
file copy -force $output_dir/$project_name.runs/impl_1/fpga_top.bit $output_dir/riscv_cpu_ego1.bit

puts "=============================================="
puts "  BUILD COMPLETED SUCCESSFULLY!"
puts "=============================================="
puts "Bitstream: $output_dir/riscv_cpu_ego1.bit"
puts "Reports: $output_dir/*.rpt"
puts "=============================================="

# 关闭项目
close_project

