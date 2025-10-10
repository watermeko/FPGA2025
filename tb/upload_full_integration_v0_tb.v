`timescale 1ns / 1ps

// ============================================================================
// Testbench: upload_full_integration_v0_tb
// Description: 带0版本模块的集成测试 (Adapter_0 + Packer_0 + Arbiter_0)
//
// 架构:
//   [UART Handler] -> [Adapter_0] -> [Packer_0] -> [Arbiter_0] -> [Processor]
//   [SPI Handler]  -> [Adapter_0] -> [Packer_0] -> [Arbiter_0] -> [Processor]
//
// 测试目的：
//   1. 验证旧版本模块的功能
//   2. 对比与最新版本的差异
//   3. 重现优先级Bug（Arbiter_0中SPI>UART）
//
// 测试场景:
//   1. UART单独发送
//   2. SPI单独发送
//   3. 并发发送（观察优先级：预期SPI优先，与新版不同）
//   4. 背压测试
//   5. 交替发送
// ============================================================================

module upload_full_integration_v0_tb();

    parameter CLK_PERIOD = 16.67;  // 60MHz
    parameter NUM_CHANNELS = 2;     // UART + SPI

    // ========================================================================
    // 信号声明
    // ========================================================================

    // 时钟和复位
    reg clk;
    reg rst_n;

    // ===== UART Handler 模拟输出 =====
    reg        uart_upload_active;
    reg [7:0]  uart_upload_data;
    reg [7:0]  uart_upload_source;
    reg        uart_upload_valid;
    wire       uart_upload_ready;

    // ===== SPI Handler 模拟输出 =====
    reg        spi_upload_active;
    reg [7:0]  spi_upload_data;
    reg [7:0]  spi_upload_source;
    reg        spi_upload_valid;
    wire       spi_upload_ready;

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
    integer uart_bytes_sent = 0;
    integer spi_bytes_sent = 0;

    // 优先级观察
    integer first_concurrent_source = -1;  // 记录并发时谁先被服务

    // ========================================================================
    // 模块实例化（使用带0版本）
    // ========================================================================

    // ----- UART Adapter (Version 0) -----
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

    // ----- SPI Adapter (Version 0) -----
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

    // ----- Multi-channel Packer (Version 0) -----
    upload_packer #(
        .NUM_CHANNELS(2),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req({spi_packer_req, uart_packer_req}),
        .raw_upload_data({spi_packer_data, uart_packer_data}),
        .raw_upload_source({spi_packer_source, uart_packer_source}),
        .raw_upload_valid({spi_packer_valid, uart_packer_valid}),
        .raw_upload_ready({spi_packer_ready, uart_packer_ready}),
        .packed_upload_req(packed_req),
        .packed_upload_data(packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid(packed_valid),
        .packed_upload_ready(arbiter_ready)
    );

    // ----- Arbiter (Version 0) -----
    // 注意：这个版本的优先级是 SPI > UART（Bug版本）
    upload_arbiter #(
        .NUM_SOURCES(2),
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
    // 输出监控（增加优先级观察）
    // ========================================================================
    always @(posedge clk) begin
        if (merged_valid && processor_ready) begin
            total_bytes_received = total_bytes_received + 1;

            // 记录并发测试时第一个被服务的源
            if (first_concurrent_source == -1 && merged_source != 8'h00) begin
                first_concurrent_source = merged_source;
            end

            $display("[%0t] OUTPUT: 0x%02x (source=0x%02x, req=%b, total=%0d)",
                $time, merged_data, merged_source, merged_req, total_bytes_received);
        end
    end

    // ========================================================================
    // 测试任务
    // ========================================================================

    // 任务：模拟UART Handler发送数据
    task send_uart_packet;
        input [7:0] num_bytes;
        input [7:0] start_value;
        integer i;
        begin
            $display("\n[%0t] ===== UART Sending %0d bytes (start=0x%02x) =====",
                $time, num_bytes, start_value);

            uart_upload_source = 8'h01;
            uart_upload_active = 1;

            for (i = 0; i < num_bytes; i = i + 1) begin
                @(posedge clk);
                while (!uart_upload_ready) @(posedge clk);

                uart_upload_data = start_value + i;
                uart_upload_valid = 1;
                uart_bytes_sent = uart_bytes_sent + 1;
                $display("[%0t] UART TX: byte[%0d]=0x%02x", $time, i, uart_upload_data);

                @(posedge clk);
                uart_upload_valid = 0;
            end

            @(posedge clk);
            uart_upload_active = 0;
            uart_packets_sent = uart_packets_sent + 1;
            $display("[%0t] UART packet complete", $time);
        end
    endtask

    // 任务：模拟SPI Handler发送数据
    task send_spi_packet;
        input [7:0] num_bytes;
        input [7:0] start_value;
        integer i;
        begin
            $display("\n[%0t] ===== SPI Sending %0d bytes (start=0x%02x) =====",
                $time, num_bytes, start_value);

            spi_upload_source = 8'h03;
            spi_upload_active = 1;

            for (i = 0; i < num_bytes; i = i + 1) begin
                @(posedge clk);
                while (!spi_upload_ready) @(posedge clk);

                spi_upload_data = start_value + i;
                spi_upload_valid = 1;
                spi_bytes_sent = spi_bytes_sent + 1;
                $display("[%0t] SPI TX: byte[%0d]=0x%02x", $time, i, spi_upload_data);

                @(posedge clk);
                spi_upload_valid = 0;
            end

            @(posedge clk);
            spi_upload_active = 0;
            spi_packets_sent = spi_packets_sent + 1;
            $display("[%0t] SPI packet complete", $time);
        end
    endtask

    // 任务：并发发送（测试优先级Bug）
    task concurrent_send_test;
        begin
            $display("\n[%0t] ===== CONCURRENT TEST: UART & SPI Simultaneous =====", $time);
            $display("NOTE: Version 0 has SPI > UART priority (Bug!)");
            $display("TIMING: SPI starts slightly earlier to trigger priority bug");

            first_concurrent_source = -1;  // 重置观察变量

            fork
                begin
                    // UART延迟1个时钟周期
                    #(CLK_PERIOD * 1);
                    send_uart_packet(3, 8'hA0);
                end

                begin
                    // SPI先启动，这样可以触发优先级选择
                    send_spi_packet(5, 8'hB0);
                end
            join

            $display("[%0t] Concurrent test complete", $time);
        end
    endtask

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        uart_upload_active = 0;
        uart_upload_data = 0;
        uart_upload_source = 8'h01;
        uart_upload_valid = 0;
        spi_upload_active = 0;
        spi_upload_data = 0;
        spi_upload_source = 8'h03;
        spi_upload_valid = 0;
        processor_ready = 1;

        $display("================================================================");
        $display("  Upload Full Integration Test - VERSION 0");
        $display("  Testing: Adapter_0 + Packer_0 + Arbiter_0");
        $display("  Note: This version has SPI > UART priority bug");
        $display("================================================================");

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // ====================================================================
        // 测试1：UART单独发送
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display(" TEST 1: UART sends 3 bytes alone");
        $display("================================================================");
        total_bytes_received = 0;
        send_uart_packet(3, 8'hC1);
        #(CLK_PERIOD * 50);

        $display("\n[TEST 1 RESULT] Expected: 9 bytes, Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 9)
            $display("TEST 1: ✓ PASS");
        else
            $display("TEST 1: ✗ FAIL");

        // ====================================================================
        // 测试2：SPI单独发送
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display(" TEST 2: SPI sends 4 bytes alone");
        $display("================================================================");
        total_bytes_received = 0;
        send_spi_packet(4, 8'hD1);
        #(CLK_PERIOD * 50);

        $display("\n[TEST 2 RESULT] Expected: 10 bytes, Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 10)
            $display("TEST 2: ✓ PASS");
        else
            $display("TEST 2: ✗ FAIL");

        // ====================================================================
        // 测试3：并发发送 - 观察优先级Bug
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display(" TEST 3: Concurrent send - PRIORITY BUG TEST");
        $display(" Expected behavior (V0): SPI has higher priority");
        $display("================================================================");
        total_bytes_received = 0;
        concurrent_send_test();
        #(CLK_PERIOD * 100);

        $display("\n[TEST 3 RESULT] Expected: 20 bytes, Received: %0d bytes", total_bytes_received);
        if (first_concurrent_source == 8'h03) begin
            $display("TEST 3 PRIORITY: SPI served first (0x03) - Bug confirmed! ⚠️");
        end else if (first_concurrent_source == 8'h01) begin
            $display("TEST 3 PRIORITY: UART served first (0x01) - Unexpected behavior");
        end else begin
            $display("TEST 3 PRIORITY: Unknown first source");
        end

        if (total_bytes_received == 20)
            $display("TEST 3: ✓ PASS (data integrity)");
        else
            $display("TEST 3: ✗ FAIL");

        // ====================================================================
        // 测试4：背压测试
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display(" TEST 4: Backpressure test");
        $display("================================================================");
        total_bytes_received = 0;

        fork
            begin
                send_uart_packet(2, 8'hE0);
            end

            begin
                #(CLK_PERIOD * 10);
                processor_ready = 0;
                $display("[%0t] >>> Processor BUSY", $time);
                #(CLK_PERIOD * 20);
                processor_ready = 1;
                $display("[%0t] >>> Processor READY", $time);
            end
        join

        #(CLK_PERIOD * 50);
        $display("\n[TEST 4 RESULT] Expected: 8 bytes, Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 8)
            $display("TEST 4: ✓ PASS");
        else
            $display("TEST 4: ✗ FAIL");

        // ====================================================================
        // 测试5：交替发送
        // ====================================================================
        $display("\n");
        $display("================================================================");
        $display(" TEST 5: Alternating packets");
        $display("================================================================");
        total_bytes_received = 0;

        send_uart_packet(2, 8'hF0);
        #(CLK_PERIOD * 5);
        send_spi_packet(2, 8'hF4);
        #(CLK_PERIOD * 5);
        send_uart_packet(1, 8'hF8);
        #(CLK_PERIOD * 80);

        $display("\n[TEST 5 RESULT] Expected: 23 bytes, Received: %0d bytes", total_bytes_received);
        if (total_bytes_received == 23)
            $display("TEST 5: ✓ PASS");
        else
            $display("TEST 5: ✗ FAIL");

        // ====================================================================
        // 最终统计和版本差异说明
        // ====================================================================
        #(CLK_PERIOD * 20);
        $display("\n");
        $display("================================================================");
        $display("  FINAL SUMMARY - VERSION 0");
        $display("================================================================");
        $display("  UART packets sent:     %0d", uart_packets_sent);
        $display("  SPI packets sent:      %0d", spi_packets_sent);
        $display("  Total bytes sent:      %0d", uart_bytes_sent + spi_bytes_sent);
        $display("  Total bytes received:  %0d", total_bytes_received);
        $display("================================================================");
        $display("  VERSION 0 KNOWN ISSUES:");
        $display("  1. Arbiter priority: SPI > UART (should be UART > SPI)");
        $display("  2. Implementation uses fifo_rd_en_ctrl workaround");
        $display("================================================================");

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

    // ========================================================================
    // 波形生成
    // ========================================================================
    initial begin
        $dumpfile("upload_full_integration_v0_tb.vcd");
        $dumpvars(0, upload_full_integration_v0_tb);
    end

endmodule
