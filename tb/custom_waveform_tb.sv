`timescale 1ns/1ps

module custom_waveform_tb();

    localparam int MAX_SAMPLES        = 4096;
    localparam int MAX_PAYLOAD_BYTES  = 7 + (MAX_SAMPLES * 2);
    localparam int DAC_MAX            = 14'h3FFF;
    localparam real DDS_CLOCK_HZ      = 100_000_000.0;
    string waveform_path = "sim/custom_waveform_tb/waveform_1760526061.csv";

    reg clk;
    reg dac_clk;
    reg rst_n;

    reg [7:0]  cmd_type;
    reg [15:0] cmd_length;
    reg [7:0]  cmd_data;
    reg [15:0] cmd_data_index;
    reg        cmd_start;
    reg        cmd_data_valid;
    reg        cmd_done;
    wire       cmd_ready;

    wire [13:0] dac_data;
    wire        playing;

    custom_waveform_handler u_dut(
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
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .playing(playing)
    );

    initial begin
        clk = 1'b0;
        forever #8.333 clk = ~clk;  // 60 MHz
    end

    initial begin
        dac_clk = 1'b0;
        forever #2.5 dac_clk = ~dac_clk;  // 200 MHz
    end

    logic [13:0] waveform_buffer [0:MAX_SAMPLES-1];
    int          waveform_samples;

    function automatic logic [31:0] calc_sample_rate_word(int wave_len, real freq_hz);
        real playback_freq;
        int unsigned raw;
    begin
        playback_freq = freq_hz * wave_len;
        raw = $rtoi((playback_freq * 1048576.0) / DDS_CLOCK_HZ);
        if (raw == 0) begin
            raw = 1;
        end
        calc_sample_rate_word = raw[31:0];
    end
    endfunction

    task automatic load_waveform_from_csv(
        input string filename,
        output int sample_count
    );
        int file;
        int r;
        int raw_value;
        string line;
        string open_path;
        sample_count = 0;

        open_path = filename;
        file = $fopen(open_path, "r");
        if (file == 0) begin
            open_path = {"../../", filename};
            file = $fopen(open_path, "r");
        end
        if (file == 0) begin
            open_path = {"./", filename};
            file = $fopen(open_path, "r");
        end
        if (file == 0) begin
            $error("Failed to open waveform file: %s", filename);
            sample_count = 0;
            return;
        end

        $display("Reading waveform from %s", open_path);

        while (!$feof(file)) begin
            line = "";
            r = $fgets(line, file);
            if (r == 0) begin
                break;
            end

            if (line.len() == 0) begin
                continue;
            end

            if ($sscanf(line, "%d", raw_value) != 1) begin
                $fatal(1, "Waveform file must contain integer samples: %s", open_path);
            end

            if (sample_count >= MAX_SAMPLES) begin
                $fatal(1, "Waveform exceeds MAX_SAMPLES (%0d)", MAX_SAMPLES);
            end

            if (raw_value < 0) begin
                raw_value = 0;
            end else if (raw_value > DAC_MAX) begin
                raw_value = DAC_MAX;
            end

            waveform_buffer[sample_count] = raw_value[13:0];
            sample_count++;
        end

        $fclose(file);

        if (sample_count == 0) begin
            $fatal(1, "Waveform file is empty: %s", open_path);
        end
    endtask

    task automatic send_command(
        input [7:0]  cmd,
        input [15:0] length,
        input byte unsigned data_array [0:MAX_PAYLOAD_BYTES-1],
        input int data_count
    );
        int j;
    begin
        @(posedge clk);
        cmd_type  <= cmd;
        cmd_length <= length;
        cmd_start <= 1'b1;
        @(posedge clk);
        cmd_start <= 1'b0;

        for (j = 0; j < data_count; j++) begin
            wait (cmd_ready == 1'b1);
            @(posedge clk);
            cmd_data       <= data_array[j];
            cmd_data_index <= j[15:0];
            cmd_data_valid <= 1'b1;
            @(posedge clk);
            cmd_data_valid <= 1'b0;
        end

        @(posedge clk);
        cmd_done <= 1'b1;
        @(posedge clk);
        cmd_done <= 1'b0;

        $display("[%0t] Command 0x%02X sent (len=%0d)", $time, cmd, length);
    end
    endtask

    task automatic upload_waveform_single_packet(
        input [7:0]  control_byte,
        input int    sample_count,
        input logic [13:0] waveform_data [0:MAX_SAMPLES-1],
        input logic [31:0] sample_rate_word
    );
        byte unsigned payload [0:MAX_PAYLOAD_BYTES-1];
        int idx;
        int k;
        int payload_len;
    begin
        if (sample_count <= 0) begin
            $fatal(1, "Invalid sample_count (%0d)", sample_count);
        end

        idx = 0;
        payload[idx++] = control_byte;
        payload[idx++] = sample_count[15:8];
        payload[idx++] = sample_count[7:0];
        payload[idx++] = sample_rate_word[31:24];
        payload[idx++] = sample_rate_word[23:16];
        payload[idx++] = sample_rate_word[15:8];
        payload[idx++] = sample_rate_word[7:0];

        for (k = 0; k < sample_count; k++) begin
            payload[idx++] = waveform_data[k][7:0];
            payload[idx++] = waveform_data[k][13:8];
        end

        payload_len = idx;
        send_command(8'hFC, payload_len[15:0], payload, payload_len);
        $display("[%0t] Waveform uploaded (loop=%b, samples=%0d)", $time, control_byte[2], sample_count);
    end
    endtask

    integer dac_log;
    reg playing_d;

    initial begin
        dac_log = $fopen("dac_output.txt", "w");
        if (dac_log == 0) begin
            $fatal(1, "Failed to open dac_output.txt for writing");
        end
    end

    always @(posedge dac_clk) begin
        if (playing) begin
            $fwrite(dac_log, "%0d\n", dac_data);
        end
    end

    final begin
        if (dac_log != 0) begin
            $fclose(dac_log);
        end
        $display("DAC output saved to dac_output.txt");
    end

    initial begin
        rst_n = 1'b0;
        cmd_type = 8'd0;
        cmd_length = 16'd0;
        cmd_data = 8'd0;
        cmd_data_index = 16'd0;
        cmd_start = 1'b0;
        cmd_data_valid = 1'b0;
        cmd_done = 1'b0;

        if ($value$plusargs("WAVEFORM=%s", waveform_path)) begin
            $display("Waveform override via +WAVEFORM: %s", waveform_path);
        end else begin
            $display("Using default waveform: %s", waveform_path);
        end

        load_waveform_from_csv(waveform_path, waveform_samples);
        if (waveform_samples == 0) begin
            $fatal(1, "No samples loaded, aborting simulation.");
        end
        $display("Loaded %0d samples", waveform_samples);

        #100;
        rst_n = 1'b1;
        #100;

        $display("========================================");
        $display("Test 1: Loop playback");
        $display("========================================");

        upload_waveform_single_packet(
            8'h04,
            waveform_samples,
            waveform_buffer,
            calc_sample_rate_word(waveform_samples, 1000.0)
        );

        #100000;

        $display("\n========================================");
        $display("Test 2: Single-pass playback");
        $display("========================================");

        upload_waveform_single_packet(
            8'h00,
            waveform_samples,
            waveform_buffer,
            calc_sample_rate_word(waveform_samples, 1000.0)
        );

        fork
            begin
                wait (playing == 1'b0);
                $display("[%0t] Playback stopped (single-pass)", $time);
            end
            begin
                #200000;
                if (playing) begin
                    $fatal(1, "Playback did not stop in single-pass mode");
                end
            end
        join_any
        disable fork;

        $display("\n========================================");
        $display("All tests completed");
        $display("========================================");

        #5000;
        $finish;
    end

    always @(posedge dac_clk or negedge rst_n) begin
        if (!rst_n) begin
            playing_d <= 1'b0;
        end else begin
            playing_d <= playing;
            if (playing && !playing_d) begin
                $display("[%0t] Playback started", $time);
            end else if (!playing && playing_d) begin
                $display("[%0t] Playback stopped", $time);
            end
        end
    end

    initial begin
        $dumpfile("custom_waveform_tb.vcd");
        $dumpvars(0, custom_waveform_tb);
    end

endmodule
