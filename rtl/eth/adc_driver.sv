module adc_driver (
    input  wire        clk_ddr,          // Clock driving ODDR outputs
    input  wire        clk_sample,       // Sampling clock for IDDR and registers
    input  wire [13:0] adc_data_in,      // ADC differential data input
    output wire        adc_clk_out,      // Forwarded ADC clock
    output wire        mux_select_out,   // ADC mux select signal
    output reg  [13:0] adc_data_a,       // Registered even-sample data
    output reg  [13:0] adc_data_b        // Registered odd-sample data
);

// Forward the ADC sample clock using an ODDR primitive
ODDR adc_clk_forward (
    .Q0(adc_clk_out),
    .Q1(),
    .D0(1'b1),
    .D1(1'b0),
    .TX(1'b0),
    .CLK(clk_ddr)
);
defparam adc_clk_forward.TXCLK_POL = 1'b0;
defparam adc_clk_forward.INIT = 1'b0;

// Generate the mux select signal using a second ODDR
ODDR adc_mux_select (
    .Q0(mux_select_out),
    .Q1(),
    .D0(1'b1),
    .D1(1'b0),
    .TX(1'b0),
    .CLK(clk_ddr)
);
defparam adc_mux_select.TXCLK_POL = 1'b0;
defparam adc_mux_select.INIT = 1'b0;

// Capture double data rate ADC inputs
wire [13:0] adc_data_a_ddr;
wire [13:0] adc_data_b_ddr;

genvar i;
generate
    for (i = 0; i < 14; i = i + 1) begin : iddr_gen
        IDDR adc_iddr (
            .Q0(adc_data_a_ddr[i]),
            .Q1(adc_data_b_ddr[i]),
            .D(adc_data_in[i]),
            .CLK(clk_sample)
        );
        defparam adc_iddr.Q0_INIT = 1'b0;
        defparam adc_iddr.Q1_INIT = 1'b0;
    end
endgenerate

// Register the IDDR outputs to ease timing closure
always @(posedge clk_sample) begin
    adc_data_a <= adc_data_a_ddr;
    adc_data_b <= adc_data_b_ddr;
end

endmodule
