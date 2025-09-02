module led(
        input wire clk,
        input wire rst_n,
        output reg [3:0] led
    );

parameter CNT_MAX = 24_999_999; 
reg [24:0] counter;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        counter <= 0;
    end
    else if (counter == CNT_MAX) begin
        counter <= 0;
    end 
    else begin
        counter <= counter + 1;
    end
end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            led <= 4'b0000;
        end
        else if (counter == CNT_MAX) begin
            led <= led + 1;
        end
    end

endmodule
