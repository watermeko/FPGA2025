# 退出上次仿真
quit -sim

# 清理并重新创建工作库
# vdel -lib work -all
vlib work
vmap work work

# 使用SystemVerilog编译选项
vlog -sv ../../rtl/logic/*.sv
vlog -sv ../../tb/dsm_multichannel_tb.sv

# 开始仿真 (使用voptargs保持信号可见性)
vsim work.dsm_multichannel_tb -voptargs="+acc"

# 清除之前的波形
delete wave *

# 添加时钟和复位信号
add wave -noupdate -group "Clock & Reset" -color Yellow /dsm_multichannel_tb/clk
add wave -noupdate -group "Clock & Reset" -color Red /dsm_multichannel_tb/rst_n

# 添加控制信号 (以二进制格式显示)
add wave -noupdate -group "Control Signals" -radix binary /dsm_multichannel_tb/measure_start
add wave -noupdate -group "Control Signals" -radix binary /dsm_multichannel_tb/measure_pin
add wave -noupdate -group "Control Signals" -radix binary /dsm_multichannel_tb/measure_done

# 添加打包的输出信号 (以十六进制显示)
add wave -noupdate -group "Packed Outputs" -radix hexadecimal /dsm_multichannel_tb/high_time
add wave -noupdate -group "Packed Outputs" -radix hexadecimal /dsm_multichannel_tb/low_time
add wave -noupdate -group "Packed Outputs" -radix hexadecimal /dsm_multichannel_tb/period_time
add wave -noupdate -group "Packed Outputs" -radix hexadecimal /dsm_multichannel_tb/duty_cycle

# 添加解包后的信号数组 (十进制显示)
add wave -noupdate -group "Unpacked Results" -radix decimal /dsm_multichannel_tb/high_time_ch
add wave -noupdate -group "Unpacked Results" -radix decimal /dsm_multichannel_tb/low_time_ch
add wave -noupdate -group "Unpacked Results" -radix decimal /dsm_multichannel_tb/period_time_ch
add wave -noupdate -group "Unpacked Results" -radix decimal /dsm_multichannel_tb/duty_cycle_ch

# 添加DUT内部信号阵列
add wave -noupdate -group "DUT Internal Arrays" -radix decimal /dsm_multichannel_tb/dut/high_time_array
add wave -noupdate -group "DUT Internal Arrays" -radix decimal /dsm_multichannel_tb/dut/low_time_array
add wave -noupdate -group "DUT Internal Arrays" -radix decimal /dsm_multichannel_tb/dut/period_time_array
add wave -noupdate -group "DUT Internal Arrays" -radix decimal /dsm_multichannel_tb/dut/duty_cycle_array

# 添加各个通道的详细信号 (使用安全的路径检查)
for {set i 0} {$i < 8} {incr i} {
    # 每个通道的输入信号
    add wave -noupdate -group "Channel $i Signals" -color Cyan -radix binary /dsm_multichannel_tb/measure_start\[$i\]
    add wave -noupdate -group "Channel $i Signals" -color Green -radix binary /dsm_multichannel_tb/measure_pin\[$i\]
    add wave -noupdate -group "Channel $i Signals" -color Orange -radix binary /dsm_multichannel_tb/measure_done\[$i\]
    
    # 每个通道的输出结果 (十进制显示)
    add wave -noupdate -group "Channel $i Results" -radix decimal /dsm_multichannel_tb/high_time_ch\[$i\]
    add wave -noupdate -group "Channel $i Results" -radix decimal /dsm_multichannel_tb/low_time_ch\[$i\]
    add wave -noupdate -group "Channel $i Results" -radix decimal /dsm_multichannel_tb/period_time_ch\[$i\]
    add wave -noupdate -group "Channel $i Results" -radix decimal /dsm_multichannel_tb/duty_cycle_ch\[$i\]
    
    # 尝试添加内部状态机信号 (可能需要根据实际模块调整路径)
    # 使用 catch 命令来避免路径错误导致脚本中断
    catch {
        add wave -noupdate -group "Channel $i Internal" -radix binary /dsm_multichannel_tb/dut/dsm_instances\[$i\]/dsm_inst/state
        add wave -noupdate -group "Channel $i Internal" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[$i\]/dsm_inst/high_counter
        add wave -noupdate -group "Channel $i Internal" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[$i\]/dsm_inst/low_counter
        add wave -noupdate -group "Channel $i Internal" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[$i\]/dsm_inst/period_counter
    }
}

# 尝试添加所有DUT实例的内部信号 (批量方式)
catch {
    add wave -noupdate -group "All DSM Instances" -radix binary /dsm_multichannel_tb/dut/dsm_instances\[*\]/dsm_inst/state
    add wave -noupdate -group "All DSM Instances" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[*\]/dsm_inst/high_counter
    add wave -noupdate -group "All DSM Instances" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[*\]/dsm_inst/low_counter
    add wave -noupdate -group "All DSM Instances" -radix decimal /dsm_multichannel_tb/dut/dsm_instances\[*\]/dsm_inst/period_counter
}

# 配置波形显示 (使用兼容的选项)
catch { configure wave -namecolwidth 300 }
catch { configure wave -valuecolwidth 100 }
catch { configure wave -justifyvalue left }
catch { configure wave -signalnamewidth 1 }
catch { configure wave -snapdistance 10 }
catch { configure wave -datasetprefix 0 }
catch { configure wave -rowmargin 4 }
catch { configure wave -childrowmargin 2 }
catch { configure wave -gridoffset 0 }
catch { configure wave -gridperiod 1000 }
catch { configure wave -griddelta 40 }
catch { configure wave -timeline 0 }
catch { configure wave -timelineunits ns }

# 移除不兼容的颜色配置选项
# configure wave -backgroundcolor {#FFFFFF}
# configure wave -textcolor {#000000}  
# configure wave -vectorcolor {#0000FF}

# 展开重要的信号组
catch { wave expand "Clock & Reset" }
catch { wave expand "Control Signals" }
catch { wave expand "Channel 0 Signals" }
catch { wave expand "Channel 0 Results" }
catch { wave expand "Unpacked Results" }

# 运行仿真前先检查设计
echo "Checking design hierarchy..."
catch { describe /dsm_multichannel_tb/dut }

# 运行仿真
echo "Starting simulation..."
run 100us

# 优化波形显示
catch { wave zoom full }
catch { wave cursor time 0 }

# 设置一些有用的书签
catch {
    bookmark add "Reset Release" 500ns
    bookmark add "First Test Start" 1us
    bookmark add "Single Channel Tests" 10us
    bookmark add "Multi Channel Test" 50us
    bookmark add "Test Complete" 90us
}

# 显示所有窗口
view *

# 打印仿真信息和可用信号
echo ""
echo "=========================================="
echo "Simulation completed successfully!"
echo "Wave window configured with signal groups"
echo "Total simulation time: 100us"
echo "=========================================="
echo ""
echo "Available Signal Groups:"
echo "- Clock & Reset: Basic timing signals"
echo "- Control Signals: Start/done/pin signals (packed)" 
echo "- Packed Outputs: Combined output vectors"
echo "- Unpacked Results: Individual channel results as arrays"
echo "- Channel X Signals: Individual channel I/O signals"
echo "- Channel X Results: Individual channel measurement results"
echo "- DUT Internal Arrays: Internal signal arrays"
echo "- Channel X Internal: Internal state (if available)"
echo ""

# 显示设计层次信息
echo "Design Hierarchy:"
echo "=================="
catch { describe /dsm_multichannel_tb/dut }

echo ""
echo "Simulation ready! Use 'run <time>' to continue simulation."
echo "Example: run 50us"

# 手动设置一些基本的显示格式
echo ""
echo "Manual Wave Configuration Tips:"
echo "- Right-click on wave window to change display options"
echo "- Use View->Zoom->Zoom Full to fit waveforms"
echo "- Use Edit->Select All, then right-click to change radix for multiple signals"
echo ""

# 自动保存波形配置 (可选)
catch { write format wave -window .main_pane.wave.interior.cs.body.pw.wf dsm_wave_config.do }

# 显示可用的波形操作命令
echo "Useful wave commands:"
echo "- wave zoom full"
echo "- wave cursor time <time_value>"
echo "- run <additional_time>"
echo "- restart -f"