# ==============================================================================
# GOWIN GW5A 仿真库编译脚本
# ==============================================================================

echo "开始编译 GOWIN GW5A 仿真库..."
echo "这可能需要几分钟时间..."

# 创建 gw5a 库
vlib gw5a
vmap gw5a gw5a

# 编译 VHDL 原语
echo "正在编译 VHDL 原语..."
vcom -work gw5a E:/GOWIN/Gowin_V1.9.9_x64/IDE/simlib/gw5a/prim_sim.vhd

# 编译 Verilog 原语
echo "正在编译 Verilog 原语..."
vlog -work gw5a E:/GOWIN/Gowin_V1.9.9_x64/IDE/simlib/gw5a/prim_sim.v

echo ""
echo "===================================="
echo "GOWIN GW5A 库编译完成！"
echo "库位置: ./gw5a"
echo "===================================="
echo ""
echo "现在可以运行 CDC_US 仿真了："
echo "  do cmd_cdc_us.do"
