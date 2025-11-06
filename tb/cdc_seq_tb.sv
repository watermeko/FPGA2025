// ============================================================================
// Module:      cdc_seq_tb (CDC Sequence Generator Integration Testbench)
// Author:      Claude
// Date:        2025-10-24
//
// Description:
// Testbench for the CDC module with Sequence Generator Handler integration.
// Tests the SEQ_CONFIG (0xF0) command with custom sequence outputs.
// ============================================================================

`timescale 1ns / 1ps

module cdc_seq_tb;

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
    wire [7:0] seq_pins;  // NEW: Sequence outputs
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

    // Digital Capture input (stub)
    reg [7:0] dc_signal_in;

    // Debug output
    wire debug_out;

    // USB upload interface
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;

    // Testbench variables
    integer i;

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
        .seq_pins(seq_pins),        // NEW
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
    // Sequence Configuration Command (0xF0)
    //-------------------------------------------------------------------------
    // Payload: 13 bytes
    //   [0]     Channel (0-7)
    //   [1]     Enable (0/1)
    //   [2-3]   Freq divider (big-endian)
    //   [4]     Sequence length (1-64)
    //   [5-12]  Sequence data (8 bytes, little-endian)
    //-------------------------------------------------------------------------
    task automatic send_seq_config(
        input [2:0]  channel,
        input        enable,
        input [15:0] freq_div,
        input [6:0]  seq_len,
        input [63:0] seq_data
    );
        reg [7:0] checksum;
        reg [7:0] payload [0:12];
        integer i;
        begin
            // Build payload
            payload[0]  = {5'b0, channel};
            payload[1]  = {7'b0, enable};
            payload[2]  = freq_div[15:8];   // High byte
            payload[3]  = freq_div[7:0];    // Low byte
            payload[4]  = {1'b0, seq_len};
            payload[5]  = seq_data[7:0];    // LSB first
            payload[6]  = seq_data[15:8];
            payload[7]  = seq_data[23:16];
            payload[8]  = seq_data[31:24];
            payload[9]  = seq_data[39:32];
            payload[10] = seq_data[47:40];
            payload[11] = seq_data[55:48];
            payload[12] = seq_data[63:56];  // MSB last

            // Calculate checksum (CMD + LEN_H + LEN_L + all payload bytes)
            checksum = 8'hF0 + 8'h00 + 8'h0D;
            for (i = 0; i < 13; i = i + 1) begin
                checksum = checksum + payload[i];
            end

            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Sending SEQ CONFIG Command (0xF0)", $time);
            $display("[%0t] Channel: %0d", $time, channel);
            $display("[%0t] Enable: %0d", $time, enable);
            $display("[%0t] Freq Div: %0d (Base freq: %0d Hz)", $time, freq_div, CLK_FREQ / freq_div);
            $display("[%0t] Seq Len: %0d bits", $time, seq_len);
            $display("[%0t] Seq Data: 0x%0h", $time, seq_data);
            $display("[%0t] Output Freq: %0d Hz", $time, CLK_FREQ / freq_div / seq_len);
            $display("[%0t] ========================================", $time);

            // Send frame
            send_usb_byte(8'hAA);        // Header H
            send_usb_byte(8'h55);        // Header L
            send_usb_byte(8'hF0);        // Command: SEQ_CONFIG
            send_usb_byte(8'h00);        // Length H
            send_usb_byte(8'h0D);        // Length L (13 bytes)

            // Send payload
            for (i = 0; i < 13; i = i + 1) begin
                send_usb_byte(payload[i]);
            end

            send_usb_byte(checksum);     // Checksum

            #(CLK_PERIOD_NS * 100); // Wait for command processing
            $display("[%0t] SEQ CONFIG command sent", $time);
        end
    endtask

    //-------------------------------------------------------------------------
    // Sequence Handler State Monitor
    //-------------------------------------------------------------------------
    reg [1:0] prev_handler_state;

    initial begin
        prev_handler_state = 2'b00;
    end

    always @(posedge clk) begin
        if (dut.u_seq_handler.handler_state != prev_handler_state) begin
            $display("[%0t] SEQ Handler State: %s -> %s", $time,
                     get_handler_state_name(prev_handler_state),
                     get_handler_state_name(dut.u_seq_handler.handler_state));
            prev_handler_state = dut.u_seq_handler.handler_state;
        end
    end

    //-------------------------------------------------------------------------
    // State Name Helper Function
    //-------------------------------------------------------------------------
    function automatic string get_handler_state_name(input [1:0] state);
        case (state)
            2'd0: return "H_IDLE";
            2'd1: return "H_RECEIVING";
            2'd2: return "H_UPDATE_CONFIG";
            2'd3: return "H_STROBE";
            default: return "UNKNOWN";
        endcase
    endfunction

    //-------------------------------------------------------------------------
    // Sequence Output Monitor (Sample first few transitions)
    //-------------------------------------------------------------------------
    reg [7:0] prev_seq_pins;
    integer   transition_count [0:7];

    initial begin
        prev_seq_pins = 8'h00;
        for (i = 0; i < 8; i = i + 1) begin
            transition_count[i] = 0;
        end
    end

    always @(posedge clk) begin
        for (i = 0; i < 8; i = i + 1) begin
            if (seq_pins[i] !== prev_seq_pins[i]) begin
                if (transition_count[i] < 20) begin // Show first 20 transitions per channel
                    $display("[%0t] CH%0d: %b -> %b (transition #%0d)",
                             $time, i, prev_seq_pins[i], seq_pins[i], transition_count[i]);
                end
                transition_count[i] = transition_count[i] + 1;
            end
        end
        prev_seq_pins = seq_pins;
    end

    //-------------------------------------------------------------------------
    // Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 50);

        $display("");
        $display("================================================================================");
        $display("  CDC Sequence Generator Integration Test");
        $display("================================================================================");
        $display("");

        //=====================================================================
        // TEST 1: Channel 0, 1MHz base freq, 10-bit pattern "0101010101"
        //         Expected output: 100kHz
        //=====================================================================
        $display("");
        $display("### TEST 1: CH0 @ 1MHz base, 10-bit alternating (100kHz output) ###");
        send_seq_config(
            .channel(3'd0),
            .enable(1'b1),
            .freq_div(16'd60),          // 60MHz / 60 = 1MHz
            .seq_len(7'd10),            // 10 bits
            .seq_data(64'h0000000000000155)  // 0101010101
        );
        #(CLK_PERIOD_NS * 120000); // Run for 120us (expect ~12 complete sequences)

        //=====================================================================
        // TEST 2: Channel 1, 2MHz base freq, 8-bit pattern "11001100"
        //         Expected output: 250kHz
        //=====================================================================
        $display("");
        $display("### TEST 2: CH1 @ 2MHz base, 8-bit pattern (250kHz output) ###");
        send_seq_config(
            .channel(3'd1),
            .enable(1'b1),
            .freq_div(16'd30),          // 60MHz / 30 = 2MHz
            .seq_len(7'd8),             // 8 bits
            .seq_data(64'h00000000000000CC)  // 11001100
        );
        #(CLK_PERIOD_NS * 80000); // Run for 80us

        //=====================================================================
        // TEST 3: Channel 2, 4MHz base freq, 4-bit pattern "1010"
        //         Expected output: 1MHz
        //=====================================================================
        $display("");
        $display("### TEST 3: CH2 @ 4MHz base, 4-bit pattern (1MHz output) ###");
        send_seq_config(
            .channel(3'd2),
            .enable(1'b1),
            .freq_div(16'd15),          // 60MHz / 15 = 4MHz
            .seq_len(7'd4),             // 4 bits
            .seq_data(64'h000000000000000A)  // 1010
        );
        #(CLK_PERIOD_NS * 40000); // Run for 40us

        //=====================================================================
        // TEST 4: Channel 3, 500kHz base freq, 2-bit pattern "11"
        //         Expected output: 250kHz
        //=====================================================================
        $display("");
        $display("### TEST 4: CH3 @ 500kHz base, 2-bit pattern (250kHz output) ###");
        send_seq_config(
            .channel(3'd3),
            .enable(1'b1),
            .freq_div(16'd120),         // 60MHz / 120 = 500kHz
            .seq_len(7'd2),             // 2 bits
            .seq_data(64'h0000000000000003)  // 11
        );
        #(CLK_PERIOD_NS * 40000); // Run for 40us

        //=====================================================================
        // TEST 5: Disable Channel 0
        //=====================================================================
        $display("");
        $display("### TEST 5: Disable CH0 ###");
        send_seq_config(
            .channel(3'd0),
            .enable(1'b0),              // Disable
            .freq_div(16'd60),
            .seq_len(7'd10),
            .seq_data(64'h0000000000000155)
        );
        #(CLK_PERIOD_NS * 20000);

        //=====================================================================
        // TEST 6: Multi-channel simultaneous operation
        //=====================================================================
        $display("");
        $display("### TEST 6: Configure all 8 channels simultaneously ###");

        send_seq_config(3'd0, 1'b1, 16'd60,  7'd10, 64'h0155);  // 100kHz
        send_seq_config(3'd1, 1'b1, 16'd30,  7'd8,  64'h00CC);  // 250kHz
        send_seq_config(3'd2, 1'b1, 16'd15,  7'd4,  64'h000A);  // 1MHz
        send_seq_config(3'd3, 1'b1, 16'd120, 7'd2,  64'h0003);  // 250kHz
        send_seq_config(3'd4, 1'b1, 16'd60,  7'd5,  64'h0015);  // 200kHz
        send_seq_config(3'd5, 1'b1, 16'd60,  7'd6,  64'h002A);  // 166kHz
        send_seq_config(3'd6, 1'b1, 16'd60,  7'd12, 64'h0AAA);  // 83kHz
        send_seq_config(3'd7, 1'b1, 16'd60,  7'd16, 64'hAAAA);  // 62.5kHz

        $display("[%0t] All channels configured, running for 200us...", $time);
        #(CLK_PERIOD_NS * 200000); // Run for 200us

        //=====================================================================
        // Final Summary
        //=====================================================================
        $display("");
        $display("================================================================================");
        $display("  TEST SUMMARY");
        $display("================================================================================");
        $display("Transition counts per channel:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  CH%0d: %0d transitions", i, transition_count[i]);
        end
        $display("");
        $display("  ✅ All sequence configuration commands sent successfully");
        $display("  ✅ Check waveforms to verify sequence timing and patterns");
        $display("");
        $display("================================================================================");
        $display("");

        #(CLK_PERIOD_NS * 500);
        $finish;
    end

    //-------------------------------------------------------------------------
    // VCD Dump for GTKWave
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("cdc_seq_tb.vcd");
        $dumpvars(0, cdc_seq_tb);
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #100_000_000; // 100ms timeout
        $display("");
        $display("[ERROR] Simulation timeout!");
        $display("");
        $finish;
    end

endmodule
