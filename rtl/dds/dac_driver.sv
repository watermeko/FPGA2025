module dac_driver (
    input  wire        clk_dac,          // DAC clock domain
    input  wire [13:0] dac_data_a_in,    // Even-sample data from ADC domain
    input  wire [13:0] dac_data_b_in,    // Odd-sample data from ADC domain
    output wire [13:0] dac_data_a_out,   // Registered data forwarded to DAC channel A
    output wire [13:0] dac_data_b_out,   // Registered data forwarded to DAC channel B
    output wire        dac_clk_a_out,    // Forwarded DAC clock for channel A
    output wire        dac_clk_b_out     // Forwarded DAC clock for channel B
);

// Register incoming data on the DAC clock domain (two-stage pipeline)
reg [13:0] dac_data_a_reg;
reg [13:0] dac_data_b_reg;
reg [13:0] dac_data_a_reg2;
reg [13:0] dac_data_b_reg2;

always @(posedge clk_dac) begin
    dac_data_a_reg <= dac_data_a_in;
    dac_data_b_reg <= dac_data_b_in;
    dac_data_a_reg2 <= dac_data_a_reg;
    dac_data_b_reg2 <= dac_data_b_reg;
end

assign dac_data_a_out = dac_data_a_reg2;
assign dac_data_b_out = dac_data_b_reg2;

// Generate DAC clocks using ODDR primitives
ODDR dac_clk_a_forward (
    .Q0(dac_clk_a_out),
    .Q1(),
    .D0(1'b1),
    .D1(1'b0),
    .TX(1'b0),
    .CLK(clk_dac)
);
defparam dac_clk_a_forward.TXCLK_POL = 1'b0;
defparam dac_clk_a_forward.INIT = 1'b0;

ODDR dac_clk_b_forward (
    .Q0(dac_clk_b_out),
    .Q1(),
    .D0(1'b1),
    .D1(1'b0),
    .TX(1'b0),
    .CLK(clk_dac)
);
defparam dac_clk_b_forward.TXCLK_POL = 1'b0;
defparam dac_clk_b_forward.INIT = 1'b0;

endmodule
