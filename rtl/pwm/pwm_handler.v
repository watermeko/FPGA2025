// PWM指令处理器
module pwm_handler(
        input  wire        clk,
        input  wire        rst_n,
        input  wire [7:0]  cmd_type,
        input  wire [15:0] cmd_length,
        input  wire [7:0]  cmd_data,
        input  wire [15:0] cmd_data_index,
        input  wire        cmd_start,
        input  wire        cmd_data_valid,
        input  wire        cmd_done,

        output wire        cmd_ready,
        output [7:0]       pwm_pins

    );
    
    // 状态机定义 - 增加状态以解决时序问题
    localparam H_IDLE          = 2'b00; // 空闲状态
    localparam H_RECEIVING     = 2'b01; // 接收数据
    localparam H_UPDATE_CONFIG = 2'b10; // 更新PWM配置值
    localparam H_STROBE        = 2'b11; // 发出更新脉冲

    reg [1:0] handler_state;

    // PWM配置寄存器
    reg [2:0]   pwm_ch_index;
    reg [15:0]  pwm_period;
    reg [15:0]  pwm_duty;
    reg         pwm_update_strobe;

    // 临时存储指令的payload
    reg [7:0]   pwm_data [0:4];

    // 在IDLE和RECEIVING状态下，模块都准备好接收数据
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state     <= H_IDLE;
            pwm_update_strobe <= 1'b0;
            pwm_ch_index      <= 0;
            pwm_period        <= 0;
            pwm_duty          <= 0;
            pwm_data[0] <= 8'h0;
            pwm_data[1] <= 8'h0;
            pwm_data[2] <= 8'h0;
            pwm_data[3] <= 8'h0;
            pwm_data[4] <= 8'h0;
        end
        else begin
            // 默认将脉冲信号拉低
            pwm_update_strobe <= 1'b0;

            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == 8'hFE) begin
                        handler_state <= H_RECEIVING;
                    end
                end

                H_RECEIVING: begin
                    if (cmd_data_valid) begin
                        pwm_data[cmd_data_index] <= cmd_data;
                    end

                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CONFIG; // 数据接收完毕，准备更新
                    end
                end

                H_UPDATE_CONFIG: begin
                    // 周期 1: 设置PWM配置值。
                    // 这些值将在下一个周期（H_STROBE）稳定下来。
                    pwm_ch_index      <= pwm_data[0][2:0];
                    pwm_period        <= {pwm_data[1], pwm_data[2]};
                    pwm_duty          <= {pwm_data[3], pwm_data[4]};
                    
                    handler_state <= H_STROBE; // 进入下一个状态以发出脉冲
                end

                H_STROBE: begin
                    // 周期 2: PWM配置值已经稳定。
                    // 在这个周期发出单周期更新脉冲。
                    pwm_update_strobe <= 1'b1; 
                    
                    // 完成，返回空闲状态
                    handler_state <= H_IDLE;
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase
        end
    end

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
