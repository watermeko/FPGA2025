// 数字信号测量多通道处理器
module dsm_multichannel_handler(
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
        
        // 数字信号输入
        input  wire [7:0]  dsm_signal_in,
        
        // 数据上传接口
        output reg         upload_req,        // 上传请求
        output reg  [7:0]  upload_data,       // 上传数据  
        output reg  [7:0]  upload_source,     // 数据源标识
        output reg         upload_valid,      // 上传数据有效
        input  wire        upload_ready       // 上传准备就绪

    );

    // Command type codes
    localparam CMD_DSM_MEASURE = 8'h0A;  // DSM测量指令
    
    // Upload source identifier for DSM
    localparam UPLOAD_SOURCE_DSM = 8'h03;

    // State machine definition
    localparam H_IDLE        = 2'b00; // 空闲状态
    localparam H_RX_CMD      = 2'b01; // 接收命令数据
    localparam H_MEASURING   = 2'b10; // 测量中
    localparam H_UPLOAD_DATA = 2'b11; // 上传测量结果

    // Upload state machine definition  
    localparam UP_IDLE = 2'b00;
    localparam UP_SEND = 2'b01;
    localparam UP_WAIT = 2'b10;

    reg [1:0] handler_state;
    reg [1:0] upload_state;

    // 临时存储指令的payload (通道掩码)
    reg [7:0] channel_mask;

    // 上传相关寄存器
    reg [3:0]  upload_channel;     // 当前上传的通道（需要4位以支持0-8）
    reg [3:0]  upload_byte_index;  // 当前上传的字节索引

    // DSM模块接口信号
    wire [7:0]   measure_start;
    wire [7:0]   measure_done;
    wire [127:0] high_time;     // 8通道 * 16位
    wire [127:0] low_time;      // 8通道 * 16位
    wire [127:0] period_time;   // 8通道 * 16位
    wire [127:0] duty_cycle;    // 8通道 * 16位

    // 测量启动控制
    reg  [7:0]   measure_start_reg;
    reg  [7:0]   measure_done_sync;
    wire         all_done;

    assign measure_start = measure_start_reg;
    assign all_done = &(measure_done | ~channel_mask); // 所有启用通道都完成

    // Ready to accept new commands or receive command data
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RX_CMD);

    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= H_IDLE;
            upload_state <= UP_IDLE;
            
            channel_mask <= 8'h00;
            measure_start_reg <= 8'h00;
            measure_done_sync <= 8'h00;
            
            // 清除上传接口
            upload_req <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= UPLOAD_SOURCE_DSM;
            upload_valid <= 1'b0;
            upload_channel <= 0;
            upload_byte_index <= 0;
            
        end else begin
            // 默认设置
            upload_valid <= 1'b0;
            measure_done_sync <= measure_done;

            // 主状态机
            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == CMD_DSM_MEASURE) begin
                        handler_state <= H_RX_CMD;
                        measure_start_reg <= 8'h00;
                    end
                end

                H_RX_CMD: begin
                    if (cmd_data_valid) begin
                        channel_mask <= cmd_data; // 第一个数据字节是通道掩码
                    end
                    
                    if (cmd_done) begin
                        // 启动选中通道的测量 - 延迟一个时钟周期确保channel_mask已更新
                        handler_state <= H_MEASURING;
                    end
                end

                H_MEASURING: begin
                    // 在进入测量状态时，设置测量启动信号并保持直到所有通道完成
                    if (measure_start_reg == 8'h00) begin
                        measure_start_reg <= channel_mask;  // 启动所有选中的通道
                    end
                    
                    // 检查所有选中的通道是否都完成测量
                    if (all_done) begin
                        handler_state <= H_UPLOAD_DATA;
                        upload_channel <= 0;
                        upload_byte_index <= 0;
                        measure_start_reg <= 8'h00;  // 只有在所有测量完成后才清除启动信号
                    end
                end

                H_UPLOAD_DATA: begin
                    // 检查是否所有启用通道都已上传完毕
                    if (upload_channel >= 8) begin
                        // 所有通道数据上传完毕，清除测量启动信号并回到IDLE状态
                        handler_state <= H_IDLE;
                        upload_channel <= 0;
                        upload_byte_index <= 0;
                        measure_start_reg <= 8'h00; // 在数据上传完成后清除测量启动信号
                    end
                    // 让上传状态机自己处理未启用通道的跳过
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase

            // 上传状态机
            case (upload_state)
                UP_IDLE: begin
                    if ((handler_state == H_UPLOAD_DATA) && (upload_channel < 8)) begin
                        if (channel_mask[upload_channel]) begin
                            // 当前通道启用，发出上传请求
                            upload_req <= 1'b1;
                            upload_source <= UPLOAD_SOURCE_DSM;
                            
                            // 根据通道和字节索引选择要上传的数据
                            case (upload_byte_index)
                            0: upload_data <= upload_channel;  // 通道号
                            1: begin // 高电平时间高字节
                                case (upload_channel)
                                    0: upload_data <= high_time[15:8];
                                    1: upload_data <= high_time[31:24];
                                    2: upload_data <= high_time[47:40];
                                    3: upload_data <= high_time[63:56];
                                    4: upload_data <= high_time[79:72];
                                    5: upload_data <= high_time[95:88];
                                    6: upload_data <= high_time[111:104];
                                    7: upload_data <= high_time[127:120];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            2: begin // 高电平时间低字节
                                case (upload_channel)
                                    0: upload_data <= high_time[7:0];
                                    1: upload_data <= high_time[23:16];
                                    2: upload_data <= high_time[39:32];
                                    3: upload_data <= high_time[55:48];
                                    4: upload_data <= high_time[71:64];
                                    5: upload_data <= high_time[87:80];
                                    6: upload_data <= high_time[103:96];
                                    7: upload_data <= high_time[119:112];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            3: begin // 低电平时间高字节
                                case (upload_channel)
                                    0: upload_data <= low_time[15:8];
                                    1: upload_data <= low_time[31:24];
                                    2: upload_data <= low_time[47:40];
                                    3: upload_data <= low_time[63:56];
                                    4: upload_data <= low_time[79:72];
                                    5: upload_data <= low_time[95:88];
                                    6: upload_data <= low_time[111:104];
                                    7: upload_data <= low_time[127:120];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            4: begin // 低电平时间低字节
                                case (upload_channel)
                                    0: upload_data <= low_time[7:0];
                                    1: upload_data <= low_time[23:16];
                                    2: upload_data <= low_time[39:32];
                                    3: upload_data <= low_time[55:48];
                                    4: upload_data <= low_time[71:64];
                                    5: upload_data <= low_time[87:80];
                                    6: upload_data <= low_time[103:96];
                                    7: upload_data <= low_time[119:112];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            5: begin // 周期时间高字节
                                case (upload_channel)
                                    0: upload_data <= period_time[15:8];
                                    1: upload_data <= period_time[31:24];
                                    2: upload_data <= period_time[47:40];
                                    3: upload_data <= period_time[63:56];
                                    4: upload_data <= period_time[79:72];
                                    5: upload_data <= period_time[95:88];
                                    6: upload_data <= period_time[111:104];
                                    7: upload_data <= period_time[127:120];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            6: begin // 周期时间低字节
                                case (upload_channel)
                                    0: upload_data <= period_time[7:0];
                                    1: upload_data <= period_time[23:16];
                                    2: upload_data <= period_time[39:32];
                                    3: upload_data <= period_time[55:48];
                                    4: upload_data <= period_time[71:64];
                                    5: upload_data <= period_time[87:80];
                                    6: upload_data <= period_time[103:96];
                                    7: upload_data <= period_time[119:112];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            7: begin // 占空比高字节
                                case (upload_channel)
                                    0: upload_data <= duty_cycle[15:8];
                                    1: upload_data <= duty_cycle[31:24];
                                    2: upload_data <= duty_cycle[47:40];
                                    3: upload_data <= duty_cycle[63:56];
                                    4: upload_data <= duty_cycle[79:72];
                                    5: upload_data <= duty_cycle[95:88];
                                    6: upload_data <= duty_cycle[111:104];
                                    7: upload_data <= duty_cycle[127:120];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            8: begin // 占空比低字节
                                case (upload_channel)
                                    0: upload_data <= duty_cycle[7:0];
                                    1: upload_data <= duty_cycle[23:16];
                                    2: upload_data <= duty_cycle[39:32];
                                    3: upload_data <= duty_cycle[55:48];
                                    4: upload_data <= duty_cycle[71:64];
                                    5: upload_data <= duty_cycle[87:80];
                                    6: upload_data <= duty_cycle[103:96];
                                    7: upload_data <= duty_cycle[119:112];
                                    default: upload_data <= 8'h00;
                                endcase
                            end
                            default: upload_data <= 8'h00;
                            endcase
                            
                            // 等待仲裁器就绪后再设置valid
                            if (upload_ready) begin
                                upload_valid <= 1'b1;
                                upload_state <= UP_SEND;
                            end
                        end else if (!channel_mask[upload_channel]) begin
                            // 当前通道未启用，跳过到下一个通道
                            upload_channel <= upload_channel + 1;
                            upload_byte_index <= 0;
                        end
                    end
                end
                
                UP_SEND: begin
                    if (upload_ready) begin
                        upload_byte_index <= upload_byte_index + 1;
                        upload_state <= UP_WAIT;
                    end
                end
                
                UP_WAIT: begin
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                    
                    if (upload_byte_index >= 9) begin
                        // 当前通道所有数据上传完毕，移到下一个通道
                        upload_channel <= upload_channel + 1;
                        upload_byte_index <= 0;
                        upload_state <= UP_IDLE;
                    end else if (upload_ready) begin
                        upload_state <= UP_IDLE;
                    end
                end
                
                default: begin
                    upload_state <= UP_IDLE;
                end
            endcase
        end
    end

    // 实例化DSM多通道模块
    dsm_multichannel #(
        .NUM_CHANNELS(8)
    ) u_dsm_multichannel (
        .clk           (clk),
        .rst_n         (rst_n),
        .measure_start (measure_start),
        .measure_pin   (dsm_signal_in),
        .high_time     (high_time),
        .low_time      (low_time),
        // .period_time   (period_time),
        // .duty_cycle    (duty_cycle),
        .measure_done  (measure_done)
    );

endmodule