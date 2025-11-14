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

//        output cdc_debug_signal,

        output       spi_clk,
        output       spi_cs_n,
        output       spi_mosi,
        input        spi_miso,

       input       spi_slave_clk,
       input       spi_slave_cs_n,
       input       spi_slave_mosi,
       output      spi_slave_miso,


        // DSM 数字信号测量输入（8通道）
        input [7:0]  dsm_signal_in,

        // Digital Capture 数字逻辑捕获输入（8通道）
        input [7:0]  dc_signal_in,

        // I2C Interface
        output       i2c_scl,
        inout        i2c_sda,
        // 理论上可以复用但是会报错 我先再引俩引脚 我没招了
        inout        i2c_scl_slave,
        inout        i2c_sda_slave,

        // Dual-channel DAC outputs
        output [13:0] dac_data_a_out,
        output [13:0] dac_data_b_out,
        output        dac_clk_a_out,
        output        dac_clk_b_out,
    //eth_rx
    input         rgmii_rx_clk_i,
    input  [3:0]  rgmii_rxd,
    input         rgmii_rxdv,
    output 		  eth_rst_n, 
    output        eth_mdc,
    output        eth_mdio, 

    //eth_tx
    output        rgmii_tx_clk,
    output  [3:0] rgmii_txd,
    output        rgmii_txen,

    //ddr
    output [13:0] O_ddr_addr        ,
    output [2:0] O_ddr_ba           ,
    output O_ddr_cs_n               ,
    output O_ddr_ras_n              ,
    output O_ddr_cas_n              ,
    output O_ddr_we_n               ,
    output O_ddr_clk                ,
    output O_ddr_clk_n              ,
    output O_ddr_cke                ,
    output O_ddr_odt                ,
    output O_ddr_reset_n            ,
    output [1:0] O_ddr_dqm          ,
    inout [15:0] IO_ddr_dq          ,
    inout [1:0] IO_ddr_dqs          ,
    inout [1:0] IO_ddr_dqs_n    ,

    output adc_mux_select,
    input [13:0] adc_data_in,
    output adc_clk_out

    );

    // 时钟相关信号
    wire CLK24M;
    wire fclk_480M;
    wire clk200m, ad_ddr_eth_clk,ad_ddr_eth_clk_raw;
    wire PHY_CLK;
    wire pll_locked;
    wire system_rst_n;  // 系统复位信号
    wire ad_ddr_clk_400m /* synthesis syn_keep=1 */;
    wire ad_ddr_pll_lock;
    wire adc_sample_clk;
    wire pll_lock_sync;
    wire pll_mdrp_wr;
    wire pll_mdrp_inc;
    wire [1:0] pll_mdrp_op;
    wire [7:0] pll_mdrp_wdata;
    wire [7:0] pll_mdrp_rdata;

    // 同步复位相关信号
    reg rst_n_sync1, rst_n_sync2;
    reg clk24m_rst_n_sync1, clk24m_rst_n_sync2;
    reg ad_ddr_rst_n_sync1, ad_ddr_rst_n_sync2;
    


    // USB CDC到CDC模块的数据连接
    wire [7:0] usb_data;
    wire       usb_data_valid;
    wire       usb_cdc_led;
    wire       cdc_led_out;
    
    // 数据上传连接
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;

    // DAC时钟和数据信号(200MHz DAC时钟域)
    wire signed [13:0] dac_data_a_internal;
    wire signed [13:0] dac_data_b_internal;

    // 同步复位逻辑 - 输入时钟域同步
    always @(posedge clk) begin
        rst_n_sync1 <= rst_n;
        rst_n_sync2 <= rst_n_sync1;
    end

    // 同步复位逻辑 - CLK24M时钟域同步
    always @(posedge CLK24M) begin
        clk24m_rst_n_sync1 <= rst_n_sync2;
        clk24m_rst_n_sync2 <= clk24m_rst_n_sync1;
    end

    // 同步复位逻辑 - ad_ddr_clk_400m时钟域同步
    always @(posedge clk) begin
        ad_ddr_rst_n_sync1 <= rst_n;
        ad_ddr_rst_n_sync2 <= ad_ddr_rst_n_sync1;
    end

    wire [7:0] dc_usb_upload_data;
    wire       dc_usb_upload_valid;
    wire       dc_fifo_afull;  // EP3 FIFO almost full (backpressure)
    
    // 生成系统复位信号：确保PLL锁定后才释放复位
    assign system_rst_n = rst_n_sync2 & pll_locked;
    //==============================================================
    //======时钟生成模块
    //==============================================================

    // 第一级PLL: 50MHz → 24MHz (使用同步复位)
    Gowin_PLL_24 u_pll_24(
        .clkout0(CLK24M),
        .clkout1(adc_sample_clk),
        .clkout2(clk120m),
        .clkin(clk),
        .reset(~rst_n_sync2),
        .mdclk(clk)
    );




    // 第二级PLL: 24MHz → 480MHz + 60MHz (使用同步复位)
    Gowin_PLL u_pll(
        .lock(pll_locked),
        .reset(~clk24m_rst_n_sync2),
        // .mdclk(clk),
        .clkout0(fclk_480M), // accually 960m
        .clkout1(PHY_CLK),  // 60MHz
        .clkin(CLK24M)
    );

    ad_ddr_eth_pll u_ad_ddr_eth_pll(
        .lock(ad_ddr_pll_lock),
        .clkout0(),
        .clkout1(),
        .clkout2(ad_ddr_clk_400m),
        .mdrdo(pll_mdrp_rdata),
        .clkin(clk),
        .reset(~ad_ddr_rst_n_sync2),
        .mdclk(clk),
        .mdopc(pll_mdrp_op),
        .mdainc(pll_mdrp_inc),
        .mdwdi(pll_mdrp_wdata)
    );

    pll_mDRP_intf u_pll_mDRP_intf(
        .clk(clk),
        .rst_n(1'b1),
        .pll_lock(pll_lock_sync),
        .wr(pll_mdrp_wr),
        .mdrp_inc(pll_mdrp_inc),
        .mdrp_op(pll_mdrp_op),
        .mdrp_wdata(pll_mdrp_wdata),
        .mdrp_rdata(pll_mdrp_rdata)
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
        .usb_upload_valid_in(usb_upload_valid),
        .usb_dc_upload_data_in(dc_usb_upload_data),
        .usb_dc_upload_valid_in(dc_usb_upload_valid),
        .usb_dc_fifo_afull(dc_fifo_afull)  // FIFO almost full (backpressure)
    );

    // 实例化CDC模块 - 使用系统复位信号（Ultimate版本，包含DSM）
    cdc u_cdc(
        .clk(PHY_CLK),
        .rst_n(system_rst_n),
        .usb_data_in(usb_data),
        .usb_data_valid_in(usb_data_valid),
        .led_out(led[3]),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),

        .dac_clk(clk120m),
        .dac_data_a(dac_data_a_internal),
        .dac_data_b(dac_data_b_internal),

        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),

        .spi_slave_clk(spi_slave_clk),
        .spi_slave_cs_n(spi_slave_cs_n),
        .spi_slave_mosi(spi_slave_mosi),
        .spi_slave_miso(spi_slave_miso),

