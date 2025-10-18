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
        output   wire  [7:0]     pwm_pins,     // 8-channel PWM output pins
        input ext_uart_rx,
        output ext_uart_tx,

        output cdc_debug_signal,

        output       spi_clk,
        output       spi_cs_n,
        output       spi_mosi,
        input        spi_miso,

        // DSM 数字信号测量输入（8通道）
        input [7:0]  dsm_signal_in,

        // Digital Capture 数字逻辑捕获输入（8通道）
        input [7:0]  dc_signal_in,

        // I2C Interface
        output       i2c_scl,
        inout        i2c_sda,

        output [13:0] dac_data,
        output dac_clk

    );

    // 时钟相关信号
    wire CLK24M;
    wire fclk_480M;
    wire clk200m;
    wire PHY_CLK;
    wire pll_locked;
    wire system_rst_n;  // 系统复位信号
    


    // USB CDC到CDC模块的数据连接
    wire [7:0] usb_data;
    wire       usb_data_valid;
    wire       usb_cdc_led;
    wire       cdc_led_out;
    
    // 数据上传连接
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    
    // 生成系统复位信号：确保PLL锁定后才释放复位
    assign system_rst_n = rst_n & pll_locked;
    //==============================================================
    //======时钟生成模块
    //==============================================================
    
    // 第一级PLL: 50MHz → 24MHz
    Gowin_PLL_24 u_pll_24(
        .clkout0(CLK24M), 
        .clkout1(clk200m),
        .clkout2(dac_clk),
        .clkin(clk),
        .reset(~rst_n)
        //.mdclk(clk)
    );

    // 第二级PLL: 24MHz → 480MHz + 60MHz  
    Gowin_PLL u_pll(
        .lock(pll_locked), 
        .reset(~rst_n),
        .mdclk(clk),
        .clkout0(fclk_480M), 
        .clkout1(PHY_CLK),  // 60MHz
        .clkin(CLK24M)
    );

    // 实例化USB_CDC模块
    USB_CDC u_usb_cdc(
        .CLK_IN(clk),
        .PHY_CLKOUT_i(PHY_CLK),
        .fclk_480M_i(fclk_480M),
        .pll_locked_i(pll_locked),
        .LED(usb_cdc_led),
        .usb_dxp_io(usb_dxp_io),
        .usb_dxn_io(usb_dxn_io),
        .usb_rxdp_i(usb_rxdp_i),
        .usb_rxdn_i(usb_rxdn_i),
        .usb_pullup_en_o(usb_pullup_en_o),
        .usb_term_dp_io(usb_term_dp_io),
        .usb_term_dn_io(usb_term_dn_io),
        .usb_data_out(usb_data),
        .usb_data_valid_out(usb_data_valid),
        
        // 数据上传接口
        .usb_upload_data_in(usb_upload_data),
        .usb_upload_valid_in(usb_upload_valid)
    );

    // 实例化CDC模块 - 使用系统复位信号（Ultimate版本，包含DSM）
    cdc u_cdc(
        .clk(PHY_CLK),
        .rst_n(system_rst_n),
        .usb_data_in(usb_data),
        .usb_data_valid_in(usb_data_valid),
        .led_out(cdc_led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),

        .dac_clk(clk200m),
        .dac_data(dac_data),

//        .dac_clk(),
//        .dac_data(),

        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),

        .dsm_signal_in(dsm_signal_in),  // DSM 8通道输入
        .dc_signal_in(dc_signal_in),    // Digital Capture 8通道输入

        .i2c_scl(i2c_scl),              // I2C SCL
        .i2c_sda(i2c_sda),              // I2C SDA

        .debug_out(cdc_debug_signal),

        // 数据上传接口
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    // LED输出
    assign led[0] = cdc_led_out;
    assign led[1] = usb_cdc_led;
    assign led[3] = 2'b00;
    assign led[2] = usb_data_valid;




endmodule
