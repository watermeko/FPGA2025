# Base 50 MHz reference coming from the board
create_clock -name clk_50m -period 20.000 [get_ports {clk}]

# Clocks produced by u_pll_24 (24 MHz system)
create_clock -name clk24m -period 41.6667 [get_nets {CLK24M}]

# USB PHY PLL outputs (60 MHz UTMI / 960 MHz sampling)
create_clock -name phy_clk_60m -period 16.6667 [get_nets {PHY_CLK}]
create_clock -name usb_phy_clk -period 1.04165 [get_nets {fclk_480M}]

# Treat unrelated domains as asynchronous to suppress false CDC timing
set_clock_groups -asynchronous -group {clk_50m} -group {clk24m}
set_clock_groups -asynchronous -group {phy_clk_60m} -group {usb_phy_clk}

# Asynchronous resets
set_false_path -from [get_ports {rst_n}]

# Relax USB PHY internal paths (vendor IP with internal constraints)
set_multicycle_path -setup 2 -through [get_nets {u_usb_cdc/u_USB_SoftPHY_Top/usb2_0_softphy/u_usb_20_phy_utmi/u_usb2_0_softphy/u_usb_phy_hs/i_rx_phy/*}]
set_multicycle_path -hold 1 -through [get_nets {u_usb_cdc/u_USB_SoftPHY_Top/usb2_0_softphy/u_usb_20_phy_utmi/u_usb2_0_softphy/u_usb_phy_hs/i_rx_phy/*}]