//        .dsm_signal_in(dsm_signal_in),  // DSM 8通道输入
        .dc_signal_in(dc_signal_in),    // Digital Capture 8通道输入

        .i2c_scl(i2c_scl),              // I2C SCL
        .i2c_sda(i2c_sda),              // I2C SDA

        .i2c_scl_slave(i2c_scl_slave),
        .i2c_sda_slave(i2c_sda_slave),

        .debug_out(cdc_debug_signal),

        // 数据上传接口
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid),
        .dc_usb_upload_data(dc_usb_upload_data),
        .dc_usb_upload_valid(dc_usb_upload_valid),
        .dc_fifo_afull(dc_fifo_afull)  // EP3 FIFO backpressure
    );

    // LED输出
    //assign led[0] = cdc_led_out;
    //assign led[1] = usb_cdc_led;
    //assign led[3] = 2'b00;
    //assign led[2] = usb_data_valid;


acm9238_ddr3_rgmii u_acm9238_ddr3_rgmii(
	.clk50m         	( clk          ),
	.reset_n        	( rst_n_sync2  ),
	.clk_400M       	( ad_ddr_clk_400m ),
    .adc_sample_clk     ( adc_sample_clk   ),
	.pll_lock       	( ad_ddr_pll_lock ),
	.led            	( led[2:0]     ),
    .adc_clk_out(adc_clk_out),
    .adc_data_in(adc_data_in),
    .adc_mux_select(adc_mux_select),
	.rgmii_rx_clk_i 	( rgmii_rx_clk_i  ),
	.rgmii_rxd      	( rgmii_rxd       ),
	.rgmii_rxdv     	( rgmii_rxdv      ),
	.eth_rst_n      	( eth_rst_n       ),
	.eth_mdc        	( eth_mdc         ),
	.eth_mdio       	( eth_mdio        ),
	.rgmii_tx_clk   	( rgmii_tx_clk    ),
	.rgmii_txd      	( rgmii_txd       ),
	.rgmii_txen     	( rgmii_txen      ),
	.O_ddr_addr     	( O_ddr_addr      ),
	.O_ddr_ba       	( O_ddr_ba        ),
	.O_ddr_cs_n     	( O_ddr_cs_n      ),
	.O_ddr_ras_n    	( O_ddr_ras_n     ),
	.O_ddr_cas_n    	( O_ddr_cas_n     ),
	.O_ddr_we_n     	( O_ddr_we_n      ),
	.O_ddr_clk      	( O_ddr_clk       ),
	.O_ddr_clk_n    	( O_ddr_clk_n     ),
	.O_ddr_cke      	( O_ddr_cke       ),
	.O_ddr_odt      	( O_ddr_odt       ),
	.O_ddr_reset_n  	( O_ddr_reset_n   ),
	.O_ddr_dqm      	( O_ddr_dqm       ),
	.IO_ddr_dq      	( IO_ddr_dq       ),
	.IO_ddr_dqs     	( IO_ddr_dqs      ),
	.IO_ddr_dqs_n   	( IO_ddr_dqs_n    ),
	.pll_mdrp_wr    	( pll_mdrp_wr     ),
	.pll_lock_sync  	( pll_lock_sync   )
);

// 实例化双通道DAC驱动器
dac_driver u_dac_driver (
    .clk_dac         (clk120m),
    .dac_data_a_in   (dac_data_a_internal),
    .dac_data_b_in   (dac_data_b_internal),
    .dac_data_a_out  (dac_data_a_out),
    .dac_data_b_out  (dac_data_b_out),
    .dac_clk_a_out   (dac_clk_a_out),
    .dac_clk_b_out   (dac_clk_b_out)
);


endmodule
