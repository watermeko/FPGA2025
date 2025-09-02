`timescale 1ns/1ns
`define CLOCK_PERIOD 20
module led_tb();
    reg clk;
    reg reset_n;
    wire [3:0] led;
    led u_led (
        .clk(clk),
        .rst_n(reset_n),
        .led(led)
    );
    initial
        clk = 1;
    always #(`CLOCK_PERIOD/2) clk = ~clk;
    initial begin
        reset_n = 1'b0;
        #(`CLOCK_PERIOD *200 + 1);
        reset_n = 1'b1;
        #2000000000;
        $stop;
    end
endmodule
