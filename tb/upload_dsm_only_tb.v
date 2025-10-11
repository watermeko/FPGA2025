`timescale 1ns / 1ps

// ============================================================================
// Testbench: upload_dsm_only_tb
// Description: DSM单独测试 (仅测试DSM + Upload Pipeline)
//
// 架构:
//   [DSM Handler] -> [Adapter] -> [Packer] -> [Arbiter] -> [Processor]
//
// 测试目的:
//   1. 验证DSM handler的upload功能
//   2. 验证upload pipeline (Adapter -> Packer -> Arbiter)
//   3. 检查协议格式 (0xAA44 + source + length + data + checksum)
// ============================================================================

module upload_dsm_only_tb();

    parameter CLK_PERIOD = 16.67;  // 60MHz
    parameter NUM_CHANNELS = 3;     // 保持3通道架构，但只使用通道2 (DSM)

    // ========================================================================
    // 信号声明
    // ========================================================================

    // 时钟和复位
    reg clk;
    reg rst_n;

    // ===== 模拟Command Processor接口 =====
    reg [7:0]  cmd_type;
    reg [15:0] cmd_length;
    reg [7:0]  cmd_data;
    reg [15:0] cmd_data_index;
    reg        cmd_start;
    reg        cmd_data_valid;
    reg        cmd_done;

    // ===== DSM Handler 输出 =====
    reg  [7:0] dsm_signal_in;
    wire       dsm_cmd_ready;
    wire       dsm_upload_active;
    wire       dsm_upload_req;
    wire [7:0] dsm_upload_data;
    wire [7:0] dsm_upload_source;
    wire       dsm_upload_valid;
    wire       dsm_upload_ready;

    // ===== Adapter 输出 -> Packer 输入 =====
    wire       dsm_packer_req;
    wire [7:0] dsm_packer_data;
    wire [7:0] dsm_packer_source;
    wire       dsm_packer_valid;
    wire       dsm_packer_ready;

    // ===== Packer 输出 -> Arbiter 输入 (仅通道2有效) =====
    wire [NUM_CHANNELS-1:0]      packed_req;
    wire [NUM_CHANNELS*8-1:0]    packed_data;
    wire [NUM_CHANNELS*8-1:0]    packed_source;
    wire [NUM_CHANNELS-1:0]      packed_valid;
    wire [NUM_CHANNELS-1:0]      arbiter_ready;

    // 未使用通道的输入（接地）
    wire       dummy_packer_req_0 = 1'b0;
    wire [7:0] dummy_packer_data_0 = 8'h00;
    wire [7:0] dummy_packer_source_0 = 8'h00;
    wire       dummy_packer_valid_0 = 1'b0;
    wire       dummy_packer_ready_0;  // 未使用

    wire       dummy_packer_req_1 = 1'b0;
    wire [7:0] dummy_packer_data_1 = 8'h00;
    wire [7:0] dummy_packer_source_1 = 8'h00;
    wire       dummy_packer_valid_1 = 1'b0;
    wire       dummy_packer_ready_1;  // 未使用

    // ===== Arbiter 输出 -> Processor =====
    wire       merged_upload_req;
    wire [7:0] merged_upload_data;
    wire [7:0] merged_upload_source;
    wire       merged_upload_valid;
    reg        merged_upload_ready;

    // ===== 统计信息 =====
    integer dsm_byte_count = 0;
    integer merged_byte_count = 0;

    // ========================================================================
    // 模块实例化
    // ========================================================================

    // ----- DSM Handler -----
    dsm_multichannel_handler u_dsm_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(dsm_cmd_ready),
        .dsm_signal_in(dsm_signal_in),
        .upload_active(dsm_upload_active),
        .upload_req(dsm_upload_req),
        .upload_data(dsm_upload_data),
        .upload_source(dsm_upload_source),
        .upload_valid(dsm_upload_valid),
        .upload_ready(dsm_upload_ready)
    );

    // ----- DSM Adapter -----
    upload_adapter u_dsm_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(dsm_upload_active),
        .handler_upload_data(dsm_upload_data),
        .handler_upload_source(dsm_upload_source),
        .handler_upload_valid(dsm_upload_valid),
        .handler_upload_ready(dsm_upload_ready),
        .packer_upload_req(dsm_packer_req),
        .packer_upload_data(dsm_packer_data),
        .packer_upload_source(dsm_packer_source),
        .packer_upload_valid(dsm_packer_valid),
        .packer_upload_ready(dsm_packer_ready)
    );

    // ----- Multi-channel Packer (3 channels, 只有通道2有效) -----
    upload_packer #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        // 通道0,1接地，通道2接DSM
        .raw_upload_req({dsm_packer_req, dummy_packer_req_1, dummy_packer_req_0}),
        .raw_upload_data({dsm_packer_data, dummy_packer_data_1, dummy_packer_data_0}),
        .raw_upload_source({dsm_packer_source, dummy_packer_source_1, dummy_packer_source_0}),
        .raw_upload_valid({dsm_packer_valid, dummy_packer_valid_1, dummy_packer_valid_0}),
        .raw_upload_ready({dsm_packer_ready, dummy_packer_ready_1, dummy_packer_ready_0}),
        .packed_upload_req(packed_req),
        .packed_upload_data(packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid(packed_valid),
        .packed_upload_ready(arbiter_ready)
    );

    // ----- Arbiter (3 sources, 只有source 2有效) -----
    upload_arbiter #(
        .NUM_SOURCES(NUM_CHANNELS),
        .FIFO_DEPTH(128)
    ) u_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .src_upload_req(packed_req),
        .src_upload_data(packed_data),
        .src_upload_source(packed_source),
        .src_upload_valid(packed_valid),
        .src_upload_ready(arbiter_ready),
        .merged_upload_req(merged_upload_req),
        .merged_upload_data(merged_upload_data),
        .merged_upload_source(merged_upload_source),
        .merged_upload_valid(merged_upload_valid),
        .processor_upload_ready(merged_upload_ready)
    );

    // ========================================================================
    // 时钟生成
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ========================================================================
    // 输出监控
    // ========================================================================

    // 监控DSM handler输出
    always @(posedge clk) begin
        if (dsm_upload_valid && dsm_upload_ready) begin
            dsm_byte_count = dsm_byte_count + 1;
            $display("[%0t] DSM->Adapter: 0x%02x (source=0x%02x, req=%b)",
                $time, dsm_upload_data, dsm_upload_source, dsm_upload_req);
        end
    end

    // 监控Arbiter最终输出
    always @(posedge clk) begin
        if (merged_upload_valid && merged_upload_ready) begin
            merged_byte_count = merged_byte_count + 1;
            $display("[%0t] MERGED OUTPUT [%0d]: 0x%02x (source=0x%02x, req=%b)",
                $time, merged_byte_count, merged_upload_data, merged_upload_source, merged_upload_req);
        end
    end

    // ========================================================================
    // DSM信号生成 (模拟方波信号)
    // ========================================================================
    initial begin
        dsm_signal_in = 8'h00;
        #(CLK_PERIOD * 150);  // 等待初始化

        forever begin
            // 通道0: 模拟1kHz方波 (仿真加速: 30us高 + 30us低 = 60us周期)
            dsm_signal_in[0] = 1;
            #30000;  // 高电平 30us
            dsm_signal_in[0] = 0;
            #30000;  // 低电平 30us
        end
    end

    // ========================================================================
    // 测试任务
    // ========================================================================

    // 任务：发送DSM测量指令
    task send_dsm_measure_cmd;
        input [7:0] channel_mask;
        begin
            $display("\n[%0t] ===== Sending DSM MEASURE Command =====", $time);
            $display("  Channel mask: 0x%02x", channel_mask);

            @(posedge clk);
            cmd_type <= 8'h0A;  // CMD_DSM_MEASURE
            cmd_length <= 16'h0001;
            cmd_start <= 1;

            @(posedge clk);
            cmd_start <= 0;
            cmd_data <= channel_mask;
            cmd_data_index <= 0;
            cmd_data_valid <= 1;

            @(posedge clk);
            cmd_data_valid <= 0;
            cmd_done <= 1;

            @(posedge clk);
            cmd_done <= 0;

            $display("[%0t] DSM command sent, waiting for measurement...", $time);
        end
    endtask

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        merged_upload_ready = 1;

        $display("================================================================");
        $display("  DSM Upload Integration Test");
        $display("  Testing: DSM -> Adapter -> Packer -> Arbiter");
        $display("================================================================");

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试：DSM测量通道0
        // ====================================================================
        $display("\n================================================================");
        $display(" TEST: DSM measure channel 0");
        $display(" Expected output: 11 bytes total (UPDATED)");
        $display("   - Header: 0xAA 0x44 (2 bytes)");
        $display("   - Source: 0x0A (1 byte)");
        $display("   - Length: 0x00 0x05 (2 bytes, big-endian, UPDATED)");
        $display("   - Data: ch_num + measurements (5 bytes, UPDATED)");
        $display("   - Checksum: XOR (1 byte)");
        $display("================================================================");

        dsm_byte_count = 0;
        merged_byte_count = 0;

        send_dsm_measure_cmd(8'h01);  // 只启用通道0

        #(CLK_PERIOD * 5000);  // 等待测量完成和数据上传

        $display("\n================================================================");
        $display(" TEST RESULT");
        $display("================================================================");
        $display("  DSM handler output:    %0d bytes", dsm_byte_count);
        $display("  Merged arbiter output: %0d bytes", merged_byte_count);
        $display("================================================================");

        if (merged_byte_count == 11) begin
            $display("✓ PASS: Received correct number of bytes (11)");
        end else begin
            $display("✗ FAIL: Expected 11 bytes, got %0d", merged_byte_count);
        end

        #(CLK_PERIOD * 100);
        $display("\nSimulation completed!");
        $finish;
    end

    // ========================================================================
    // 超时保护
    // ========================================================================
    initial begin
        #(CLK_PERIOD * 10000);
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
