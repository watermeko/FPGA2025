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
    input  wire        upload_ready,      // Upload ready from arbiter
    input  wire        fifo_almost_full   // FIFO almost full signal (backpressure)
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
    reg [7:0] divider_high_byte;   // Stores high byte of divider
    reg [7:0] divider_low_byte;    // Stores low byte of divider

    // ========================================================================
    // Sampling clock divider
    // ========================================================================
    reg reset_sample_counter;  // Flag to reset counter when divider changes

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;

            // Reset counter when flag is set from state machine
            if (reset_sample_counter) begin
                sample_counter <= 16'd0;
            end else if (capture_enable) begin
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
    // Signal capture + internal FIFO (sync + no-skip sampling)
    // Captures every sample_tick into a small FIFO decoupled from USB upload,
    // so backpressure does not stretch sampling intervals. Adds 2-FF sync to
    // reduce metastability when dc_signal_in is asynchronous to clk.
    // ========================================================================

    // Two-flip-flop synchronizers for each bit
    reg [7:0] dc_sync1;
    reg [7:0] dc_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_sync1 <= 8'h00;
            dc_sync2 <= 8'h00;
        end else begin
            dc_sync1 <= dc_signal_in;
            dc_sync2 <= dc_sync1;
        end
    end

    // Small sample FIFO (simple circular buffer)
    localparam integer SAMP_FIFO_DEPTH = 2048;
    localparam integer SAMP_AW = $clog2(SAMP_FIFO_DEPTH);
    reg [7:0] samp_mem [0:SAMP_FIFO_DEPTH-1];
    reg [SAMP_AW-1:0] samp_wr_ptr;
    reg [SAMP_AW-1:0] samp_rd_ptr;
    reg [SAMP_AW:0]   samp_count;  // one extra bit for full detection

    wire samp_full     = (samp_count == SAMP_FIFO_DEPTH);
    wire samp_empty    = (samp_count == 0);
    wire samp_can_read = !samp_empty && !fifo_almost_full;
    wire samp_push     = capture_enable && sample_tick && !samp_full;
    wire samp_pop      = !samp_empty && upload_valid && upload_ready;

    // Write on every sampling tick when enabled
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            samp_wr_ptr <= {SAMP_AW{1'b0}};
            samp_rd_ptr <= {SAMP_AW{1'b0}};
            samp_count  <= {SAMP_AW+1{1'b0}};
        end else begin
            if (samp_push) begin
                samp_mem[samp_wr_ptr] <= dc_sync2;  // store synchronized inputs
                samp_wr_ptr <= (samp_wr_ptr == SAMP_FIFO_DEPTH-1) ? {SAMP_AW{1'b0}} : samp_wr_ptr + 1'b1;
            end else if (capture_enable && sample_tick && samp_full) begin
                // FIFO full: drop newest sample (overflow). Consider exposing a counter if needed.
            end

            if (samp_pop) begin
                samp_rd_ptr <= (samp_rd_ptr == SAMP_FIFO_DEPTH-1) ? {SAMP_AW{1'b0}} : samp_rd_ptr + 1'b1;
            end

            case ({samp_push, samp_pop})
                2'b10: samp_count <= samp_count + 1'b1;
                2'b01: samp_count <= samp_count - 1'b1;
                default: samp_count <= samp_count;
            endcase
        end
    end
    // ========================================================================
    // Upload logic - stream from internal sample FIFO when USB path can accept
    // One byte per sample. We keep upload_req low (0) to mark no packet boundaries,
    // so upload_arbiter can preempt DC at any time.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            upload_data  <= 8'h00;
            upload_valid <= 1'b0;
            upload_req   <= 1'b0;
        end else begin
            upload_valid <= 1'b0; // default
            upload_req   <= 1'b0;

            if (samp_can_read) begin
                // Present next sample; pop only on upload_ready
                upload_data  <= samp_mem[samp_rd_ptr];
                upload_valid <= 1'b1;
            end
        end
    end
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
            divider_high_byte <= 8'h00;
            divider_low_byte <= 8'h00;
            capture_enable <= 1'b0;
            reset_sample_counter <= 1'b0;

            upload_source <= UPLOAD_SOURCE_DC;

        end else begin
            // Default: clear reset flag
            reset_sample_counter <= 1'b0;
            // ================================================================
            // Handler state machine
            // ================================================================
            case (handler_state)
                H_IDLE: begin
                    if (cmd_start) begin
                        if (cmd_type == CMD_DC_START) begin
                            divider_high_byte <= 8'h00;
                            divider_low_byte <= 8'h00;
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
                            divider_high_byte <= cmd_data;  // High byte
                        end else if (cmd_data_index == 1) begin
                            divider_low_byte <= cmd_data;   // Low byte
                        end
                    end

                    if (cmd_done) begin
                        // Load divider (handle simultaneous cmd_done + final data byte)
                        if (cmd_data_valid && (cmd_data_index == 16'd1)) begin
                            sample_divider <= {divider_high_byte, cmd_data};
                        end else begin
                            sample_divider <= {divider_high_byte, divider_low_byte};
                        end
                        reset_sample_counter <= 1'b1;  // Signal to reset sample_counter
                        capture_enable <= 1'b1;
                        handler_state <= H_CAPTURING;
                    end
                end

                H_CAPTURING: begin
                    // Check for stop command or new start command (to change sampling rate)
                    if (cmd_start) begin
                        if (cmd_type == CMD_DC_STOP) begin
                            capture_enable <= 1'b0;
                            handler_state <= H_IDLE;
                        end else if (cmd_type == CMD_DC_START) begin
                            // Allow restarting with new parameters
                            capture_enable <= 1'b0;
                            divider_high_byte <= 8'h00;
                            divider_low_byte <= 8'h00;
                            handler_state <= H_RX_CMD;
                        end
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
