`timescale 1ns / 1ps

// 简化版 SPI Handler 测试平台 - 用于快速验证优化后的流式架构
module spi_handler_simple_tb;

    // ==================== 时钟和复位 ====================
    reg clk;
    reg rst_n;

    // ==================== 命令接口 ====================
    reg  [7:0]  cmd_type;
    reg  [15:0] cmd_length;
    reg  [7:0]  cmd_data;
    reg  [15:0] cmd_data_index;
    reg         cmd_start;
    reg         cmd_data_valid;
    reg         cmd_done;
    wire        cmd_ready;

    // ==================== SPI 物理接口 ====================
    wire spi_clk;
    wire spi_cs_n;
    wire spi_mosi;
    reg  spi_miso;

    // ==================== 上传接口 ====================
    wire        upload_active;
    wire        upload_req;
    wire [7:0]  upload_data;
    wire [7:0]  upload_source;
    wire        upload_valid;
    reg         upload_ready;

    // ==================== DUT 实例化 ====================
    spi_handler #(
        .CLK_DIV(2)  // 快速时钟用于仿真
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(cmd_ready),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .upload_active(upload_active),
        .upload_req(upload_req),
        .upload_data(upload_data),
        .upload_source(upload_source),
        .upload_valid(upload_valid),
        .upload_ready(upload_ready)
    );

    // ==================== 时钟生成 (60MHz) ====================
    initial begin
        clk = 0;
        forever #8.33 clk = ~clk;
    end

    // ==================== 简单的 SPI 从机模型 ====================
    reg [7:0] miso_data;
    reg [2:0] bit_counter;

    always @(posedge spi_clk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            bit_counter <= 0;
            miso_data <= 8'hA5;  // 固定返回 0xA5
        end else begin
            bit_counter <= bit_counter + 1;
        end
    end

    always @(*) begin
        if (spi_cs_n)
            spi_miso = 1'b1;
        else
            spi_miso = miso_data[7];
    end

    always @(negedge spi_clk) begin
        if (!spi_cs_n) begin
            miso_data <= {miso_data[6:0], 1'b0};
        end
    end

    // ==================== 测试任务 ====================
    task send_byte;
        input [15:0] index;
        input [7:0]  data;
        begin
            @(posedge clk);
            cmd_data_index = index;
            cmd_data = data;
            cmd_data_valid = 1'b1;
            @(posedge clk);
            cmd_data_valid = 1'b0;
        end
    endtask

    // ==================== 监控 ====================
    always @(posedge clk) begin
        if (upload_valid) begin
            $display("[%0t] ✓ Upload: data=0x%02x, source=0x%02x",
                     $time, upload_data, upload_source);
        end

        if (uut.spi_start) begin
            $display("[%0t] → SPI Start: tx=0x%02x", $time, uut.current_tx_byte);
        end

        if (uut.spi_done) begin
            $display("[%0t] ← SPI Done: rx=0x%02x", $time, uut.spi_rx_byte);
        end
    end

    // 状态监控
    reg [2:0] prev_state;
    initial prev_state = 0;
    always @(posedge clk) begin
        if (uut.state != prev_state) begin
            case (uut.state)
                0: $display("[%0t] State: IDLE", $time);
                1: $display("[%0t] State: WAIT_HEADER", $time);
                2: $display("[%0t] State: TX_PHASE", $time);
                3: $display("[%0t] State: RX_PHASE", $time);
                4: $display("[%0t] State: WAIT_SPI_DONE", $time);
                5: $display("[%0t] State: UPLOAD_BYTE", $time);
            endcase
            prev_state = uut.state;
        end
    end

    // ==================== 测试序列 ====================
    integer errors;

    initial begin
        errors = 0;

        // 初始化
        rst_n = 0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        upload_ready = 1;  // 上传通道始终就绪

        #100;
        rst_n = 1;
        #100;

        $display("\n========================================");
        $display("  SPI Handler 流式架构验证测试");
        $display("========================================\n");

        // ==================== 测试 1: 纯写操作 ====================
        $display("\n[TEST 1] 纯写操作: write_len=2, read_len=0");
        $display("------------------------------------------");

        wait(cmd_ready);
        @(posedge clk);
        cmd_type = 8'h11;
        cmd_length = 16'd4;  // 2 (header) + 2 (data)
        cmd_start = 1;
        @(posedge clk);
        cmd_start = 0;

        send_byte(0, 8'd2);   // write_len = 2
        send_byte(1, 8'd0);   // read_len = 0
        send_byte(2, 8'hAA);  // data[0]
        send_byte(3, 8'hBB);  // data[1]

        @(posedge clk);
        cmd_done = 1;
        @(posedge clk);
        cmd_done = 0;

        wait(uut.state == 0);  // 等待返回 IDLE
        #500;
        $display("[TEST 1] 完成\n");

        // ==================== 测试 2: 纯读操作 ====================
        $display("\n[TEST 2] 纯读操作: write_len=0, read_len=2");
        $display("------------------------------------------");

        wait(cmd_ready);
        @(posedge clk);
        cmd_type = 8'h11;
        cmd_length = 16'd2;  // 仅 header
        cmd_start = 1;
        @(posedge clk);
        cmd_start = 0;

        send_byte(0, 8'd0);   // write_len = 0
        send_byte(1, 8'd2);   // read_len = 2

        @(posedge clk);
        cmd_done = 1;
        @(posedge clk);
        cmd_done = 0;

        wait(uut.state == 0);
        #500;
        $display("[TEST 2] 完成\n");

        // ==================== 测试 3: 读写混合 ====================
        $display("\n[TEST 3] 读写混合: write_len=1, read_len=1");
        $display("------------------------------------------");

        wait(cmd_ready);
        @(posedge clk);
        cmd_type = 8'h11;
        cmd_length = 16'd3;  // 2 (header) + 1 (data)
        cmd_start = 1;
        @(posedge clk);
        cmd_start = 0;

        send_byte(0, 8'd1);   // write_len = 1
        send_byte(1, 8'd1);   // read_len = 1
        send_byte(2, 8'hCC);  // data[0]

        @(posedge clk);
        cmd_done = 1;
        @(posedge clk);
        cmd_done = 0;

        wait(uut.state == 0);
        #500;
        $display("[TEST 3] 完成\n");

        // ==================== 测试总结 ====================
        #1000;
        $display("\n========================================");
        if (errors == 0) begin
            $display("  ✓ 所有测试通过！");
        end else begin
            $display("  ✗ 发现 %0d 个错误", errors);
        end
        $display("========================================\n");

        $finish;
    end

    // 超时保护
    initial begin
        #50000;
        $display("\n[ERROR] 测试超时！");
        $finish;
    end

endmodule
