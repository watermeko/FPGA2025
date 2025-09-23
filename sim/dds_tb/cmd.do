# 退出上次仿真
quit -sim

# 清理并重新创建工作库
vdel -lib work -all
vlib work
vmap work work

# 使用SystemVerilog编译选项
vlog -sv ../../rtl/dds/*.v
vlog -sv ../../tb/dds_tb.sv

# 开始仿真 (使用voptargs保持信号可见性)
vsim work.dds_tb -voptargs="+acc"
# vsim -L gw5a -Lf gw5a work.cdc_tb -voptargs="+acc" -vopt 

# 手动添加关键信号 (避免使用通配符)
if {[catch {
    add wave /dds_tb/clock
    add wave /dds_tb/reset
    add wave /dds_tb/fre_word
    add wave /dds_tb/pha_word
    add wave /dds_tb/wave_sin
    add wave /dds_tb/wave_tri  
    add wave /dds_tb/wave_saw
    add wave /dds_tb/test_phase
} result]} {
    puts "Warning: Some signals could not be added"
}

# 配置波形
configure wave -timelineunits ns
configure wave -signalnamewidth 200

# 运行仿真
run 50us

# 显示所有窗口
view *