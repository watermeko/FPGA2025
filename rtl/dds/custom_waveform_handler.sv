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
    output logic signed [13:0] dac_data,
    output logic        playing,
    output logic        dac_active
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

    logic [7:0]  header_buffer [0:6];
    logic [11:0] write_addr;
    logic [15:0] sample_word;
    logic        sample_byte_sel;
    logic        ram_wr_en;
    logic [11:0] ram_wr_addr;
    logic signed [13:0] ram_wr_data;

    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state    <= H_IDLE;
            waveform_length  <= 16'd0;
            sample_rate_word <= 32'd0;
            loop_enable      <= 1'b0;
            play_enable      <= 1'b0;
            write_addr       <= 12'd0;
            sample_word      <= 16'd0;
            sample_byte_sel  <= 1'b0;
            ram_wr_en        <= 1'b0;
            ram_wr_addr      <= 12'd0;
            ram_wr_data      <= 14'sd0;

            for (int i = 0; i < 7; i++) begin
                header_buffer[i] <= 8'h00;
            end
        end else begin
            ram_wr_en <= 1'b0;
            play_enable <= 1'b0;

            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == 8'hFC) begin
                        handler_state   <= H_RECEIVING;
                        write_addr      <= 12'd0;
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
                                ram_wr_en         <= 1'b1;
                                ram_wr_addr       <= write_addr;
                                ram_wr_data       <= decode_sample(cmd_data, sample_word[7:0]);
                                write_addr        <= write_addr + 1'b1;
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

    logic signed [13:0] waveform_ram [0:4095];
    logic signed [13:0] ram_rd_data;
    logic [11:0] ram_rd_addr;

    always @(posedge clk) begin
        if (ram_wr_en && (ram_wr_addr < 4096)) begin
            waveform_ram[ram_wr_addr] <= ram_wr_data;
        end
    end

    always @(posedge dac_clk) begin
        ram_rd_data <= waveform_ram[ram_rd_addr];
    end

    logic        play_enable_sync1, play_enable_sync2, play_enable_sync3;
    logic        release_sync1, release_sync2, release_sync3;
    logic        loop_enable_sync1, loop_enable_sync2;
    logic [15:0] waveform_length_sync1, waveform_length_sync2;
    logic [31:0] sample_rate_word_sync1, sample_rate_word_sync2;

    logic [31:0] phase_acc;
    wire  [31:0] phase_next = phase_acc + sample_rate_word_sync2;
    wire  [11:0] addr_from_phase = phase_acc[31:20];

    logic playback_active;
    logic dac_claim;

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
            waveform_length_sync1  <= 16'd0;
            waveform_length_sync2  <= 16'd0;
            sample_rate_word_sync1 <= 32'd0;
            sample_rate_word_sync2 <= 32'd0;
            phase_acc              <= 32'd0;
            ram_rd_addr            <= 12'd0;
            playback_active        <= 1'b0;
            dac_claim              <= 1'b0;
            dac_data               <= 14'sd0;
        end else begin
            play_enable_sync1      <= play_enable;
            play_enable_sync2      <= play_enable_sync1;
            play_enable_sync3      <= play_enable_sync2;

            release_sync1          <= release_override;
            release_sync2          <= release_sync1;
            release_sync3          <= release_sync2;

            loop_enable_sync1      <= loop_enable;
            loop_enable_sync2      <= loop_enable_sync1;
            waveform_length_sync1  <= waveform_length;
            waveform_length_sync2  <= waveform_length_sync1;
            sample_rate_word_sync1 <= sample_rate_word;
            sample_rate_word_sync2 <= sample_rate_word_sync1;

            // Handle start / release pulses
            if (play_enable_sync2 && !play_enable_sync3) begin
                dac_claim       <= (waveform_length_sync2 != 0);
                playback_active <= (waveform_length_sync2 != 0);
                phase_acc       <= 32'd0;
                ram_rd_addr     <= 12'd0;
            end else if (release_sync2 && !release_sync3) begin
                dac_claim       <= 1'b0;
                playback_active <= 1'b0;
                phase_acc       <= 32'd0;
                ram_rd_addr     <= 12'd0;
            end else if (playback_active) begin
                phase_acc <= phase_next;

                if (addr_from_phase >= waveform_length_sync2[11:0]) begin
                    if (loop_enable_sync2) begin
                        ram_rd_addr <= addr_from_phase - waveform_length_sync2[11:0];
                        phase_acc   <= phase_next - {waveform_length_sync2[11:0], 20'd0};
                    end else begin
                        playback_active <= 1'b0;
                        phase_acc       <= 32'd0;
                        ram_rd_addr     <= 12'd0;
                    end
                end else begin
                    ram_rd_addr <= addr_from_phase;
                end
            end

            if (playback_active) begin
                dac_data <= -ram_rd_data;
            end else begin
                dac_data <= 14'sd0;
            end
        end
    end

    assign playing    = playback_active;
    assign dac_active = dac_claim;

endmodule
