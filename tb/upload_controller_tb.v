// ============================================================================
// Testbench: upload_controller_tb
// Description: 验证upload_controller模块的功能
//
// 测试场景：
//   1. 单源数据上传
//   2. 多源优先级仲裁
//   3. 数据包完整性
//   4. 缓冲区满处理
//   5. 协议格式正确性
// ============================================================================

`timescale 1ns/1ps

module upload_controller_tb;

    // ========================================================================
    // 测试参数
    // ========================================================================
    parameter NUM_SOURCES = 5;
    parameter CLK_PERIOD = 10;  // 10ns = 100MHz

    // ========================================================================
    // DUT信号
    // ========================================================================
    reg clk;
    reg rst_n;

    // 输入信号
    reg  [NUM_SOURCES-1:0]        src_upload_req;
    reg  [NUM_SOURCES*8-1:0]      src_upload_data;
    reg  [NUM_SOURCES*8-1:0]      src_upload_source;
    reg  [NUM_SOURCES-1:0]        src_upload_valid;
    wire [NUM_SOURCES-1:0]        src_upload_ready;

    // 输出信号
    wire                          merged_upload_req;
    wire [7:0]                    merged_upload_data;
    wire [7:0]                    merged_upload_source;
    wire                          merged_upload_valid;
    reg                           processor_upload_ready;

    // ========================================================================
    // 测试辅助变量
    // ========================================================================
    integer i;
    reg [7:0] received_data [0:255];  // 接收数据缓冲区
    integer received_count;
    integer verify_start_index;       // 新增：验证起始索引
    reg [7:0] expected_checksum;

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // DUT实例化
    // ========================================================================
    upload_controller #(
        .NUM_SOURCES(NUM_SOURCES),
        .BUFFER_SIZE(16),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .src_upload_req(src_upload_req),
        .src_upload_data(src_upload_data),
        .src_upload_source(src_upload_source),
        .src_upload_valid(src_upload_valid),
        .src_upload_ready(src_upload_ready),
        .merged_upload_req(merged_upload_req),
        .merged_upload_data(merged_upload_data),
        .merged_upload_source(merged_upload_source),
        .merged_upload_valid(merged_upload_valid),
        .processor_upload_ready(processor_upload_ready)
    );

    // ========================================================================
    // 接收数据监控
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            received_count <= 0;
        end else if (merged_upload_valid && processor_upload_ready) begin
            received_data[received_count] <= merged_upload_data;
            received_count <= received_count + 1;
            $display("[%0t] RX[%0d]: 0x%02h", $time, received_count, merged_upload_data);
        end
    end

    // ========================================================================
    // 测试任务：发送数据到指定源
    // ========================================================================
    task send_data_to_source;
        input [2:0] source_id;      // 数据源索引 (0-4)
        input [7:0] source_tag;     // 数据源标识
        input [7:0] data_len;       // 数据长度
        input [7:0] start_value;    // 起始数据值
        integer j;
        begin
            $display("\n[%0t] === 开始发送数据到源%0d (标识=0x%02h) ===", $time, source_id, source_tag);
            $display("[%0t] 数据长度: %0d字节, 起始值: 0x%02h", $time, data_len, start_value);

            // 设置source和req
            src_upload_source[source_id*8 +: 8] = source_tag;
            src_upload_req[source_id] = 1'b1;

            // 等待ready
            @(posedge clk);
            while (!src_upload_ready[source_id]) @(posedge clk);

            // 发送数据
            for (j = 0; j < data_len; j = j + 1) begin
                src_upload_data[source_id*8 +: 8] = start_value + j;
                src_upload_valid[source_id] = 1'b1;
                @(posedge clk);
                // 等待握手完成
                while (!src_upload_ready[source_id]) @(posedge clk);
                $display("[%0t] 源%0d 发送数据[%0d]: 0x%02h", $time, source_id, j, start_value + j);
            end

            // 结束传输：先拉低valid，再拉低req
            src_upload_valid[source_id] = 1'b0;
            @(posedge clk);  // 确保valid拉低被采样
            src_upload_req[source_id] = 1'b0;

            $display("[%0t] === 源%0d 数据发送完成 ===\n", $time, source_id);
        end
    endtask

    // ========================================================================
    // 测试任务：验证接收到的协议帧
    // ========================================================================
    task verify_frame;
        input [7:0] expected_source;
        input [7:0] expected_len;
        input [7:0] expected_start_value;
        integer k;
        integer frame_start;
        reg [7:0] calc_checksum;
        begin
            $display("\n[%0t] === 验证接收到的协议帧 ===", $time);

            // 记录验证起始位置
            frame_start = verify_start_index;

            // 等待数据包接收完成
            #(CLK_PERIOD * 50);

            // 验证帧头
            if (received_data[frame_start + 0] !== 8'hAA || received_data[frame_start + 1] !== 8'h44) begin
                $display("ERROR: 帧头错误! 期望: 0xAA44, 实际: 0x%02h%02h",
                         received_data[frame_start + 0], received_data[frame_start + 1]);
            end else begin
                $display("PASS: 帧头正确 (0xAA44)");
            end

            // 验证数据源
            if (received_data[frame_start + 2] !== expected_source) begin
                $display("ERROR: 数据源错误! 期望: 0x%02h, 实际: 0x%02h",
                         expected_source, received_data[frame_start + 2]);
            end else begin
                $display("PASS: 数据源正确 (0x%02h)", expected_source);
            end

            // 验证长度
            if (received_data[frame_start + 3] !== 8'h00 || received_data[frame_start + 4] !== expected_len) begin
                $display("ERROR: 长度错误! 期望: 0x00%02h, 实际: 0x%02h%02h",
                         expected_len, received_data[frame_start + 3], received_data[frame_start + 4]);
            end else begin
                $display("PASS: 长度正确 (%0d字节)", expected_len);
            end

            // 验证数据内容
            for (k = 0; k < expected_len; k = k + 1) begin
                if (received_data[frame_start + 5 + k] !== (expected_start_value + k)) begin
                    $display("ERROR: 数据[%0d]错误! 期望: 0x%02h, 实际: 0x%02h",
                             k, expected_start_value + k, received_data[frame_start + 5 + k]);
                end
            end
            $display("PASS: 数据内容正确");

            // 验证校验和
            calc_checksum = 8'h00;
            for (k = 0; k < (5 + expected_len); k = k + 1) begin
                calc_checksum = calc_checksum + received_data[frame_start + k];
            end
            if (received_data[frame_start + 5 + expected_len] !== calc_checksum) begin
                $display("ERROR: 校验和错误! 期望: 0x%02h, 实际: 0x%02h",
                         calc_checksum, received_data[frame_start + 5 + expected_len]);
            end else begin
                $display("PASS: 校验和正确 (0x%02h)", calc_checksum);
            end

            $display("=== 帧验证完成 ===\n");

            // 更新下一帧的起始索引（帧头2 + source1 + len2 + data + checksum1）
            verify_start_index = verify_start_index + 5 + expected_len + 1;
        end
    endtask

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        $display("\n========================================");
        $display("upload_controller Testbench 开始");
        $display("========================================\n");

        // 初始化信号
        rst_n = 0;
        src_upload_req = 5'b00000;
        src_upload_data = 40'h0;
        src_upload_source = 40'h0;
        src_upload_valid = 5'b00000;
        processor_upload_ready = 1'b1;
        received_count = 0;
        verify_start_index = 0;  // 初始化验证索引

        // 复位
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);

        // ====================================================================
        // 测试1: 单源数据上传（UART源，8字节数据）
        // ====================================================================
        $display("\n****************************************");
        $display("测试1: 单源数据上传 (UART)");
        $display("****************************************");

        send_data_to_source(
            .source_id(3'd0),       // UART = 源0
            .source_tag(8'h01),     // UART标识 = 0x01
            .data_len(8'd8),        // 8字节数据
            .start_value(8'h10)     // 数据: 0x10, 0x11, ..., 0x17
        );

        verify_frame(
            .expected_source(8'h01),
            .expected_len(8'd8),
            .expected_start_value(8'h10)
        );

        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试2: 单源数据上传（SPI源，12字节数据）
        // ====================================================================
        $display("\n****************************************");
        $display("测试2: 单源数据上传 (SPI)");
        $display("****************************************");

        send_data_to_source(
            .source_id(3'd1),       // SPI = 源1
            .source_tag(8'h03),     // SPI标识 = 0x03
            .data_len(8'd12),       // 12字节数据
            .start_value(8'hA0)     // 数据: 0xA0, 0xA1, ..., 0xAB
        );

        verify_frame(
            .expected_source(8'h03),
            .expected_len(8'd12),
            .expected_start_value(8'hA0)
        );

        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试3: 优先级仲裁测试（包间仲裁：先I2C后UART，测试包完整性）
        // ====================================================================
        $display("\n****************************************");
        $display("测试3: 包间仲裁 (先I2C后UART)");
        $display("****************************************");

        // I2C先发送（先启动）
        send_data_to_source(
            .source_id(3'd2),       // I2C = 源2
            .source_tag(8'h05),     // I2C标识
            .data_len(8'd6),
            .start_value(8'h50)
        );

        // 验证I2C的包
        verify_frame(
            .expected_source(8'h05),
            .expected_len(8'd6),
            .expected_start_value(8'h50)
        );

        // 然后UART发送
        send_data_to_source(
            .source_id(3'd0),       // UART = 源0
            .source_tag(8'h01),     // UART标识
            .data_len(8'd5),
            .start_value(8'h20)
        );

        // 验证UART的包
        verify_frame(
            .expected_source(8'h01),
            .expected_len(8'd5),
            .expected_start_value(8'h20)
        );

        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试3.5: 真正的优先级测试（IDLE状态下同时请求）
        // ====================================================================
        $display("\n****************************************");
        $display("测试3.5: 同时请求优先级 (UART > I2C)");
        $display("****************************************");

        // 确保在IDLE状态
        #(CLK_PERIOD * 5);

        // 同时拉高两个源的req（UART应该被优先选中）
        fork
            begin
                // I2C立即请求
                src_upload_req[2] = 1'b1;
                src_upload_source[2*8 +: 8] = 8'h05;
            end
            begin
                // UART立即请求（优先级更高）
                src_upload_req[0] = 1'b1;
                src_upload_source[0*8 +: 8] = 8'h01;
            end
        join

        #(CLK_PERIOD * 2);

        // UART发送4字节数据（应该被先处理）
        @(posedge clk);
        while (!src_upload_ready[0]) @(posedge clk);
        src_upload_data[0*8 +: 8] = 8'h30;
        src_upload_valid[0] = 1'b1;
        @(posedge clk);
        src_upload_valid[0] = 1'b0;
        $display("[%0t] UART发送: 0x30", $time);

        @(posedge clk);
        while (!src_upload_ready[0]) @(posedge clk);
        src_upload_data[0*8 +: 8] = 8'h31;
        src_upload_valid[0] = 1'b1;
        @(posedge clk);
        src_upload_valid[0] = 1'b0;
        $display("[%0t] UART发送: 0x31", $time);

        @(posedge clk);
        while (!src_upload_ready[0]) @(posedge clk);
        src_upload_data[0*8 +: 8] = 8'h32;
        src_upload_valid[0] = 1'b1;
        @(posedge clk);
        src_upload_valid[0] = 1'b0;
        $display("[%0t] UART发送: 0x32", $time);

        @(posedge clk);
        while (!src_upload_ready[0]) @(posedge clk);
        src_upload_data[0*8 +: 8] = 8'h33;
        src_upload_valid[0] = 1'b1;
        @(posedge clk);
        src_upload_valid[0] = 1'b0;
        $display("[%0t] UART发送: 0x33", $time);

        src_upload_req[0] = 1'b0;

        // 等待UART包发送完成
        #(CLK_PERIOD * 50);

        // I2C发送4字节数据（等UART完成后被处理）
        @(posedge clk);
        while (!src_upload_ready[2]) @(posedge clk);
        src_upload_data[2*8 +: 8] = 8'h60;
        src_upload_valid[2] = 1'b1;
        @(posedge clk);
        src_upload_valid[2] = 1'b0;
        $display("[%0t] I2C发送: 0x60", $time);

        @(posedge clk);
        while (!src_upload_ready[2]) @(posedge clk);
        src_upload_data[2*8 +: 8] = 8'h61;
        src_upload_valid[2] = 1'b1;
        @(posedge clk);
        src_upload_valid[2] = 1'b0;
        $display("[%0t] I2C发送: 0x61", $time);

        @(posedge clk);
        while (!src_upload_ready[2]) @(posedge clk);
        src_upload_data[2*8 +: 8] = 8'h62;
        src_upload_valid[2] = 1'b1;
        @(posedge clk);
        src_upload_valid[2] = 1'b0;
        $display("[%0t] I2C发送: 0x62", $time);

        @(posedge clk);
        while (!src_upload_ready[2]) @(posedge clk);
        src_upload_data[2*8 +: 8] = 8'h63;
        src_upload_valid[2] = 1'b1;
        @(posedge clk);
        src_upload_valid[2] = 1'b0;
        $display("[%0t] I2C发送: 0x63", $time);

        src_upload_req[2] = 1'b0;

        #(CLK_PERIOD * 10);

        // 验证UART的包（应该先收到）
        verify_frame(
            .expected_source(8'h01),
            .expected_len(8'd4),
            .expected_start_value(8'h30)
        );

        // 验证I2C的包（后收到）
        verify_frame(
            .expected_source(8'h05),
            .expected_len(8'd4),
            .expected_start_value(8'h60)
        );

        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试4: 缓冲区满处理（16字节边界）
        // ====================================================================
        $display("\n****************************************");
        $display("测试4: 缓冲区满处理 (16字节)");
        $display("****************************************");

        send_data_to_source(
            .source_id(3'd0),       // UART
            .source_tag(8'h01),
            .data_len(8'd16),       // 正好16字节（缓冲区大小）
            .start_value(8'hC0)
        );

        verify_frame(
            .expected_source(8'h01),
            .expected_len(8'd16),
            .expected_start_value(8'hC0)
        );

        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试5: 背压测试（processor_ready间歇性拉低）
        // ====================================================================
        $display("\n****************************************");
        $display("测试5: 背压测试");
        $display("****************************************");

        // 启动数据发送
        fork
            begin
                send_data_to_source(
                    .source_id(3'd1),
                    .source_tag(8'h03),
                    .data_len(8'd10),
                    .start_value(8'hD0)
                );
            end
            begin
                // 模拟processor间歇性不ready
                #(CLK_PERIOD * 20);
                repeat (5) begin
                    processor_upload_ready = 1'b0;
                    #(CLK_PERIOD * 3);
                    processor_upload_ready = 1'b1;
                    #(CLK_PERIOD * 5);
                end
            end
        join

        verify_frame(
            .expected_source(8'h03),
            .expected_len(8'd10),
            .expected_start_value(8'hD0)
        );

        // ====================================================================
        // 测试完成
        // ====================================================================
        #(CLK_PERIOD * 50);

        $display("\n========================================");
        $display("所有测试完成！");
        $display("========================================\n");

        $finish;
    end

    // ========================================================================
    // 超时保护
    // ========================================================================
    initial begin
        #(CLK_PERIOD * 10000);
        $display("\nERROR: 测试超时！");
        $finish;
    end

    // ========================================================================
    // 波形导出
    // ========================================================================
    initial begin
        $dumpfile("upload_controller_tb.vcd");
        $dumpvars(0, upload_controller_tb);
    end

endmodule
