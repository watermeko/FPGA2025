module ad9226(
    input rst_n,
    input clk,

    output adc_clk,
    input [11:0] adc_data,
    output [11:0] ad_data
);


// 时钟域同步：双触发器同步器
logic [11:0] adc_data_sync1, adc_data_sync2;

assign ad_data = adc_data_sync2;  // 直接输出，不进行位反转
assign adc_clk = ~clk;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        adc_data_sync1 <= 12'd0;     // 第一级同步器复位
        adc_data_sync2 <= 12'd0;     // 第二级同步器复位
    end else begin
        adc_data_sync1 <= adc_data;      // 第一级：直接采样ADC数据
        adc_data_sync2 <= adc_data_sync1; // 第二级：同步稳定数据
    end
end

endmodule