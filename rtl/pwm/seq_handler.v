// ============================================================================
// Module:  seq_handler
// Author:  Claude
// Date:    2025-10-24
//
// Description:
// Command protocol handler for the custom sequence generator.
// Receives configuration commands via the command bus and configures
// the appropriate sequence channel.
//
// Command Code: 0xF0 (SEQ_CONFIG)
//
// Payload Format (13 bytes):
//   Byte 0:      Channel index [2:0] (0-7)
//   Byte 1:      Enable flag (0=disable, 1=enable)
//   Byte 2-3:    Frequency divider (16-bit, big-endian)
//   Byte 4:      Sequence length in bits (1-64)
//   Byte 5-12:   Sequence data (8 bytes, 64 bits, LSB first)
//
// Example:
//   Command: AA 55 F0 00 0D [CH] [EN] [DIV_H] [DIV_L] [LEN] [D0..D7] CS
//
//   For 1MHz base freq (60MHz / 60 = 1MHz):
//     CH=0, EN=1, DIV=60, LEN=10, SEQ=0b0101010101
//   Bytes: 00 01 00 3C 0A 55 01 00 00 00 00 00 00
// ============================================================================
module seq_handler(
    input  wire        clk,
    input  wire        rst_n,

    // Command bus interface
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,

    output wire        cmd_ready,

    // Sequence outputs
    output wire [7:0]  seq_pins
);

    // State machine definition
    localparam H_IDLE          = 2'b00;  // Idle state
    localparam H_RECEIVING     = 2'b01;  // Receiving data
    localparam H_UPDATE_CONFIG = 2'b10;  // Update sequence config values
    localparam H_STROBE        = 2'b11;  // Issue update pulse

    reg [1:0] handler_state;

    // Configuration registers
    reg [2:0]   seq_ch_index;
    reg         seq_enable;
    reg [15:0]  seq_freq_div;
    reg [6:0]   seq_length;
    reg [63:0]  seq_data;
    reg         seq_update_strobe;

    // Temporary storage for command payload (13 bytes)
    reg [7:0]   seq_cmd_data [0:12];

    // Ready when IDLE or RECEIVING
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RECEIVING);

    // State machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state     <= H_IDLE;
            seq_update_strobe <= 1'b0;
            seq_ch_index      <= 0;
            seq_enable        <= 1'b0;
            seq_freq_div      <= 0;
            seq_length        <= 0;
            seq_data          <= 64'h0;

            // Clear temporary storage
            seq_cmd_data[0]  <= 8'h0;
            seq_cmd_data[1]  <= 8'h0;
            seq_cmd_data[2]  <= 8'h0;
            seq_cmd_data[3]  <= 8'h0;
            seq_cmd_data[4]  <= 8'h0;
            seq_cmd_data[5]  <= 8'h0;
            seq_cmd_data[6]  <= 8'h0;
            seq_cmd_data[7]  <= 8'h0;
            seq_cmd_data[8]  <= 8'h0;
            seq_cmd_data[9]  <= 8'h0;
            seq_cmd_data[10] <= 8'h0;
            seq_cmd_data[11] <= 8'h0;
            seq_cmd_data[12] <= 8'h0;
        end
        else begin
            // Default: pull strobe low
            seq_update_strobe <= 1'b0;

            case (handler_state)
                H_IDLE: begin
                    if (cmd_start && cmd_type == 8'hF0) begin
                        handler_state <= H_RECEIVING;
                    end
                end

                H_RECEIVING: begin
                    if (cmd_data_valid && cmd_data_index < 13) begin
                        seq_cmd_data[cmd_data_index] <= cmd_data;
                    end

                    if (cmd_done) begin
                        handler_state <= H_UPDATE_CONFIG;
                    end
                end

                H_UPDATE_CONFIG: begin
                    // Cycle 1: Set configuration values
                    // Parse the 13-byte payload
                    seq_ch_index <= seq_cmd_data[0][2:0];
                    seq_enable   <= seq_cmd_data[1][0];
                    seq_freq_div <= {seq_cmd_data[2], seq_cmd_data[3]};
                    seq_length   <= seq_cmd_data[4][6:0];

                    // Sequence data: 8 bytes (LSB first)
                    seq_data <= {
                        seq_cmd_data[12],
                        seq_cmd_data[11],
                        seq_cmd_data[10],
                        seq_cmd_data[9],
                        seq_cmd_data[8],
                        seq_cmd_data[7],
                        seq_cmd_data[6],
                        seq_cmd_data[5]
                    };

                    handler_state <= H_STROBE;
                end

                H_STROBE: begin
                    // Cycle 2: Config values are now stable
                    // Issue single-cycle update pulse
                    seq_update_strobe <= 1'b1;

                    // Return to idle
                    handler_state <= H_IDLE;
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase
        end
    end

    // Instantiate the multi-channel sequence generator
    seq_multi_channel #(
        .NUM_CHANNELS(8),
        .DIVIDER_WIDTH(16),
        .SEQ_MAX_BITS(64)
    ) u_seq_multi (
        .clk(clk),
        .rst_n(rst_n),
        .config_ch_index_in(seq_ch_index),
        .config_freq_div_in(seq_freq_div),
        .config_seq_data_in(seq_data),
        .config_seq_len_in(seq_length),
        .config_enable_in(seq_enable),
        .config_update_strobe(seq_update_strobe),
        .seq_out_vector(seq_pins)
    );

endmodule
