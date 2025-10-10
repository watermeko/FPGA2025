`timescale 1ns / 1ps

// ============================================================================
// Testbench: upload_arbiter_tb
// Description: 测试upload_arbiter模块的仲裁功能
//
// Test scenarios:
//   1. 单源上传（UART）
//   2. 单源上传（SPI）
//   3. 同时上传 - 测试仲裁
//   4. 轮询防饿死
//   5. 握手时序测试
// ============================================================================

module upload_arbiter_tb();

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Parameters
    parameter CLK_PERIOD = 16.67;  // 60MHz clock (16.67ns period)
    parameter NUM_SOURCES = 2;

    // Source signals (UART=0, SPI=1)
    reg [NUM_SOURCES-1:0]       src_upload_req;
    reg [NUM_SOURCES*8-1:0]     src_upload_data;
    reg [NUM_SOURCES*8-1:0]     src_upload_source;
    reg [NUM_SOURCES-1:0]       src_upload_valid;
    wire [NUM_SOURCES-1:0]      src_upload_ready;

    // Merged signals to processor
    wire                        merged_upload_req;
    wire [7:0]                  merged_upload_data;
    wire [7:0]                  merged_upload_source;
    wire                        merged_upload_valid;
    reg                         processor_upload_ready;

    // Helper signals for easier access
    reg        uart_req;
    reg [7:0]  uart_data;
    reg        uart_valid;
    wire       uart_ready;

    reg        spi_req;
    reg [7:0]  spi_data;
    reg        spi_valid;
    wire       spi_ready;

    // Pack signals
    always @(*) begin
        src_upload_req = {spi_req, uart_req};
        src_upload_data = {spi_data, uart_data};
        src_upload_source = {8'h03, 8'h01};  // SPI=0x03, UART=0x01
        src_upload_valid = {spi_valid, uart_valid};
    end

    // Unpack ready signals
    assign uart_ready = src_upload_ready[0];
    assign spi_ready = src_upload_ready[1];

    // Instantiate DUT
    upload_arbiter #(
        .NUM_SOURCES(NUM_SOURCES)
    ) u_arbiter (
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

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test statistics
    integer uart_sent_count = 0;
    integer spi_sent_count = 0;
    integer total_received = 0;

    // Monitor merged output
    always @(posedge clk) begin
        if (merged_upload_valid && processor_upload_ready) begin
            total_received = total_received + 1;
            $display("[%0t] RECEIVED: data=0x%02x, source=0x%02x (total=%0d)",
                     $time, merged_upload_data, merged_upload_source, total_received);
        end
    end

    // Main test procedure
    initial begin
        // Initialize
        rst_n = 0;
        uart_req = 0;
        uart_data = 8'h00;
        uart_valid = 0;
        spi_req = 0;
        spi_data = 8'h00;
        spi_valid = 0;
        processor_upload_ready = 1;  // Processor always ready

        $display("========================================");
        $display("Upload Arbiter Testbench");
        $display("========================================");

        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // ============================================================
        // Test 1: UART单独上传3字节
        // ============================================================
        $display("\n[TEST 1] UART sends 3 bytes alone");
        uart_req = 1;
        send_uart_byte(8'hA1);
        send_uart_byte(8'hA2);
        send_uart_byte(8'hA3);
        uart_req = 0;
        #(CLK_PERIOD * 5);

        // ============================================================
        // Test 2: SPI单独上传3字节
        // ============================================================
        $display("\n[TEST 2] SPI sends 3 bytes alone");
        spi_req = 1;
        send_spi_byte(8'hB1);
        send_spi_byte(8'hB2);
        send_spi_byte(8'hB3);
        spi_req = 0;
        #(CLK_PERIOD * 5);

        // ============================================================
        // Test 3: UART和SPI同时请求上传（测试仲裁）
        // ============================================================
        $display("\n[TEST 3] UART and SPI request simultaneously");

        // 同时启动两个源的req
        uart_req = 1;
        spi_req = 1;
        #(CLK_PERIOD * 2);

        // 使用fork并行发送
        fork
            // UART线程：连续发送5字节
            begin
                repeat(5) begin
                    @(posedge clk);
                    wait(uart_ready);
                    if (uart_sent_count == 3) uart_data = 8'hC1;
                    else if (uart_sent_count == 4) uart_data = 8'hC2;
                    else if (uart_sent_count == 5) uart_data = 8'hC3;
                    else if (uart_sent_count == 6) uart_data = 8'hC4;
                    else if (uart_sent_count == 7) uart_data = 8'hC5;
                    uart_valid = 1;
                    uart_sent_count = uart_sent_count + 1;
                    $display("[%0t] UART SEND: 0x%02x (count=%0d)", $time, uart_data, uart_sent_count);
                    @(posedge clk);
                    uart_valid = 0;
                end
                uart_req = 0;
            end

            // SPI线程：连续发送5字节
            begin
                repeat(5) begin
                    @(posedge clk);
                    wait(spi_ready);
                    if (spi_sent_count == 3) spi_data = 8'hD1;
                    else if (spi_sent_count == 4) spi_data = 8'hD2;
                    else if (spi_sent_count == 5) spi_data = 8'hD3;
                    else if (spi_sent_count == 6) spi_data = 8'hD4;
                    else if (spi_sent_count == 7) spi_data = 8'hD5;
                    spi_valid = 1;
                    spi_sent_count = spi_sent_count + 1;
                    $display("[%0t] SPI SEND: 0x%02x (count=%0d)", $time, spi_data, spi_sent_count);
                    @(posedge clk);
                    spi_valid = 0;
                end
                spi_req = 0;
            end
        join

        #(CLK_PERIOD * 10);

        // ============================================================
        // Test 4: 测试轮询机制（防饿死）
        // ============================================================
        $display("\n[TEST 4] Round-robin fairness test");
        // UART先请求
        uart_req = 1;
        send_uart_byte(8'hE1);
        send_uart_byte(8'hE2);

        // 然后SPI也请求（应该等UART完成后轮到SPI）
        spi_req = 1;
        send_spi_byte(8'hF1);
        send_spi_byte(8'hF2);

        // UART继续发送
        send_uart_byte(8'hE3);
        uart_req = 0;

        send_spi_byte(8'hF3);
        spi_req = 0;

        #(CLK_PERIOD * 10);

        // ============================================================
        // Test 5: Processor busy测试（握手时序）
        // ============================================================
        $display("\n[TEST 5] Processor busy (backpressure test)");
        uart_req = 1;

        // 发送第1字节
        send_uart_byte(8'h11);

        // Processor变busy
        processor_upload_ready = 0;
        $display("[%0t] Processor BUSY", $time);
        #(CLK_PERIOD * 10);

        // Processor恢复ready
        processor_upload_ready = 1;
        $display("[%0t] Processor READY", $time);

        // 继续发送
        send_uart_byte(8'h22);
        send_uart_byte(8'h33);
        uart_req = 0;

        #(CLK_PERIOD * 10);

        // ============================================================
        // 测试结束统计
        // ============================================================
        $display("\n========================================");
        $display("Test Summary:");
        $display("  UART sent:     %0d bytes", uart_sent_count);
        $display("  SPI sent:      %0d bytes", spi_sent_count);
        $display("  Total sent:    %0d bytes", uart_sent_count + spi_sent_count);
        $display("  Total received: %0d bytes", total_received);

        if (total_received == uart_sent_count + spi_sent_count) begin
            $display("  Result: PASS ✓");
        end else begin
            $display("  Result: FAIL ✗");
        end
        $display("========================================\n");

        #(CLK_PERIOD * 20);
        $finish;
    end

    // Task: Send UART byte
    task send_uart_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            wait(uart_ready);  // 等待ready
            uart_data = data;
            uart_valid = 1;
            uart_sent_count = uart_sent_count + 1;
            $display("[%0t] UART SEND: 0x%02x (count=%0d)", $time, data, uart_sent_count);
            @(posedge clk);
            uart_valid = 0;
            @(posedge clk);  // 等待一个周期
        end
    endtask

    // Task: Send SPI byte
    task send_spi_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            wait(spi_ready);  // 等待ready
            spi_data = data;
            spi_valid = 1;
            spi_sent_count = spi_sent_count + 1;
            $display("[%0t] SPI SEND: 0x%02x (count=%0d)", $time, data, spi_sent_count);
            @(posedge clk);
            spi_valid = 0;
            @(posedge clk);  // 等待一个周期
        end
    endtask

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("upload_arbiter_tb.vcd");
        $dumpvars(0, upload_arbiter_tb);
    end

endmodule
