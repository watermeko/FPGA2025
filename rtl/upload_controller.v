// ============================================================================
// Module: upload_controller (统一仲裁+打包控制器)
// Description: 合并了upload_arbiter和upload_packer的功能，优化CLS使用
//
// 架构优化：
//   - 单一状态机（替代原来5+1个状态机）
//   - 单一数据缓冲区（替代原来5×16字节分布式缓存）
//   - 统一的仲裁和打包逻辑
//   - 时分复用设计，降低资源占用
//
// 功能：
//   1. 固定优先级仲裁：uart > spi > i2c > spi_slave > i2c_slave
//   2. 自动打包成协议格式：0xAA44 + source + length + data + checksum
//   3. 保证数据包完整性（不会中途切换数据源）
//
// 相比原架构的优化：
//   - CLS资源节省：约400-500个
//   - 状态机数量：6个 → 1个
//   - 缓冲区：80字节 → 16字节
// ============================================================================

module upload_controller #(
    parameter NUM_SOURCES = 6,              // 数据源数量
    parameter BUFFER_SIZE = 16,             // 单一共享缓冲区大小（字节）
    parameter [7:0] FRAME_HEADER_H = 8'hAA, // 帧头高字节
    parameter [7:0] FRAME_HEADER_L = 8'h44  // 帧头低字节
)(
    input wire clk,
    input wire rst_n,

    // 输入：来自各个handler的原始数据（多源向量）
    input  wire [NUM_SOURCES-1:0]        src_upload_req,      // 上传请求
    input  wire [NUM_SOURCES*8-1:0]      src_upload_data,     // 原始数据
    input  wire [NUM_SOURCES*8-1:0]      src_upload_source,   // 数据来源
    input  wire [NUM_SOURCES-1:0]        src_upload_valid,    // 数据有效
    output wire [NUM_SOURCES-1:0]        src_upload_ready,    // 准备接收

    // 输出：打包后的协议数据到processor
    output reg                           merged_upload_req,   // 上传请求
    output reg  [7:0]                    merged_upload_data,  // 打包数据
    output reg  [7:0]                    merged_upload_source,// 数据来源
    output reg                           merged_upload_valid, // 数据有效
    input  wire                          processor_upload_ready // 准备接收
);

    // ========================================================================
    // 状态机定义（单一统一状态机）
    // ========================================================================
    localparam IDLE          = 4'd0;  // 空闲，等待数据源
    localparam COLLECT       = 4'd1;  // 收集原始数据到缓冲区
    localparam SEND_HEADER1  = 4'd2;  // 发送帧头第1字节 0xAA
    localparam SEND_HEADER2  = 4'd3;  // 发送帧头第2字节 0x44
    localparam SEND_SOURCE   = 4'd4;  // 发送数据来源
    localparam SEND_LEN_H    = 4'd5;  // 发送长度高字节
    localparam SEND_LEN_L    = 4'd6;  // 发送长度低字节
    localparam SEND_DATA     = 4'd7;  // 发送数据
    localparam SEND_CHECKSUM = 4'd8;  // 发送校验和

    reg [3:0] state;

    // ========================================================================
    // 共享资源（所有通道共用）
    // ========================================================================
    reg [7:0] data_buffer [0:BUFFER_SIZE-1];  // 单一共享缓冲区
    reg [7:0] data_count;                     // 当前数据计数
    reg [7:0] data_index;                     // 发送数据索引
    reg [2:0] current_source;                 // 当前服务的数据源(0-4)
    reg [7:0] current_source_id;              // 当前数据源ID
    reg [7:0] checksum;                       // 校验和
    reg       in_packet;                      // 正在处理数据包标志

    // ========================================================================
    // 优先级仲裁逻辑（组合逻辑）
    // ========================================================================
    reg [2:0] next_source;
    reg       source_available;

    integer i;
    always @(*) begin
        next_source = 3'd0;
        source_available = 1'b0;

        // 固定优先级：0(uart) > 1(spi) > 2(i2c) > 3(spi_slave) > 4(i2c_slave)
        for (i = NUM_SOURCES - 1; i >= 0; i = i - 1) begin
            if (src_upload_req[i]) begin
                next_source = i[2:0];
                source_available = 1'b1;
            end
        end
    end

    // ========================================================================
    // Ready信号生成（只有当前服务的源ready为高）
    // ========================================================================
    genvar j;
    generate
        for (j = 0; j < NUM_SOURCES; j = j + 1) begin : gen_ready
            assign src_upload_ready[j] = (state == COLLECT) &&
                                         (current_source == j[2:0]) &&
                                         (data_count < BUFFER_SIZE);
        end
    endgenerate

    // ========================================================================
    // 主状态机（单一控制逻辑）
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_source <= 3'd0;
            current_source_id <= 8'd0;
            data_count <= 8'd0;
            data_index <= 8'd0;
            checksum <= 8'd0;
            in_packet <= 1'b0;
            merged_upload_req <= 1'b0;
            merged_upload_data <= 8'd0;
            merged_upload_source <= 8'd0;
            merged_upload_valid <= 1'b0;
        end else begin
            case (state)
                // ================================================================
                // IDLE: 等待任意数据源有数据请求
                // ================================================================
                IDLE: begin
                    merged_upload_req <= 1'b0;
                    merged_upload_valid <= 1'b0;
                    merged_upload_data <= 8'd0;  // 清空数据线
                    data_count <= 8'd0;
                    data_index <= 8'd0;
                    checksum <= 8'd0;

                    if (source_available) begin
                        // 选中优先级最高的数据源
                        current_source <= next_source;
                        current_source_id <= src_upload_source[next_source*8 +: 8];
                        in_packet <= 1'b1;
                        state <= COLLECT;
                    end
                end

                // ================================================================
                // COLLECT: 收集原始数据到缓冲区
                // ================================================================
                COLLECT: begin
                    // 接收数据
                    if (src_upload_valid[current_source] &&
                        src_upload_ready[current_source]) begin
                        data_buffer[data_count] <= src_upload_data[current_source*8 +: 8];
                        data_count <= data_count + 1;
                    end

                    // 收集完成条件：
                    // 1. req拉低 且 当前没有pending的valid数据
                    // 2. 或者缓冲区即将满（下一次写入会达到上限）
                    if ((!src_upload_req[current_source] && !src_upload_valid[current_source]) ||
                        (data_count >= BUFFER_SIZE - 1)) begin
                        if (data_count > 0) begin
                            // 有数据，开始打包
                            state <= SEND_HEADER1;
                        end else begin
                            // 无数据，返回IDLE
                            in_packet <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end

                // ================================================================
                // SEND_HEADER1: 发送帧头第1字节
                // ================================================================
                SEND_HEADER1: begin
                    merged_upload_req <= 1'b1;
                    merged_upload_source <= current_source_id;

                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= FRAME_HEADER_H;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= FRAME_HEADER_H;
                        merged_upload_valid <= 1'b0;
                        state <= SEND_HEADER2;
                    end
                end

                // ================================================================
                // SEND_HEADER2: 发送帧头第2字节
                // ================================================================
                SEND_HEADER2: begin
                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= FRAME_HEADER_L;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= checksum + FRAME_HEADER_L;
                        merged_upload_valid <= 1'b0;
                        state <= SEND_SOURCE;
                    end
                end

                // ================================================================
                // SEND_SOURCE: 发送数据来源
                // ================================================================
                SEND_SOURCE: begin
                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= current_source_id;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= checksum + current_source_id;
                        merged_upload_valid <= 1'b0;
                        state <= SEND_LEN_H;
                    end
                end

                // ================================================================
                // SEND_LEN_H: 发送长度高字节（固定为0）
                // ================================================================
                SEND_LEN_H: begin
                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= 8'h00;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= checksum + 8'h00;
                        merged_upload_valid <= 1'b0;
                        state <= SEND_LEN_L;
                    end
                end

                // ================================================================
                // SEND_LEN_L: 发送长度低字节
                // ================================================================
                SEND_LEN_L: begin
                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= data_count;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= checksum + data_count;
                        data_index <= 8'd0;
                        merged_upload_valid <= 1'b0;  // 握手成功，拉低valid
                        state <= SEND_DATA;
                    end
                end

                // ================================================================
                // SEND_DATA: 发送数据字节
                // ================================================================
                SEND_DATA: begin
                    // 只在第一次进入状态或状态保持时设置数据（关键：只设置一次）
                    if (!merged_upload_valid) begin
                        merged_upload_data <= data_buffer[data_index];
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        checksum <= checksum + data_buffer[data_index];
                        merged_upload_valid <= 1'b0;  // 握手成功，拉低valid

                        if (data_index == data_count - 1) begin
                            // 最后一个数据字节已发送，转到发送校验和
                            state <= SEND_CHECKSUM;
                        end else begin
                            // 还有更多数据，递增索引
                            data_index <= data_index + 1;
                            // 保持在SEND_DATA状态，下一周期会重新设置valid和data
                        end
                    end
                end

                // ================================================================
                // SEND_CHECKSUM: 发送校验和，完成一个数据包
                // ================================================================
                SEND_CHECKSUM: begin
                    // 只在第一次进入状态时设置数据
                    if (!merged_upload_valid) begin
                        merged_upload_data <= checksum;
                        merged_upload_valid <= 1'b1;
                    end

                    if (processor_upload_ready && merged_upload_valid) begin
                        in_packet <= 1'b0;
                        merged_upload_valid <= 1'b0;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
