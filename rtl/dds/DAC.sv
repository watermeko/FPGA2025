module DAC(
    input clk,
    input rst_n,

    // input [31:0] fre_word,
    // input [31:0] pha_word,

    output [13:0] dac_data,
    output dac_clk
);

// logic clk100m;
// 	SSCPLL_Top your_instance_name(
// 		.clkin(clk), //input clkin
// 		.rstn(rst_n), //input rstn
// 		.clkout(clk100m) //output clkout
// 	);
    Gowin_PLL your_instance_name(
        .clkin(clk), //input  clkin
        .clkout0(clk100m), //output  clkout0
        // .mdclk(mdclk), //input  mdclk
        .reset(~rst_n) //input  reset
);
assign dac_clk = clk100m;
// 200MHz dac_clk
// 10MHz, 0 deg
logic [31:0] fre_word = 32'd214748365;
logic [31:0] pha_word = 32'd00000000;  //


logic [13:0] wave_sin;
logic [13:0] wave_tri;
logic [13:0] wave_saw;

logic [13:0] dac_data_internal;
 reg [13:0] dac_data_reg;

assign dac_data_internal = wave_saw;

// 在DAC模块中添加输出寄存器
always @(negedge dac_clk) begin
    if (!rst_n) begin
        dac_data_reg <= 14'b0;
    end else begin
        dac_data_reg <= dac_data_internal;
    end
end

assign dac_data = dac_data_reg;

DDS #(
    .OUTPUT_WIDTH 	(14  ),
    .PHASE_WIDTH  	(32  ))
u_DDS(
    .clock    	(dac_clk     ),
    .reset    	(~rst_n     ),
    .fre_word 	(fre_word  ),
    .pha_word 	(pha_word  ),
    .wave_sin 	(wave_sin  ),
    .wave_tri 	(wave_tri  ),
    .wave_saw 	(wave_saw  )
);


endmodule