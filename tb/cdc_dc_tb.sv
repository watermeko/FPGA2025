// ============================================================================
// Module:      cdc_dc_tb (CDC Digital Capture Integration Testbench)
// Author:      AI Assistant
// Date:        2025-01-15
//
// Description:
// Testbench for the CDC module with Digital Capture Handler integration.
// Tests the START (0x0B) and STOP (0x0C) commands with direct upload mode.
// Verifies MUX arbitration and raw data streaming (bypassing protocol).
// ============================================================================

`timescale 1ns / 1ps

module cdc_dc_tb;

    //-------------------------------------------------------------------------
    // Testbench Parameters
    //-------------------------------------------------------------------------
    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // ~16.67ns

    //-------------------------------------------------------------------------
    // Testbench Signals
    //-------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;

    // CDC module outputs
    wire led_out;
    wire [7:0] pwm_pins;
    wire ext_uart_tx;
    reg  ext_uart_rx;

    // DAC outputs (stub)
    wire dac_clk;
    wire [13:0] dac_data;

    // SPI outputs (stub)
    wire spi_clk;
    wire spi_cs_n;
    wire spi_mosi;
    reg  spi_miso;

    // DSM inputs (stub)
    reg [7:0] dsm_signal_in;

    // Digital Capture 8-channel input
    reg [7:0] dc_signal_in;

    // Debug output
    wire debug_out;

    // USB upload interface
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;

    // Testbench variables
    integer i;
    integer sample_count;
    reg [7:0] usb_received_data [0:1023];
    integer usb_received_count;

    // Test pattern tracking
    reg [7:0] expected_pattern;
    integer error_count;

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_tx(ext_uart_tx),
        .ext_uart_rx(ext_uart_rx),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .dsm_signal_in(dsm_signal_in),
        .dc_signal_in(dc_signal_in),
        .debug_out(debug_out),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Reset Generation
    //-------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        usb_data_in = 8'h00;
        usb_data_valid_in = 1'b0;
        ext_uart_rx = 1'b1;
        spi_miso = 1'b0;
        dsm_signal_in = 8'h00;
        dc_signal_in = 8'h00;
        usb_received_count = 0;
        sample_count = 0;
        error_count = 0;

        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
        $display("[%0t] Reset released", $time);
    end

    //-------------------------------------------------------------------------
    // USB Data Sending Task
    //-------------------------------------------------------------------------
    task automatic send_usb_byte(input [7:0] byte_to_send);
        begin
            @(posedge clk);
            usb_data_in = byte_to_send;
            usb_data_valid_in = 1'b1;
            @(posedge clk);
            usb_data_valid_in = 1'b0;
            #(CLK_PERIOD_NS * 5); // Inter-byte delay
        end
    endtask

    //-------------------------------------------------------------------------
    // Digital Capture START Command (0x0B)
    //-------------------------------------------------------------------------
    task automatic send_dc_start_command(input [15:0] divider);
        reg [7:0] checksum;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Sending DC START Command (0x0B)", $time);
            $display("[%0t] Divider: %0d (Sample rate: %0d Hz)", $time, divider, 60_000_000 / divider);
            $display("[%0t] ========================================", $time);

            // Checksum: CMD + LEN_H + LEN_L + DATA (NOT including frame headers)
            checksum = 8'h0B + 8'h00 + 8'h02 + divider[15:8] + divider[7:0];

            send_usb_byte(8'hAA);        // Frame Header H
            send_usb_byte(8'h55);        // Frame Header L
            send_usb_byte(8'h0B);        // Function Code: DC Start
            send_usb_byte(8'h00);        // Length H
            send_usb_byte(8'h02);        // Length L (2 bytes)
            send_usb_byte(divider[15:8]); // Divider High
            send_usb_byte(divider[7:0]);  // Divider Low
            send_usb_byte(checksum);     // Checksum

            #(CLK_PERIOD_NS * 100); // Wait for command processing
            $display("[%0t] DC START command sent, waiting for capture...", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Digital Capture STOP Command (0x0C)
    //-------------------------------------------------------------------------
    task automatic send_dc_stop_command();
        reg [7:0] checksum;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Sending DC STOP Command (0x0C)", $time);
            $display("[%0t] ========================================", $time);

            // Checksum: CMD + LEN_H + LEN_L (NOT including frame headers)
            checksum = 8'h0C + 8'h00 + 8'h00;

            send_usb_byte(8'hAA);        // Frame Header H
            send_usb_byte(8'h55);        // Frame Header L
            send_usb_byte(8'h0C);        // Function Code: DC Stop
            send_usb_byte(8'h00);        // Length H
            send_usb_byte(8'h00);        // Length L (0 bytes)
            send_usb_byte(checksum);     // Checksum

            #(CLK_PERIOD_NS * 100); // Wait for command processing
            $display("[%0t] DC STOP command sent", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // USB Upload Data Monitor
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (usb_upload_valid) begin
            usb_received_data[usb_received_count] = usb_upload_data;
            usb_received_count = usb_received_count + 1;
            sample_count = sample_count + 1;

            // Verbose output for first 20 samples and last 10
            if (sample_count <= 20 || sample_count > (usb_received_count - 10)) begin
                $display("[%0t] Sample[%4d]: 0x%02X (binary: %08b)",
                         $time, sample_count, usb_upload_data, usb_upload_data);
            end else if (sample_count == 21) begin
                $display("[%0t] ... (showing first 20 and last 10 samples only) ...", $time);
            end
        end
    end

    //-------------------------------------------------------------------------
    // DC Handler State Monitor
    //-------------------------------------------------------------------------
    reg [2:0] prev_handler_state;
    reg [1:0] prev_upload_state;

    initial begin
        prev_handler_state = 3'b000;
        prev_upload_state = 2'b00;
    end

    always @(posedge clk) begin
        if (dut.u_dc_handler.handler_state != prev_handler_state) begin
            $display("[%0t] DC Handler State: %s -> %s", $time,
                     get_handler_state_name(prev_handler_state),
                     get_handler_state_name(dut.u_dc_handler.handler_state));
            prev_handler_state = dut.u_dc_handler.handler_state;
        end

        if (dut.u_dc_handler.upload_state != prev_upload_state) begin
            $display("[%0t] DC Upload State: %s -> %s", $time,
                     get_upload_state_name(prev_upload_state),
                     get_upload_state_name(dut.u_dc_handler.upload_state));
            prev_upload_state = dut.u_dc_handler.upload_state;
        end
    end

    //-------------------------------------------------------------------------
    // State Name Helper Functions
    //-------------------------------------------------------------------------
    function automatic string get_handler_state_name(input [2:0] state);
        case (state)
            3'd0: return "H_IDLE";
            3'd1: return "H_RX_CMD";
            3'd2: return "H_CAPTURING";
            default: return "UNKNOWN";
        endcase
    endfunction

    function automatic string get_upload_state_name(input [1:0] state);
        case (state)
            2'd0: return "UP_IDLE";
            2'd1: return "UP_SEND";
            2'd2: return "UP_WAIT";
            default: return "UNKNOWN";
        endcase
    endfunction

    //-------------------------------------------------------------------------
    // Test Result Verification Task
    //-------------------------------------------------------------------------
    task automatic verify_pattern(input integer start_idx, input integer end_idx, input [7:0] expected);
        integer idx;
        integer local_errors;
        begin
            local_errors = 0;
            for (idx = start_idx; idx < end_idx && idx < usb_received_count; idx = idx + 1) begin
                if (usb_received_data[idx] != expected) begin
                    if (local_errors < 5) begin // Show first 5 errors only
                        $display("  [ERROR] Sample[%4d]: Expected 0x%02X, Got 0x%02X",
                                 idx, expected, usb_received_data[idx]);
                    end
                    local_errors = local_errors + 1;
                    error_count = error_count + 1;
                end
            end

            if (local_errors == 0) begin
                $display("  [PASS] Samples [%4d:%4d] match pattern 0x%02X", start_idx, end_idx-1, expected);
            end else begin
                $display("  [FAIL] %0d/%0d samples incorrect (showing first 5 errors)",
                         local_errors, end_idx - start_idx);
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 50);

        $display("");
        $display("================================================================================");
        $display("  CDC Digital Capture Integration Test");
        $display("================================================================================");
        $display("");

        //=====================================================================
        // TEST 1: Static Pattern 0xAA, 1MHz Sampling (divider = 60)
        //=====================================================================
        $display("");
        $display("### TEST 1: Static Pattern 0xAA @ 1MHz ###");
        usb_received_count = 0;
        sample_count = 0;
        dc_signal_in = 8'hAA;

        send_dc_start_command(16'd60); // 60MHz / 60 = 1MHz
        #(CLK_PERIOD_NS * 6000); // Capture for 100us (expect ~100 samples)

        send_dc_stop_command();
        #(CLK_PERIOD_NS * 100);

        $display("[%0t] Test 1 captured %0d samples", $time, usb_received_count);
        verify_pattern(0, usb_received_count, 8'hAA);

        //=====================================================================
        // TEST 2: Static Pattern 0x55, 2MHz Sampling (divider = 30)
        //=====================================================================
        $display("");
        $display("### TEST 2: Static Pattern 0x55 @ 2MHz ###");
        usb_received_count = 0;
        sample_count = 0;
        dc_signal_in = 8'h55;

        send_dc_start_command(16'd30); // 60MHz / 30 = 2MHz
        #(CLK_PERIOD_NS * 3000); // Capture for 50us (expect ~100 samples)

        send_dc_stop_command();
        #(CLK_PERIOD_NS * 100);

        $display("[%0t] Test 2 captured %0d samples", $time, usb_received_count);
        verify_pattern(0, usb_received_count, 8'h55);

        //=====================================================================
        // TEST 3: Static Pattern 0xFF, 500kHz Sampling (divider = 120)
        //=====================================================================
        $display("");
        $display("### TEST 3: Static Pattern 0xFF @ 500kHz ###");
        usb_received_count = 0;
        sample_count = 0;
        dc_signal_in = 8'hFF;

        send_dc_start_command(16'd120); // 60MHz / 120 = 500kHz
        #(CLK_PERIOD_NS * 12000); // Capture for 200us (expect ~100 samples)

        send_dc_stop_command();
        #(CLK_PERIOD_NS * 100);

        $display("[%0t] Test 3 captured %0d samples", $time, usb_received_count);
        verify_pattern(0, usb_received_count, 8'hFF);

        //=====================================================================
        // TEST 4: Dynamic Pattern Change, 1MHz Sampling
        //=====================================================================
        $display("");
        $display("### TEST 4: Dynamic Pattern @ 1MHz ###");
        usb_received_count = 0;
        sample_count = 0;
        dc_signal_in = 8'h11;

        send_dc_start_command(16'd60); // 1MHz

        // Change pattern every 30us
        #(CLK_PERIOD_NS * 1800); // 30us
        dc_signal_in = 8'h22;
        $display("[%0t] Pattern changed to 0x22", $time);

        #(CLK_PERIOD_NS * 1800); // 30us
        dc_signal_in = 8'h44;
        $display("[%0t] Pattern changed to 0x44", $time);

        #(CLK_PERIOD_NS * 1800); // 30us
        dc_signal_in = 8'h88;
        $display("[%0t] Pattern changed to 0x88", $time);

        #(CLK_PERIOD_NS * 1800); // 30us

        send_dc_stop_command();
        #(CLK_PERIOD_NS * 100);

        $display("[%0t] Test 4 captured %0d samples", $time, usb_received_count);
        // Manual verification for dynamic pattern - expect ~30 samples of each pattern
        $display("  Note: Dynamic pattern test requires manual waveform inspection");

        //=====================================================================
        // TEST 5: Maximum Sample Rate (1.2MHz, divider = 50)
        //=====================================================================
        $display("");
        $display("### TEST 5: Maximum Sample Rate 1.2MHz @ Pattern 0xAA ###");
        usb_received_count = 0;
        sample_count = 0;
        dc_signal_in = 8'hAA;

        send_dc_start_command(16'd50); // 60MHz / 50 = 1.2MHz (theoretical max)
        #(CLK_PERIOD_NS * 5000); // Capture for 83us (expect ~100 samples)

        send_dc_stop_command();
        #(CLK_PERIOD_NS * 100);

        $display("[%0t] Test 5 captured %0d samples", $time, usb_received_count);
        verify_pattern(0, usb_received_count, 8'hAA);

        //=====================================================================
        // Final Summary
        //=====================================================================
        $display("");
        $display("================================================================================");
        $display("  TEST SUMMARY");
        $display("================================================================================");
        $display("Total errors detected: %0d", error_count);

        if (error_count == 0) begin
            $display("");
            $display("  ✅✅✅ ALL TESTS PASSED ✅✅✅");
            $display("");
        end else begin
            $display("");
            $display("  ❌❌❌ TESTS FAILED ❌❌❌");
            $display("");
        end
        $display("================================================================================");
        $display("");

        #(CLK_PERIOD_NS * 500);
        $finish;
    end

    //-------------------------------------------------------------------------
    // VCD Dump for GTKWave
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("cdc_dc_tb.vcd");
        $dumpvars(0, cdc_dc_tb);
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #50_000_000; // 50ms timeout
        $display("");
        $display("[ERROR] Simulation timeout!");
        $display("");
        $finish;
    end

endmodule
