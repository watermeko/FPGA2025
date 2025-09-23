//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.11.02 (64-bit) 
//Created Time: 2025-09-21 00:03:43
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
create_generated_clock -name dac_clk -source [get_ports {clk}] -master_clock clk -multiply_by 4 [get_ports {dac_clk}]
set_output_delay -clock dac_clk 2 -max [get_ports {dac_data[13] dac_data[12] dac_data[11] dac_data[10] dac_data[9] dac_data[8] dac_data[7] dac_data[6] dac_data[5] dac_data[4] dac_data[3] dac_data[2] dac_data[1] dac_data[0]}]
set_output_delay -clock dac_clk -1 -min [get_ports {dac_data[13] dac_data[12] dac_data[11] dac_data[10] dac_data[9] dac_data[8] dac_data[7] dac_data[6] dac_data[5] dac_data[4] dac_data[3] dac_data[2] dac_data[1] dac_data[0]}]
