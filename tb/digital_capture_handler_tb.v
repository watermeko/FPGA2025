`timescale 1ns / 1ps
// ============================================================================
// Digital Capture Handler Testbench - Complete System Integration Test
// Tests digital capture functionality as a standalone handler module
// Author: AI Assistant (based on cdc_dsm_simple_tb reference)
// ============================================================================

module digital_capture_handler_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    localparam CLK_FREQ      = 60_000_000;  // 60MHz system clock
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;  // ~16.67ns

    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg         clk;
    reg         rst_n;

    // Command interface
    reg  [7:0]  cmd_type;
    reg  [15:0] cmd_length;
    reg  [7:0]  cmd_data;
    reg  [15:0] cmd_data_index;
    reg         cmd_start;
    reg         cmd_data_valid;
    reg         cmd_done;
    wire        cmd_ready;

    // Digital signal inputs (8 channels)
    reg  [7:0]  dc_signal_in;

    // Upload interface
    wire        upload_active;
    wire        upload_req;
    wire [7:0]  upload_data;
    wire [7:0]  upload_source;
    wire        upload_valid;
    reg         upload_ready;

    integer i;

    // ========================================================================
    // DUT Instantiation - digital_capture_handler module
    // ========================================================================
    digital_capture_handler u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_type         (cmd_type),
        .cmd_length       (cmd_length),
        .cmd_data         (cmd_data),
        .cmd_data_index   (cmd_data_index),
        .cmd_start        (cmd_start),
        .cmd_data_valid   (cmd_data_valid),
        .cmd_done         (cmd_done),
        .cmd_ready        (cmd_ready),
        .dc_signal_in     (dc_signal_in),
        .upload_active    (upload_active),
        .upload_req       (upload_req),
        .upload_data      (upload_data),
        .upload_source    (upload_source),
        .upload_valid     (upload_valid),
        .upload_ready     (upload_ready)
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
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        dc_signal_in = 8'h00;
        upload_ready = 1;  // Always ready to accept uploads
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    // ========================================================================
    // Digital Signal Pattern Generator Tasks
    // ========================================================================

    // Static pattern
    task automatic set_pattern(input [7:0] pattern);
        begin
            dc_signal_in = pattern;
        end
    endtask

    // Generate rotating pattern
    task automatic generate_rotating_pattern(
        input integer num_changes,
        input integer cycles_per_change
    );
        integer change, cycle;
        begin
            $display("[%0t] Generating rotating pattern: %0d changes, %0d cycles each",
                     $time, num_changes, cycles_per_change);

            for (change = 0; change < num_changes; change = change + 1) begin
                dc_signal_in = change[7:0];
                for (cycle = 0; cycle < cycles_per_change; cycle = cycle + 1)
                    @(posedge clk);
            end
        end
    endtask

    // Generate alternating bit pattern
    task automatic generate_alternating(
        input integer num_toggles,
        input integer cycles_per_toggle
    );
        integer toggle, cycle;
        begin
            $display("[%0t] Generating alternating pattern: %0d toggles, %0d cycles each",
                     $time, num_toggles, cycles_per_toggle);

            for (toggle = 0; toggle < num_toggles; toggle = toggle + 1) begin
                dc_signal_in = (toggle % 2) ? 8'hAA : 8'h55;
                for (cycle = 0; cycle < cycles_per_toggle; cycle = cycle + 1)
                    @(posedge clk);
            end
        end
    endtask

    // ========================================================================
    // Command Send Tasks (Simulating Protocol)
    // ========================================================================

    // Send START command with divider
    // Format: CMD=0x0B, LENGTH=2, DATA=[divider_high, divider_low]
    task automatic send_dc_start_command(input [15:0] divider);
        begin
            $display("\n[%0t] ======= Sending DC START Command: Divider=%0d =======",
                     $time, divider);

            // Send command header
            cmd_type = 8'h0B;      // CMD_DC_START
            cmd_length = 16'd2;    // 2 bytes
            cmd_start = 1;
            @(posedge clk);
            cmd_start = 0;
            @(posedge clk);

            // Send divider high byte
            cmd_data = divider[15:8];
            cmd_data_index = 16'd0;
            cmd_data_valid = 1;
            @(posedge clk);
            cmd_data_valid = 0;
            @(posedge clk);

            // Send divider low byte
            cmd_data = divider[7:0];
            cmd_data_index = 16'd1;
            cmd_data_valid = 1;
            @(posedge clk);
            cmd_data_valid = 0;
            @(posedge clk);

            // Send done signal
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;

            $display("[%0t] DC START command sent (divider=%0d, sample_rate=%0d Hz)",
                     $time, divider, CLK_FREQ / divider);
        end
    endtask

    // Send STOP command
    // Format: CMD=0x0C, LENGTH=0
    task automatic send_dc_stop_command();
        begin
            $display("\n[%0t] ======= Sending DC STOP Command =======", $time);

            cmd_type = 8'h0C;      // CMD_DC_STOP
            cmd_length = 16'd0;    // No data
            cmd_start = 1;
            @(posedge clk);
            cmd_start = 0;
            @(posedge clk);

            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;

            $display("[%0t] DC STOP command sent", $time);
        end
    endtask

    // ========================================================================
    // Upload Data Capture
    // ========================================================================
    reg [7:0] captured_samples [0:1023];  // Store up to 1024 samples
    integer   sample_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            sample_count <= 0;
        end else if (upload_valid && upload_ready) begin
            $display("[%0t] 📥 CAPTURED [%0d] = 0x%02X (%08b)",
                     $time, sample_count, upload_data, upload_data);
            captured_samples[sample_count] <= upload_data;
            sample_count <= sample_count + 1;
        end
    end

    // ========================================================================
    // Verification Tasks
    // ========================================================================

    // Verify that capture is active and receiving data
    task automatic verify_capture_active(input integer expected_min_samples);
        integer initial_count;
        begin
            $display("\n--- Verifying Capture Active ---");
            initial_count = sample_count;

            // Wait some time for samples to accumulate
            repeat(1000) @(posedge clk);

            if (sample_count > initial_count) begin
                $display("✅ PASS: Capture active (%0d new samples received)",
                         sample_count - initial_count);
            end else begin
                $display("❌ FAIL: No new samples received (expected active capture)");
            end

            if (sample_count >= expected_min_samples) begin
                $display("✅ PASS: Sample count %0d >= expected %0d",
                         sample_count, expected_min_samples);
            end else begin
                $display("⚠️  WARNING: Sample count %0d < expected %0d",
                         sample_count, expected_min_samples);
            end
        end
    endtask

    // Verify that capture has stopped
    task automatic verify_capture_stopped();
        integer count_before, count_after;
        begin
            $display("\n--- Verifying Capture Stopped ---");
            count_before = sample_count;

            // Wait some time
            repeat(1000) @(posedge clk);
            count_after = sample_count;

            if (count_after == count_before) begin
                $display("✅ PASS: Capture stopped (no new samples)");
            end else begin
                $display("❌ FAIL: Still receiving samples (%0d new)",
                         count_after - count_before);
            end
        end
    endtask

    // Verify upload source identifier
    task automatic verify_upload_source();
        begin
            $display("\n--- Verifying Upload Source ---");
            if (upload_active) begin
                if (upload_source == 8'h0B) begin
                    $display("✅ PASS: Upload source = 0x0B (correct)");
                end else begin
                    $display("❌ FAIL: Upload source = 0x%02X (expected 0x0B)", upload_source);
                end
            end else begin
                $display("⚠️  INFO: Upload not currently active");
            end
        end
    endtask

    // Verify captured pattern matches expected
    task automatic verify_captured_pattern(
        input integer start_idx,
        input integer end_idx,
        input [7:0] expected_pattern
    );
        integer idx, errors;
        begin
            $display("\n--- Verifying Captured Pattern ---");
            $display("Range: samples[%0d:%0d]", start_idx, end_idx);
            $display("Expected: 0x%02X (%08b)", expected_pattern, expected_pattern);

            errors = 0;
            for (idx = start_idx; idx <= end_idx && idx < sample_count; idx = idx + 1) begin
                if (captured_samples[idx] != expected_pattern) begin
                    $display("❌ Mismatch at sample[%0d]: got 0x%02X, expected 0x%02X",
                             idx, captured_samples[idx], expected_pattern);
                    errors = errors + 1;
                end
            end

            if (errors == 0) begin
                $display("✅ PASS: All samples match expected pattern");
            end else begin
                $display("❌ FAIL: %0d mismatches found", errors);
            end
        end
    endtask

    // ========================================================================
    // Complete Test Sequence Tasks
    // ========================================================================

    task automatic run_capture_test(
        input string test_name,
        input [15:0] divider,
        input [7:0] static_pattern,
        input integer capture_duration_us
    );
        integer start_count, end_count;
        integer expected_samples;
        begin
            $display("\n========================================");
            $display("=== %s ===", test_name);
            $display("========================================");

            start_count = sample_count;

            // Step 1: Set input pattern
            set_pattern(static_pattern);
            $display("[%0t] Input pattern set to 0x%02X (%08b)",
                     $time, static_pattern, static_pattern);

            // Step 2: Send START command
            send_dc_start_command(divider);

            // Wait for handler to start
            repeat(100) @(posedge clk);

            // Step 3: Verify capture is active
            verify_capture_active(5);

            // Step 4: Run capture for specified duration
            $display("[%0t] Running capture for %0d us...", $time, capture_duration_us);
            #(capture_duration_us * 1000);  // Convert to ns

            // Step 5: Send STOP command
            send_dc_stop_command();

            // Wait for handler to stop
            repeat(100) @(posedge clk);

            // Step 6: Verify capture stopped
            verify_capture_stopped();

            // Step 7: Verify source identifier
            @(posedge clk);
            // verify_upload_source();  // Only valid when upload_active is high

            // Step 8: Verify captured data
            end_count = sample_count;
            expected_samples = (capture_duration_us * 1000) / (CLK_PERIOD_NS * divider);

            $display("\n=== Test Results ===");
            $display("Samples captured: %0d", end_count - start_count);
            $display("Expected (approx): %0d", expected_samples);

            if (end_count > start_count) begin
                verify_captured_pattern(start_count, end_count - 1, static_pattern);
            end

            $display("\n=== Test Complete ===\n");
        end
    endtask

    // ========================================================================
    // Debug Monitors
    // ========================================================================

    // State change monitoring
    reg [2:0] prev_handler_state = 3'b000;
    reg [1:0] prev_upload_state = 2'b00;

    always @(posedge clk) begin
        // Monitor handler state changes
        if (u_dut.handler_state != prev_handler_state) begin
            case (u_dut.handler_state)
                3'b000: $display("[%0t] 🔄 DC_HANDLER: → IDLE", $time);
                3'b001: $display("[%0t] 🔄 DC_HANDLER: → RX_CMD", $time);
                3'b010: $display("[%0t] 🔄 DC_HANDLER: → CAPTURING (divider=%0d)",
                               $time, u_dut.sample_divider);
                default: $display("[%0t] 🔄 DC_HANDLER: → UNKNOWN STATE", $time);
            endcase
            prev_handler_state = u_dut.handler_state;
        end

        // Monitor upload sub-state
        if (u_dut.upload_state != prev_upload_state) begin
            case (u_dut.upload_state)
                2'b00: $display("[%0t]   └─ Upload: IDLE", $time);
                2'b01: $display("[%0t]   └─ Upload: SEND (data=0x%02X)",
                               $time, u_dut.upload_data);
                2'b10: $display("[%0t]   └─ Upload: WAIT", $time);
            endcase
            prev_upload_state = u_dut.upload_state;
        end
    end

    // Sample tick monitoring
    always @(posedge clk) begin
        if (u_dut.sample_tick) begin
            $display("[%0t] ⏱️  SAMPLE_TICK: captured=0x%02X (%08b)",
                     $time, u_dut.captured_data, u_dut.captured_data);
        end
    end

    // Upload activity monitoring
    always @(posedge clk) begin
        if (upload_req && upload_valid) begin
            $display("[%0t] 📤 UPLOAD: req=%0b, valid=%0b, data=0x%02X, source=0x%02X, ready=%0b",
                     $time, upload_req, upload_valid, upload_data, upload_source, upload_ready);
        end
    end

    // Blocking detection
    always @(posedge clk) begin
        if (upload_req && upload_valid && !upload_ready) begin
            $display("[%0t] ⚠️  BLOCKED: upload_ready=0", $time);
        end
    end

    // ========================================================================
    // Main Test Sequence
    // ========================================================================
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 100);

        $display("\n================================================");
        $display("=== Digital Capture Handler System Test ===");
        $display("=== System Clock: %0d MHz ===", CLK_FREQ / 1_000_000);
        $display("================================================\n");

        // Test 1: Slow sampling (1MHz), static pattern 0xAA
        run_capture_test(
            "Test 1: 1MHz Sampling, Pattern 0xAA",
            16'd60,        // 60MHz / 60 = 1MHz
            8'hAA,         // Pattern: 10101010
            100            // Capture for 100us
        );

        // Test 2: Fast sampling (2MHz), static pattern 0x55
        run_capture_test(
            "Test 2: 2MHz Sampling, Pattern 0x55",
            16'd30,        // 60MHz / 30 = 2MHz
            8'h55,         // Pattern: 01010101
            50             // Capture for 50us
        );

        // Test 3: Medium sampling (500kHz), pattern 0xFF
        run_capture_test(
            "Test 3: 500kHz Sampling, Pattern 0xFF",
            16'd120,       // 60MHz / 120 = 500kHz
            8'hFF,         // Pattern: 11111111
            100            // Capture for 100us
        );

        // Test 4: Very slow sampling (100kHz), pattern 0x00
        run_capture_test(
            "Test 4: 100kHz Sampling, Pattern 0x00",
            16'd600,       // 60MHz / 600 = 100kHz
            8'h00,         // Pattern: 00000000
            100            // Capture for 100us
        );

        // Test 5: Dynamic pattern during capture
        $display("\n========================================");
        $display("=== Test 5: Dynamic Pattern ===");
        $display("========================================");

        sample_count = 0;  // Reset counter
        set_pattern(8'h11);
        send_dc_start_command(16'd60);  // 1MHz
        repeat(100) @(posedge clk);

        // Change pattern while capturing
        $display("[%0t] Changing pattern to 0x22...", $time);
        set_pattern(8'h22);
        #50000;  // 50us

        $display("[%0t] Changing pattern to 0x44...", $time);
        set_pattern(8'h44);
        #50000;  // 50us

        $display("[%0t] Changing pattern to 0x88...", $time);
        set_pattern(8'h88);
        #50000;  // 50us

        send_dc_stop_command();
        repeat(100) @(posedge clk);
        verify_capture_stopped();

        $display("Test 5: Total samples = %0d", sample_count);
        $display("\n=== Test 5 Complete ===\n");

        // Summary
        $display("\n================================================");
        $display("=== All Tests Complete ===");
        $display("=== Total Samples Captured: %0d ===", sample_count);
        $display("================================================\n");

        #(CLK_PERIOD_NS * 1000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #(CLK_PERIOD_NS * 5_000_000); // 5M cycles timeout (~83ms @ 60MHz)
        $display("\n❌ ERROR: Simulation timeout!");
        $finish;
    end

    // ========================================================================
    // Waveform Dump
    // ========================================================================
    initial begin
        $dumpfile("digital_capture_handler_tb.vcd");
        $dumpvars(0, digital_capture_handler_tb);
    end

endmodule
