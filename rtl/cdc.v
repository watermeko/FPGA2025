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
        output [13:0] dac_data,

        inout wire SCL,
        inout wire SDA,
        
        // 数据上传接口
        output [7:0] usb_upload_data,
        output       usb_upload_valid
    );

    wire parser_done,parser_error;
    wire [7:0] cmd_out;
    wire [15:0] len_out;
    parameter PAYLOAD_ADDR_WIDTH=$clog2(256);
    wire [7:0] payload_read_data;
    wire [PAYLOAD_ADDR_WIDTH-1:0] payload_read_addr;
    // 在cdc模块中添加边沿检测
    reg usb_data_valid_in_d1;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            usb_data_valid_in_d1 <= 1'b0;
        end else begin
            usb_data_valid_in_d1 <= usb_data_valid_in;
        end
    end
    
    wire usb_data_valid_pulse = usb_data_valid_in & ~usb_data_valid_in_d1;
    
    // 修改protocol_parser的连接
    protocol_parser #(
        .MAX_PAYLOAD_LEN(256)
    ) u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_data(usb_data_in),
        .uart_rx_valid(usb_data_valid_in),  // 使用脉冲信号

        // Payload read port - not used in this test, tie address to 0
        .payload_read_addr(payload_read_addr),
        .payload_read_data(payload_read_data),

        // Parser outputs
        .parse_done(parser_done),
        .parse_error(parser_error),
        .cmd_out(cmd_out),
        .len_out(len_out)
    );

    // 通用指令接口
    wire [7:0]  cmd_type;
    wire [15:0] cmd_length;
    wire [7:0]  cmd_data;
    wire [15:0] cmd_data_index;
    wire        cmd_start;
    wire        cmd_data_valid;
    wire        cmd_done;
    
    wire i2c_cmd_ready;

    // I2C 上传接口信号
    wire i2c_upload_req;
    wire [7:0] i2c_upload_data;
    wire [7:0] i2c_upload_source;
    wire i2c_upload_valid;

    wire pwm_ready,ext_uart_ready,dac_ready;
    wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready & i2c_cmd_ready;
    
    // 数据上传接口信号
    wire        uart_upload_req;
    wire [7:0]  uart_upload_data;
    wire [7:0]  uart_upload_source;
    wire        uart_upload_valid;
    wire        uart_upload_ready;

    wire upload_req_combined = uart_upload_req | i2c_upload_req; 
    wire [7:0] upload_data_combined = i2c_upload_req ? i2c_upload_data : uart_upload_data;
    wire [7:0] upload_source_combined = i2c_upload_req ? i2c_upload_source : uart_upload_source;
    wire upload_valid_combined = i2c_upload_req ? i2c_upload_valid : uart_upload_valid;


    
    // 数据分发者
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
        
        // 数据上传接口
        .upload_req_in(upload_req_combined),
        .upload_data_in(upload_data_combined),
        .upload_source_in(upload_source_combined),
        .upload_valid_in(upload_valid_combined),
        
        .usb_upload_data_out(usb_upload_data),
        .usb_upload_valid_out(usb_upload_valid)
    );
    
    // PWM处理器
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
        
        // 数据上传接口
        .upload_req(uart_upload_req),
        .upload_data(uart_upload_data),
        .upload_source(uart_upload_source),
        .upload_valid(uart_upload_valid),
        .upload_ready(uart_upload_ready)
    );

    // 例化 i2c_handler
    i2c_handler u_i2c_handler (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_type       (cmd_type),
        .cmd_length     (cmd_length),
        .cmd_data       (cmd_data),
        .cmd_data_index (cmd_data_index),
        .cmd_start      (cmd_start),
        .cmd_data_valid (cmd_data_valid),
        .cmd_done       (cmd_done),
        .cmd_ready      (i2c_cmd_ready),

        .i2c_scl        (SCL), // 直接连接到顶层 inout 端口
        .i2c_sda        (SDA), // 直接连接到顶层 inout 端口

        .upload_req     (i2c_upload_req),
        .upload_data    (i2c_upload_data),
        .upload_source  (i2c_upload_source),
        .upload_valid   (i2c_upload_valid),
        .upload_ready   (upload_ready) // 从 command_processor 获取
    );

    dac_handler u_dac_handler(
        .clk            	(clk             ),
        .rst_n          	(rst_n           ),
        .cmd_type       	(cmd_type        ),
        .cmd_length     	(cmd_length      ),
        .cmd_data       	(cmd_data        ),
        .cmd_data_index 	(cmd_data_index  ),
        .cmd_start      	(cmd_start       ),
        .cmd_data_valid 	(cmd_data_valid  ),
        .cmd_done       	(cmd_done        ),
        .cmd_ready      	(dac_ready       ),

        .dac_clk            (dac_clk),
        .dac_data       	(dac_data        )
    );


endmodule