`timescale 1ns / 1ps

// ============================================================================
// Testbench: upload_packer_tb (多通道版本)
// Description: 测试upload_packer模块的多通道并行打包功能
//
// Test scenarios:
//   1. UART单独发送3字节
//   2. SPI单独发送3字节
//   3. UART和SPI并行发送（测试真正并行）
// ============================================================================

module upload_packer_tb();

    // Clock and Reset
    reg clk;
    reg rst_n;

    // Parameters
    parameter CLK_PERIOD = 16.67;  // 60MHz clock
    parameter NUM_CHANNELS = 2;    // 2通道：UART + SPI

    // Multi-channel signals
    reg  [NUM_CHANNELS-1:0]       raw_upload_req;
    reg  [NUM_CHANNELS*8-1:0]     raw_upload_data;
    reg  [NUM_CHANNELS*8-1:0]     raw_upload_source;
    reg  [NUM_CHANNELS-1:0]       raw_upload_valid;
    wire [NUM_CHANNELS-1:0]       raw_upload_ready;

    wire [NUM_CHANNELS-1:0]       packed_upload_req;
    wire [NUM_CHANNELS*8-1:0]     packed_upload_data;
    wire [NUM_CHANNELS*8-1:0]     packed_upload_source;
    wire [NUM_CHANNELS-1:0]       packed_upload_valid;
    reg  [NUM_CHANNELS-1:0]       packed_upload_ready;

    // Helper signals for UART (channel 0)
    reg        uart_req;
    reg [7:0]  uart_data;
    reg        uart_valid;
    wire       uart_ready;
    wire       uart_packed_valid;
    wire [7:0] uart_packed_data;

    // Helper signals for SPI (channel 1)
    reg        spi_req;
    reg [7:0]  spi_data;
    reg        spi_valid;
    wire       spi_ready;
    wire       spi_packed_valid;
    wire [7:0] spi_packed_data;

    // Pack/Unpack
    always @(*) begin
        raw_upload_req = {spi_req, uart_req};
        raw_upload_data = {spi_data, uart_data};
        raw_upload_source = {8'h03, 8'h01};
        raw_upload_valid = {spi_valid, uart_valid};
    end

    assign uart_ready = raw_upload_ready[0];
    assign spi_ready = raw_upload_ready[1];
    assign uart_packed_valid = packed_upload_valid[0];
    assign spi_packed_valid = packed_upload_valid[1];
    assign uart_packed_data = packed_upload_data[7:0];
    assign spi_packed_data = packed_upload_data[15:8];

    // DUT
    upload_packer #(
        .NUM_CHANNELS(NUM_CHANNELS)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req(raw_upload_req),
        .raw_upload_data(raw_upload_data),
        .raw_upload_source(raw_upload_source),
        .raw_upload_valid(raw_upload_valid),
        .raw_upload_ready(raw_upload_ready),
        .packed_upload_req(packed_upload_req),
        .packed_upload_data(packed_upload_data),
        .packed_upload_source(packed_upload_source),
        .packed_upload_valid(packed_upload_valid),
        .packed_upload_ready(packed_upload_ready)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test statistics
    integer uart_bytes_received;
    integer spi_bytes_received;

    // Monitor UART output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_bytes_received <= 0;
        end else begin
            if (uart_packed_valid && packed_upload_ready[0]) begin
                uart_bytes_received <= uart_bytes_received + 1;
                $display("[%0t] UART PACKED: 0x%02x (total=%0d)", $time, uart_packed_data, uart_bytes_received + 1);
            end
            // Debug: monitor valid without ready
            if (uart_packed_valid && !packed_upload_ready[0]) begin
                $display("[%0t] UART PACKED BLOCKED: valid=1 but ready=0", $time);
            end
        end
    end

    // Monitor SPI output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_bytes_received <= 0;
        end else begin
            if (spi_packed_valid && packed_upload_ready[1]) begin
                spi_bytes_received <= spi_bytes_received + 1;
                $display("[%0t] SPI PACKED: 0x%02x (total=%0d)", $time, spi_packed_data, spi_bytes_received + 1);
            end
            // Debug: monitor valid without ready
            if (spi_packed_valid && !packed_upload_ready[1]) begin
                $display("[%0t] SPI PACKED BLOCKED: valid=1 but ready=0", $time);
            end
        end
    end

    // Debug: Monitor raw input
    always @(posedge clk) begin
        if (uart_valid && uart_ready) begin
            $display("[%0t] UART RAW INPUT: 0x%02x", $time, uart_data);
        end
        if (spi_valid && spi_ready) begin
            $display("[%0t] SPI RAW INPUT: 0x%02x", $time, spi_data);
        end
    end

    // Debug: Monitor req signals
    always @(posedge clk) begin
        if (uart_req)
            $display("[%0t] UART req=1, ready=%b", $time, uart_ready);
        if (spi_req)
            $display("[%0t] SPI req=1, ready=%b", $time, spi_ready);
    end

    // Debug: Monitor packer internal state (channel 0 - UART)
    always @(posedge clk) begin
        if (u_packer.state[0] != 0) begin
            $display("[%0t] UART Packer State=%0d, data_count=%0d",
                $time, u_packer.state[0],
                u_packer.data_count[0]);
        end
    end

    // Debug: Monitor packed_upload_valid
    always @(posedge clk) begin
        if (packed_upload_valid != 0) begin
            $display("[%0t] packed_upload_valid=%b, packed_upload_data=0x%04x",
                $time, packed_upload_valid, packed_upload_data);
        end
    end

    // Main test
    initial begin
        // Initialize
        rst_n = 0;
        uart_req = 0;
        uart_data = 0;
        uart_valid = 0;
        spi_req = 0;
        spi_data = 0;
        spi_valid = 0;
        packed_upload_ready = 2'b11;

        $display("========================================");
        $display("Multi-Channel Upload Packer Testbench");
        $display("========================================");

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // ============================================================
        // Test 1: UART发送3字节
        // ============================================================
        $display("\n[TEST 1] UART sends 3 bytes");
        uart_bytes_received = 0;
        uart_req = 1;

        @(posedge clk);
        wait(uart_ready);
        uart_data = 8'hA1;
        uart_valid = 1;
        @(posedge clk);
        uart_valid = 0;

        @(posedge clk);
        wait(uart_ready);
        uart_data = 8'hA2;
        uart_valid = 1;
        @(posedge clk);
        uart_valid = 0;

        @(posedge clk);
        wait(uart_ready);
        uart_data = 8'hA3;
        uart_valid = 1;
        @(posedge clk);
        uart_valid = 0;

        @(posedge clk);
        uart_req = 0;

        #(CLK_PERIOD * 20);
        if (uart_bytes_received == 9)
            $display("TEST 1: PASS (9 bytes received)");
        else
            $display("TEST 1: FAIL (expected 9, got %0d)", uart_bytes_received);

        // ============================================================
        // Test 2: SPI发送3字节
        // ============================================================
        $display("\n[TEST 2] SPI sends 3 bytes");
        spi_bytes_received = 0;
        spi_req = 1;

        @(posedge clk);
        wait(spi_ready);
        spi_data = 8'hB1;
        spi_valid = 1;
        @(posedge clk);
        spi_valid = 0;

        @(posedge clk);
        wait(spi_ready);
        spi_data = 8'hB2;
        spi_valid = 1;
        @(posedge clk);
        spi_valid = 0;

        @(posedge clk);
        wait(spi_ready);
        spi_data = 8'hB3;
        spi_valid = 1;
        @(posedge clk);
        spi_valid = 0;

        @(posedge clk);
        spi_req = 0;

        #(CLK_PERIOD * 20);
        if (spi_bytes_received == 9)
            $display("TEST 2: PASS (9 bytes received)");
        else
            $display("TEST 2: FAIL (expected 9, got %0d)", spi_bytes_received);

        // ============================================================
        // Test 3: UART和SPI并行发送（测试真正并行）
        // ============================================================
        $display("\n[TEST 3] UART and SPI send simultaneously (parallel test)");
        uart_bytes_received = 0;
        spi_bytes_received = 0;

        // 同时启动
        uart_req = 1;
        spi_req = 1;

        fork
            // UART线程
            begin
                repeat(2) begin
                    @(posedge clk);
                    wait(uart_ready);
                    uart_data = 8'hC0 + uart_bytes_received;
                    uart_valid = 1;
                    @(posedge clk);
                    uart_valid = 0;
                end
                uart_req = 0;
            end

            // SPI线程
            begin
                repeat(2) begin
                    @(posedge clk);
                    wait(spi_ready);
                    spi_data = 8'hD0 + spi_bytes_received;
                    spi_valid = 1;
                    @(posedge clk);
                    spi_valid = 0;
                end
                spi_req = 0;
            end
        join

        #(CLK_PERIOD * 30);
        $display("UART packed: %0d bytes, SPI packed: %0d bytes", uart_bytes_received, spi_bytes_received);
        if (uart_bytes_received == 8 && spi_bytes_received == 8)
            $display("TEST 3: PASS (parallel packing works!)");
        else
            $display("TEST 3: FAIL");

        // ============================================================
        // Test completed
        // ============================================================
        #(CLK_PERIOD * 20);
        $display("\n========================================");
        $display("All tests completed");
        $display("========================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 3000);
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("upload_packer_tb.vcd");
        $dumpvars(0, upload_packer_tb);
    end

endmodule
