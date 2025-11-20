vsim -novopt work.can_handler_tb
run 180us

echo "=== At 180us (During Peer TX) ==="
echo "CAN Bus Signals:"
examine -radix bin can_bus
examine -radix bin handler_can_tx  
examine -radix bin handler_can_rx
examine -radix bin peer_can_tx
examine -radix bin peer_can_rx

quit -f
