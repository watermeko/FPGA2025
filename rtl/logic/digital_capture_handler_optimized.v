// ============================================================================
// Module: digital_capture_handler  (HIGH-SPEED OPTIMIZED VERSION)
// Description: 8-channel digital signal real-time capture module
//              Continuously samples 8 digital input channels and uploads
//              their logic states as a single byte (bit[n] = channel[n])
//
// Features:
//   - Configurable sampling rate via clock divider
//   - Start/Stop control via commands
//   - Real-time streaming upload with ZERO-LATENCY pipeline
//   - 8 channels packed into 1 byte per sample
//   - Maximum sampling rate: 60 MHz (limited by system clock)
//
// OPTIMIZATION: Simplified upload state machine for maximum throughput
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
    input  wire        upload_ready       // Upload ready from arbiter (unused in optimized version)
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

    reg [2:0] handler_state;

    // ========================================================================
    // Registers
    // ========================================================================
    reg [15:0] sample_divider;     // Sampling clock divider
    reg [15:0] sample_counter;     // Sampling counter
    reg        sample_tick;        // Sampling tick pulse
    reg        capture_enable;     // Capture enable flag
    reg [7:0]  captured_data;      // Captured 8-channel data

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
                sample_counter <= 16'd0;  // Reset counter when disabled
            end
        end
    end

    // ========================================================================
    // Signal capture logic - OPTIMIZED: Direct capture without sync
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_data <= 8'h00;
        end else begin
            if (sample_tick && capture_enable) begin
                // Direct capture on sampling tick
                captured_data <= dc_signal_in;
            end
        end
    end

    // ========================================================================
    // Upload logic - OPTIMIZED: Single-cycle upload, no state machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            upload_data <= 8'h00;
            upload_valid <= 1'b0;
            upload_req <= 1'b0;
        end else begin
            // Direct upload when sample_tick occurs during capturing
            if ((handler_state == H_CAPTURING) && sample_tick) begin
                upload_data <= captured_data;  // Use captured data (already sampled)
                upload_valid <= 1'b1;
                upload_req <= 1'b1;
            end else begin
                upload_valid <= 1'b0;
                upload_req <= 1'b0;
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

            sample_divider <= 16'd60;  // Default: 60MHz/60 = 1MHz
            capture_enable <= 1'b0;

            upload_source <= UPLOAD_SOURCE_DC;

            cmd_data_buf[0] <= 8'h00;
            cmd_data_buf[1] <= 8'h00;

        end else begin
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
                        // Note: sample_counter will be reset by capture_enable logic
                    end
                end

                H_CAPTURING: begin
                    // Check for stop command
                    if (cmd_start && cmd_type == CMD_DC_STOP) begin
                        capture_enable <= 1'b0;
                        handler_state <= H_IDLE;
                    end
                    // Upload is handled by separate always block above
                end

                default: begin
                    handler_state <= H_IDLE;
                end
            endcase
        end
    end

endmodule
