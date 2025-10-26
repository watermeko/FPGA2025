// DAC指令处理器 - 双通道版本
module dac_handler(
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

        input               dac_clk,
        output logic [13:0] dac_data_a,    // Channel A output
        output logic [13:0] dac_data_b     // Channel B output

    );
    
    // 状态机定义
    localparam H_IDLE          = 2'b00; // 空闲状态
    localparam H_RECEIVING     = 2'b01; // 接收数据
    localparam H_UPDATE_CONFIG = 2'b10; // 更新DAC配置值

    reg [1:0] handler_state;

    // DAC配置寄存器 - 双通道
    reg [2:0]   wave_type_a, wave_type_b;           // 波形类型
    reg [31:0]  frequency_word_a, frequency_word_b; // 频率字
    reg [31:0]  phase_word_a, phase_word_b;         // 相位字

    // 临时存储指令的payload（10字节：通道号 + 9字节配置）
    reg [7:0]   dac_data_buffer [0:9];
    reg         target_channel;  // 0=Channel A, 1=Channel B

    // 在IDLE和RECEIVING状态下，模块都准备好接收数据
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state     <= H_IDLE;
            wave_type_a       <= 3'b000;  // 默认正弦波
            wave_type_b       <= 3'b000;
            frequency_word_a  <= 32'd21474836;   // 默认1MHz
            frequency_word_b  <= 32'd21474836;
            phase_word_a      <= 32'd0;          // 默认0相位
            phase_word_b      <= 32'd0;
            target_channel    <= 1'b0;
            // 初始化数据缓冲区
            for (int i = 0; i < 10; i++) begin
                dac_data_buffer[i] <= 8'h0;
            end
        end
        else begin
            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == 8'hFD) begin
                        handler_state <= H_RECEIVING;
                    end
                end

                H_RECEIVING: begin
                    if (cmd_data_valid && cmd_data_index < 10) begin
                        dac_data_buffer[cmd_data_index] <= cmd_data;
                    end

                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CONFIG; // 数据接收完毕，准备更新
                    end
                end

                H_UPDATE_CONFIG: begin
                    // 解析接收到的数据并更新对应通道配置
                    target_channel = dac_data_buffer[0][0];  // 通道选择

                    if (target_channel == 1'b0) begin  // Channel A
                        wave_type_a      <= dac_data_buffer[1][2:0];
                        frequency_word_a <= {dac_data_buffer[2], dac_data_buffer[3],
                                           dac_data_buffer[4], dac_data_buffer[5]};
                        phase_word_a     <= {dac_data_buffer[6], dac_data_buffer[7],
                                           dac_data_buffer[8], dac_data_buffer[9]};
                    end else begin  // Channel B
                        wave_type_b      <= dac_data_buffer[1][2:0];
                        frequency_word_b <= {dac_data_buffer[2], dac_data_buffer[3],
                                           dac_data_buffer[4], dac_data_buffer[5]};
                        phase_word_b     <= {dac_data_buffer[6], dac_data_buffer[7],
                                           dac_data_buffer[8], dac_data_buffer[9]};
                    end

                    // 配置更新完成，返回空闲状态
                    handler_state <= H_IDLE;
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase
        end
    end

    // DAC模块实例化 - 双通道
    DAC u_DAC_A(
        .clk      	(dac_clk         ),
        .rst_n    	(rst_n           ),
        .fre_word 	(frequency_word_a),
        .pha_word 	(phase_word_a    ),
        .wave_type  (wave_type_a     ),
        .dac_data 	(dac_data_a      )
    );

    DAC u_DAC_B(
        .clk      	(dac_clk         ),
        .rst_n    	(rst_n           ),
        .fre_word 	(frequency_word_b),
        .pha_word 	(phase_word_b    ),
        .wave_type  (wave_type_b     ),
        .dac_data 	(dac_data_b      )
    );

endmodule