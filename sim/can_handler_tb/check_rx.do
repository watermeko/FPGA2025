vsim -novopt work.can_handler_tb
run 179us

echo "=== Before Peer TX (179us) ==="
examine -radix bin u_dut/u_can_top/can_rx
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/rx_buf
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/rx_fall
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/inframe

run 500ns

echo ""
echo "=== During Peer TX (179.5us) ==="
examine -radix bin u_dut/u_can_top/can_rx
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/rx_buf
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/rx_fall
examine -radix bin u_dut/u_can_top/u_can_level_packet/u_can_level_bit/inframe

quit -f
