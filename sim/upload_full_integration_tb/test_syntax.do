# 快速语法检查脚本
puts "=========================================="
puts "  Syntax Check Only"
puts "=========================================="

# 清理
if {[file exists work]} {
    vdel -all
}
vlib work

# 编译源文件
puts "\nCompiling upload_adapter_0.v..."
vlog -work work ../../rtl/upload_adapter_0.v

puts "\nCompiling upload_packer.v..."
vlog -work work ../../rtl/upload_packer.v

puts "\nCompiling upload_arbiter.v..."
vlog -work work ../../rtl/upload_arbiter.v

puts "\nCompiling testbench..."
vlog -work work ../../tb/upload_full_integration_tb.v

puts "\n=========================================="
puts "  Syntax check completed!"
puts "=========================================="

quit -f
