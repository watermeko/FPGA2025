module custom_waveform_handler(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [7:0]   cmd_type,
    input  wire [15:0]  cmd_length,
    input  wire [7:0]   cmd_data,
    input  wire [15:0]  cmd_data_index,
    input  wire         cmd_start,
    input  wire         cmd_data_valid,
    input  wire         cmd_done,
    output wire         cmd_ready,

    input  wire         release_override,

    input  wire         dac_clk,
    output logic signed [13:0] dac_data_a,      // Channel A
    output logic signed [13:0] dac_data_b,      // Channel B
    output logic        playing_a,
    output logic        playing_b,
    output logic        dac_active_a,
    output logic        dac_active_b
);

    localparam H_IDLE         = 2'b00;
    localparam H_RECEIVING    = 2'b01;
    localparam H_PARSE_HEADER = 2'b10;
    localparam H_PROCESS      = 2'b11;

    logic [1:0]  handler_state;
    logic [15:0] waveform_length;
    logic [31:0] sample_rate_word;
    logic        loop_enable;
    logic        play_enable;
    logic        target_channel;  // 0=Channel A, 1=Channel B

    logic [7:0]  header_buffer [0:6];
    logic [7:0] write_addr;  // 8-bit address for 256 entries
    logic [15:0] sample_word;
    logic        sample_byte_sel;
    logic        ram_wr_en_a, ram_wr_en_b;
    logic [7:0] ram_wr_addr;  // 8-bit address for 256-entry SDPB
    logic signed [13:0] ram_wr_data;

    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state    <= H_IDLE;
            waveform_length  <= 16'd0;
            sample_rate_word <= 32'd0;
            loop_enable      <= 1'b0;
            play_enable      <= 1'b0;
            target_channel   <= 1'b0;
            write_addr       <= 8'd0;
            sample_word      <= 16'd0;
            sample_byte_sel  <= 1'b0;
            ram_wr_en_a      <= 1'b0;
            ram_wr_en_b      <= 1'b0;
            ram_wr_addr      <= 8'd0;
            ram_wr_data      <= 14'sd0;

            for (int i = 0; i < 7; i++) begin
                header_buffer[i] <= 8'h00;
            end
        end else begin
            ram_wr_en_a <= 1'b0;
            ram_wr_en_b <= 1'b0;
            play_enable <= 1'b0;

            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == 8'hFC) begin
                        handler_state   <= H_RECEIVING;
                        write_addr      <= 8'd0;
                        sample_byte_sel <= 1'b0;
                        play_enable     <= 1'b0;
                    end
                end

                H_RECEIVING: begin
                    if (cmd_data_valid) begin
                        if (cmd_data_index < 7) begin
                            header_buffer[cmd_data_index] <= cmd_data;
                        end else begin
                            if (!sample_byte_sel) begin
                                sample_word[7:0] <= cmd_data;
                                sample_byte_sel  <= 1'b1;
                            end else begin
                                sample_word[15:8] <= cmd_data;
                                sample_byte_sel   <= 1'b0;

                                // Write to independent SDPB for target channel
                                ram_wr_addr  <= write_addr;  // 8-bit address (0-255)
                                ram_wr_data  <= decode_sample(cmd_data, sample_word[7:0]);

                                // Select which channel to write
                                if (header_buffer[0][3] == 1'b0) begin
                                    // Channel A write
                                    ram_wr_en_a <= 1'b1;
                                end else begin
                                    // Channel B write
                                    ram_wr_en_b <= 1'b1;
                                end

                                write_addr <= write_addr + 1'b1;
                            end
                        end
                    end

                    if (cmd_done) begin
                        handler_state <= H_PARSE_HEADER;
                    end
                end

                H_PARSE_HEADER: begin
                    waveform_length  <= {header_buffer[1], header_buffer[2]};
                    sample_rate_word <= {header_buffer[3], header_buffer[4], header_buffer[5], header_buffer[6]};
                    loop_enable      <= header_buffer[0][2];
                    target_channel   <= header_buffer[0][3];
                    handler_state    <= H_PROCESS;
                end

                H_PROCESS: begin
                    play_enable <= (waveform_length != 0);
                    handler_state <= H_IDLE;
                end

                default: handler_state <= H_IDLE;
            endcase
        end
    end

    function automatic logic signed [13:0] decode_sample(
        input [7:0] high_byte,
        input [7:0] low_byte
    );
        logic [13:0] raw;
        logic signed [14:0] centered;
    begin
        raw = {high_byte[5:0], low_byte};
        centered = $signed({1'b0, raw}) - 15'sd8192;
        if (centered > 15'sd8191) begin
            decode_sample = 14'sd8191;
        end else if (centered < -15'sd8192) begin
            decode_sample = -14'sd8192;
        end else begin
            decode_sample = centered[13:0];
        end
    end
    endfunction

    // Unified dual-channel waveform storage using two independent GOWIN SDPB IPs
    // Each SDPB: 256×14-bit (uses 1 BSRAM block each, 2 total)
    // Channel A and Channel B have independent address spaces
    logic signed [13:0] ram_rd_data_a, ram_rd_data_b;
    logic [7:0] ram_rd_addr_a, ram_rd_addr_b;  // 8-bit addresses for 256-entry SDPB

    // Instantiate GOWIN SDPB IP core for Channel A
    custom_wave_sdpb u_waveform_sdpb_a (
        // Write port (clk domain)
        .clka(clk),
        .cea(ram_wr_en_a),               // Write enable for channel A
        .reset(~rst_n),                  // Active high reset
        .ada(ram_wr_addr),               // 8-bit write address (0-255)
        .din(ram_wr_data),               // 14-bit write data

        // Read port (dac_clk domain)
        .clkb(dac_clk),
        .ceb(1'b1),                      // Clock enable always on for read
        .oce(1'b1),                      // Output clock enable
        .adb(ram_rd_addr_a),             // 8-bit read address
        .dout(ram_rd_data_a)             // 14-bit read data
    );

    // Instantiate GOWIN SDPB IP core for Channel B
    custom_wave_sdpb u_waveform_sdpb_b (
        // Write port (clk domain)
        .clka(clk),
        .cea(ram_wr_en_b),               // Write enable for channel B
        .reset(~rst_n),                  // Active high reset
        .ada(ram_wr_addr),               // 8-bit write address (0-255)
        .din(ram_wr_data),               // 14-bit write data

        // Read port (dac_clk domain)
        .clkb(dac_clk),
        .ceb(1'b1),                      // Clock enable always on for read
        .oce(1'b1),                      // Output clock enable
        .adb(ram_rd_addr_b),             // 8-bit read address
        .dout(ram_rd_data_b)             // 14-bit read data
    );

    // Clock domain crossing synchronizers - duplicated for both channels
    logic        play_enable_sync1, play_enable_sync2, play_enable_sync3;
    logic        release_sync1, release_sync2, release_sync3;
    logic        loop_enable_sync1, loop_enable_sync2;
    logic        target_channel_sync1, target_channel_sync2;
    logic [15:0] waveform_length_sync1, waveform_length_sync2;
    logic [31:0] sample_rate_word_sync1, sample_rate_word_sync2;

    // Per-channel playback control
    logic [31:0] phase_acc_a, phase_acc_b;
    wire  [31:0] phase_next_a = phase_acc_a + sample_rate_word_a;
    wire  [31:0] phase_next_b = phase_acc_b + sample_rate_word_b;
    wire  [7:0] addr_offset_a = phase_acc_a[31:24];  // 8-bit address from phase[31:24] (0-255)
    wire  [7:0] addr_offset_b = phase_acc_b[31:24];  // Supports up to 256 samples per channel

    logic playback_active_a, playback_active_b;
    logic dac_claim_a, dac_claim_b;

    // Synchronized playback parameters per channel
    logic [15:0] waveform_length_a, waveform_length_b;
    logic [31:0] sample_rate_word_a, sample_rate_word_b;
    logic        loop_enable_a, loop_enable_b;

    // Pipeline registers for glitch-free output (matches DDS two-stage pipeline)
    logic signed [13:0] dac_data_a_stage1, dac_data_b_stage1;

    always @(posedge dac_clk or negedge rst_n) begin
        if (!rst_n) begin
            play_enable_sync1      <= 1'b0;
            play_enable_sync2      <= 1'b0;
            play_enable_sync3      <= 1'b0;
            release_sync1          <= 1'b0;
            release_sync2          <= 1'b0;
            release_sync3          <= 1'b0;
            loop_enable_sync1      <= 1'b0;
            loop_enable_sync2      <= 1'b0;
            target_channel_sync1   <= 1'b0;
            target_channel_sync2   <= 1'b0;
            waveform_length_sync1  <= 16'd0;
            waveform_length_sync2  <= 16'd0;
            sample_rate_word_sync1 <= 32'd0;
            sample_rate_word_sync2 <= 32'd0;

            // Channel A
            phase_acc_a            <= 32'd0;
            ram_rd_addr_a          <= 8'd0;
            playback_active_a      <= 1'b0;
            dac_claim_a            <= 1'b0;
            dac_data_a_stage1      <= 14'sd0;
            dac_data_a             <= 14'sd0;
            waveform_length_a      <= 16'd0;
            sample_rate_word_a     <= 32'd0;
            loop_enable_a          <= 1'b0;

            // Channel B
            phase_acc_b            <= 32'd0;
            ram_rd_addr_b          <= 8'd0;
            playback_active_b      <= 1'b0;
            dac_claim_b            <= 1'b0;
            dac_data_b_stage1      <= 14'sd0;
            dac_data_b             <= 14'sd0;
            waveform_length_b      <= 16'd0;
            sample_rate_word_b     <= 32'd0;
            loop_enable_b          <= 1'b0;
        end else begin
            // Synchronize control signals
            play_enable_sync1      <= play_enable;
            play_enable_sync2      <= play_enable_sync1;
            play_enable_sync3      <= play_enable_sync2;

            release_sync1          <= release_override;
            release_sync2          <= release_sync1;
            release_sync3          <= release_sync2;

            loop_enable_sync1      <= loop_enable;
            loop_enable_sync2      <= loop_enable_sync1;
            target_channel_sync1   <= target_channel;
            target_channel_sync2   <= target_channel_sync1;
            waveform_length_sync1  <= waveform_length;
            waveform_length_sync2  <= waveform_length_sync1;
            sample_rate_word_sync1 <= sample_rate_word;
            sample_rate_word_sync2 <= sample_rate_word_sync1;

            // Handle start / release pulses for Channel A
            if (play_enable_sync2 && !play_enable_sync3 && target_channel_sync2 == 1'b0) begin
                dac_claim_a        <= (waveform_length_sync2 != 0);
                playback_active_a  <= (waveform_length_sync2 != 0);
                phase_acc_a        <= 32'd0;
                ram_rd_addr_a      <= 8'd0;
                waveform_length_a  <= waveform_length_sync2;
                sample_rate_word_a <= sample_rate_word_sync2;
                loop_enable_a      <= loop_enable_sync2;
            end else if (release_sync2 && !release_sync3) begin
                dac_claim_a       <= 1'b0;
                playback_active_a <= 1'b0;
                phase_acc_a       <= 32'd0;
                ram_rd_addr_a     <= 8'd0;
            end else if (playback_active_a) begin
                phase_acc_a <= phase_next_a;

                // Check if 8-bit address exceeds waveform length
                // Special handling for length=256: no wrapping needed (8-bit addr naturally wraps at 256)
                if (waveform_length_a == 16'd256) begin
                    // Length is exactly 256, use all addresses 0-255 naturally
                    ram_rd_addr_a <= addr_offset_a;
                end else if (addr_offset_a >= waveform_length_a[7:0]) begin
                    if (loop_enable_a) begin
                        // Wrap around: modulo operation
                        ram_rd_addr_a <= addr_offset_a - waveform_length_a[7:0];
                    end else begin
                        // Non-loop mode: stop playback
                        playback_active_a <= 1'b0;
                        phase_acc_a       <= 32'd0;
                        ram_rd_addr_a     <= 8'd0;
                    end
                end else begin
                    ram_rd_addr_a <= addr_offset_a;
                end
            end

            // Handle start / release pulses for Channel B
            if (play_enable_sync2 && !play_enable_sync3 && target_channel_sync2 == 1'b1) begin
                dac_claim_b        <= (waveform_length_sync2 != 0);
                playback_active_b  <= (waveform_length_sync2 != 0);
                phase_acc_b        <= 32'd0;
                ram_rd_addr_b      <= 8'd0;
                waveform_length_b  <= waveform_length_sync2;
                sample_rate_word_b <= sample_rate_word_sync2;
                loop_enable_b      <= loop_enable_sync2;
            end else if (release_sync2 && !release_sync3) begin
                dac_claim_b       <= 1'b0;
                playback_active_b <= 1'b0;
                phase_acc_b       <= 32'd0;
                ram_rd_addr_b     <= 8'd0;
            end else if (playback_active_b) begin
                phase_acc_b <= phase_next_b;

                // Check if 8-bit address exceeds waveform length
                // Special handling for length=256: no wrapping needed (8-bit addr naturally wraps at 256)
                if (waveform_length_b == 16'd256) begin
                    // Length is exactly 256, use all addresses 0-255 naturally
                    ram_rd_addr_b <= addr_offset_b;
                end else if (addr_offset_b >= waveform_length_b[7:0]) begin
                    if (loop_enable_b) begin
                        // Wrap around: modulo operation
                        ram_rd_addr_b <= addr_offset_b - waveform_length_b[7:0];
                    end else begin
                        // Non-loop mode: stop playback
                        playback_active_b <= 1'b0;
                        phase_acc_b       <= 32'd0;
                        ram_rd_addr_b     <= 8'd0;
                    end
                end else begin
                    ram_rd_addr_b <= addr_offset_b;
                end
            end

            // Output data for both channels with two-stage pipeline for glitch-free output
            // Stage 1: Direct from SDPB output (already registered)
            if (playback_active_a) begin
                dac_data_a_stage1 <= ram_rd_data_a;
            end else begin
                dac_data_a_stage1 <= 14'sd0;
            end

            if (playback_active_b) begin
                dac_data_b_stage1 <= ram_rd_data_b;
            end else begin
                dac_data_b_stage1 <= 14'sd0;
            end

            // Stage 2: Final output register (matches DDS pipeline depth)
            dac_data_a <= dac_data_a_stage1;
            dac_data_b <= dac_data_b_stage1;
        end
    end

    assign playing_a    = playback_active_a;
    assign playing_b    = playback_active_b;
    assign dac_active_a = dac_claim_a;
    assign dac_active_b = dac_claim_b;

endmodule