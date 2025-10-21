module cdc(
    input clk,
    input rst_n,

    input [7:0] usb_data_in,
    input       usb_data_valid_in,

    output led_out,
    output [7:0] pwm_pins,

    input ext_uart_rx,
    output ext_uart_tx,


    input dac_clk,
    output signed [13:0] dac_data_a,      // Channel A
    output signed [13:0] dac_data_b,      // Channel B

    output       spi_clk,
    output       spi_cs_n,
    output       spi_mosi,
    input        spi_miso,

    // DSM 数字信号测量输入
    input [7:0]  dsm_signal_in,

    // Digital Capture 数字逻辑捕获输入（8通道）
    input [7:0]  dc_signal_in,

    // I2C Interface
    output       i2c_scl,
    inout        i2c_sda,

    output wire  debug_out, // 用于调试的输出信号

    output [7:0] usb_upload_data,
    output       usb_upload_valid
);
    // --- Internal Wires ---
    wire parser_done, parser_error;
    wire [7:0] cmd_out;
    wire [15:0] len_out;
    parameter PAYLOAD_ADDR_WIDTH=$clog2(1024);
    wire [7:0] payload_read_data;
    wire [PAYLOAD_ADDR_WIDTH-1:0] payload_read_addr;
    reg usb_data_valid_in_d1;
    wire usb_data_valid_pulse = usb_data_valid_in & ~usb_data_valid_in_d1;

    // --- Command Bus Wires ---
    wire [7:0]  cmd_type;
    wire [15:0] cmd_length;
    wire [7:0]  cmd_data;
    wire [15:0] cmd_data_index;
    wire        cmd_start;
    wire        cmd_data_valid;
    wire        cmd_done;

    // --- Ready & Upload Wires from Handlers ---
    wire        pwm_ready, ext_uart_ready, dac_ready, spi_ready, dsm_ready, i2c_ready, custom_wave_ready;
    wire        processor_upload_ready;

    // === Handler 上传信号（原始） ===
    wire        uart_upload_active;
    wire        uart_upload_req;
    wire [7:0]  uart_upload_data;
    wire [7:0]  uart_upload_source;
    wire        uart_upload_valid;
    wire        uart_upload_ready;

    wire        spi_upload_active;
    wire        spi_upload_req;
    wire [7:0]  spi_upload_data;
    wire [7:0]  spi_upload_source;
    wire        spi_upload_valid;
    wire        spi_upload_ready;

    wire        dsm_upload_active;
    wire        dsm_upload_req;
    wire [7:0]  dsm_upload_data;
    wire [7:0]  dsm_upload_source;
    wire        dsm_upload_valid;
    wire        dsm_upload_ready;

    wire        i2c_upload_active;
    wire        i2c_upload_req;
    wire [7:0]  i2c_upload_data;
    wire [7:0]  i2c_upload_source;
    wire        i2c_upload_valid;
    wire        i2c_upload_ready;

    // === Digital Capture Handler 上传信号 ===
    wire        dc_ready;
    wire        dc_upload_active;
    wire        dc_upload_req;
    wire [7:0]  dc_upload_data;
    wire [7:0]  dc_upload_source;
    wire        dc_upload_valid;

    // *** 完整版本: 检查所有 handler (PWM + UART + DAC + SPI + DSM + I2C + DC) ***
    wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready & spi_ready & dsm_ready & i2c_ready & dc_ready;

    // ========================================================================
    // 上传数据流水线：Handler -> Adapter -> Packer -> Arbiter -> Processor
    // 使用带0版本的三个模块
    // ========================================================================

    parameter NUM_UPLOAD_CHANNELS = 4;  // UART + SPI + DSM + I2C

    // --- Adapter 输出 -> Packer 输入 ---
    wire       uart_packer_req;
    wire [7:0] uart_packer_data;
    wire [7:0] uart_packer_source;
    wire       uart_packer_valid;
    wire       uart_packer_ready;

    wire       spi_packer_req;
    wire [7:0] spi_packer_data;
    wire [7:0] spi_packer_source;
    wire       spi_packer_valid;
    wire       spi_packer_ready;

    wire       dsm_packer_req;
    wire [7:0] dsm_packer_data;
    wire [7:0] dsm_packer_source;
    wire       dsm_packer_valid;
    wire       dsm_packer_ready;

    wire       i2c_packer_req;
    wire [7:0] i2c_packer_data;
    wire [7:0] i2c_packer_source;
    wire       i2c_packer_valid;
    wire       i2c_packer_ready;

    // --- Packer 输出 -> Arbiter 输入 ---
    wire [NUM_UPLOAD_CHANNELS-1:0]      packed_req;
    wire [NUM_UPLOAD_CHANNELS*8-1:0]    packed_data;
    wire [NUM_UPLOAD_CHANNELS*8-1:0]    packed_source;
    wire [NUM_UPLOAD_CHANNELS-1:0]      packed_valid;
    wire [NUM_UPLOAD_CHANNELS-1:0]      arbiter_ready;

    // --- Arbiter 输出 -> Processor (最终合并) ---
    wire        merged_upload_req;
    wire [7:0]  merged_upload_data;
    wire [7:0]  merged_upload_source;
    wire        merged_upload_valid;

    // ========================================================================
    // MUX 仲裁：Digital Capture 直通模式 vs 协议封装模式
    // DC Handler 优先级最高，当 active 时直接连接到 processor
    // TEMPORARILY DISABLED - Debugging DC module issues
    // ========================================================================
    wire        final_upload_req;
    wire [7:0]  final_upload_data;
    wire [7:0]  final_upload_source;
    wire        final_upload_valid;


    wire        custom_wave_active_a, custom_wave_active_b;
    wire signed [13:0] dac_data_dds_a, dac_data_dds_b;
    wire signed [13:0] dac_data_custom_a, dac_data_custom_b;

    wire custom_release_override = cmd_start && (cmd_type == 8'hFD);

    // DC module enabled - direct passthrough mode for high-speed streaming
    assign final_upload_req    = dc_upload_active ? dc_upload_req    : merged_upload_req;
    assign final_upload_data   = dc_upload_active ? dc_upload_data   : merged_upload_data;
    assign final_upload_source = dc_upload_active ? dc_upload_source : merged_upload_source;
    assign final_upload_valid  = dc_upload_active ? dc_upload_valid  : merged_upload_valid;


    // --- UART Adapter ---
    upload_adapter u_uart_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(uart_upload_active),
        .handler_upload_data(uart_upload_data),
        .handler_upload_source(uart_upload_source),
        .handler_upload_valid(uart_upload_valid),
        .handler_upload_ready(uart_upload_ready),
        .packer_upload_req(uart_packer_req),
        .packer_upload_data(uart_packer_data),
        .packer_upload_source(uart_packer_source),
        .packer_upload_valid(uart_packer_valid),
        .packer_upload_ready(uart_packer_ready)
    );

    // --- SPI Adapter ---
    upload_adapter u_spi_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(spi_upload_active),
        .handler_upload_data(spi_upload_data),
        .handler_upload_source(spi_upload_source),
        .handler_upload_valid(spi_upload_valid),
        .handler_upload_ready(spi_upload_ready),
        .packer_upload_req(spi_packer_req),
        .packer_upload_data(spi_packer_data),
        .packer_upload_source(spi_packer_source),
        .packer_upload_valid(spi_packer_valid),
        .packer_upload_ready(spi_packer_ready)
    );

    // --- DSM Adapter ---
    upload_adapter u_dsm_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(dsm_upload_active),
        .handler_upload_data(dsm_upload_data),
        .handler_upload_source(dsm_upload_source),
        .handler_upload_valid(dsm_upload_valid),
        .handler_upload_ready(dsm_upload_ready),
        .packer_upload_req(dsm_packer_req),
        .packer_upload_data(dsm_packer_data),
        .packer_upload_source(dsm_packer_source),
        .packer_upload_valid(dsm_packer_valid),
        .packer_upload_ready(dsm_packer_ready)
    );

    // --- I2C Adapter ---
    upload_adapter u_i2c_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(i2c_upload_active),
        .handler_upload_data(i2c_upload_data),
        .handler_upload_source(i2c_upload_source),
        .handler_upload_valid(i2c_upload_valid),
        .handler_upload_ready(i2c_upload_ready),
        .packer_upload_req(i2c_packer_req),
        .packer_upload_data(i2c_packer_data),
        .packer_upload_source(i2c_packer_source),
        .packer_upload_valid(i2c_packer_valid),
        .packer_upload_ready(i2c_packer_ready)
    );

    // --- Multi-channel Packer (Version 0) ---
    upload_packer #(
        .NUM_CHANNELS(NUM_UPLOAD_CHANNELS),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req({i2c_packer_req, dsm_packer_req, spi_packer_req, uart_packer_req}),
        .raw_upload_data({i2c_packer_data, dsm_packer_data, spi_packer_data, uart_packer_data}),
        .raw_upload_source({i2c_packer_source, dsm_packer_source, spi_packer_source, uart_packer_source}),
        .raw_upload_valid({i2c_packer_valid, dsm_packer_valid, spi_packer_valid, uart_packer_valid}),
        .raw_upload_ready({i2c_packer_ready, dsm_packer_ready, spi_packer_ready, uart_packer_ready}),
        .packed_upload_req(packed_req),
        .packed_upload_data(packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid(packed_valid),
        .packed_upload_ready(arbiter_ready)
    );

    // --- Arbiter (Version 0) ---
    upload_arbiter #(
        .NUM_SOURCES(NUM_UPLOAD_CHANNELS),
        .FIFO_DEPTH(32)
    ) u_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .src_upload_req(packed_req),
        .src_upload_data(packed_data),
        .src_upload_source(packed_source),
        .src_upload_valid(packed_valid),
        .src_upload_ready(arbiter_ready),
        .merged_upload_req(merged_upload_req),
        .merged_upload_data(merged_upload_data),
        .merged_upload_source(merged_upload_source),
        .merged_upload_valid(merged_upload_valid),
        .processor_upload_ready(processor_upload_ready)
    );

    // --- Edge Detector for usb_data_valid_in ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) usb_data_valid_in_d1 <= 1'b0;
        else        usb_data_valid_in_d1 <= usb_data_valid_in;
    end
    
    // --- Core Modules Instantiation ---
    protocol_parser #(
        .MAX_PAYLOAD_LEN(1024)
    ) u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_data(usb_data_in),
        .uart_rx_valid(usb_data_valid_pulse),
        .payload_read_addr(payload_read_addr),
        .payload_read_data(payload_read_data),
        .parse_done(parser_done),
        .parse_error(parser_error),
        .cmd_out(cmd_out),
        .len_out(len_out)
    );

    command_processor #(
        .PAYLOAD_ADDR_WIDTH(PAYLOAD_ADDR_WIDTH)
    ) u_command_processor (
        .clk(clk),
        .rst_n(rst_n),
        .parse_done(parser_done),
        .cmd_out(cmd_out),
        .len_out(len_out),
        .payload_read_data(payload_read_data),
        .led_out(led_out),
        .payload_read_addr(payload_read_addr),
        .cmd_type_out(cmd_type),
        .cmd_length_out(cmd_length),
        .cmd_data_out(cmd_data),
        .cmd_data_index_out(cmd_data_index),
        .cmd_start_out(cmd_start),
        .cmd_data_valid_out(cmd_data_valid),
        .cmd_done_out(cmd_done),
        .cmd_ready_in(cmd_ready),
        .upload_req_in(final_upload_req),
        .upload_data_in(final_upload_data),
        .upload_source_in(final_upload_source),
        .upload_valid_in(final_upload_valid),
        .upload_ready_out(processor_upload_ready),
        .usb_upload_data_out(usb_upload_data),
        .usb_upload_valid_out(usb_upload_valid)
    );

    // --- Handler Modules Instantiation (全部保留) ---
    pwm_handler u_pwm_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(pwm_ready),
        .pwm_pins(pwm_pins)
    );

    uart_handler u_uart_handler(
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(ext_uart_ready),
        .ext_uart_tx(ext_uart_tx),
        .ext_uart_rx(ext_uart_rx),
        .upload_active(uart_upload_active),
        .upload_req(uart_upload_req),
        .upload_data(uart_upload_data),
        .upload_source(uart_upload_source),
        .upload_valid(uart_upload_valid),
        .upload_ready(uart_upload_ready)
    );

    assign dac_ready = 1'b1;
    // dac_handler u_dac_handler(
    //     .clk(clk),
    //     .rst_n(rst_n),
    //     .cmd_type(cmd_type),
    //     .cmd_length(cmd_length),
    //     .cmd_data(cmd_data),
    //     .cmd_data_index(cmd_data_index),
    //     .cmd_start(cmd_start),
    //     .cmd_data_valid(cmd_data_valid),
    //     .cmd_done(cmd_done),
    //     .cmd_ready(dac_ready),
    //     .dac_clk(dac_clk),
    //     .dac_data_a(dac_data_dds_a),
    //     .dac_data_b(dac_data_dds_b)
    // );

    spi_handler #(
        .CLK_DIV(32)
    ) u_spi_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(spi_ready),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .upload_active(spi_upload_active),
        .upload_req(spi_upload_req),
        .upload_data(spi_upload_data),
        .upload_source(spi_upload_source),
        .upload_valid(spi_upload_valid),
        .upload_ready(spi_upload_ready)
    );

    dsm_multichannel_handler u_dsm_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(dsm_ready),
        .dsm_signal_in(dsm_signal_in),
        .upload_active(dsm_upload_active),
        .upload_req(dsm_upload_req),
        .upload_data(dsm_upload_data),
        .upload_source(dsm_upload_source),
        .upload_valid(dsm_upload_valid),
        .upload_ready(dsm_upload_ready)
    );

    i2c_handler #(
        .WRITE_BUFFER_SIZE(64),
        .READ_BUFFER_SIZE(64)
    ) u_i2c_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(i2c_ready),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),
        .upload_active(i2c_upload_active),
        .upload_req(i2c_upload_req),
        .upload_data(i2c_upload_data),
        .upload_source(i2c_upload_source),
        .upload_valid(i2c_upload_valid),
        .upload_ready(i2c_upload_ready)
    );

    // Digital Capture Handler - 直通上传模式
    digital_capture_handler u_dc_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(dc_ready),
        .dc_signal_in(dc_signal_in),
        .upload_active(dc_upload_active),
        .upload_req(dc_upload_req),
        .upload_data(dc_upload_data),
        .upload_source(dc_upload_source),
        .upload_valid(dc_upload_valid),
        .upload_ready(processor_upload_ready)
    );

    custom_waveform_handler u_custom_waveform_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(custom_wave_ready),
        .release_override(custom_release_override),
        .dac_clk(dac_clk),
        .dac_data_a(dac_data_custom_a),
        .dac_data_b(dac_data_custom_b),
        .playing_a(),
        .playing_b(),
        .dac_active_a(custom_wave_active_a),
        .dac_active_b(custom_wave_active_b)
    );



    // DAC数据格式转换：二补码 → 偏移二进制 (Offset Binary)
    // 二补码: 0x2000(-8192) ~ 0x0000(0) ~ 0x1FFF(+8191)
    // 偏移二进制: 0x0000(最小) ~ 0x2000(零点) ~ 0x3FFF(最大)
    // 转换公式: offset_binary = twos_complement ^ 0x2000 (翻转符号位)

    // 幅度缩放：缩小到80%避免截顶 (×13107/16384 ≈ ×0.8)
    wire signed [13:0] dac_data_mux_a = (custom_wave_active_a | custom_wave_active_b) ? dac_data_custom_a : dac_data_dds_a;
    wire signed [13:0] dac_data_mux_b = (custom_wave_active_a | custom_wave_active_b) ? dac_data_custom_b : dac_data_dds_b;

    wire signed [27:0] scaled_a = $signed(dac_data_mux_a) * $signed(14'sd6554);  // ×0.8 (6554/8192)
    wire signed [27:0] scaled_b = $signed(dac_data_mux_b) * $signed(14'sd6554);
    wire signed [13:0] dac_data_twos_a = scaled_a[26:13];  // 取高14位
    wire signed [13:0] dac_data_twos_b = scaled_b[26:13];

    assign dac_data_a = {~dac_data_twos_a[13], dac_data_twos_a[12:0]};  // 翻转符号位
    assign dac_data_b = {~dac_data_twos_b[13], dac_data_twos_b[12:0]};  // 翻转符号位

    assign debug_out = u_spi_handler.spi_start;

endmodule