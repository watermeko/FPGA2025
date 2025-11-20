vsim -novopt work.can_handler_tb
run 180us
run 10us

echo "=== After Peer TX (190us) ===" 
echo "Packet level signals:"
examine -radix bin u_dut/u_can_top/u_can_level_packet/pkt_rx_valid
examine -radix hex u_dut/u_can_top/u_can_level_packet/pkt_rx_id
examine -radix bin u_dut/u_can_top/u_can_level_packet/pkt_rx_ide

echo ""
echo "Top level RX:"
examine -radix bin u_dut/u_can_top/pkt_rx_valid
examine -radix hex u_dut/u_can_top/pkt_rx_id
examine -radix bin u_dut/u_can_top/pkt_rx_ack

quit -f
