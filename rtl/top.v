module top(
        input wire clk,
        input wire rst_n,
        
        // USB CDC相关端口
        inout      usb_dxp_io,
        inout      usb_dxn_io,
        input      usb_rxdp_i,
        input      usb_rxdn_i,
        output     usb_pullup_en_o,
        inout      usb_term_dp_io,
        inout      usb_term_dn_io,
        
        output wire [3:0] led,
        output   wire  [7:0]     pwm_pins      // 8-channel PWM output pins
    );

    // USB CDC到CDC模块的数据连接
    wire [7:0] usb_data;
    wire       usb_data_valid;
    wire       usb_cdc_led;
    wire       cdc_led_out;

    wire PHY_CLK;
    // 实例化USB_CDC模块
    USB_CDC u_usb_cdc(
        .CLK_IN(clk),
        .PHY_CLKOUT_o(PHY_CLK),
        .LED(usb_cdc_led),
        .usb_dxp_io(usb_dxp_io),
        .usb_dxn_io(usb_dxn_io),
        .usb_rxdp_i(usb_rxdp_i),
        .usb_rxdn_i(usb_rxdn_i),
        .usb_pullup_en_o(usb_pullup_en_o),
        .usb_term_dp_io(usb_term_dp_io),
        .usb_term_dn_io(usb_term_dn_io),
        .usb_data_out(usb_data),
        .usb_data_valid_out(usb_data_valid)
    );

    // 实例化CDC模块
    cdc u_cdc(
        .clk(PHY_CLK),
        .rst_n(rst_n),
        .usb_data_in(usb_data),
        .usb_data_valid_in(usb_data_valid),
        .led_out(cdc_led_out),
        .pwm_pins(pwm_pins)
    );

    // LED输出
    assign led[0] = cdc_led_out;
    assign led[1] = usb_cdc_led;
    assign led[3:2] = 2'b00;

endmodule
