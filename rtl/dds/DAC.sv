module DAC(
    input clk,
    input rst_n,

    input [31:0] fre_word,
    input [31:0] pha_word,
    input [1:0]  wave_type,     // 波形类型选择：0=正弦波，1=三角波，2=锯齿波，3=方波

    output [13:0] dac_data
);

// 200MHz clk
// 1MHz, 0 deg (适合示波器观测的频率)
// 计算：fre_word = (目标频率 × 2^32) / DAC时钟频率
// fre_word = (1MHz × 2^32) / 200MHz = 21474836
// logic [31:0] fre_word = 32'd214748365;  // 1MHz方波
// logic [31:0] pha_word = 32'd00000000;  //


logic [13:0] wave_sin;
logic [13:0] wave_tri;
logic [13:0] wave_saw;
logic [13:0] wave_sqr;

logic [13:0] dac_data_internal;
reg [13:0] dac_data_reg;

// 根据wave_type选择输出波形
always_comb begin
    case (wave_type)
        2'b00: dac_data_internal = wave_sin;  // 正弦波
        2'b01: dac_data_internal = wave_tri;  // 三角波
        2'b10: dac_data_internal = wave_saw;  // 锯齿波
        2'b11: dac_data_internal = wave_sqr;  // 方波
        default: dac_data_internal = wave_sin; // 默认正弦波
    endcase
end

// 在DAC模块中添加输出寄存器
always @(negedge clk) begin
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
    .clock    	(clk     ),
    .reset    	(~rst_n     ),
    .fre_word 	(fre_word  ),
    .pha_word 	(pha_word  ),
    .wave_sin 	(wave_sin  ),
    .wave_tri 	(wave_tri  ),
    .wave_saw 	(wave_saw  ),
    .wave_sqr   (wave_sqr  )
);


endmodule