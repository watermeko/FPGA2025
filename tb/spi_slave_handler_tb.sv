// ============================================================================
// Module:      spi_slave_handler_tb
// Author:      AI Assistant
// Date:        2025-01-23
//
// Description:
// Testbench for SPI Slave Handler module
// Tests功能码 0x14 (预装发送数据) and 0x15 (控制上传使能)
// Verifies SPI slave physical layer and data upload functionality
// ============================================================================

`timescale 1ns / 1ps

module spi_slave_handler_tb;

    //-------------------------------------------------------------------------
    // Testbench Parameters
    //-------------------------------------------------------------------------
    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // ~16.67ns
    localparam SPI_CLK_PERIOD_NS = 1000; // 1MHz SPI clock

    //-------------------------------------------------------------------------
    // Testbench Signals
    //-------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    // Command bus
    reg [7:0]  cmd_type;
    reg [15:0] cmd_length;
    reg [7:0]  cmd_data;
    reg [15:0] cmd_data_index;
    reg        cmd_start;
    reg        cmd_data_valid;
    reg        cmd_done;
    wire       cmd_ready;

    // SPI slave interface
    reg        spi_clk;
    reg        spi_cs_n;
    reg        spi_mosi;
    wire       spi_miso;

    // Upload interface
    wire       upload_active;
    wire       upload_req;
    wire [7:0] upload_data;
    wire [7:0] upload_source;
    wire       upload_valid;
    reg        upload_ready;

    // Testbench variables
    integer i, j;
    reg [7:0] test_data [0:255];
    reg [7:0] spi_master_read_data [0:255];
    reg [7:0] uploaded_data [0:255];
    integer uploaded_count;
    integer test_pass_count;
    integer test_fail_count;
    integer test5_upload_start;

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    spi_slave_handler dut (
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

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Upload Data Capture
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            uploaded_count <= 0;
        end else if (upload_valid && upload_ready) begin
            uploaded_data[uploaded_count] <= upload_data;
            uploaded_count <= uploaded_count + 1;
            $display("[%0t] UPLOAD: data[%0d]=0x%02x, source=0x%02x",
                     $time, uploaded_count, upload_data, upload_source);
        end
    end

    //-------------------------------------------------------------------------
    // Task: Send Command (模拟command_processor行为)
    //-------------------------------------------------------------------------
    task automatic send_command(
        input [7:0]  cmd,
        input [15:0] length,
        input [7:0]  data_array [0:255],
        input integer data_len
    );
        integer idx;
        begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] Sending Command 0x%02x, length=%0d", $time, cmd, length);
            $display("[%0t] ========================================", $time);

            // Wait for cmd_ready
            wait(cmd_ready == 1'b1);
            @(posedge clk);

            // Assert cmd_start
            cmd_type <= cmd;
            cmd_length <= length;
            cmd_start <= 1'b1;
            @(posedge clk);
            cmd_start <= 1'b0;

            // Send data bytes
            for (idx = 0; idx < data_len; idx = idx + 1) begin
                @(posedge clk);
                cmd_data <= data_array[idx];
                cmd_data_index <= idx;
                cmd_data_valid <= 1'b1;
                @(posedge clk);
                cmd_data_valid <= 1'b0;
            end

            // Assert cmd_done
            repeat(2) @(posedge clk);
            cmd_done <= 1'b1;
            @(posedge clk);
            cmd_done <= 1'b0;

            $display("[%0t] Command transmission complete", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: SPI Master Read (从FPGA从机读取数据)
    //-------------------------------------------------------------------------
    task automatic spi_master_read(
        input integer byte_count,
        output reg [7:0] read_data [0:255]
    );
        integer byte_idx, bit_idx;
        reg [7:0] rx_byte;
        begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] SPI Master: Reading %0d bytes from slave", $time, byte_count);
            $display("[%0t] ========================================", $time);

            // Assert CS once for all bytes (continuous transfer)
            spi_cs_n = 1'b0;
            #(SPI_CLK_PERIOD_NS * 10);  // 等待从机准备好（同步延迟）

            for (byte_idx = 0; byte_idx < byte_count; byte_idx = byte_idx + 1) begin
                rx_byte = 8'h00;

                // Transfer 8 bits
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    // Falling edge - slave updates MISO here
                    spi_clk = 1'b0;
                    // MOSI = 0 (dummy data for read)
                    spi_mosi = 1'b0;
                    #(SPI_CLK_PERIOD_NS / 2);

                    // Rising edge - sample MISO
                    spi_clk = 1'b1;
                    #(SPI_CLK_PERIOD_NS / 4);  // Wait for setup time
                    rx_byte[7 - bit_idx] = spi_miso;
                    #(SPI_CLK_PERIOD_NS / 4);
                end

                read_data[byte_idx] = rx_byte;
                $display("[%0t] SPI Master: Read byte[%0d]=0x%02x",
                         $time, byte_idx, rx_byte);
            end

            // Deassert CS after all bytes
            #(SPI_CLK_PERIOD_NS);
            spi_cs_n = 1'b1;
            #(SPI_CLK_PERIOD_NS * 4);

            $display("[%0t] SPI Master: Read complete", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: SPI Master Write (向FPGA从机写入数据)
    //-------------------------------------------------------------------------
    task automatic spi_master_write(
        input integer byte_count,
        input reg [7:0] write_data [0:255]
    );
        integer byte_idx, bit_idx;
        reg [7:0] tx_byte;
        begin
            $display("\n[%0t] ========================================", $time);
            $display("[%0t] SPI Master: Writing %0d bytes to slave", $time, byte_count);
            $display("[%0t] ========================================", $time);

            // Assert CS once for all bytes (continuous transfer)
            spi_cs_n = 1'b0;
            #(SPI_CLK_PERIOD_NS * 10);  // 等待从机准备好（同步延迟）

            for (byte_idx = 0; byte_idx < byte_count; byte_idx = byte_idx + 1) begin
                tx_byte = write_data[byte_idx];
                $display("[%0t] SPI Master: Writing byte[%0d]=0x%02x",
                         $time, byte_idx, tx_byte);

                // Transfer 8 bits (MSB first)
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    // Falling edge - setup MOSI
                    spi_clk = 1'b0;
                    spi_mosi = tx_byte[7 - bit_idx];
                    #(SPI_CLK_PERIOD_NS / 2);

                    // Rising edge - slave samples MOSI
                    spi_clk = 1'b1;
                    #(SPI_CLK_PERIOD_NS / 2);
                end
            end

            // Deassert CS after all bytes
            #(SPI_CLK_PERIOD_NS);
            spi_cs_n = 1'b1;
            #(SPI_CLK_PERIOD_NS * 4);

            $display("[%0t] SPI Master: Write complete", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Task: Verify Data
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
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        // Initialize
        rst_n = 1'b0;
        cmd_type = 8'h00;
        cmd_length = 16'h0000;
        cmd_data = 8'h00;
        cmd_data_index = 16'h0000;
        cmd_start = 1'b0;
        cmd_data_valid = 1'b0;
        cmd_done = 1'b0;
        spi_clk = 1'b0;
        spi_cs_n = 1'b1;
        spi_mosi = 1'b0;
        upload_ready = 1'b1;  // Always ready
        uploaded_count = 0;
        test_pass_count = 0;
        test_fail_count = 0;

        // Reset
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
        #(CLK_PERIOD_NS * 10);

        // =====================================================================
        // Test 1: 预装数据测试 (功能码 0x14)
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 1: 预装发送数据 (功能码 0x14)");
        $display("====================================================================");

        // Prepare test data "FPGA2025"
        test_data[0] = 8'h46; // F
        test_data[1] = 8'h50; // P
        test_data[2] = 8'h47; // G
        test_data[3] = 8'h41; // A
        test_data[4] = 8'h32; // 2
        test_data[5] = 8'h30; // 0
        test_data[6] = 8'h32; // 2
        test_data[7] = 8'h35; // 5

        // Send 0x14 command
        send_command(8'h14, 16'd8, test_data, 8);
        #(CLK_PERIOD_NS * 50);

        // SPI master reads from slave
        spi_master_read(8, spi_master_read_data);
        #(CLK_PERIOD_NS * 50);

        // Verify
        verify_data(test_data, spi_master_read_data, 8, "Test 1: 预装数据读取");

        // =====================================================================
        // Test 2: 启用上传并写入数据 (功能码 0x15 + SPI写入)
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 2: 启用接收上传 (功能码 0x15)");
        $display("====================================================================");

        // Send 0x15 command to enable upload
        test_data[0] = 8'h01; // Enable upload
        send_command(8'h15, 16'd1, test_data, 1);
        #(CLK_PERIOD_NS * 50);

        // Prepare write data
        test_data[0] = 8'hDE;
        test_data[1] = 8'hAD;
        test_data[2] = 8'hBE;
        test_data[3] = 8'hEF;

        // SPI master writes to slave
        uploaded_count = 0;  // Reset counter
        spi_master_write(4, test_data);
        #(CLK_PERIOD_NS * 200);  // Wait for upload

        // Verify uploaded data
        verify_data(test_data, uploaded_data, 4, "Test 2: 接收数据上传");

        // Check upload source
        if (upload_source == 8'h14) begin
            $display("[%0t] PASS: Upload source = 0x14 (correct)", $time);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("[%0t] FAIL: Upload source = 0x%02x (expected 0x14)",
                     $time, upload_source);
            test_fail_count = test_fail_count + 1;
        end

        // =====================================================================
        // Test 3: 禁用上传 (功能码 0x15, data=0)
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 3: 禁用接收上传 (功能码 0x15)");
        $display("====================================================================");

        // Send 0x15 command to disable upload
        test_data[0] = 8'h00; // Disable upload
        send_command(8'h15, 16'd1, test_data, 1);
        #(CLK_PERIOD_NS * 50);

        // Write data (should NOT be uploaded)
        test_data[0] = 8'h11;
        test_data[1] = 8'h22;
        uploaded_count = 0;  // Reset counter
        spi_master_write(2, test_data);
        #(CLK_PERIOD_NS * 200);

        // Verify no data uploaded
        if (uploaded_count == 0) begin
            $display("[%0t] PASS: No data uploaded (upload disabled)", $time);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("[%0t] FAIL: %0d bytes uploaded (should be 0)",
                     $time, uploaded_count);
            test_fail_count = test_fail_count + 1;
        end

        // =====================================================================
        // Test 4: 大数据块预装测试 (128字节)
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 4: 大数据块预装 (128字节)");
        $display("====================================================================");

        // Prepare large data block
        for (i = 0; i < 128; i = i + 1) begin
            test_data[i] = i;
        end

        // Send 0x14 command
        send_command(8'h14, 16'd128, test_data, 128);
        #(CLK_PERIOD_NS * 50);

        // SPI master reads
        spi_master_read(128, spi_master_read_data);
        #(CLK_PERIOD_NS * 50);

        // Verify
        verify_data(test_data, spi_master_read_data, 128, "Test 4: 大数据块读取");

        // =====================================================================
        // Test 5: 双向通信测试 (同时读写)
        // =====================================================================
        $display("\n");
        $display("====================================================================");
        $display("TEST 5: 双向通信 (预装数据 + 启用上传 + 同时读写)");
        $display("====================================================================");

        // Preload TX data
        for (i = 0; i < 16; i = i + 1) begin
            test_data[i] = 8'hA0 + i;
        end
        send_command(8'h14, 16'd16, test_data, 16);
        #(CLK_PERIOD_NS * 50);

        // Enable upload
        test_data[0] = 8'h01;
        send_command(8'h15, 16'd1, test_data, 1);
        #(CLK_PERIOD_NS * 50);

        // Prepare write data
        for (i = 0; i < 16; i = i + 1) begin
            test_data[i] = 8'hB0 + i;
        end

        // Reset counters
        test5_upload_start = uploaded_count;  // 记录Test 5开始时的上传计数

        // 确保CS先拉高（复位从机状态）
        spi_cs_n = 1'b1;
        #(SPI_CLK_PERIOD_NS * 20);

        // SPI Master: Simultaneous read/write
        $display("\n[%0t] Starting simultaneous read/write...", $time);
        spi_cs_n = 1'b0;
        #(SPI_CLK_PERIOD_NS * 10);  // 等待从机准备好

        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                // Falling edge - setup MOSI
                spi_clk = 1'b0;
                spi_mosi = test_data[i][7 - j];
                #(SPI_CLK_PERIOD_NS / 2);

                // Rising edge - sample MISO
                spi_clk = 1'b1;
                #(SPI_CLK_PERIOD_NS / 4);
                spi_master_read_data[i][7 - j] = spi_miso;
                #(SPI_CLK_PERIOD_NS / 4);
            end
            $display("[%0t] SPI: TX=0x%02x, RX=0x%02x",
                     $time, test_data[i], spi_master_read_data[i]);
        end

        spi_cs_n = 1'b1;
        #(CLK_PERIOD_NS * 200);

        $display("[%0t] Verifying RX data (should match preloaded A0-AF)...", $time);
        for (i = 0; i < 16; i = i + 1) begin
            if (spi_master_read_data[i] !== (8'hA0 + i)) begin
                $display("[%0t] FAIL: RX[%0d]=0x%02x, expected=0x%02x",
                         $time, i, spi_master_read_data[i], 8'hA0 + i);
                test_fail_count = test_fail_count + 1;
            end
        end

        $display("[%0t] Verifying uploaded data (should match written B0-BF)...", $time);
        #(CLK_PERIOD_NS * 50);
        for (i = 0; i < 16 && (test5_upload_start + i) < uploaded_count; i = i + 1) begin
            if (uploaded_data[test5_upload_start + i] !== (8'hB0 + i)) begin
                $display("[%0t] FAIL: Upload[%0d]=0x%02x, expected=0x%02x",
                         $time, i, uploaded_data[test5_upload_start + i], 8'hB0 + i);
                test_fail_count = test_fail_count + 1;
            end
        end

        if (test_fail_count == 0) begin
            $display("[%0t] PASS: Test 5 双向通信成功!", $time);
            test_pass_count = test_pass_count + 1;
        end

        // =====================================================================
        // Test Summary
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
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #100_000_000; // 100ms timeout
        $display("[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

endmodule
