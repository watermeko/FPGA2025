`timescale 1ns/1ps

module cdc_custom_waveform_tb;

    // ------------------------------------------------------------------------
    // Local Parameters
    // ------------------------------------------------------------------------
    localparam int CLK_FREQ_HZ        = 60_000_000;
    localparam int CLK_PERIOD_NS      = 1_000_000_000 / CLK_FREQ_HZ;
    localparam int MAX_SAMPLES        = 4096;
    localparam int MAX_PAYLOAD_BYTES  = 7 + (MAX_SAMPLES * 2);
    localparam real DAC_CLK_HZ        = 200_000_000.0;
    localparam real SIM_PLAYBACK_FREQ_HZ = 5_000.0;

    string waveform_path = "sim/custom_waveform_tb/waveform_1760526061.csv";

    // ------------------------------------------------------------------------
    // DUT Interface Signals
    // ------------------------------------------------------------------------
    reg                   clk;
    reg                   rst_n;
    reg  [7:0]            usb_data_in;
    reg                   usb_data_valid_in;
    wire                  led_out;
    wire [7:0]            pwm_pins;
    reg                   ext_uart_rx;
    wire                  ext_uart_tx;
    reg                   spi_miso;
    wire                  spi_clk;
    wire                  spi_cs_n;
    wire                  spi_mosi;
    reg  [7:0]            dsm_signal_in;
    wire [7:0]            usb_upload_data;
    wire                  usb_upload_valid;
    reg                   dac_clk;
    wire signed [13:0]    dac_data;

    // ------------------------------------------------------------------------
    // Instantiate Device Under Test
    // ------------------------------------------------------------------------
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .dsm_signal_in(dsm_signal_in),
        .debug_out(),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid),
        .dc_usb_upload_data(),
        .dc_usb_upload_valid()
    );

    // ------------------------------------------------------------------------
    // Clocks and Reset
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        dac_clk = 1'b0;
        forever #2.5 dac_clk = ~dac_clk; // 200 MHz DAC clock
    end

    initial begin
        rst_n             = 1'b0;
        usb_data_in       = 8'h00;
        usb_data_valid_in = 1'b0;
        ext_uart_rx       = 1'b1;
        spi_miso          = 1'b0;
        dsm_signal_in     = 8'h00;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    // ------------------------------------------------------------------------
    // Utility Tasks / Functions
    // ------------------------------------------------------------------------
    function automatic logic [31:0] calc_sample_rate_word(
        input int  sample_count,
        input real target_freq_hz
    );
        real playback_rate;
        real ratio;
        longint unsigned raw;
    begin
        playback_rate = target_freq_hz * sample_count;
        ratio = (playback_rate * 1048576.0) / DAC_CLK_HZ;
        raw = (ratio < 0.0) ? 0 : longint'(ratio);
        if (raw == 0) begin
            raw = 1;
        end
        calc_sample_rate_word = raw[31:0];
    end
    endfunction

    task automatic send_usb_byte(input [7:0] byte_value);
        begin
            @(posedge clk);
            usb_data_in       <= byte_value;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;
            usb_data_in       <= 8'h00;
            #(CLK_PERIOD_NS * 10);
        end
    endtask

    task automatic send_dac_command(
        input [1:0]  wave_type,
        input [31:0] freq_word,
        input [31:0] phase_word
    );
        int unsigned sum;
        byte unsigned checksum;
        begin
            sum = 8'hFD + 16'h0009;
            sum += {6'b0, wave_type};
            sum += freq_word[31:24] + freq_word[23:16] + freq_word[15:8] + freq_word[7:0];
            sum += phase_word[31:24] + phase_word[23:16] + phase_word[15:8] + phase_word[7:0];
            checksum = sum[7:0];

            send_usb_byte(8'hAA);
            send_usb_byte(8'h55);
            send_usb_byte(8'hFD);
            send_usb_byte(8'h00);
            send_usb_byte(8'h09);
            send_usb_byte({6'b0, wave_type});
            send_usb_byte(freq_word[31:24]);
            send_usb_byte(freq_word[23:16]);
            send_usb_byte(freq_word[15:8]);
            send_usb_byte(freq_word[7:0]);
            send_usb_byte(phase_word[31:24]);
            send_usb_byte(phase_word[23:16]);
            send_usb_byte(phase_word[15:8]);
            send_usb_byte(phase_word[7:0]);
            send_usb_byte(checksum);

            #(CLK_PERIOD_NS * 200);
        end
    endtask

    task automatic load_waveform_from_csv(
        input  string filename,
        output int    sample_count,
        output logic signed [13:0] samples [0:MAX_SAMPLES-1]
    );
        string try_path;
        int file, r, sample_val;
        logic signed [14:0] centered;
        sample_count = 0;

        try_path = filename;
        file = $fopen(try_path, "r");
        if (file == 0) begin
            try_path = {"../../", filename};
            file = $fopen(try_path, "r");
        end
        if (file == 0) begin
            try_path = {"./", filename};
            file = $fopen(try_path, "r");
        end
        if (file == 0) begin
            $fatal(1, "Failed to open waveform file: %s", filename);
        end

        $display("Reading waveform from %s", try_path);

        while (!$feof(file)) begin
            r = $fscanf(file, "%d\n", sample_val);
            if (r != 1) begin
                if (!$feof(file)) begin
                    $fatal(1, "Invalid sample entry in %s", try_path);
                end
            end else begin
                if (sample_count >= MAX_SAMPLES) begin
                    $fatal(1, "Waveform exceeds MAX_SAMPLES (%0d)", MAX_SAMPLES);
                end
                if (sample_val < 0) begin
                    sample_val = 0;
                end else if (sample_val > 14'h3FFF) begin
                    sample_val = 14'h3FFF;
                end

                sample_val = sample_val & 14'h3FFF;
                centered = $signed({1'b0, sample_val}) - 15'sd8192;
                samples[sample_count] = centered[13:0];
                sample_count++;
            end
        end
        $fclose(file);

        if (sample_count == 0) begin
            $fatal(1, "Waveform file is empty: %s", try_path);
        end
    endtask

    task automatic send_custom_wave_command(
        input byte unsigned             control_byte,
        input int                       sample_count,
        input logic [31:0]              sample_rate_word,
        input logic signed [13:0]       samples [0:MAX_SAMPLES-1]
    );
        byte unsigned payload   [0:MAX_PAYLOAD_BYTES-1];
        int           idx;
        int           payload_len;
        int unsigned  sum;
        byte unsigned checksum;
        int           k;
        logic signed [14:0] offset_calc;
        logic [13:0]        sample_offset;
        begin
            idx = 0;
            payload[idx++] = control_byte;
            payload[idx++] = sample_count[15:8];
            payload[idx++] = sample_count[7:0];
            payload[idx++] = sample_rate_word[31:24];
            payload[idx++] = sample_rate_word[23:16];
            payload[idx++] = sample_rate_word[15:8];
            payload[idx++] = sample_rate_word[7:0];

            for (k = 0; k < sample_count; k++) begin
                offset_calc = $signed({samples[k][13], samples[k]}) + 15'sd8192;
                if (offset_calc < 0) begin
                    sample_offset = 14'h0000;
                end else if (offset_calc > 15'sd16383) begin
                    sample_offset = 14'h3FFF;
                end else begin
                    sample_offset = offset_calc[13:0];
                end

                payload[idx++] = sample_offset[7:0];
                payload[idx++] = sample_offset[13:8];
            end

            payload_len = idx;

            sum = 8'hFC + payload_len[15:8] + payload_len[7:0];
            for (k = 0; k < payload_len; k++) begin
                sum += payload[k];
            end
            checksum = sum[7:0];

            $display("[%0t] Sending Custom Waveform command (samples=%0d)", $time, sample_count);

            send_usb_byte(8'hAA);
            send_usb_byte(8'h55);
            send_usb_byte(8'hFC);
            send_usb_byte(payload_len[15:8]);
            send_usb_byte(payload_len[7:0]);

            for (k = 0; k < payload_len; k++) begin
                send_usb_byte(payload[k]);
            end

            send_usb_byte(checksum);
            #(CLK_PERIOD_NS * 400);
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Sequence
    // ------------------------------------------------------------------------
    logic signed [13:0] waveform_samples [0:MAX_SAMPLES-1];
    int          waveform_count;
    logic [31:0] sample_rate_word;
    bit  [MAX_SAMPLES-1:0] sample_seen;

    initial begin : TEST_SEQUENCE
        int sample_checks;
        int addr_prev1;
        int addr_prev2;
        int addr_now;

        wait (rst_n == 1'b1);

        load_waveform_from_csv(waveform_path, waveform_count, waveform_samples);

        sample_rate_word = calc_sample_rate_word(waveform_count, SIM_PLAYBACK_FREQ_HZ);
        $display("[%0t] Calculated sample_rate_word = 0x%08h", $time, sample_rate_word);

        send_custom_wave_command(8'h04, waveform_count, sample_rate_word, waveform_samples);
        wait (dut.u_custom_waveform_handler.handler_state == dut.u_custom_waveform_handler.H_IDLE);
        #(CLK_PERIOD_NS * 20);
        $display("[%0t] Waveform upload sequence complete", $time);

        wait (dut.u_custom_waveform_handler.playback_active == 1'b1);
        $display("[%0t] Custom waveform playback asserted", $time);

        sample_seen = '0;
        addr_prev1 = dut.u_custom_waveform_handler.ram_rd_addr;
        addr_prev2 = addr_prev1;
        sample_checks = 0;
    
        repeat (waveform_count * 128) begin
            @(posedge dac_clk);
            addr_now = dut.u_custom_waveform_handler.ram_rd_addr;
            if (dut.u_custom_waveform_handler.playback_active) begin
                if (addr_prev2 < waveform_count) begin
                    if (dac_data !== waveform_samples[addr_prev2]) begin
                        $fatal(1, "Playback mismatch at sample %0d: expected %0d, got %0d",
                               addr_prev2, waveform_samples[addr_prev2], dac_data);
                    end
                    if (!sample_seen[addr_prev2]) begin
                        sample_seen[addr_prev2] = 1'b1;
                        sample_checks++;
                    end
                end
            end
            addr_prev2 = addr_prev1;
            addr_prev1 = addr_now;
        end
    
        if (sample_checks < 16) begin
            $fatal(1, "Observed only %0d unique samples; expected active playback", sample_checks);
        end

        $display("[%0t] Observed %0d unique playback samples", $time, sample_checks);

        // Keep the custom waveform running for observation
        repeat (waveform_count * 256) begin
            @(posedge dac_clk);
        end
        #100_000; // extra observation time (~100ns)

        send_dac_command(2'b00, 32'h0100_0000, 32'h0000_0000);
        #(CLK_PERIOD_NS * 200);
        wait (dut.custom_wave_active == 1'b0);
        $display("[%0t] DAC handler command issued; custom waveform released", $time);

        $display("[%0t] cdc_custom_waveform_tb completed successfully", $time);
        #(CLK_PERIOD_NS * 50);
        $finish;
    end

endmodule
