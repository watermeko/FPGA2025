onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group {Clock & Reset} -color Yellow /dsm_multichannel_tb/clk
add wave -noupdate -group {Clock & Reset} -color Red /dsm_multichannel_tb/rst_n
add wave -noupdate -group {Control Signals} -radix binary /dsm_multichannel_tb/measure_start
add wave -noupdate -group {Control Signals} -radix binary /dsm_multichannel_tb/measure_pin
add wave -noupdate -group {Control Signals} -radix binary /dsm_multichannel_tb/measure_done
add wave -noupdate -group {Packed Outputs} -radix hexadecimal /dsm_multichannel_tb/high_time
add wave -noupdate -group {Packed Outputs} -radix hexadecimal /dsm_multichannel_tb/low_time
add wave -noupdate -group {Packed Outputs} -radix hexadecimal /dsm_multichannel_tb/period_time
add wave -noupdate -group {Packed Outputs} -radix hexadecimal /dsm_multichannel_tb/duty_cycle
add wave -noupdate -group {Unpacked Results} -radix decimal /dsm_multichannel_tb/high_time_ch
add wave -noupdate -group {Unpacked Results} -radix decimal /dsm_multichannel_tb/low_time_ch
add wave -noupdate -group {Unpacked Results} -radix decimal /dsm_multichannel_tb/period_time_ch
add wave -noupdate -group {Unpacked Results} -radix decimal /dsm_multichannel_tb/duty_cycle_ch
add wave -noupdate -group {DUT Internal Arrays} -radix decimal /dsm_multichannel_tb/dut/high_time_array
add wave -noupdate -group {DUT Internal Arrays} -radix decimal /dsm_multichannel_tb/dut/low_time_array
add wave -noupdate -group {DUT Internal Arrays} -radix decimal /dsm_multichannel_tb/dut/period_time_array
add wave -noupdate -group {DUT Internal Arrays} -radix decimal /dsm_multichannel_tb/dut/duty_cycle_array
add wave -noupdate -group {Channel 0 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[0]}
add wave -noupdate -group {Channel 0 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[0]}
add wave -noupdate -group {Channel 0 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[0]}
add wave -noupdate -group {Channel 0 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[0]}
add wave -noupdate -group {Channel 0 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[0]}
add wave -noupdate -group {Channel 0 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[0]}
add wave -noupdate -group {Channel 0 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[0]}
add wave -noupdate -group {Channel 0 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[0]/dsm_inst/state}
add wave -noupdate -group {Channel 0 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[0]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 0 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[0]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 0 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[0]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 1 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[1]}
add wave -noupdate -group {Channel 1 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[1]}
add wave -noupdate -group {Channel 1 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[1]}
add wave -noupdate -group {Channel 1 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[1]}
add wave -noupdate -group {Channel 1 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[1]}
add wave -noupdate -group {Channel 1 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[1]}
add wave -noupdate -group {Channel 1 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[1]}
add wave -noupdate -group {Channel 1 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[1]/dsm_inst/state}
add wave -noupdate -group {Channel 1 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[1]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 1 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[1]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 1 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[1]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 2 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[2]}
add wave -noupdate -group {Channel 2 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[2]}
add wave -noupdate -group {Channel 2 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[2]}
add wave -noupdate -group {Channel 2 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[2]}
add wave -noupdate -group {Channel 2 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[2]}
add wave -noupdate -group {Channel 2 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[2]}
add wave -noupdate -group {Channel 2 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[2]}
add wave -noupdate -group {Channel 2 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[2]/dsm_inst/state}
add wave -noupdate -group {Channel 2 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[2]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 2 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[2]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 2 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[2]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 3 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[3]}
add wave -noupdate -group {Channel 3 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[3]}
add wave -noupdate -group {Channel 3 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[3]}
add wave -noupdate -group {Channel 3 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[3]}
add wave -noupdate -group {Channel 3 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[3]}
add wave -noupdate -group {Channel 3 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[3]}
add wave -noupdate -group {Channel 3 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[3]}
add wave -noupdate -group {Channel 3 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[3]/dsm_inst/state}
add wave -noupdate -group {Channel 3 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[3]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 3 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[3]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 3 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[3]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 4 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[4]}
add wave -noupdate -group {Channel 4 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[4]}
add wave -noupdate -group {Channel 4 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[4]}
add wave -noupdate -group {Channel 4 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[4]}
add wave -noupdate -group {Channel 4 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[4]}
add wave -noupdate -group {Channel 4 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[4]}
add wave -noupdate -group {Channel 4 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[4]}
add wave -noupdate -group {Channel 4 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[4]/dsm_inst/state}
add wave -noupdate -group {Channel 4 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[4]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 4 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[4]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 4 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[4]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 5 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[5]}
add wave -noupdate -group {Channel 5 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[5]}
add wave -noupdate -group {Channel 5 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[5]}
add wave -noupdate -group {Channel 5 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[5]}
add wave -noupdate -group {Channel 5 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[5]}
add wave -noupdate -group {Channel 5 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[5]}
add wave -noupdate -group {Channel 5 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[5]}
add wave -noupdate -group {Channel 5 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[5]/dsm_inst/state}
add wave -noupdate -group {Channel 5 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[5]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 5 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[5]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 5 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[5]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 6 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[6]}
add wave -noupdate -group {Channel 6 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[6]}
add wave -noupdate -group {Channel 6 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[6]}
add wave -noupdate -group {Channel 6 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[6]}
add wave -noupdate -group {Channel 6 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[6]}
add wave -noupdate -group {Channel 6 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[6]}
add wave -noupdate -group {Channel 6 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[6]}
add wave -noupdate -group {Channel 6 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[6]/dsm_inst/state}
add wave -noupdate -group {Channel 6 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[6]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 6 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[6]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 6 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[6]/dsm_inst/period_counter}
add wave -noupdate -group {Channel 7 Signals} -color Cyan -radix binary {/dsm_multichannel_tb/measure_start[7]}
add wave -noupdate -group {Channel 7 Signals} -color Green -radix binary {/dsm_multichannel_tb/measure_pin[7]}
add wave -noupdate -group {Channel 7 Signals} -color Orange -radix binary {/dsm_multichannel_tb/measure_done[7]}
add wave -noupdate -group {Channel 7 Results} -radix decimal {/dsm_multichannel_tb/high_time_ch[7]}
add wave -noupdate -group {Channel 7 Results} -radix decimal {/dsm_multichannel_tb/low_time_ch[7]}
add wave -noupdate -group {Channel 7 Results} -radix decimal {/dsm_multichannel_tb/period_time_ch[7]}
add wave -noupdate -group {Channel 7 Results} -radix decimal {/dsm_multichannel_tb/duty_cycle_ch[7]}
add wave -noupdate -group {Channel 7 Internal} -radix binary {/dsm_multichannel_tb/dut/dsm_instances[7]/dsm_inst/state}
add wave -noupdate -group {Channel 7 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[7]/dsm_inst/high_counter}
add wave -noupdate -group {Channel 7 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[7]/dsm_inst/low_counter}
add wave -noupdate -group {Channel 7 Internal} -radix decimal {/dsm_multichannel_tb/dut/dsm_instances[7]/dsm_inst/period_counter}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 300
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1000
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {105 us}
