// ============================================================================
// Module:      spi_master_slave_tb
// Author:      AI Assistant
// Date:        2025-01-23
//
// Description:
// 使用真实的SPI Master Handler和SPI Slave Handler进行测试
// 测试场景：
//   - Master通过0x11命令写入数据到外部从机
//   - Slave通过0x14预装数据，Master读取
//   - Slave通过0x15启用上传，接收Master发送的数据并上传
// ============================================================================

`timescale 1ns / 1ps

module spi_master_slave_tb;

    //-------------------------------------------------------------------------
    // 参数定义
    //-------------------------------------------------------------------------
    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // ~16.67ns

    //-------------------------------------------------------------------------
    // 测试信号
    //-------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    // Master命令总线
    reg [7:0]  master_cmd_type;
    reg [15:0] master_cmd_length;
    reg [7:0]  master_cmd_data;
    reg [15:0] master_cmd_data_index;
    reg        master_cmd_start;
    reg        master_cmd_data_valid;
    reg        master_cmd_done;
    wire       master_cmd_ready;

    // Master上传接口
    wire       master_upload_active;
    wire       master_upload_req;
    wire [7:0] master_upload_data;
    wire [7:0] master_upload_source;
    wire       master_upload_valid;
    reg        master_upload_ready;

    // Slave命令总线
    reg [7:0]  slave_cmd_type;
    reg [15:0] slave_cmd_length;
    reg [7:0]  slave_cmd_data;
    reg [15:0] slave_cmd_data_index;
    reg        slave_cmd_start;
    reg        slave_cmd_data_valid;
    reg        slave_cmd_done;
    wire       slave_cmd_ready;

    // Slave上传接口
    wire       slave_upload_active;
    wire       slave_upload_req;
    wire [7:0] slave_upload_data;
    wire [7:0] slave_upload_source;
    wire       slave_upload_valid;
    reg        slave_upload_ready;

    // SPI总线
    wire       spi_clk;
    wire       spi_cs_n;
    wire       spi_mosi;
    wire       spi_miso;

    // 测试变量
    integer i;
    reg [7:0] test_data [0:255];
    reg [7:0] master_uploaded_data [0:255];
    reg [7:0] slave_uploaded_data [0:255];
    integer master_upload_count;
    integer slave_upload_count;
    integer test_pass_count;
    integer test_fail_count;

    //-------------------------------------------------------------------------
    // DUT实例化
    //-------------------------------------------------------------------------

    // SPI Master Handler (CLK_DIV=30 → 60MHz/30/2 = 1MHz SPI时钟)
    spi_handler #(
        .CLK_DIV(30)
    ) u_master (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(master_cmd_type),
        .cmd_length(master_cmd_length),
        .cmd_data(master_cmd_data),
        .cmd_data_index(master_cmd_data_index),
        .cmd_start(master_cmd_start),
        .cmd_data_valid(master_cmd_data_valid),
        .cmd_done(master_cmd_done),
        .cmd_ready(master_cmd_ready),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .upload_active(master_upload_active),
        .upload_req(master_upload_req),
        .upload_data(master_upload_data),
        .upload_source(master_upload_source),
        .upload_valid(master_upload_valid),
        .upload_ready(master_upload_ready)
    );

    // SPI Slave Handler
    spi_slave_handler u_slave (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(slave_cmd_type),
        .cmd_length(slave_cmd_length),
        .cmd_data(slave_cmd_data),
        .cmd_data_index(slave_cmd_data_index),
        .cmd_start(slave_cmd_start),
        .cmd_data_valid(slave_cmd_data_valid),
        .cmd_done(slave_cmd_done),
        .cmd_ready(slave_cmd_ready),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .upload_active(slave_upload_active),
        .upload_req(slave_upload_req),
        .upload_data(slave_upload_data),
        .upload_source(slave_upload_source),
        .upload_valid(slave_upload_valid),
        .upload_ready(slave_upload_ready)
    );

    //-------------------------------------------------------------------------
    // 时钟生成
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Master上传数据捕获
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            master_upload_count <= 0;
        end else if (master_upload_valid && master_upload_ready) begin
            master_uploaded_data[master_upload_count] <= master_upload_data;
            master_upload_count <= master_upload_count + 1;
            $display("[%0t] MASTER UPLOAD: data[%0d]=0x%02x, source=0x%02x",
                     $time, master_upload_count, master_upload_data, master_upload_source);
        end
    end

    //-------------------------------------------------------------------------
    // Slave上传数据捕获
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            slave_upload_count <= 0;
        end else if (slave_upload_valid && slave_upload_ready) begin
            slave_uploaded_data[slave_upload_count] <= slave_upload_data;
            slave_upload_count <= slave_upload_count + 1;
            $display("[%0t] SLAVE UPLOAD: data[%0d]=0x%02x, source=0x%02x",
                     $time, slave_upload_count, slave_upload_data, slave_upload_source);
        end
    end

    //-------------------------------------------------------------------------
    // Task: 发送Master命令
    //-------------------------------------------------------------------------
    task automatic send_master_cmd(
        input [7:0]  cmd,
        input [15:0] length,
        input [7:0]  data_array [0:255],
        input integer data_len
    );
        integer idx;
        begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] Sending MASTER Command 0x%02x, length=%0d", $time, cmd, length);
            $display("[%0t] ========================================", $time);

            wait(master_cmd_ready == 1'b1);
            @(posedge clk);

            master_cmd_type <= cmd;
            master_cmd_length <= length;
            master_cmd_start <= 1'b1;
            @(posedge clk);
            master_cmd_start <= 1'b0;

            for (idx = 0; idx < data_len; idx = idx + 1) begin
                @(posedge clk);
                master_cmd_data <= data_array[idx];
                master_cmd_data_index <= idx;
                master_cmd_data_valid <= 1'b1;
                @(posedge clk);
                master_cmd_data_valid <= 1'b0;
            end

            repeat(2) @(posedge clk);
            master_cmd_done <= 1'b1;
            @(posedge clk);
            master_cmd_done <= 1'b0;

            $display("[%0t] Master command transmission complete", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: 发送Slave命令
    //-------------------------------------------------------------------------
    task automatic send_slave_cmd(
        input [7:0]  cmd,
        input [15:0] length,
        input [7:0]  data_array [0:255],
        input integer data_len
    );
        integer idx;
        begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] Sending SLAVE Command 0x%02x, length=%0d", $time, cmd, length);
            $display("[%0t] ========================================", $time);

            wait(slave_cmd_ready == 1'b1);
            @(posedge clk);

            slave_cmd_type <= cmd;
            slave_cmd_length <= length;
            slave_cmd_start <= 1'b1;
            @(posedge clk);
            slave_cmd_start <= 1'b0;

            for (idx = 0; idx < data_len; idx = idx + 1) begin
                @(posedge clk);
                slave_cmd_data <= data_array[idx];
                slave_cmd_data_index <= idx;
                slave_cmd_data_valid <= 1'b1;
                @(posedge clk);
                slave_cmd_data_valid <= 1'b0;
            end

            repeat(2) @(posedge clk);
            slave_cmd_done <= 1'b1;
            @(posedge clk);
            slave_cmd_done <= 1'b0;

            $display("[%0t] Slave command transmission complete", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: 验证数据
    //-------------------------------------------------------------------------
    task automatic verify_data(
        input [7:0] expected [0:255],
        input [7:0] actual [0:255],
        input integer count,
        input string test_name
    );
        integer idx;
        integer errors;
        begin
            errors = 0;
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] Verifying: %s", $time, test_name);
            $display("[%0t] ========================================", $time);

            for (idx = 0; idx < count; idx = idx + 1) begin
                if (expected[idx] !== actual[idx]) begin
                    $display("[%0t] ERROR: byte[%0d] expected=0x%02x, actual=0x%02x",
                             $time, idx, expected[idx], actual[idx]);
                    errors = errors + 1;
                end
            end

            if (errors == 0) begin
                $display("[%0t] PASS: %s - All %0d bytes match!",
                         $time, test_name, count);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("[%0t] FAIL: %s - %0d errors found!",
                         $time, test_name, errors);
                test_fail_count = test_fail_count + 1;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // 主测试序列
    //-------------------------------------------------------------------------
    initial begin
        // 初始化
        rst_n = 1'b0;
        master_cmd_type = 8'h00;
        master_cmd_length = 16'h0000;
        master_cmd_data = 8'h00;
        master_cmd_data_index = 16'h0000;
        master_cmd_start = 1'b0;
        master_cmd_data_valid = 1'b0;
        master_cmd_done = 1'b0;
        master_upload_ready = 1'b1;
        master_upload_count = 0;

        slave_cmd_type = 8'h00;
        slave_cmd_length = 16'h0000;
        slave_cmd_data = 8'h00;
        slave_cmd_data_index = 16'h0000;
        slave_cmd_start = 1'b0;
        slave_cmd_data_valid = 1'b0;
        slave_cmd_done = 1'b0;
        slave_upload_ready = 1'b1;
        slave_upload_count = 0;

        test_pass_count = 0;
        test_fail_count = 0;

        // 复位
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
        #(CLK_PERIOD_NS * 10);

        // =====================================================================
        // Test 1: Master写入数据到Slave（Slave启用上传）
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 1: Master写入数据 → Slave接收并上传");
        $display("====================================================================");

        // 步骤1：Slave启用上传（0x15，data=0x01）
        test_data[0] = 8'h01;
        send_slave_cmd(8'h15, 16'd1, test_data, 1);
        #(CLK_PERIOD_NS * 50);

        // 步骤2：Master写入4字节（0x11命令）
        // 格式：[write_len][read_len][data...]
        test_data[0] = 8'h04; // write_len = 4
        test_data[1] = 8'h00; // read_len = 0
        test_data[2] = 8'hAA; // 数据
        test_data[3] = 8'hBB;
        test_data[4] = 8'hCC;
        test_data[5] = 8'hDD;
        slave_upload_count = 0;  // 重置计数器
        send_master_cmd(8'h11, 16'd6, test_data, 6);

        // 等待SPI传输完成和上传
        #(CLK_PERIOD_NS * 5000);

        // 验证Slave上传的数据（从test_data[2]开始是实际数据）
        test_data[0] = 8'hAA;
        test_data[1] = 8'hBB;
        test_data[2] = 8'hCC;
        test_data[3] = 8'hDD;
        verify_data(test_data, slave_uploaded_data, 4, "Test 1: Slave接收数据");

        // =====================================================================
        // Test 2: Slave预装数据 → Master读取
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 2: Slave预装数据 → Master读取并上传");
        $display("====================================================================");

        // 步骤1：Slave预装数据（0x14，"FPGA2025"）
        test_data[0] = 8'h46; // F
        test_data[1] = 8'h50; // P
        test_data[2] = 8'h47; // G
        test_data[3] = 8'h41; // A
        test_data[4] = 8'h32; // 2
        test_data[5] = 8'h30; // 0
        test_data[6] = 8'h32; // 2
        test_data[7] = 8'h35; // 5
        send_slave_cmd(8'h14, 16'd8, test_data, 8);
        #(CLK_PERIOD_NS * 50);

        // 步骤2：Master读取8字节（0x11命令）
        // 格式：[write_len][read_len]
        master_upload_count = 0;  // 重置计数器
        test_data[0] = 8'h00; // write_len = 0
        test_data[1] = 8'h08; // read_len = 8
        send_master_cmd(8'h11, 16'd2, test_data, 2);

        // 等待SPI传输完成和上传
        #(CLK_PERIOD_NS * 5000);

        // 验证Master上传的数据
        test_data[0] = 8'h46;
        test_data[1] = 8'h50;
        test_data[2] = 8'h47;
        test_data[3] = 8'h41;
        test_data[4] = 8'h32;
        test_data[5] = 8'h30;
        test_data[6] = 8'h32;
        test_data[7] = 8'h35;
        verify_data(test_data, master_uploaded_data, 8, "Test 2: Master读取数据");

        // =====================================================================
        // 测试总结
        // =====================================================================
        #(CLK_PERIOD_NS * 100);
        $display("\n");
        $display("====================================================================");
        $display("SIMULATION COMPLETE");
        $display("====================================================================");
        $display("Total Tests: %0d", test_pass_count + test_fail_count);
        $display("Passed:      %0d", test_pass_count);
        $display("Failed:      %0d", test_fail_count);
        $display("====================================================================");

        if (test_fail_count == 0) begin
            $display(">>> ALL TESTS PASSED! <<<");
        end else begin
            $display(">>> SOME TESTS FAILED <<<");
        end

        $display("\n");
        $finish;
    end

    //-------------------------------------------------------------------------
    // 超时看门狗
    //-------------------------------------------------------------------------
    initial begin
        #100_000_000; // 100ms timeout
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

endmodule
