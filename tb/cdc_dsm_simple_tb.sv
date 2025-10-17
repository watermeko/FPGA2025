`timescale 1ns / 1ps
// ============================================================================
// CDC DSM Testbench - Testing DSM functionality in the full CDC module
// Tests digital signal measurement with various frequencies and duty cycles
// ============================================================================

module cdc_dsm_simple_tb;

    localparam CLK_FREQ      = 60_000_000;  // 60MHz system clock
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;  // ~16.67ns

    // DUT Signals
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;
    reg [7:0] dsm_signal_in;

    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    wire       led_out;
    wire [7:0] pwm_pins;
    wire       ext_uart_tx;
    wire [13:0] dac_data;

    reg        ext_uart_rx;
    reg        spi_miso;
    wire       spi_clk;
    wire       spi_cs_n;
    wire       spi_mosi;
    wire       debug_out;

    integer i;

    // ========================================================================
    // DUT Instantiation - Full CDC module
    // ========================================================================
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(1'b1),
        .ext_uart_tx(ext_uart_tx),
        .dac_clk(clk),  // Use system clock for DAC
        .dac_data(dac_data),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(1'b0),
        .dsm_signal_in(dsm_signal_in),
        .debug_out(debug_out),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    // ========================================================================
    // Clock and Reset Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        usb_data_in = 0;
        usb_data_valid_in = 0;
        dsm_signal_in = 8'h00;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    // ========================================================================
    // DSM Signal Generator Tasks
    // ========================================================================

    // Generate a square wave on a specific channel
    task automatic generate_square_wave(
        input integer channel,
        input integer high_cycles,
        input integer low_cycles,
        input integer num_periods
    );
        integer p, j;
        begin
            $display("[%0t] DSM Channel %0d: Generating %0d periods (H=%0d, L=%0d cycles)",
                     $time, channel, num_periods, high_cycles, low_cycles);

            for (p = 0; p < num_periods; p = p + 1) begin
                // High period
                dsm_signal_in[channel] = 1'b1;
                for (j = 0; j < high_cycles; j = j + 1)
                    @(posedge clk);

                // Low period
                dsm_signal_in[channel] = 1'b0;
                for (j = 0; j < low_cycles; j = j + 1)
                    @(posedge clk);
            end
        end
    endtask

    // Generate 1kHz square wave (for 60MHz clock: period=60000 cycles)
    task automatic generate_1khz_50duty(input integer channel, input integer num_periods);
        begin
            generate_square_wave(channel, 30000, 30000, num_periods);
        end
    endtask

    // Generate 10kHz square wave (for 60MHz clock: period=6000 cycles)
    task automatic generate_10khz_50duty(input integer channel, input integer num_periods);
        begin
            generate_square_wave(channel, 3000, 3000, num_periods);
        end
    endtask

    // Generate variable duty cycle signal
    task automatic generate_variable_duty(
        input integer channel,
        input integer duty_percent,  // 0-100
        input integer frequency_hz,
        input integer num_periods
    );
        integer total_cycles, high_cycles, low_cycles;
        begin
            total_cycles = CLK_FREQ / frequency_hz;
            high_cycles = (total_cycles * duty_percent) / 100;
            low_cycles = total_cycles - high_cycles;

            $display("[%0t] DSM Channel %0d: %0dHz @ %0d%% duty (H=%0d, L=%0d)",
                     $time, channel, frequency_hz, duty_percent, high_cycles, low_cycles);

            generate_square_wave(channel, high_cycles, low_cycles, num_periods);
        end
    endtask

    // ========================================================================
    // USB Data Send Task
    // ========================================================================
    task send_usb_byte(input [7:0] byte_to_send);
        begin
            @(posedge clk);
            usb_data_in = byte_to_send;
            usb_data_valid_in = 1'b1;
            @(posedge clk);
            usb_data_valid_in = 1'b0;
            #(CLK_PERIOD_NS * 2);
        end
    endtask

    // ========================================================================
    // DSM Command Send Task
    // Format: AA 55 0A 00 01 [CHANNEL_MASK] CHECKSUM
    // ========================================================================
    task automatic send_dsm_command(input [7:0] channel_mask);
        reg [7:0] checksum;
        begin
            $display("\n[%0t] ======= Sending DSM Command: Channel Mask=0x%02X =======",
                     $time, channel_mask);

            // Calculate checksum: CMD + LEN_H + LEN_L + DATA
            checksum = 8'h0A + 8'h00 + 8'h01 + channel_mask;

            // Send frame
            send_usb_byte(8'hAA);           // Header 1
            send_usb_byte(8'h55);           // Header 2
            send_usb_byte(8'h0A);           // Command: DSM Measure
            send_usb_byte(8'h00);           // Length High
            send_usb_byte(8'h01);           // Length Low (1 byte)
            send_usb_byte(channel_mask);    // Channel mask
            send_usb_byte(checksum);        // Checksum

            $display("[%0t] DSM Command sent (checksum=0x%02x)", $time, checksum);
        end
    endtask

    // ========================================================================
    // USB Upload Data Capture
    // ========================================================================
    reg [7:0] usb_received_data [0:255];
    integer   usb_received_count;

    always @(posedge clk) begin
        if (usb_upload_valid) begin
            $display("[%0t] USB UPLOAD [%0d] = 0x%02x",
                     $time, usb_received_count, usb_upload_data);
            usb_received_data[usb_received_count] = usb_upload_data;
            usb_received_count = usb_received_count + 1;
        end
    end

    // ========================================================================
    // DSM Result Structure
    // ========================================================================
    typedef struct {
        int channel;
        int high_time;
        int low_time;
    } dsm_result_t;

    dsm_result_t parsed_results[8];
    integer parsed_count;

    // ========================================================================
    // Parse DSM Upload Data
    // Frame: AA 44 0A LEN_H LEN_L [CH0 H_H H_L L_H L_L] [CH1...] CHECKSUM
    // Each channel: 5 bytes (channel_id + high_time_16bit + low_time_16bit)
    // ========================================================================
    task parse_dsm_upload_data;
        integer idx, ch_count, k;
        reg [7:0] header1, header2, source, len_h, len_l;
        integer payload_len;
        begin
            $display("\n=== Parsing DSM Upload Data ===");
            $display("Total bytes received: %0d", usb_received_count);

            if (usb_received_count < 6) begin
                $display("❌ ERROR: Too few bytes received");
                return;
            end

            // Parse header
            header1 = usb_received_data[0];
            header2 = usb_received_data[1];
            source = usb_received_data[2];
            len_h = usb_received_data[3];
            len_l = usb_received_data[4];
            payload_len = {len_h, len_l};

            $display("Header: 0x%02X%02X (expect AA44)", header1, header2);
            $display("Source: 0x%02X (expect 0A=DSM)", source);
            $display("Payload Length: %0d bytes", payload_len);

            if (header1 != 8'hAA || header2 != 8'h44) begin
                $display("❌ ERROR: Invalid header!");
                return;
            end

            if (source != 8'h0A) begin
                $display("❌ ERROR: Invalid source! Expected 0x0A (DSM)");
                return;
            end

            // Parse channel data (5 bytes per channel)
            ch_count = 0;
            idx = 5;  // Start after header

            while (idx + 4 < usb_received_count - 1 && ch_count < 8) begin
                parsed_results[ch_count].channel = usb_received_data[idx];
                parsed_results[ch_count].high_time = {usb_received_data[idx+1], usb_received_data[idx+2]};
                parsed_results[ch_count].low_time = {usb_received_data[idx+3], usb_received_data[idx+4]};

                $display("\nChannel %0d:", parsed_results[ch_count].channel);
                $display("  High Time: %0d cycles", parsed_results[ch_count].high_time);
                $display("  Low Time:  %0d cycles", parsed_results[ch_count].low_time);
                $display("  Period:    %0d cycles",
                         parsed_results[ch_count].high_time + parsed_results[ch_count].low_time);

                if (parsed_results[ch_count].high_time + parsed_results[ch_count].low_time > 0) begin
                    $display("  Frequency: %0d Hz",
                             CLK_FREQ / (parsed_results[ch_count].high_time + parsed_results[ch_count].low_time));
                    $display("  Duty:      %0d%%",
                             (parsed_results[ch_count].high_time * 100) /
                             (parsed_results[ch_count].high_time + parsed_results[ch_count].low_time));
                end

                ch_count = ch_count + 1;
                idx = idx + 5;
            end

            parsed_count = ch_count;
            $display("\nSuccessfully parsed %0d channel(s)", parsed_count);
        end
    endtask

    // ========================================================================
    // Verification Task
    // ========================================================================
    task automatic verify_dsm_measurement(
        input integer channel,
        input integer expected_high,
        input integer expected_low,
        input integer tolerance
    );
        integer errors;
        integer actual_high, actual_low;
        begin
            errors = 0;

            if (channel >= parsed_count) begin
                $display("❌ FAIL: Channel %0d not found in results", channel);
                return;
            end

            actual_high = parsed_results[channel].high_time;
            actual_low = parsed_results[channel].low_time;

            $display("\n--- Verification: Channel %0d ---", channel);
            $display("Expected: High=%0d, Low=%0d", expected_high, expected_low);
            $display("Actual:   High=%0d, Low=%0d", actual_high, actual_low);
            $display("Tolerance: ±%0d cycles", tolerance);

            // Check high time
            if (actual_high >= expected_high - tolerance &&
                actual_high <= expected_high + tolerance) begin
                $display("✅ High time: PASS");
            end else begin
                $display("❌ High time: FAIL (off by %0d)", actual_high - expected_high);
                errors = errors + 1;
            end

            // Check low time
            if (actual_low >= expected_low - tolerance &&
                actual_low <= expected_low + tolerance) begin
                $display("✅ Low time: PASS");
            end else begin
                $display("❌ Low time: FAIL (off by %0d)", actual_low - expected_low);
                errors = errors + 1;
            end

            if (errors == 0)
                $display("✅ FINAL: PASS");
            else
                $display("❌ FINAL: FAIL (%0d error(s))", errors);
        end
    endtask

    // ========================================================================
    // Complete Test Sequence Task
    // ========================================================================
    task automatic run_dsm_test(
        input string test_name,
        input [7:0] channel_mask,
        input integer channel_to_test,
        input integer signal_high_cycles,
        input integer signal_low_cycles,
        input integer num_periods
    );
        begin
            $display("\n========================================");
            $display("=== %s ===", test_name);
            $display("========================================");

            usb_received_count = 0;
            dsm_signal_in = 8'h00;

            // Step 1: Send DSM command
            send_dsm_command(channel_mask);
            #(CLK_PERIOD_NS * 500);

            // Step 2: Start signal generation in background
            $display("[%0t] Starting signal generation on channel %0d...", $time, channel_to_test);
            fork
                generate_square_wave(channel_to_test, signal_high_cycles, signal_low_cycles, num_periods);
            join_none

            // Step 3: Wait for measurement and upload
            #(CLK_PERIOD_NS * (signal_high_cycles + signal_low_cycles) * (num_periods + 2));
            #(CLK_PERIOD_NS * 5000);  // Extra time for upload

            // Step 4: Parse and verify results
            parse_dsm_upload_data();
            verify_dsm_measurement(0, signal_high_cycles, signal_low_cycles, 3);

            $display("\n=== Test Complete ===\n");
        end
    endtask

    // ========================================================================
    // Debug Monitors
    // ========================================================================

    // State change monitoring
    reg [1:0] prev_handler_state = 2'b00;
    reg [1:0] prev_upload_state = 2'b00;
    reg [7:0] prev_measure_done = 8'h00;

    always @(posedge clk) begin
        // Monitor DSM Handler state changes
        if (dut.u_dsm_handler.handler_state != prev_handler_state) begin
            case (dut.u_dsm_handler.handler_state)
                2'b00: $display("[%0t] 🔄 DSM_HANDLER: → IDLE", $time);
                2'b01: $display("[%0t] 🔄 DSM_HANDLER: → RX_CMD (channel_mask=0x%02X)",
                               $time, dut.u_dsm_handler.channel_mask);
                2'b10: $display("[%0t] 🔄 DSM_HANDLER: → MEASURING", $time);
                2'b11: $display("[%0t] 🔄 DSM_HANDLER: → UPLOAD_DATA", $time);
            endcase
            prev_handler_state = dut.u_dsm_handler.handler_state;
        end

        // Monitor upload sub-state
        if (dut.u_dsm_handler.upload_state != prev_upload_state) begin
            case (dut.u_dsm_handler.upload_state)
                2'b00: $display("[%0t]   └─ Upload: IDLE", $time);
                2'b01: $display("[%0t]   └─ Upload: SEND (ch=%0d, byte=%0d)",
                               $time, dut.u_dsm_handler.upload_channel,
                               dut.u_dsm_handler.upload_byte_index);
                2'b10: $display("[%0t]   └─ Upload: WAIT", $time);
            endcase
            prev_upload_state = dut.u_dsm_handler.upload_state;
        end

        // Monitor measurement done
        if (dut.u_dsm_handler.measure_done != prev_measure_done) begin
            $display("[%0t] 📊 measure_done: 0x%02X → 0x%02X",
                     $time, prev_measure_done, dut.u_dsm_handler.measure_done);
            prev_measure_done = dut.u_dsm_handler.measure_done;
        end
    end

    // ========================================================================
    // Upload Pipeline Debug - Track data through each stage
    // ========================================================================

    // DSM Handler → Adapter
    always @(posedge clk) begin
        if (dut.u_dsm_handler.upload_valid) begin
            $display("[%0t] 📤 DSM_HANDLER: upload_valid=1, data=0x%02X, req=%0b, ready=%0b, active=%0b",
                     $time, dut.u_dsm_handler.upload_data,
                     dut.u_dsm_handler.upload_req,
                     dut.u_dsm_handler.upload_ready,
                     dut.u_dsm_handler.upload_active);
        end
    end

    // Adapter → Packer
    always @(posedge clk) begin
        if (dut.u_dsm_adapter.packer_upload_valid) begin
            $display("[%0t] 📦 ADAPTER→PACKER: valid=1, data=0x%02X, req=%0b, ready=%0b",
                     $time, dut.u_dsm_adapter.packer_upload_data,
                     dut.u_dsm_adapter.packer_upload_req,
                     dut.u_dsm_adapter.packer_upload_ready);
        end
    end

    // Packer → Arbiter (Channel 2 = DSM)
    always @(posedge clk) begin
        if (dut.packed_valid[2]) begin
            $display("[%0t] 📮 PACKER[2]→ARBITER: valid=1, data=0x%02X, req=%0b, ready=%0b",
                     $time, dut.packed_data[23:16],
                     dut.packed_req[2],
                     dut.arbiter_ready[2]);
        end
    end

    // Arbiter → Processor
    always @(posedge clk) begin
        if (dut.merged_upload_valid) begin
            $display("[%0t] 🔗 ARBITER→PROCESSOR: valid=1, data=0x%02X, source=0x%02X, req=%0b, ready=%0b",
                     $time, dut.merged_upload_data,
                     dut.merged_upload_source,
                     dut.merged_upload_req,
                     dut.processor_upload_ready);
        end
    end

    // Final USB output
    always @(posedge clk) begin
        if (usb_upload_valid) begin
            $display("[%0t] ✅ USB_OUTPUT[%0d]: 0x%02X",
                     $time, usb_received_count, usb_upload_data);
        end
    end

    // ========================================================================
    // DSM Measurement Results Debug
    // ========================================================================

    // Monitor when measurement completes
    reg measure_done_ch0_prev = 1'b0;
    always @(posedge clk) begin
        if (dut.u_dsm_handler.u_dsm_multichannel.measure_done[0] &&
            !measure_done_ch0_prev) begin
            $display("[%0t] ✨ CH0 Measurement Complete!", $time);
            $display("       High: %0d cycles",
                     dut.u_dsm_handler.u_dsm_multichannel.high_time[15:0]);
            $display("       Low:  %0d cycles",
                     dut.u_dsm_handler.u_dsm_multichannel.low_time[15:0]);
        end
        measure_done_ch0_prev = dut.u_dsm_handler.u_dsm_multichannel.measure_done[0];
    end

    // ========================================================================
    // Ready Signal Monitoring - Find blocking points
    // ========================================================================

    always @(posedge clk) begin
        // Check if handler is trying to upload but blocked
        if (dut.u_dsm_handler.upload_active && dut.u_dsm_handler.upload_valid &&
            !dut.u_dsm_handler.upload_ready) begin
            $display("[%0t] ⚠️  BLOCKED: Handler upload_ready=0", $time);
        end

        // Check if adapter is blocked
        if (dut.u_dsm_adapter.packer_upload_valid &&
            !dut.u_dsm_adapter.packer_upload_ready) begin
            $display("[%0t] ⚠️  BLOCKED: Adapter packer_ready=0", $time);
        end

        // Check if packer is blocked
        if (dut.packed_valid[2] && !dut.arbiter_ready[2]) begin
            $display("[%0t] ⚠️  BLOCKED: Packer arbiter_ready[2]=0", $time);
        end

        // Check if arbiter is blocked
        if (dut.merged_upload_valid && !dut.processor_upload_ready) begin
            $display("[%0t] ⚠️  BLOCKED: Arbiter processor_ready=0", $time);
        end
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 100);

        $display("\n================================================");
        $display("=== Starting CDC DSM Test Sequence ===");
        $display("=== System Clock: %0d MHz ===", CLK_FREQ / 1_000_000);
        $display("================================================\n");

        // Test 1: 1kHz, 50% duty cycle
        run_dsm_test(
            "Test 1: 1kHz @ 50% Duty",
            8'h01,      // Channel 0 only
            0,          // Test channel 0
            30000,      // High cycles
            30000,      // Low cycles
            3           // 3 periods
        );

        // Test 2: 10kHz, 50% duty cycle
        run_dsm_test(
            "Test 2: 10kHz @ 50% Duty",
            8'h01,      // Channel 0 only
            0,          // Test channel 0
            3000,       // High cycles
            3000,       // Low cycles
            5           // 5 periods
        );

        // Test 3: 1kHz, 25% duty cycle
        run_dsm_test(
            "Test 3: 1kHz @ 25% Duty",
            8'h01,      // Channel 0 only
            0,          // Test channel 0
            15000,      // High cycles (25%)
            45000,      // Low cycles (75%)
            3           // 3 periods
        );

        // Test 4: 1kHz, 75% duty cycle
        run_dsm_test(
            "Test 4: 1kHz @ 75% Duty",
            8'h01,      // Channel 0 only
            0,          // Test channel 0
            45000,      // High cycles (75%)
            15000,      // Low cycles (25%)
            3           // 3 periods
        );

        $display("\n================================================");
        $display("=== All Tests Complete ===");
        $display("================================================\n");

        #(CLK_PERIOD_NS * 1000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #(CLK_PERIOD_NS * 10_000_000); // 10M cycles timeout
        $display("\n❌ ERROR: Simulation timeout!");
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("cdc_dsm_simple_tb.vcd");
        $dumpvars(0, cdc_dsm_simple_tb);
    end

endmodule
