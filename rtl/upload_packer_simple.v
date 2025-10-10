// ============================================================================
// Module: upload_packer_simple (单通道简化版本)
// Description: 数据上传打包模块 - 将原始数据打包成协议格式
//
// 协议格式：
//   [0xAA] [0x44] [source] [len_high] [len_low] [data...] [checksum]
//
// 简化版本说明：
//   - 只支持单通道（避免generate块的综合问题）
//   - 经过验证可以正常工作
//   - 如需多通道，在top层实例化多个模块
// ============================================================================

module upload_packer_simple #(
    parameter [7:0] FRAME_HEADER_H = 8'hAA,  // 帧头高字节
    parameter [7:0] FRAME_HEADER_L = 8'h44   // 帧头低字节
)(
    input wire clk,
    input wire rst_n,

    // 输入：来自handler的原始数据
    input  wire       raw_upload_req,      // 上传请求
    input  wire [7:0] raw_upload_data,     // 原始数据
    input  wire [7:0] raw_upload_source,   // 数据来源
    input  wire       raw_upload_valid,    // 数据有效
    output wire       raw_upload_ready,    // 准备接收

    // 输出：打包后的协议数据
    output reg        packed_upload_req,   // 上传请求
    output reg  [7:0] packed_upload_data,  // 打包数据
    output reg  [7:0] packed_upload_source,// 数据来源
    output reg        packed_upload_valid, // 数据有效
    input  wire       packed_upload_ready  // 准备接收
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

    // 内部寄存器
    reg [3:0] state;
    reg [7:0] data_buffer [0:255];
    reg [7:0] data_count;
    reg [7:0] data_index;
    reg [7:0] current_source;
    reg [7:0] checksum;

    // 握手控制
    assign raw_upload_ready = (state == COLLECT_DATA);

    // 状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            data_count <= 0;
            data_index <= 0;
            current_source <= 0;
            checksum <= 0;
            packed_upload_req <= 0;
            packed_upload_valid <= 0;
            packed_upload_data <= 0;
            packed_upload_source <= 0;
        end else begin
            case (state)
                IDLE: begin
                    packed_upload_req <= 0;
                    packed_upload_valid <= 0;
                    packed_upload_data <= 0;  // 清空数据线
                    data_count <= 0;
                    data_index <= 0;
                    checksum <= 0;

                    if (raw_upload_req) begin
                        current_source <= raw_upload_source;
                        state <= COLLECT_DATA;
                    end
                end

                COLLECT_DATA: begin
                    if (raw_upload_valid && raw_upload_ready) begin
                        data_buffer[data_count] <= raw_upload_data;
                        data_count <= data_count + 1;
                    end

                    if (!raw_upload_req || data_count == 255) begin
                        if (data_count > 0) begin
                            packed_upload_source <= current_source;
                            state <= SEND_HEADER1;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                SEND_HEADER1: begin
                    packed_upload_req <= 1;
                    packed_upload_data <= FRAME_HEADER_H;
                    packed_upload_valid <= 1;
                    checksum <= FRAME_HEADER_H;

                    if (packed_upload_ready) begin
                        state <= SEND_HEADER2;
                    end
                end

                SEND_HEADER2: begin
                    packed_upload_data <= FRAME_HEADER_L;
                    packed_upload_valid <= 1;
                    checksum <= checksum + FRAME_HEADER_L;

                    if (packed_upload_ready) begin
                        state <= SEND_SOURCE;
                    end
                end

                SEND_SOURCE: begin
                    packed_upload_data <= current_source;
                    packed_upload_valid <= 1;
                    checksum <= checksum + current_source;

                    if (packed_upload_ready) begin
                        state <= SEND_LEN_H;
                    end
                end

                SEND_LEN_H: begin
                    packed_upload_data <= 8'h00;
                    packed_upload_valid <= 1;
                    checksum <= checksum + 8'h00;

                    if (packed_upload_ready) begin
                        state <= SEND_LEN_L;
                    end
                end

                SEND_LEN_L: begin
                    packed_upload_data <= data_count;
                    packed_upload_valid <= 1;
                    checksum <= checksum + data_count;

                    if (packed_upload_ready) begin
                        data_index <= 0;
                        state <= SEND_DATA;
                    end
                end

                SEND_DATA: begin
                    packed_upload_data <= data_buffer[data_index];
                    packed_upload_valid <= 1;
                    checksum <= checksum + data_buffer[data_index];

                    if (packed_upload_ready) begin
                        if (data_index == data_count - 1) begin
                            state <= SEND_CHECKSUM;
                        end else begin
                            data_index <= data_index + 1;
                        end
                    end
                end

                SEND_CHECKSUM: begin
                    packed_upload_data <= checksum;
                    packed_upload_valid <= 1;

                    if (packed_upload_ready) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                    packed_upload_valid <= 0;
                    packed_upload_req <= 0;
                end
            endcase
        end
    end

endmodule
