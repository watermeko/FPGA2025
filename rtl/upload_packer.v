// ============================================================================
// Module: upload_packer (多通道可配置版本)
// Description: 数据上传打包模块 - 将原始数据打包成协议格式
//
// 功能：
//   - 支持多通道并行打包（通过参数配置）
//   - 输入：原始数据流 (data, source, valid/ready握手)
//   - 输出：协议格式数据 (0xAA44 + source + length + data + checksum)
//   - 自动计算数据长度和校验和
//
// 协议格式：
//   [0xAA] [0x44] [source] [len_high] [len_low] [data...] [checksum]
//
// 接口说明：
//   - 所有通道信号使用向量拼接
//   - 例：2通道时，raw_upload_data[15:8]=通道1, [7:0]=通道0
//   - 每个通道独立工作，互不干扰
//
// 使用示例：
//   upload_packer #(.NUM_CHANNELS(2)) u_packer (
//       .raw_upload_req({spi_req, uart_req}),
//       .raw_upload_data({spi_data, uart_data}),
//       .raw_upload_source({8'h03, 8'h01}),
//       ...
//   );
// ============================================================================

module upload_packer #(
    parameter NUM_CHANNELS = 2,              // 通道数量
    parameter [7:0] FRAME_HEADER_H = 8'hAA,  // 帧头高字节
    parameter [7:0] FRAME_HEADER_L = 8'h44   // 帧头低字节
)(
    input wire clk,
    input wire rst_n,

    // 输入：来自handler的原始数据（多通道向量）
    input  wire [NUM_CHANNELS-1:0]        raw_upload_req,      // 上传请求
    input  wire [NUM_CHANNELS*8-1:0]      raw_upload_data,     // 原始数据
    input  wire [NUM_CHANNELS*8-1:0]      raw_upload_source,   // 数据来源
    input  wire [NUM_CHANNELS-1:0]        raw_upload_valid,    // 数据有效
    output wire [NUM_CHANNELS-1:0]        raw_upload_ready,    // 准备接收

    // 输出：打包后的协议数据（多通道向量）
    output wire [NUM_CHANNELS-1:0]        packed_upload_req,   // 上传请求
    output wire [NUM_CHANNELS*8-1:0]      packed_upload_data,  // 打包数据
    output wire [NUM_CHANNELS*8-1:0]      packed_upload_source,// 数据来源
    output wire [NUM_CHANNELS-1:0]        packed_upload_valid, // 数据有效
    input  wire [NUM_CHANNELS-1:0]        packed_upload_ready  // 准备接收
);

    // 状态机定义
    localparam IDLE         = 4'd0;
    localparam COLLECT_DATA = 4'd1;
    localparam SEND_HEADER1 = 4'd2;
    localparam SEND_HEADER2 = 4'd3;
    localparam SEND_SOURCE  = 4'd4;
    localparam SEND_LEN_H   = 4'd5;
    localparam SEND_LEN_L   = 4'd6;
    localparam SEND_DATA    = 4'd7;
    localparam SEND_CHECKSUM= 4'd8;

    // 内部寄存器数组（在 generate 外部声明）
    reg [3:0] state [0:NUM_CHANNELS-1];
    reg [7:0] data_buffer [0:NUM_CHANNELS-1][0:255];
    reg [7:0] data_count [0:NUM_CHANNELS-1];
    reg [7:0] data_index [0:NUM_CHANNELS-1];
    reg [7:0] current_source [0:NUM_CHANNELS-1];
    reg [7:0] checksum [0:NUM_CHANNELS-1];

    reg [NUM_CHANNELS-1:0] ch_packed_req;
    reg [NUM_CHANNELS*8-1:0] ch_packed_data;
    reg [NUM_CHANNELS*8-1:0] ch_packed_source;
    reg [NUM_CHANNELS-1:0] ch_packed_valid;

    // 连接内部寄存器到输出端口（在 generate 外部）
    assign packed_upload_req = ch_packed_req;
    assign packed_upload_data = ch_packed_data;
    assign packed_upload_source = ch_packed_source;
    assign packed_upload_valid = ch_packed_valid;

    // 为每个通道生成独立的打包逻辑
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : gen_packer_channels
            // 握手控制
            assign raw_upload_ready[i] = (state[i] == COLLECT_DATA);

            // 每个通道的独立状态机
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    state[i] <= IDLE;
                    data_count[i] <= 0;
                    data_index[i] <= 0;
                    current_source[i] <= 0;
                    checksum[i] <= 0;
                    ch_packed_req[i] <= 0;
                    ch_packed_valid[i] <= 0;
                    ch_packed_data[i*8 +: 8] <= 0;
                    ch_packed_source[i*8 +: 8] <= 0;
                end else begin
                    case (state[i])
                        IDLE: begin
                            ch_packed_req[i] <= 0;
                            ch_packed_valid[i] <= 0;
                            data_count[i] <= 0;
                            data_index[i] <= 0;
                            checksum[i] <= 0;

                            // 检测到上传请求，开始收集数据
                            if (raw_upload_req[i]) begin
                                current_source[i] <= raw_upload_source[i*8 +: 8];
                                state[i] <= COLLECT_DATA;
                            end
                        end

                        COLLECT_DATA: begin
                            // 收集原始数据到缓冲区
                            if (raw_upload_valid[i] && raw_upload_ready[i]) begin
                                data_buffer[i][data_count[i]] <= raw_upload_data[i*8 +: 8];
                                data_count[i] <= data_count[i] + 1;
                            end

                            // 数据收集完成（req拉低）或缓冲区满
                            if (!raw_upload_req[i] || data_count[i] == 255) begin
                                if (data_count[i] > 0) begin
                                    // 有数据，开始打包发送
                                    ch_packed_source[i*8 +: 8] <= current_source[i];
                                    state[i] <= SEND_HEADER1;
                                end else begin
                                    // 没有数据，返回IDLE
                                    state[i] <= IDLE;
                                end
                            end
                        end

                        SEND_HEADER1: begin
                            // 发送帧头第1字节
                            ch_packed_req[i] <= 1;
                            ch_packed_data[i*8 +: 8] <= FRAME_HEADER_H;
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= FRAME_HEADER_H;

                            if (packed_upload_ready[i]) begin
                                state[i] <= SEND_HEADER2;
                            end
                        end

                        SEND_HEADER2: begin
                            // 发送帧头第2字节
                            ch_packed_data[i*8 +: 8] <= FRAME_HEADER_L;
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= checksum[i] + FRAME_HEADER_L;

                            if (packed_upload_ready[i]) begin
                                state[i] <= SEND_SOURCE;
                            end
                        end

                        SEND_SOURCE: begin
                            // 发送数据来源
                            ch_packed_data[i*8 +: 8] <= current_source[i];
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= checksum[i] + current_source[i];

                            if (packed_upload_ready[i]) begin
                                state[i] <= SEND_LEN_H;
                            end
                        end

                        SEND_LEN_H: begin
                            // 发送长度高字节（固定为0，因为最大256字节）
                            ch_packed_data[i*8 +: 8] <= 8'h00;
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= checksum[i] + 8'h00;

                            if (packed_upload_ready[i]) begin
                                state[i] <= SEND_LEN_L;
                            end
                        end

                        SEND_LEN_L: begin
                            // 发送长度低字节
                            ch_packed_data[i*8 +: 8] <= data_count[i];
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= checksum[i] + data_count[i];

                            if (packed_upload_ready[i]) begin
                                data_index[i] <= 0;
                                state[i] <= SEND_DATA;
                            end
                        end

                        SEND_DATA: begin
                            // 发送数据字节
                            ch_packed_data[i*8 +: 8] <= data_buffer[i][data_index[i]];
                            ch_packed_valid[i] <= 1;
                            checksum[i] <= checksum[i] + data_buffer[i][data_index[i]];

                            if (packed_upload_ready[i]) begin
                                if (data_index[i] == data_count[i] - 1) begin
                                    // 数据发送完成
                                    state[i] <= SEND_CHECKSUM;
                                end else begin
                                    data_index[i] <= data_index[i] + 1;
                                end
                            end
                        end

                        SEND_CHECKSUM: begin
                            // 发送校验和
                            ch_packed_data[i*8 +: 8] <= checksum[i];
                            ch_packed_valid[i] <= 1;

                            if (packed_upload_ready[i]) begin
                                state[i] <= IDLE;
                            end
                        end

                        default: begin
                            state[i] <= IDLE;
                            ch_packed_valid[i] <= 0;
                            ch_packed_req[i] <= 0;
                        end
                    endcase
                end
            end
        end
    endgenerate

endmodule
