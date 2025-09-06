module cdc(
        input clk,
        input rst_n,
        
        // 新增：串口数据输入端口
        input [7:0] usb_data_in,
        input       usb_data_valid_in,

        output led_out,
        output    [7:0]     pwm_pins      // 8-channel PWM output pins
    );
    // 移除内部的串口数据信号定义，改为使用输入端口
    // wire [7:0] rx_data_out;
    // wire rx_data_valid;

    wire parser_done,parser_error;
    wire [7:0] cmd_out;
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
        .uart_rx_valid(usb_data_valid_pulse),  // 使用脉冲信号

        // Payload read port - not used in this test, tie address to 0
        .payload_read_addr(payload_read_addr),
        .payload_read_data(payload_read_data),

        // Parser outputs
        .parse_done(parser_done),
        .parse_error(parser_error),
        .cmd_out(cmd_out),
        .len_out()
    );



    wire [2:0]  pwm_ch_index;
    wire [15:0] pwm_period;
    wire [15:0] pwm_duty;
    wire        pwm_update_strobe;
    command_processor #(
                          .PAYLOAD_ADDR_WIDTH(PAYLOAD_ADDR_WIDTH)
                      ) u_command_processor (
                          .clk(clk),
                          .rst_n(rst_n),
                          .parse_done(parser_done),
                          .cmd_out(cmd_out),
                          .payload_read_data(payload_read_data),
                          .led_out(led_out),
                          .payload_read_addr(payload_read_addr),
                          .pwm_config_ch_index_out(pwm_ch_index),
                          .pwm_config_period_out(pwm_period),
                          .pwm_config_duty_out(pwm_duty),
                          .pwm_config_update_strobe(pwm_update_strobe)
                      );


    // 5. Multi-Channel PWM Generator: The hardware that generates PWM waves
    pwm_multi_channel #(
                          .NUM_CHANNELS(8),
                          .COUNTER_WIDTH(16)
                      ) u_pwm_multi (
                          .clk(clk),
                          .rst_n(rst_n),
                          .config_ch_index_in(pwm_ch_index),
                          .config_period_in(pwm_period),
                          .config_duty_in(pwm_duty),
                          .config_update_strobe(pwm_update_strobe),
                          .pwm_out_vector(pwm_pins)
                      );



endmodule
