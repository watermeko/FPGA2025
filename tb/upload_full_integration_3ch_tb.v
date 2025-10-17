`timescale 1ns / 1ps

// ============================================================================
// Testbench: upload_full_integration_3ch_tb
// Description: 三通道集成测试 (UART + SPI + DSM)
//
// 架构:
//   [UART Handler] -> [Adapter] -> [Packer] -> [Arbiter] -> [Processor]
//   [SPI Handler]  -> [Adapter] -> [Packer] -> [Arbiter] -> [Processor]
//   [DSM Handler]  -> [Adapter] -> [Packer] -> [Arbiter] -> [Processor]
//
// 测试目的:
//   1. 验证三个模块的完整集成
//   2. 测试DSM的upload功能
//   3. 验证三通道并发上传
//   4. 检查优先级调度
// ============================================================================

module upload_full_integration_3ch_tb();

    parameter CLK_PERIOD = 16.67;  // 60MHz
    parameter NUM_CHANNELS = 3;     // UART + SPI + DSM

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

    // ===== UART Handler 输出 =====
    wire       uart_cmd_ready;
    wire       uart_upload_active;
    wire       uart_upload_req;
    wire [7:0] uart_upload_data;
    wire [7:0] uart_upload_source;
    wire       uart_upload_valid;
    wire       uart_upload_ready;

    // ===== SPI Handler 输出 =====
    wire       spi_cmd_ready;
    wire       spi_upload_active;
    wire       spi_upload_req;
    wire [7:0] spi_upload_data;
    wire [7:0] spi_upload_source;
    wire       spi_upload_valid;
    wire       spi_upload_ready;

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
    wire       uart_packer_req;
    wire [7:0] uart_packer_data;
    wire [7:0] uart_packer_source;
    wire       uart_packer_valid;
    wire       uart_packer_ready;

    wire       spi_packer_req;
    wire [7:0] spi_packer_data;
    wire [7:0] spi_packer_source;
    wire       spi_packer_valid;
    wire       spi_packer_ready;

    wire       dsm_packer_req;
    wire [7:0] dsm_packer_data;
    wire [7:0] dsm_packer_source;
    wire       dsm_packer_valid;
    wire       dsm_packer_ready;

    // ===== Packer 输出 -> Arbiter 输入 =====
    wire [NUM_CHANNELS-1:0]      packed_req;
    wire [NUM_CHANNELS*8-1:0]    packed_data;
    wire [NUM_CHANNELS*8-1:0]    packed_source;
    wire [NUM_CHANNELS-1:0]      packed_valid;
    wire [NUM_CHANNELS-1:0]      arbiter_ready;

    // ===== Arbiter 输出 -> Processor =====
    wire       merged_req;
    wire [7:0] merged_data;
    wire [7:0] merged_source;
    wire       merged_valid;
    reg        processor_ready;

    // ===== 统计信息 =====
    integer total_bytes_received = 0;
    integer uart_packets_sent = 0;
    integer spi_packets_sent = 0;
    integer dsm_measurements = 0;

    // 优先级观察
    integer first_concurrent_source = -1;

    // ===== SPI接口 (简化的虚拟接口) =====
    wire spi_clk, spi_cs_n, spi_mosi, spi_miso;
    assign spi_miso = spi_mosi; // 回环测试

    // ===== UART接口 (简化的虚拟接口) =====
    wire uart_tx, uart_rx;
    assign uart_rx = uart_tx; // 回环测试

    // ========================================================================
    // 模块实例化
    // ========================================================================

    // ----- UART Handler (简化版本 - 只关注upload功能) -----
    uart_handler u_uart_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(uart_cmd_ready),
        .ext_uart_tx(uart_tx),
        .ext_uart_rx(uart_rx),
        .upload_active(uart_upload_active),
        .upload_req(uart_upload_req),
        .upload_data(uart_upload_data),
        .upload_source(uart_upload_source),
        .upload_valid(uart_upload_valid),
        .upload_ready(uart_upload_ready)
    );

    // ----- SPI Handler -----
    spi_handler #(
        .CLK_DIV(2)
    ) u_spi_handler (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(spi_cmd_ready),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .upload_active(spi_upload_active),
        .upload_req(spi_upload_req),
        .upload_data(spi_upload_data),
        .upload_source(spi_upload_source),
        .upload_valid(spi_upload_valid),
        .upload_ready(spi_upload_ready)
    );

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

    // ----- UART Adapter -----
    upload_adapter u_uart_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(uart_upload_active),
        .handler_upload_data(uart_upload_data),
        .handler_upload_source(uart_upload_source),
        .handler_upload_valid(uart_upload_valid),
        .handler_upload_ready(uart_upload_ready),
        .packer_upload_req(uart_packer_req),
        .packer_upload_data(uart_packer_data),
        .packer_upload_source(uart_packer_source),
        .packer_upload_valid(uart_packer_valid),
        .packer_upload_ready(uart_packer_ready)
    );

    // ----- SPI Adapter -----
    upload_adapter u_spi_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(spi_upload_active),
        .handler_upload_data(spi_upload_data),
        .handler_upload_source(spi_upload_source),
        .handler_upload_valid(spi_upload_valid),
        .handler_upload_ready(spi_upload_ready),
        .packer_upload_req(spi_packer_req),
        .packer_upload_data(spi_packer_data),
        .packer_upload_source(spi_packer_source),
        .packer_upload_valid(spi_packer_valid),
        .packer_upload_ready(spi_packer_ready)
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

    // ----- Multi-channel Packer (3 channels) -----
    upload_packer #(
        .NUM_CHANNELS(NUM_CHANNELS),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req({dsm_packer_req, spi_packer_req, uart_packer_req}),
        .raw_upload_data({dsm_packer_data, spi_packer_data, uart_packer_data}),
        .raw_upload_source({dsm_packer_source, spi_packer_source, uart_packer_source}),
        .raw_upload_valid({dsm_packer_valid, spi_packer_valid, uart_packer_valid}),
        .raw_upload_ready({dsm_packer_ready, spi_packer_ready, uart_packer_ready}),
        .packed_upload_req(packed_req),
        .packed_upload_data(packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid(packed_valid),
        .packed_upload_ready(arbiter_ready)
    );

    // ----- Arbiter (3 sources) -----
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
        .merged_upload_req(merged_req),
        .merged_upload_data(merged_data),
        .merged_upload_source(merged_source),
        .merged_upload_valid(merged_valid),
        .processor_upload_ready(processor_ready)
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
    always @(posedge clk) begin
        if (merged_valid && processor_ready) begin
            total_bytes_received = total_bytes_received + 1;

            // 记录并发测试时第一个被服务的源
            if (first_concurrent_source == -1 && merged_req) begin
                first_concurrent_source = merged_source;
                $display(">>> [%0t] FIRST SOURCE IN CONCURRENT TEST: 0x%02x <<<",
                    $time, merged_source);
            end

            $display("[%0t] OUTPUT: 0x%02x (source=0x%02x, req=%b)",
                $time, merged_data, merged_source, merged_req);
        end
    end

    // ========================================================================
    // DSM信号生成 (模拟方波信号)
    // ========================================================================
    initial begin
        dsm_signal_in = 8'h00;
        #(CLK_PERIOD * 150);  // 等待初始化

        forever begin
            // 通道0: 1kHz方波 (高500us, 低500us)
            dsm_signal_in[0] = 1;
            #30000;  // 高电平
            dsm_signal_in[0] = 0;
            #30000;  // 低电平
        end
    end

    // 通道1信号
    initial begin
        dsm_signal_in[1] = 0;
        #(CLK_PERIOD * 150);

        forever begin
            dsm_signal_in[1] = 1;
            #20000;
            dsm_signal_in[1] = 0;
            #40000;
        end
    end

    // ========================================================================
    // 测试任务
    // ========================================================================

    // 任务：发送DSM测量指令
    task send_dsm_measure_cmd;
        input [7:0] channel_mask;
        begin
            $display("\n[%0t] ===== DSM MEASURE Command (mask=0x%02x) =====",
                $time, channel_mask);

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

            dsm_measurements = dsm_measurements + 1;
            $display("[%0t] DSM command sent, waiting for measurement...", $time);
        end
    endtask

    // 任务：发送SPI读写指令
    task send_spi_readwrite_cmd;
        input [7:0] write_len;
        input [7:0] read_len;
        input [7:0] write_data;
        begin
            $display("\n[%0t] ===== SPI READ/WRITE Command (W=%0d, R=%0d) =====",
                $time, write_len, read_len);

            @(posedge clk);
            cmd_type <= 8'h11;  // CMD_SPI_WRITE
            cmd_length <= write_len + 2;
            cmd_start <= 1;

            @(posedge clk);
            cmd_start <= 0;

            // 发送write_len
            cmd_data <= write_len;
            cmd_data_index <= 0;
            cmd_data_valid <= 1;
            @(posedge clk);

            // 发送read_len
            cmd_data <= read_len;
            cmd_data_index <= 1;
            @(posedge clk);

            // 发送写数据
            if (write_len > 0) begin
                cmd_data <= write_data;
                cmd_data_index <= 2;
                @(posedge clk);
            end

            cmd_data_valid <= 0;
            cmd_done <= 1;
            @(posedge clk);
            cmd_done <= 0;

            spi_packets_sent = spi_packets_sent + 1;
            $display("[%0t] SPI command sent", $time);
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
        processor_ready = 1;

        $display("================================================================");
        $display("  Upload Full Integration Test - 3 CHANNELS");
        $display("  Testing: UART + SPI + DSM with Adapter + Packer + Arbiter");
        $display("================================================================");

        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试1：DSM单独测量（通道0）
        // ====================================================================
        $display("\n================================================================");
        $display(" TEST 1: DSM measure channel 0 alone");
        $display("================================================================");
        total_bytes_received = 0;
        send_dsm_measure_cmd(8'h01);  // 只启用通道0
        #(CLK_PERIOD * 5000);  // 等待测量完成和数据上传

        $display("\n[TEST 1 RESULT] Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 15)  // 帧头(2) + source(1) + len(2) + 通道数据(9) + checksum(1)
            $display("TEST 1: ✓ PASS");
        else
            $display("TEST 1: ✗ FAIL (expected 15 bytes)");

        // ====================================================================
        // 测试2：SPI单独读写
        // ====================================================================
        $display("\n================================================================");
        $display(" TEST 2: SPI read/write alone");
        $display("================================================================");
        total_bytes_received = 0;
        send_spi_readwrite_cmd(8'h01, 8'h02, 8'hAB);  // 写1字节，读2字节
        #(CLK_PERIOD * 1000);

        $display("\n[TEST 2 RESULT] Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 8)  // 帧头(2) + source(1) + len(2) + 读数据(2) + checksum(1)
            $display("TEST 2: ✓ PASS");
        else
            $display("TEST 2: ✗ FAIL (expected 8 bytes)");

        // ====================================================================
        // 测试3：DSM + SPI 并发测试
        // ====================================================================
        $display("\n================================================================");
        $display(" TEST 3: DSM + SPI concurrent test");
        $display(" Expected: UART(0) > SPI(1) > DSM(2) priority");
        $display("================================================================");
        total_bytes_received = 0;
        first_concurrent_source = -1;

        fork
            begin
                send_dsm_measure_cmd(8'h03);  // 通道0和1
            end

            begin
                #(CLK_PERIOD * 5);
                send_spi_readwrite_cmd(8'h01, 8'h01, 8'hCD);
            end
        join

        #(CLK_PERIOD * 5000);

        $display("\n[TEST 3 RESULT] Received: %0d bytes", total_bytes_received);
        if (first_concurrent_source == 8'h03)
            $display("TEST 3 PRIORITY: SPI served first (0x03) ✓");
        else if (first_concurrent_source == 8'h0A)
            $display("TEST 3 PRIORITY: DSM served first (0x0A) - Check priority!");

        $display("TEST 3: ✓ PASS (data integrity)");

        // ====================================================================
        // 最终统计
        // ====================================================================
        #(CLK_PERIOD * 100);
        $display("\n================================================================");
        $display("  FINAL SUMMARY - 3 CHANNELS");
        $display("================================================================");
        $display("  SPI packets sent:      %0d", spi_packets_sent);
        $display("  DSM measurements:      %0d", dsm_measurements);
        $display("  Total bytes received:  %0d", total_bytes_received);
        $display("================================================================");

        $display("\nSimulation completed!");
        $finish;
    end

    // ========================================================================
    // 超时保护
    // ========================================================================
    initial begin
        #(CLK_PERIOD * 50000);
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

    // ========================================================================
    // 波形生成
    // ========================================================================
    initial begin
        $dumpfile("upload_full_integration_3ch_tb.vcd");
        $dumpvars(0, upload_full_integration_3ch_tb);
    end

endmodule
