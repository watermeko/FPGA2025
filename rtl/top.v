module top(
        input wire clk,
        input wire rst_n,
        output wire [3:0] led
    );

    led u_led (
            .clk(clk),
            .rst_n(rst_n),
            .led(led)
        );

endmodule
