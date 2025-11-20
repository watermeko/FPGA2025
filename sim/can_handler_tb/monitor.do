run 2.5us
echo "=== At 2.5us (after config) ==="
examine -radix hex /can_handler_tb/u_dut/rx_id_short_filter
examine -radix hex /can_handler_tb/u_dut/local_id

run 177.5us
echo "=== At 180us (Peer about to send) ==="
examine -radix hex /can_handler_tb/u_dut/rx_id_short_filter
examine -radix hex /can_handler_tb/u_dut/local_id
examine -radix hex /can_handler_tb/u_dut/u_can_top/rx_filter_short_actual
examine -radix hex /can_handler_tb/u_dut/u_can_top/local_id_actual

quit -f
