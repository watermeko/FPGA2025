// ============================================================================
// Module: cdc_int (Integrated version - same as cdc_spi for now)
// ============================================================================
module cdc_int(
    input clk,
    input rst_n,
    
    input [7:0] usb_data_in,
    input       usb_data_valid_in,

    output led_out,
    output [7:0] pwm_pins,

    input ext_uart_rx,
    output ext_uart_tx,

    input dac_clk,
    output [13:0] dac_data,
//    
    output       spi_clk,
    output       spi_cs_n,
    output       spi_mosi,
    input        spi_miso,
    
    output wire  debug_out, // 用于调试的输出信号

    output [7:0] usb_upload_data,
    output       usb_upload_valid
);
    // --- Internal Wires ---
    wire parser_done, parser_error;
    wire [7:0] cmd_out;
    wire [15:0] len_out;
    parameter PAYLOAD_ADDR_WIDTH=$clog2(256);
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
    wire        pwm_ready, ext_uart_ready, dac_ready, spi_ready;
    wire        processor_upload_ready;
    
    wire        uart_upload_req;
    wire [7:0]  uart_upload_data;
    wire [7:0]  uart_upload_source;
    wire        uart_upload_valid;
    wire        uart_upload_ready;

    wire        spi_upload_req;
    wire [7:0]  spi_upload_data;
    wire [7:0]  spi_upload_source;
    wire        spi_upload_valid;
    wire        spi_upload_ready;

    // *** 测试版本: 暂时只检查 SPI ready ***
    // 逐步调试，先让 SPI 功能正常
    wire cmd_ready = spi_ready;

    // *** 测试版本 2: 同时启用 UART 和 SPI 上传（无仲裁） ***
    // 策略：两个 handler 都给 ready，谁有数据谁上传

    // 控制信号：或运算（任意一个有请求/有效就算）
    wire        merged_upload_req    = uart_upload_req | spi_upload_req;
    wire        merged_upload_valid  = uart_upload_valid | spi_upload_valid;

    // 数据信号：简单选择（UART 优先）
    wire [7:0]  merged_upload_data   = uart_upload_valid ? uart_upload_data : spi_upload_data;
    wire [7:0]  merged_upload_source = uart_upload_valid ? uart_upload_source : spi_upload_source;

    // Ready 分配：两个都给 ready（无仲裁，可能冲突但先测试）
    assign      spi_upload_ready     = processor_upload_ready;
    assign      uart_upload_ready    = processor_upload_ready;

    // --- Edge Detector for usb_data_valid_in ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) usb_data_valid_in_d1 <= 1'b0;
        else        usb_data_valid_in_d1 <= usb_data_valid_in;
    end
    
    // --- Core Modules Instantiation ---
    protocol_parser #(
        .MAX_PAYLOAD_LEN(256)
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
        .upload_req_in(merged_upload_req),
        .upload_data_in(merged_upload_data),
        .upload_source_in(merged_upload_source),
        .upload_valid_in(merged_upload_valid),
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
        .upload_req(uart_upload_req),
        .upload_data(uart_upload_data),
        .upload_source(uart_upload_source),
        .upload_valid(uart_upload_valid),
        .upload_ready(uart_upload_ready) 
    );

    dac_handler u_dac_handler(
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(dac_ready),
        .dac_clk(dac_clk),
        .dac_data(dac_data)
    );
    
    spi_handler #(
        .CLK_DIV(32)  // SPI时钟分频32: 60MHz/32 = 1.875MHz
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
        .upload_req(spi_upload_req),
        .upload_data(spi_upload_data),
        .upload_source(spi_upload_source),
        .upload_valid(spi_upload_valid),
        .upload_ready(spi_upload_ready)
    );
     
    // 将内部的 cmd_start 信号连接到调试输出端口
assign debug_out = u_spi_handler.spi_start;
 
endmodule