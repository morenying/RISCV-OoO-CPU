#==============================================================================
# EGO1 开发板烧录脚本
# 使用方法: vivado -mode batch -source program_ego1.tcl
#==============================================================================

puts "=============================================="
puts "  EGO1 FPGA Programming Script"
puts "=============================================="

# 打开硬件管理器
open_hw_manager

# 连接到硬件服务器
puts "Connecting to hardware server..."
connect_hw_server -allow_non_jtag

# 打开硬件目标
puts "Opening hardware target..."
open_hw_target

# 获取设备
set devices [get_hw_devices]
puts "Found devices: $devices"

# 查找 Artix-7 设备
set device [lindex [get_hw_devices xc7a*] 0]
if {$device eq ""} {
    puts "ERROR: No Artix-7 device found!"
    puts "Please check:"
    puts "  1. EGO1 board is connected via USB"
    puts "  2. USB passthrough is enabled (for VM)"
    puts "  3. Drivers are installed"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 1
}

puts "Using device: $device"
current_hw_device $device

# 设置比特流文件
set bitstream_file "output/riscv_cpu_ego1.bit"
if {![file exists $bitstream_file]} {
    puts "ERROR: Bitstream file not found: $bitstream_file"
    puts "Please run synthesis first: vivado -mode batch -source vivado_ego1.tcl"
    close_hw_target
    disconnect_hw_server
    close_hw_manager
    exit 1
}

puts "Programming with: $bitstream_file"
set_property PROGRAM.FILE $bitstream_file $device

# 烧录设备
puts "Programming device..."
program_hw_devices $device

puts "=============================================="
puts "  PROGRAMMING COMPLETED SUCCESSFULLY!"
puts "=============================================="
puts "LED0 should be ON (reset complete)"
puts "LED1 should be ON (PLL locked)"
puts "=============================================="

# 关闭连接
close_hw_target
disconnect_hw_server
close_hw_manager

