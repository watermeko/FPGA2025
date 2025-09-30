// =============================================================================
// Module:       i2c_tb
// Author:       watermelon
// Date:         2025-09-26
//
// Description:
// Testbench for the CDC Top-Level module, focusing on I2C Controller functionality.
// It uses tri-state signals and pullup resistors to correctly model the I2C bus.
// It simulates sending I2C configuration, write, and read commands
// via the USB-CDC command interface, and includes verification for the read data upload.
// =============================================================================

`timescale 1ns / 1ps

`include "utils.sv"

module i2c_tb;

    // -------------------------------------------------------------------------
    // Testbench Parameters
    // -------------------------------------------------------------------------
    localparam CLK_FREQ      = 50_000_000;
    localparam CLK_PERIOD_NS = 2_000_000_000 / CLK_FREQ; // Clock period in ns

    localparam I2C_SLAVE_ADDR_7BIT = 7'h50;            // 7-bit address 0x50
    localparam I2C_SLAVE_ADDR_WRITE = {I2C_SLAVE_ADDR_7BIT, 1'b0}; // 0xA0
    localparam I2C_SLAVE_ADDR_READ  = {I2C_SLAVE_ADDR_7BIT, 1'b1};  // 0xA1

    localparam CMD_I2C_CONFIG = 8'h04;
    localparam CMD_I2C_WRITE  = 8'h05;
    localparam CMD_I2C_READ   = 8'h06;

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    logic [7:0] tb_usb_data;
    logic       tb_usb_valid;

    tri SCL;
    tri SDA;

    reg scl_slave_drv = 1'bZ;
    reg sda_slave_drv = 1'bZ;

    logic [7:0] dut_upload_data;
    logic       dut_upload_valid;

    reg i2c_clk;

    // I2C Bus Model with pull-up resistors
    pullup(SCL);
    pullup(SDA);

    assign SCL = scl_slave_drv;
    assign SDA = sda_slave_drv;


    initial begin
        $monitor("[%0t] tb_usb_valid = %b, tb_usb_data = 0x%02x", $time, tb_usb_valid, tb_usb_data);
    end
    // 确认命令确实发送
    initial begin
        $display("[%0t] I2C Bus: SCL/SDA configured with weak pull-up resistors.", $time);
    end

    // -------------------------------------------------------------------------
    // I2C Slave Model (Simple Logic for Testing)
    // -------------------------------------------------------------------------
    task automatic i2c_slave_model;
        integer i;
        logic [7:0] data_to_read[4];
        logic [7:0] data_rx;
        logic i2c_start;
        int data_index = 0;

        data_to_read[0] = 8'hDE;
        data_to_read[1] = 8'hAD;
        data_to_read[2] = 8'hBE;
        data_to_read[3] = 8'hEF;

        forever begin
            i2c_start = 1'b0;
            @(negedge SDA) if (SCL) begin
                i2c_start = 1'b1;
                $display("[%0t] I2C Slave: Detected Start condition", $time);
            end

            if (i2c_start) begin
                @(posedge SCL);
                data_rx = 0;
                for (i=0; i<8; i++) begin
                    data_rx = {data_rx[6:0], SDA};
                    @(posedge SCL);
                end

                if (data_rx == I2C_SLAVE_ADDR_WRITE) begin
                    $display("[%0t] I2C Slave: Received address (0x%02X), R/W=W. Sending ACK", $time, data_rx);
                    sda_slave_drv = 1'b0;
                    @(posedge SCL);
                    sda_slave_drv = 1'bZ;
                    data_index = 0;

                    while (1) begin
                        @(negedge SCL);
                        if (SCL && SDA) begin
                            $display("[%0t] I2C Slave: Detected Stop condition. Stop writing.", $time);
                            break;
                        end
                        @(posedge SCL);


                        for (i=0; i<8; i++) begin
                            data_rx = {data_rx[6:0], SDA};
                            @(posedge SCL);
                        end

                        $display("[%0t] I2C Slave: Received data byte %0d (0x%02X)", $time, data_index, data_rx);
                        data_index++;

                        sda_slave_drv = 1'b0;
                        @(posedge SCL);
                        sda_slave_drv = 1'bZ;
                    end

                end else if (data_rx == I2C_SLAVE_ADDR_READ) begin
                    $display("[%0t] I2C Slave: Received address (0x%02X), R/W=R. Sending ACK", $time, data_rx);
                    sda_slave_drv = 1'b0;
                    @(posedge SCL);
                    sda_slave_drv = 1'bZ;
                    data_index = 0;

                    for (int j = 0; j < 4; j++) begin
                        $display("[%0t] I2C Slave: Sending data byte %0d (0x%02X)", $time, j, data_to_read[j]);
                        @(negedge SCL);
                        for (i=0; i<8; i++) begin
                            sda_slave_drv = data_to_read[j][7-i] ? 1'bZ : 1'b0;
                            @(posedge SCL);
                            @(negedge SCL);
                        end
                        sda_slave_drv = 1'bZ;
                        @(posedge SCL);
                        if (SDA == 1'b1) begin
                            $display("[%0t] I2C Slave: Master sent NACK. Stop reading.", $time);
                            break;
                        end
                    end

                end else begin
                    $display("[%0t] I2C Slave: Received unknown address (0x%02X). Sending NACK (release SDA).", $time, data_rx);
                    sda_slave_drv = 1'bZ;
                    @(posedge SCL);
                end

                @(posedge SCL) if (SDA) $display("[%0t] I2C Slave: Detected Stop condition", $time);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Data Upload Monitor Task
    // -------------------------------------------------------------------------
    task automatic upload_monitor(input int expected_count);
        automatic reg [7:0] expected_data[] = {8'hDE, 8'hAD, 8'hBE, 8'hEF};
        integer count = 0;
        
        $display("[%0t] Upload Monitor: Started, waiting for I2C read data upload (expect %0d bytes)", $time, expected_count);

        repeat (15000) begin
            @(posedge clk);
            if (dut_upload_valid) break;
        end
        
        if (!dut_upload_valid) begin
            $error("[%0t] Upload Monitor: ERROR! Timeout waiting for upload start!", $time);
            return;
        end

        while (count < expected_count) begin
            @(posedge clk);
            if (dut_upload_valid) begin
                if (dut_upload_data == expected_data[count]) begin
                    $display("[%0t] Upload Monitor: Successfully received data [%0d]: 0x%02X", $time, count, dut_upload_data);
                end else begin
                    $error("[%0t] Upload Monitor: ERROR! Received 0x%02X, expected 0x%02X", $time, dut_upload_data, expected_data[count]);
                    break;
                end
                count++;
            end
        end

        if (count == expected_count) begin
            $display("[%0t] Upload Monitor: ** I2C read data upload and verification success! **", $time);
        end else begin
            $error("[%0t] Upload Monitor: ** I2C read data upload failed! Received %0d bytes (expected %0d) **", $time, count, expected_count);
        end
    endtask

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    // Note: Ensure the instantiated 'cdc' module has 'scl' and 'sda' ports
    cdc dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .usb_data_in        (tb_usb_data),
        .usb_data_valid_in  (tb_usb_valid),
        .i2c_clk            (clk),
        .led_out            (),
        .pwm_pins           (),
        .ext_uart_rx        (1'b1),
        .ext_uart_tx        (),
        .dac_clk            (),
        .dac_data           (),
        .SCL                (SCL),
        .SDA                (SDA),

        .usb_upload_data    (dut_upload_data),
        .usb_upload_valid   (dut_upload_valid)
    );

    initial begin
        fork
            SimSrcGen::GenClk(clk, 10ns, CLK_PERIOD_NS);
        join_none
    end

    initial begin
        SimSrcGen::GenRstN(clk, rst_n, 5, 10);
    end

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // =====================================================================
        // All variable declarations are moved to the top of the block
        // =====================================================================
        automatic reg [7:0] i2c_config_data[2];
        automatic reg [7:0] i2c_write_data[3];
        automatic reg [7:0] i2c_read_data[3];
        automatic reg [7:0] empty_data[];
        logic [7:0] write_payload[4];

        // --- Initialization ---
        tb_usb_data  = 8'h00;
        tb_usb_valid = 1'b0;
        scl_slave_drv = 1'bZ;
        sda_slave_drv = 1'bZ;

        fork
            i2c_slave_model;
        join_none

        @(posedge rst_n); // Wait for reset to de-assert
        $display("[%0t] ** Reset complete, start I2C test sequence **", $time);
        # (CLK_PERIOD_NS * 10);

        // --- TEST CASE 1: I2C Configuration (This is a placeholder, as the new handler does not use it) ---
        $display("\n=== [TEST 1] Send I2C configuration command (now unused by handler) ===");
        i2c_config_data[0] = 8'h01;
        i2c_config_data[1] = 8'hF4;
        // FIXED: Added missing len_h argument (8'h00)
        USB::SendProtocolFrame(clk, tb_usb_data, tb_usb_valid, CMD_I2C_CONFIG, 8'h00, 2, i2c_config_data, CLK_PERIOD_NS);
        $display("[%0t] I2C configuration command sent", $time);
        # (CLK_PERIOD_NS * 100);

        // --- TEST CASE 2: I2C Write ---
        $display("\n=== [TEST 2] Send I2C write command: Slave 0x50, Reg 0xAA, Data 0x12, 0x34 ===");
        write_payload[0] = I2C_SLAVE_ADDR_7BIT;
        write_payload[1] = 8'hAA;
        write_payload[2] = 8'h12;
        write_payload[3] = 8'h34;
        // FIXED: Added missing len_h argument (8'h00)
        USB::SendProtocolFrame(clk, tb_usb_data, tb_usb_valid, CMD_I2C_WRITE, 8'h00, 4, write_payload, CLK_PERIOD_NS);
        $display("[%0t] I2C write command sent (4 bytes)", $time);
        # (CLK_PERIOD_NS * 10000);

        // --- TEST CASE 3: I2C Read ---
        $display("\n=== [TEST 3] Send I2C read command: read 4 bytes from Slave 0x50, Reg 0xBB ===");
        i2c_read_data[0] = I2C_SLAVE_ADDR_7BIT; // Slave Address
        i2c_read_data[1] = 8'hBB;               // Register Address to read from
        i2c_read_data[2] = 8'h04;               // Number of bytes to read
        // FIXED: Added missing len_h argument (8'h00)
        USB::SendProtocolFrame(clk, tb_usb_data, tb_usb_valid, CMD_I2C_READ, 8'h00, 3, i2c_read_data, CLK_PERIOD_NS);
        $display("[%0t] I2C read command sent", $time);
        
        // Monitor for the uploaded data
        fork
            upload_monitor(4);
        join
        
        $display("[%0t] I2C read verification done", $time);
        # (CLK_PERIOD_NS * 100);


        // --- TEST CASE 4: Heartbeat ---
        $display("\n=== [TEST 4] Send heartbeat test command (empty frame) ===");
        // FIXED: Added missing len_h argument (8'h00)
        USB::SendProtocolFrame(clk, tb_usb_data, tb_usb_valid, 8'hFF, 8'h00, 0, empty_data, CLK_PERIOD_NS);
        $display("[%0t] Heartbeat test command sent", $time);
        # (CLK_PERIOD_NS * 100);

        $display("\n[%0t] ** Simulation finished **", $time);
        $finish;
    end
// 以下是调试

    // initial begin
    //     #100ns;
    //     scl_slave_drv = 1'b0; // 主动拉低 SCL
    //     #20ns;
    //     scl_slave_drv = 1'bZ;
    // end

    // always @(SCL or SDA) begin
    //     $display("[%0t] SCL=%b, SDA=%b", $time, SCL, SDA);
    // end


endmodule

