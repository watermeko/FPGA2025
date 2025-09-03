module top(
        input wire clk,
        input wire rst_n,

        input uart_rx,
        output uart_tx,
        output wire [3:0] led,
        output   wire  [7:0]     pwm_pins      // 8-channel PWM output pins
    );

    //     led u_led (
    //             .clk(clk),
    //             .rst_n(rst_n),
    //             .led(led)
    //         );

    // output declaration of module cdc
    wire led_out;
    cdc u_cdc(
            .clk     	(clk      ),
            .rst_n   	(rst_n    ),
            .uart_rx 	(uart_rx  ),
            .uart_tx 	(),
            .led_out 	(led_out  ),
            .pwm_pins    (pwm_pins    )
        );

    assign led[0] = led_out;

endmodule
