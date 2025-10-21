# Base 50 MHz reference coming from the board
create_clock -name clk_50m -period 20.000 [get_ports {clk}]

# External RGMII receive clock (125 MHz DDR)
create_clock -name rgmii_rx_clk -period 8.000 [get_ports {rgmii_rx_clk_i}]

# Clocks produced by u_pll_24 (24 MHz system)
create_clock -name clk24m -period 41.6667 [get_nets {CLK24M}]

# USB PHY PLL outputs (60 MHz UTMI / 960 MHz sampling)
create_clock -name phy_clk_60m -period 16.6667 [get_nets {PHY_CLK}]
create_clock -name usb_phy_clk -period 1.04165 [get_nets {fclk_480M}]

# DDR3 reference PLL running at 400 MHz
create_clock -name ddr_ref_clk -period 2.500 [get_nets {ad_ddr_clk_400m}]

# Treat unrelated clock domains as asynchronous to avoid spurious cross-domain timing violations.
set_clock_groups -asynchronous -group [get_clocks {clk_50m clk24m ddr_ref_clk}] -group [get_clocks {phy_clk_60m usb_phy_clk}]
set_clock_groups -asynchronous -group [get_clocks {clk_50m clk24m ddr_ref_clk}] -group [get_clocks {rgmii_rx_clk}]
set_clock_groups -asynchronous -group [get_clocks {phy_clk_60m usb_phy_clk}] -group [get_clocks {rgmii_rx_clk}]

# Asynchronous resets
set_false_path -from [get_ports {rst_n}]
