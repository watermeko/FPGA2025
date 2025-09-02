module top(
        input wire clk,
        input wire rst_n,

        input uart_rx,
        output uart_tx,
        output wire [3:0] led
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
        .led_out 	(led_out  )
);

assign led[0] = led_out;

endmodule
