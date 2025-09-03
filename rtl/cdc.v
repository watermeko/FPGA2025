module cdc(
        input clk,
        input rst_n,

        input uart_rx,
        output uart_tx,

        output led_out,
        output    [7:0]     pwm_pins      // 8-channel PWM output pins
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
    parameter PAYLOAD_ADDR_WIDTH=$clog2(256);
    wire [7:0] payload_read_data;
    wire [PAYLOAD_ADDR_WIDTH-1:0] payload_read_addr;
    protocol_parser #(
                        .MAX_PAYLOAD_LEN(256)
                    ) u_parser (
                        .clk(clk),
                        .rst_n(rst_n),

                        // Input from UART module
                        .uart_rx_data(rx_data_out),
                        .uart_rx_valid(rx_data_valid),

                        // Payload read port - not used in this test, tie address to 0
                        .payload_read_addr(payload_read_addr),
                        .payload_read_data(payload_read_data),

                        // Parser outputs
                        .parse_done(parser_done),
                        .parse_error(parser_error),
                        .cmd_out(cmd_out),
                        .len_out()
                    );


    wire parser_done_stretched;
    // output declaration of module pulse_stretcher

    pulse_stretcher #(
                        .STRETCH_CYCLES 	(4 )) // ! whether to reduce?
                    u_pulse_stretcher(
                        .clk                 	(clk                  ),
                        .rst_n               	(rst_n                ),
                        .pulse_in            	(parser_done             ),
                        .stretched_pulse_out 	(parser_done_stretched  )
                    );




    // command_processor #(
    //     .PAYLOAD_ADDR_WIDTH(PAYLOAD_ADDR_WIDTH)
    // )u_command_processor(
    //     .clk        	(clk         ),
    //     .rst_n      	(rst_n       ),
    //     .parse_done 	(parser_done_stretched  ),
    //     .cmd_out    	(cmd_out     ),
    //     .led_out    	(led_out     ),
    //     .payload_read_addr(),
    //     .payload_read_data(payload_read_data)
    // );

    // 4. Command Processor: Acts on parsed commands (the "brain")
    wire [2:0]  pwm_ch_index;
    wire [15:0] pwm_period;
    wire [15:0] pwm_duty;
    wire        pwm_update_strobe;
    command_processor #(
                          .PAYLOAD_ADDR_WIDTH(PAYLOAD_ADDR_WIDTH)
                      ) u_command_processor (
                          .clk(clk),
                          .rst_n(rst_n),
                          .parse_done(parser_done_stretched),
                          .cmd_out(cmd_out),
                          .payload_read_data(payload_read_data),
                          .led_out(led_out),
                          .payload_read_addr(payload_read_addr),
                          .pwm_config_ch_index_out(pwm_ch_index),
                          .pwm_config_period_out(pwm_period),
                          .pwm_config_duty_out(pwm_duty),
                          .pwm_config_update_strobe(pwm_update_strobe)
                      );


    // 5. Multi-Channel PWM Generator: The hardware that generates PWM waves
    pwm_multi_channel #(
                          .NUM_CHANNELS(8),
                          .COUNTER_WIDTH(16)
                      ) u_pwm_multi (
                          .clk(clk),
                          .rst_n(rst_n),
                          .config_ch_index_in(pwm_ch_index),
                          .config_period_in(pwm_period),
                          .config_duty_in(pwm_duty),
                          .config_update_strobe(pwm_update_strobe),
                          .pwm_out_vector(pwm_pins)
                      );



endmodule
