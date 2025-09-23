// DAC指令处理器
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
        output logic [13:0] dac_data
        
    );
    
    // 状态机定义
    localparam H_IDLE          = 2'b00; // 空闲状态
    localparam H_RECEIVING     = 2'b01; // 接收数据
    localparam H_UPDATE_CONFIG = 2'b10; // 更新DAC配置值

    reg [1:0] handler_state;

    // DAC配置寄存器
    reg [1:0]   wave_type;      // 波形类型：0=正弦波，1=三角波，2=锯齿波，3=方波
    reg [31:0]  frequency_word; // 频率字
    reg [31:0]  phase_word;     // 相位字

    // 临时存储指令的payload（9字节）
    reg [7:0]   dac_data_buffer [0:8];

    // 在IDLE和RECEIVING状态下，模块都准备好接收数据
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state     <= H_IDLE;
            wave_type         <= 2'b00;  // 默认正弦波
            frequency_word    <= 32'd21474836;   // 默认1MHz (更正计算错误)
            phase_word        <= 32'd0;          // 默认0相位
            // 初始化数据缓冲区
            for (int i = 0; i < 9; i++) begin
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
                    if (cmd_data_valid && cmd_data_index < 9) begin
                        dac_data_buffer[cmd_data_index] <= cmd_data;
                    end

                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CONFIG; // 数据接收完毕，准备更新
                    end
                end

                H_UPDATE_CONFIG: begin
                    // 解析接收到的数据并直接更新配置
                    wave_type      <= dac_data_buffer[0][1:0];  // 回退到2位
                    frequency_word <= {dac_data_buffer[1], dac_data_buffer[2], 
                                      dac_data_buffer[3], dac_data_buffer[4]};
                    phase_word     <= {dac_data_buffer[5], dac_data_buffer[6], 
                                      dac_data_buffer[7], dac_data_buffer[8]};
                    
                    // 配置更新完成，返回空闲状态
                    handler_state <= H_IDLE;
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase
        end
    end

    // DAC模块实例化，支持跨时钟域
    DAC u_DAC(
        .clk      	(dac_clk       ),
        .rst_n    	(rst_n         ),
        .fre_word 	(frequency_word),
        .pha_word 	(phase_word    ),
        .wave_type  (wave_type     ),
        .dac_data 	(dac_data      )
    );

endmodule