module cdc(
        input clk,
        input rst_n,
        
        input [7:0] usb_data_in,
        input       usb_data_valid_in,

        output led_out,
        output [7:0] pwm_pins
        

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
    
    // 
    wire pwm_ready;
    wire cmd_ready = pwm_ready;
    
    // 主控制器
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
        .cmd_ready_in(cmd_ready)
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


endmodule
