module cdc(
        input clk,
        input rst_n,

        input uart_rx,
        output uart_tx,

        output led_out
    );
    wire [7:0] rx_data_out;
    wire rx_data_valid;

    uart #(
             .CLK_FREQ  	(50_000_000  ),
             .BAUD_RATE 	(115200     ))
         u_uart(
             .clk           	(clk            ),
             .rst_n         	(rst_n          ),
             .tx_data_in    	(),
             .tx_start      	(),
             .tx_busy       	(),
             .uart_tx       	(),
             .uart_rx       	(uart_rx        ),
             .rx_data_out   	(rx_data_out    ),
             .rx_data_valid 	(rx_data_valid  )
         );

         wire parser_done,parser_error;
         wire [7:0] cmd_out;
    protocol_parser #(
                        .MAX_PAYLOAD_LEN(256)
                    ) u_parser (
                        .clk(clk),
                        .rst_n(rst_n),

                        // Input from UART module
                        .uart_rx_data(rx_data_out),
                        .uart_rx_valid(rx_data_valid),

                        // Payload read port - not used in this test, tie address to 0
                        .payload_read_addr(),
                        .payload_read_data(),

                        // Parser outputs
                        .parse_done(parser_done),
                        .parse_error(parser_error),
                        .cmd_out(cmd_out),
                        .len_out()
                    );

    
    wire parser_done_stretched;
    // output declaration of module pulse_stretcher
    
    pulse_stretcher #(
        .STRETCH_CYCLES 	(4 ))
    u_pulse_stretcher(
        .clk                 	(clk                  ),
        .rst_n               	(rst_n                ),
        .pulse_in            	(parser_done             ),
        .stretched_pulse_out 	(parser_done_stretched  )
    );
    

    

    command_processor u_command_processor(
        .clk        	(clk         ),
        .rst_n      	(rst_n       ),
        .parse_done 	(parser_done_stretched  ),
        .cmd_out    	(cmd_out     ),
        .led_out    	(led_out     )
    );
    




endmodule
