/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date   : 2019/05/01 00:00:00
// Module Name   : ad9226_12bit_to_16bit
// Description   : 将ADC采集数据进行有符号数位宽扩展
// 
// Dependencies  : 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
/////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
module ad9238_12bit_to_16bit(
  clk,
  reset_n,
  ad_data_en,
  ch_sel,
  adc_clk_out,
  adc_data_in,
  ad_out,
  ad_out_valid,
  adc_mux_select,
  adc_sample_clk
);

  input clk;
  input reset_n;
  input [1:0]ch_sel;
  output adc_clk_out;
  input adc_sample_clk;
  input[13:0] adc_data_in;
  input ad_data_en;

  output adc_mux_select;
  
  output[15:0] ad_out;
  output ad_out_valid;
  reg[15:0] ad_out;
  reg ad_out_valid;

  // AD9266 instantiation for channel 1
  // wire [11:0] ad_in1;
  // ad9226 u_ad9226(
  //   .rst_n(reset_n),
  //   .clk(clk),
  //   .adc_clk(adc_clk),
  //   .adc_data(adc_data_ch1),
  //   .ad_data(ad_in1)
  // );
  
    wire [13:0] adc_data_a;
    wire [13:0] adc_data_b;

    wire signed [13:0] ad_in1;
    wire signed [13:0] ad_in2;

    assign ad_in1 = adc_data_a;
    assign ad_in2 = adc_data_b;

    adc_driver u_adc_driver (
        .clk_ddr        (clk),
        .clk_sample     (adc_sample_clk),
        .adc_data_in    (adc_data_in),
        .adc_clk_out    (adc_clk_out),
        .mux_select_out (adc_mux_select),
        .adc_data_a     (adc_data_a),
        .adc_data_b     (adc_data_b)
    );
  //用于仿真或产生测试数据，可在通过添加`define SIM 进行宏定义
  reg [13:0] adc_test_data;
  reg [13:0] pair_sample;
  reg [13:0] next_sample;
  reg        pair_valid;
  reg        dual_phase;

  function [13:0] offset_binary;
    input signed [13:0] signed_val;
    begin
        offset_binary = signed_val + 14'h2000;
    end
  endfunction

  function [13:0] negate_sample;
    input signed [13:0] signed_val;
    begin
        negate_sample = -negate_sample;
    end
  endfunction

  always @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
      ad_out <= 16'd0;
      ad_out_valid <= 1'b0;
      adc_test_data <= 14'd0;
      pair_sample <= 14'd0;
      dual_phase <= 1'b0;
      pair_valid <= 1'b0;
      next_sample <= 14'd0;
    end else begin
      ad_out_valid <= 1'b0;

      if(ad_data_en)
        adc_test_data <= adc_test_data + 1'b1;
      else
        adc_test_data <= 14'd0;

      if(ad_data_en) begin
        case(ch_sel)
          2'b00: begin
            ad_out <= {2'b00, adc_test_data};
            ad_out_valid <= 1'b1;
            pair_valid <= 1'b0;
            dual_phase <= 1'b0;
          end
          2'b01: begin
            ad_out <= {2'b00, ad_in1};
            ad_out_valid <= 1'b1;
            pair_valid <= 1'b0;
            dual_phase <= 1'b0;
          end
          2'b10: begin
            ad_out <= {2'b00, ad_in2};
            ad_out_valid <= 1'b1;
            pair_valid <= 1'b0;
            dual_phase <= 1'b0;
          end
          2'b11: begin
            if(!pair_valid) begin
              pair_sample <= ad_in1;
              next_sample <= ad_in2;
              pair_valid <= 1'b1;
              dual_phase <= 1'b0;
            end else begin
              if(!dual_phase) begin
                ad_out <= {2'b00, pair_sample};
                ad_out_valid <= 1'b1;
                dual_phase <= 1'b1;
              end else begin
                ad_out <= {2'b00, next_sample};
                ad_out_valid <= 1'b1;
                pair_valid <= 1'b0; // Pair sent, ready for next capture
              end
            end
          end
          default: begin
            ad_out <= {2'b00, ad_in1};
            ad_out_valid <= 1'b1;
            dual_phase <= 1'b0;
          end
        endcase
      end
    end
  end
	 
endmodule
