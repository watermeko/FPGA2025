// ============================================================================
// Module: digital_capture_handler
// Description: 8-channel digital signal real-time capture module
//              Continuously samples 8 digital input channels and uploads
//              their logic states as a single byte (bit[n] = channel[n])
//
// Features:
//   - Configurable sampling rate via clock divider
//   - Start/Stop control via commands
//   - Real-time streaming upload
//   - 8 channels packed into 1 byte per sample
// ============================================================================
module digital_capture_handler(
    input  wire        clk,
    input  wire        rst_n,

    // Command interface
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,
    output wire        cmd_ready,

    // Digital signal inputs (8 channels)
    input  wire [7:0]  dc_signal_in,

    // Data upload interface
    output wire        upload_active,     // Upload active flag
    output reg         upload_req,        // Upload request
    output reg  [7:0]  upload_data,       // Upload data
    output reg  [7:0]  upload_source,     // Data source identifier
    output reg         upload_valid,      // Upload data valid
    input  wire        upload_ready       // Upload ready from arbiter
);

    // ========================================================================
    // Command type codes
    // ========================================================================
    localparam CMD_DC_START = 8'h0B;  // Start capture
    localparam CMD_DC_STOP  = 8'h0C;  // Stop capture

    // Upload source identifier
    localparam UPLOAD_SOURCE_DC = 8'h0B;

    // ========================================================================
    // State machine definitions
    // ========================================================================
    // Handler state machine
    localparam H_IDLE      = 3'b000;  // Idle state
    localparam H_RX_CMD    = 3'b001;  // Receiving command data
    localparam H_CAPTURING = 3'b010;  // Capturing and uploading

    // Upload state machine
    localparam UP_IDLE = 2'b00;
    localparam UP_SEND = 2'b01;
    localparam UP_WAIT = 2'b10;

    reg [2:0] handler_state;
    reg [1:0] upload_state;

    // ========================================================================
    // Registers
    // ========================================================================
    reg [15:0] sample_divider;     // Sampling clock divider
    reg [15:0] sample_counter;     // Sampling counter
    reg        sample_tick;        // Sampling tick pulse
    reg        capture_enable;     // Capture enable flag
    reg [7:0]  captured_data;      // Captured 8-channel data
    reg [7:0]  captured_data_sync; // Synchronized captured data
    reg        new_sample_flag;    // New sample available flag

    // Command data receive buffer
    reg [7:0] cmd_data_buf[1:0];   // Buffer for 2-byte divider value

    // ========================================================================
    // Sampling clock divider
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;
            if (capture_enable) begin
                if (sample_counter >= sample_divider - 1) begin
                    sample_counter <= 16'd0;
                    sample_tick <= 1'b1;
                end else begin
                    sample_counter <= sample_counter + 1;
                end
            end else begin
                sample_counter <= 16'd0;
            end
        end
    end

    // ========================================================================
    // Signal capture logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_data <= 8'h00;
            captured_data_sync <= 8'h00;
            new_sample_flag <= 1'b0;
        end else begin
            if (sample_tick) begin
                // Capture all 8 channels on sampling tick
                captured_data <= dc_signal_in;
                captured_data_sync <= captured_data;
                new_sample_flag <= 1'b1;
            end else if (upload_valid && upload_ready) begin
                // Clear flag after successful upload
                new_sample_flag <= 1'b0;
            end
        end
    end

    // ========================================================================
    // Ready signal: can accept commands when idle or receiving
    // ========================================================================
    assign cmd_ready = (handler_state == H_IDLE) || (handler_state == H_RX_CMD);

    // Upload active signal
    assign upload_active = (handler_state == H_CAPTURING);

    // ========================================================================
    // Main handler state machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= H_IDLE;
            upload_state <= UP_IDLE;

            sample_divider <= 16'd60;  // Default: 60MHz/60 = 1MHz
            capture_enable <= 1'b0;

            upload_req <= 1'b0;
            upload_data <= 8'h00;
            upload_source <= UPLOAD_SOURCE_DC;
            upload_valid <= 1'b0;

            cmd_data_buf[0] <= 8'h00;
            cmd_data_buf[1] <= 8'h00;

        end else begin
            // Default assignments
            upload_valid <= 1'b0;

            // ================================================================
            // Handler state machine
            // ================================================================
            case (handler_state)
                H_IDLE: begin
                    if (cmd_start) begin
                        if (cmd_type == CMD_DC_START) begin
                            handler_state <= H_RX_CMD;
                        end else if (cmd_type == CMD_DC_STOP) begin
                            capture_enable <= 1'b0;
                            // Stay in IDLE
                        end
                    end
                end

                H_RX_CMD: begin
                    // Receive 2-byte divider value (big-endian)
                    if (cmd_data_valid) begin
                        if (cmd_data_index == 0) begin
                            cmd_data_buf[0] <= cmd_data;  // High byte
                        end else if (cmd_data_index == 1) begin
                            cmd_data_buf[1] <= cmd_data;  // Low byte
                        end
                    end

                    if (cmd_done) begin
                        // Load divider and start capturing
                        sample_divider <= {cmd_data_buf[0], cmd_data_buf[1]};
                        capture_enable <= 1'b1;
                        handler_state <= H_CAPTURING;
                        upload_state <= UP_IDLE;
                    end
                end

                H_CAPTURING: begin
                    // Check for stop command
                    if (cmd_start && cmd_type == CMD_DC_STOP) begin
                        capture_enable <= 1'b0;
                        handler_state <= H_IDLE;
                        upload_state <= UP_IDLE;
                        upload_req <= 1'b0;
                    end
                    // Upload state machine handles data transmission
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase

            // ================================================================
            // Upload state machine (runs during H_CAPTURING state)
            // ================================================================
            case (upload_state)
                UP_IDLE: begin
                    if ((handler_state == H_CAPTURING) && new_sample_flag) begin
                        // New sample available, request upload
                        upload_req <= 1'b1;
                        upload_source <= UPLOAD_SOURCE_DC;
                        upload_data <= captured_data_sync;

                        if (upload_ready) begin
                            upload_valid <= 1'b1;
                            upload_state <= UP_SEND;
                        end
                    end else begin
                        upload_req <= 1'b0;
                    end
                end

                UP_SEND: begin
                    // Wait for ready signal to complete transfer
                    if (upload_ready) begin
                        upload_state <= UP_WAIT;
                    end
                end

                UP_WAIT: begin
                    // Deassert signals and return to IDLE
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                    upload_state <= UP_IDLE;
                end

                default: begin
                    upload_state <= UP_IDLE;
                end
            endcase
        end
    end

endmodule
