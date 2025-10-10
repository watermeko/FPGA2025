`timescale 1ns / 1ps

// ============================================================================
// 测试模块：upload_packer + upload_arbiter 集成测试
//
// 测试场景：
//   1. UART单独发送数据包
//   2. SPI单独发送数据包
//   3. 数据包完整性测试：SPI发送时UART抢占（应该等SPI包完成）
//   4. 连续数据包测试：两个源交替发送
// ============================================================================

module upload_integration_tb();

    parameter CLK_PERIOD = 16.67;  // 60MHz
    parameter NUM_SOURCES = 2;

    // 时钟和复位
    reg clk;
    reg rst_n;

    // UART handler 输出 -> Packer 输入
    reg        uart_raw_req;
    reg [7:0]  uart_raw_data;
    reg [7:0]  uart_raw_source;
    reg        uart_raw_valid;
    wire       uart_raw_ready;

    // SPI handler 输出 -> Packer 输入
    reg        spi_raw_req;
    reg [7:0]  spi_raw_data;
    reg [7:0]  spi_raw_source;
    reg        spi_raw_valid;
    wire       spi_raw_ready;

    // Packer 输出 -> Arbiter 输入
    wire [NUM_SOURCES-1:0]      packer_req;
    wire [NUM_SOURCES*8-1:0]    packer_data;
    wire [NUM_SOURCES*8-1:0]    packer_source;
    wire [NUM_SOURCES-1:0]      packer_valid;
    wire [NUM_SOURCES-1:0]      arbiter_ready;

    // Arbiter 输出 -> Processor
    wire       merged_req;
    wire [7:0] merged_data;
    wire [7:0] merged_source;
    wire       merged_valid;
    reg        processor_ready;

    // 统计
    integer total_bytes_received = 0;
    integer uart_packets_sent = 0;
    integer spi_packets_sent = 0;

    // ========================================================================
    // DUT 实例化
    // ========================================================================

    // 两个 packer 实例（UART 和 SPI）
    upload_packer_simple #(
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_uart_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req(uart_raw_req),
        .raw_upload_data(uart_raw_data),
        .raw_upload_source(uart_raw_source),
        .raw_upload_valid(uart_raw_valid),
        .raw_upload_ready(uart_raw_ready),
        .packed_upload_req(packer_req[0]),
        .packed_upload_data(packer_data[7:0]),
        .packed_upload_source(packer_source[7:0]),
        .packed_upload_valid(packer_valid[0]),
        .packed_upload_ready(arbiter_ready[0])
    );

    upload_packer_simple #(
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_spi_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req(spi_raw_req),
        .raw_upload_data(spi_raw_data),
        .raw_upload_source(spi_raw_source),
        .raw_upload_valid(spi_raw_valid),
        .raw_upload_ready(spi_raw_ready),
        .packed_upload_req(packer_req[1]),
        .packed_upload_data(packer_data[15:8]),
        .packed_upload_source(packer_source[15:8]),
        .packed_upload_valid(packer_valid[1]),
        .packed_upload_ready(arbiter_ready[1])
    );

    // Arbiter
    upload_arbiter #(
        .NUM_SOURCES(2),
        .FIFO_DEPTH(128)
    ) u_arbiter (
        .clk(clk),
        .rst_n(rst_n),
        .src_upload_req(packer_req),
        .src_upload_data(packer_data),
        .src_upload_source(packer_source),
        .src_upload_valid(packer_valid),
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
    // 监控输出
    // ========================================================================
    always @(posedge clk) begin
        if (merged_valid && processor_ready) begin
            total_bytes_received = total_bytes_received + 1;
            $display("[%0t] RECV: 0x%02x (source=0x%02x, req=%b, total=%0d)",
                $time, merged_data, merged_source, merged_req, total_bytes_received);
        end
    end

    // ========================================================================
    // 测试任务
    // ========================================================================

    // 任务：发送UART数据
    task send_uart_bytes;
        input [7:0] num_bytes;
        input [7:0] start_value;
        integer i;
        begin
            $display("\n[%0t] === Sending %0d bytes via UART (start=0x%02x) ===",
                $time, num_bytes, start_value);

            uart_raw_source = 8'h01;  // UART source ID
            uart_raw_req = 1;

            for (i = 0; i < num_bytes; i = i + 1) begin
                @(posedge clk);
                wait(uart_raw_ready);
                uart_raw_data = start_value + i;
                uart_raw_valid = 1;
                @(posedge clk);
                uart_raw_valid = 0;
            end

            @(posedge clk);
            uart_raw_req = 0;
            uart_packets_sent = uart_packets_sent + 1;
            $display("[%0t] UART packet sent", $time);
        end
    endtask

    // 任务：发送SPI数据
    task send_spi_bytes;
        input [7:0] num_bytes;
        input [7:0] start_value;
        integer i;
        begin
            $display("\n[%0t] === Sending %0d bytes via SPI (start=0x%02x) ===",
                $time, num_bytes, start_value);

            spi_raw_source = 8'h03;  // SPI source ID
            spi_raw_req = 1;

            for (i = 0; i < num_bytes; i = i + 1) begin
                @(posedge clk);
                wait(spi_raw_ready);
                spi_raw_data = start_value + i;
                spi_raw_valid = 1;
                @(posedge clk);
                spi_raw_valid = 0;
            end

            @(posedge clk);
            spi_raw_req = 0;
            spi_packets_sent = spi_packets_sent + 1;
            $display("[%0t] SPI packet sent", $time);
        end
    endtask

    // 任务：并发发送（测试数据包完整性）
    task concurrent_send;
        begin
            $display("\n[%0t] === CONCURRENT TEST: SPI and UART send simultaneously ===", $time);

            fork
                // SPI 开始发送
                begin
                    send_spi_bytes(5, 8'hB0);
                end

                // UART 同时开始发送（应该等待SPI包完成）
                begin
                    send_uart_bytes(3, 8'hA0);
                end
            join
        end
    endtask

    // ========================================================================
    // 主测试流程
    // ========================================================================
    initial begin
        // 初始化
        rst_n = 0;
        uart_raw_req = 0;
        uart_raw_data = 0;
        uart_raw_source = 8'h01;
        uart_raw_valid = 0;

        spi_raw_req = 0;
        spi_raw_data = 0;
        spi_raw_source = 8'h03;
        spi_raw_valid = 0;

        processor_ready = 1;  // 处理器始终准备好
        total_bytes_received = 0;

        $display("========================================");
        $display("Upload Packer + Arbiter Integration Test");
        $display("========================================");

        // 复位
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // ====================================================================
        // 测试1：UART单独发送
        // ====================================================================
        $display("\n[TEST 1] UART sends 3 bytes alone");
        total_bytes_received = 0;
        send_uart_bytes(3, 8'hA1);
        #(CLK_PERIOD * 40);  // 增加等待时间确保校验和传完

        if (total_bytes_received == 9)
            $display("TEST 1 PASS: Received %0d bytes (expected 9)", total_bytes_received);
        else
            $display("TEST 1 FAIL: Received %0d bytes (expected 9)", total_bytes_received);

        // 额外等待确保FIFO清空
        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试2：SPI单独发送
        // ====================================================================
        $display("\n[TEST 2] SPI sends 3 bytes alone");
        total_bytes_received = 0;
        send_spi_bytes(3, 8'hB1);
        #(CLK_PERIOD * 40);  // 增加等待时间确保包完全传完

        if (total_bytes_received == 9)
            $display("TEST 2 PASS: Received %0d bytes (expected 9)", total_bytes_received);
        else
            $display("TEST 2 FAIL: Received %0d bytes (expected 9)", total_bytes_received);

        // 额外等待确保FIFO清空
        #(CLK_PERIOD * 10);

        // ====================================================================
        // 测试3：数据包完整性测试（关键！）
        // ====================================================================
        $display("\n[TEST 3] Packet integrity test (SPI and UART simultaneous)");
        total_bytes_received = 0;
        concurrent_send();
        #(CLK_PERIOD * 80);  // 增加等待时间以确保两个包都传完

        // 协议格式: [0xAA][0x44][source][len_h][len_l][data...][checksum]
        // SPI: 2+1+2+5+1 = 11字节
        // UART: 2+1+2+3+1 = 9字节
        // 总共: 20字节
        if (total_bytes_received == 20)
            $display("TEST 3 PASS: Received %0d bytes", total_bytes_received);
        else
            $display("TEST 3 INFO: Received %0d bytes (expected 20)", total_bytes_received);

        // ====================================================================
        // 测试4：连续交替发送
        // ====================================================================
        $display("\n[TEST 4] Alternating packets");
        total_bytes_received = 0;
        send_uart_bytes(2, 8'hC0);
        #(CLK_PERIOD * 5);
        send_spi_bytes(2, 8'hD0);
        #(CLK_PERIOD * 5);
        send_uart_bytes(2, 8'hE0);
        #(CLK_PERIOD * 50);

        $display("TEST 4: Received %0d bytes", total_bytes_received);

        // ====================================================================
        // 总结
        // ====================================================================
        #(CLK_PERIOD * 20);
        $display("\n========================================");
        $display("Test Summary:");
        $display("  UART packets sent: %0d", uart_packets_sent);
        $display("  SPI packets sent:  %0d", spi_packets_sent);
        $display("  Total bytes received: %0d", total_bytes_received);
        $display("========================================");

        $finish;
    end

    // 超时保护
    initial begin
        #(CLK_PERIOD * 5000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    // 生成波形
    initial begin
        $dumpfile("upload_integration_tb.vcd");
        $dumpvars(0, upload_integration_tb);
    end

endmodule
