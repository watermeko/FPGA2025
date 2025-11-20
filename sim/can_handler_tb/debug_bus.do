# Debug CAN bus signals
run 180us

echo "=== At 180us (During Peer TX) ==="
echo "CAN Bus Signals:"
examine -radix bin /can_handler_tb/can_bus
examine -radix bin /can_handler_tb/handler_can_tx
examine -radix bin /can_handler_tb/handler_can_rx
examine -radix bin /can_handler_tb/peer_can_tx
examine -radix bin /can_handler_tb/peer_can_rx

echo ""
echo "Handler can_top RX path:"
examine -radix bin /can_handler_tb/u_dut/u_can_top/can_rx
examine -radix hex /can_handler_tb/u_dut/can_rx_valid
examine -radix hex /can_handler_tb/u_dut/can_rx_data

echo ""
echo "Peer can_top TX:"
examine -radix bin /can_handler_tb/u_can_peer/pkt_txing
examine -radix bin /can_handler_tb/u_can_peer/can_tx

quit -f
