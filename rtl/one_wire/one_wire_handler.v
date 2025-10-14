// ============================================================================
// Module: one_wire_handler
// Description: 1-Wire master handler with command processing interface
// Compatible with CDC command bus architecture
// ============================================================================
module one_wire_handler #(
    parameter CLK_FREQ = 60_000_000
)(
    input  wire        clk,
    input  wire        rst_n,

    // Command Bus Interface (from command_processor)
    input  wire [7:0]  cmd_type,
    input  wire [15:0] cmd_length,
    input  wire [7:0]  cmd_data,
    input  wire [15:0] cmd_data_index,
    input  wire        cmd_start,
    input  wire        cmd_data_valid,
    input  wire        cmd_done,

    output wire        cmd_ready,

    // Data Upload Interface (to upload pipeline)
    output wire        upload_active,
    output reg         upload_req,
    output reg  [7:0]  upload_data,
    output reg  [7:0]  upload_source,
    output reg         upload_valid,
    input  wire        upload_ready,

    // 1-Wire Bus
    inout  wire        onewire_io
);

    // ==================== Command Type Codes ====================
    localparam CMD_ONEWIRE_RESET       = 8'h20;  // Reset and detect presence
    localparam CMD_ONEWIRE_WRITE       = 8'h21;  // Write bytes to 1-Wire bus
    localparam CMD_ONEWIRE_READ        = 8'h22;  // Read bytes from 1-Wire bus
    localparam CMD_ONEWIRE_WRITE_READ  = 8'h23;  // Write then read

    // Upload source identifier
    localparam UPLOAD_SOURCE_ONEWIRE = 8'h04;

    // ==================== State Machine ====================
    localparam H_IDLE            = 4'd0;
    localparam H_RESET           = 4'd1;
    localparam H_WAIT_RESET      = 4'd2;
    localparam H_RX_WRITE_DATA   = 4'd3;
    localparam H_WRITE_BYTE      = 4'd4;
    localparam H_WAIT_WRITE_BIT  = 4'd5;
    localparam H_READ_BYTE       = 4'd6;
    localparam H_WAIT_READ_BIT   = 4'd7;
    localparam H_UPLOAD_BYTE     = 4'd8;
    localparam H_RX_WR_HEADER    = 4'd9;  // Receive write_len/read_len for 0x13

    reg [3:0]  handler_state;
    reg [7:0]  bit_counter;       // Bit counter for byte operations (0-7)
    reg [15:0] byte_counter;      // Byte counter
    reg [15:0] bytes_to_process;  // Total bytes to read/write
    reg [7:0]  current_byte;      // Current byte being processed
    reg [7:0]  write_len;         // For CMD_ONEWIRE_WRITE_READ
    reg [7:0]  read_len;          // For CMD_ONEWIRE_WRITE_READ
    reg        header_received;   // Flag for write_len received

    // ==================== 1-Wire Master Interface ====================
    reg        ow_start_reset;
    reg        ow_start_write_bit;
    reg        ow_start_read_bit;
    reg        ow_write_bit_data;

    wire       ow_busy;
    wire       ow_done;
    wire       ow_read_bit_data;
    wire       ow_presence_detected;

    // ==================== TX/RX FIFO ====================
    reg [7:0]  tx_fifo [0:255];
    reg [7:0]  tx_fifo_wr_ptr;
    reg [7:0]  tx_fifo_rd_ptr;
    reg [8:0]  tx_fifo_count;
    wire       tx_fifo_empty = (tx_fifo_count == 0);
    wire       tx_fifo_full  = (tx_fifo_count == 256);
    wire [7:0] tx_fifo_data_out = tx_fifo[tx_fifo_rd_ptr];

    reg [7:0]  rx_fifo [0:255];
    reg [7:0]  rx_fifo_wr_ptr;
    reg [7:0]  rx_fifo_rd_ptr;
    reg [8:0]  rx_fifo_count;
    wire       rx_fifo_empty = (rx_fifo_count == 0);
    wire       rx_fifo_full  = (rx_fifo_count == 256);
    wire [7:0] rx_fifo_data_out = rx_fifo[rx_fifo_rd_ptr];

    // ==================== Control Logic ====================
    // Ready when idle or receiving data into FIFO
    assign cmd_ready = (handler_state == H_IDLE) ||
                       ((handler_state == H_RX_WRITE_DATA || handler_state == H_RX_WR_HEADER) && !tx_fifo_full);

    assign upload_active = (handler_state == H_UPLOAD_BYTE);

    // ==================== Main State Machine ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            handler_state <= H_IDLE;
            byte_counter <= 16'd0;
            bytes_to_process <= 16'd0;
            bit_counter <= 8'd0;
            current_byte <= 8'd0;
            write_len <= 8'd0;
            read_len <= 8'd0;
            header_received <= 1'b0;

            // 1-Wire control signals
            ow_start_reset <= 1'b0;
            ow_start_write_bit <= 1'b0;
            ow_start_read_bit <= 1'b0;
            ow_write_bit_data <= 1'b0;

            // FIFO pointers
            tx_fifo_wr_ptr <= 8'd0;
            tx_fifo_rd_ptr <= 8'd0;
            tx_fifo_count  <= 9'd0;
            rx_fifo_wr_ptr <= 8'd0;
            rx_fifo_rd_ptr <= 8'd0;
            rx_fifo_count  <= 9'd0;

            // Upload interface
            upload_req <= 1'b0;
            upload_data <= 8'd0;
            upload_source <= UPLOAD_SOURCE_ONEWIRE;
            upload_valid <= 1'b0;

        end else begin
            // Default: clear single-cycle pulses
            ow_start_reset <= 1'b0;
            ow_start_write_bit <= 1'b0;
            ow_start_read_bit <= 1'b0;
            upload_valid <= 1'b0;

            case (handler_state)
                // ==================== IDLE ====================
                H_IDLE: begin
                    byte_counter <= 16'd0;
                    bit_counter <= 8'd0;
                    upload_req <= 1'b0;
                    header_received <= 1'b0;

                    if (cmd_start) begin
                        case (cmd_type)
                            CMD_ONEWIRE_RESET: begin
                                // Start reset sequence
                                handler_state <= H_RESET;
                            end

                            CMD_ONEWIRE_WRITE: begin
                                // Prepare to receive write data
                                bytes_to_process <= cmd_length;
                                handler_state <= H_RX_WRITE_DATA;
                            end

                            CMD_ONEWIRE_READ: begin
                                // cmd_length specifies number of bytes to read
                                bytes_to_process <= cmd_length;
                                handler_state <= H_READ_BYTE;
                            end

                            CMD_ONEWIRE_WRITE_READ: begin
                                // First 2 bytes: write_len, read_len
                                handler_state <= H_RX_WR_HEADER;
                            end

                            default: handler_state <= H_IDLE;
                        endcase
                    end
                end

                // ==================== RESET Operation ====================
                H_RESET: begin
                    ow_start_reset <= 1'b1;
                    handler_state <= H_WAIT_RESET;
                end

                H_WAIT_RESET: begin
                    if (ow_done) begin
                        // Reset complete, check presence
                        // Can upload presence status or just return to idle
                        handler_state <= H_IDLE;
                    end
                end

                // ==================== WRITE_READ Header Reception ====================
                H_RX_WR_HEADER: begin
                    if (cmd_data_valid) begin
                        if (!header_received) begin
                            // First byte: write_len
                            write_len <= cmd_data;
                            header_received <= 1'b1;
                        end else begin
                            // Second byte: read_len
                            read_len <= cmd_data;
                            bytes_to_process <= {8'd0, cmd_data};  // write_len

                            // Decide next state
                            if (write_len > 0) begin
                                handler_state <= H_RX_WRITE_DATA;
                            end else if (cmd_data > 0) begin
                                // Only read
                                bytes_to_process <= {8'd0, cmd_data};
                                handler_state <= H_READ_BYTE;
                            end else begin
                                // Invalid command
                                handler_state <= H_IDLE;
                            end
                        end
                    end
                end

                // ==================== Receive Write Data ====================
                H_RX_WRITE_DATA: begin
                    if (cmd_data_valid && !tx_fifo_full) begin
                        tx_fifo[tx_fifo_wr_ptr] <= cmd_data;
                        tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 1;
                        tx_fifo_count <= tx_fifo_count + 1;
                    end

                    if (cmd_done) begin
                        // All data received, start writing bytes
                        handler_state <= H_WRITE_BYTE;
                        bit_counter <= 8'd0;
                        byte_counter <= 16'd0;
                    end
                end

                // ==================== WRITE Byte ====================
                H_WRITE_BYTE: begin
                    if (!ow_busy) begin
                        if (bit_counter == 0) begin
                            if (!tx_fifo_empty) begin
                                // Load next byte from FIFO
                                current_byte <= tx_fifo_data_out;
                                tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 1;
                                tx_fifo_count <= tx_fifo_count - 1;
                            end else if (byte_counter >= bytes_to_process) begin
                                // All bytes written and transmitted
                                if (read_len > 0) begin
                                    // Start read phase
                                    bytes_to_process <= {8'd0, read_len};
                                    byte_counter <= 16'd0;
                                    handler_state <= H_READ_BYTE;
                                end else begin
                                    handler_state <= H_IDLE;
                                end
                            end
                        end

                        if (bit_counter < 8 && (bit_counter > 0 || !tx_fifo_empty || byte_counter < bytes_to_process)) begin
                            // Send next bit (LSB first) only if we have data to send
                            ow_write_bit_data <= current_byte[bit_counter];
                            ow_start_write_bit <= 1'b1;
                            handler_state <= H_WAIT_WRITE_BIT;
                        end else if (bit_counter == 8) begin
                            // Byte complete, reset for next byte
                            bit_counter <= 8'd0;
                            byte_counter <= byte_counter + 1;
                        end
                    end
                end

                H_WAIT_WRITE_BIT: begin
                    if (ow_done) begin
                        bit_counter <= bit_counter + 1;
                        handler_state <= H_WRITE_BYTE;
                    end
                end

                // ==================== READ Byte ====================
                H_READ_BYTE: begin
                    if (!ow_busy) begin
                        if (bit_counter < 8) begin
                            // Start read bit operation
                            ow_start_read_bit <= 1'b1;
                            handler_state <= H_WAIT_READ_BIT;
                        end else begin
                            // Byte complete, store in RX FIFO
                            if (!rx_fifo_full) begin
                                rx_fifo[rx_fifo_wr_ptr] <= current_byte;
                                rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 1;
                                rx_fifo_count <= rx_fifo_count + 1;
                                // Debug output
                                $display("[HANDLER] @%0t: Byte complete = 0x%02X (%b)",
                                         $time, current_byte, current_byte);
                            end

                            bit_counter <= 8'd0;
                            current_byte <= 8'd0;  // Clear for next byte
                            byte_counter <= byte_counter + 1;

                            if (byte_counter >= bytes_to_process - 1) begin
                                // All bytes read, start upload
                                handler_state <= H_UPLOAD_BYTE;
                            end
                            // else: stay in H_READ_BYTE to read next byte
                        end
                    end
                end

                H_WAIT_READ_BIT: begin
                    if (ow_done) begin
                        // Store received bit (LSB first)
                        current_byte[bit_counter] <= ow_read_bit_data;
                        // Debug output
                        $display("[HANDLER] @%0t: Bit[%0d] = %b",
                                 $time, bit_counter, ow_read_bit_data);
                        bit_counter <= bit_counter + 1;
                        handler_state <= H_READ_BYTE;
                    end
                end

                // ==================== UPLOAD Data ====================
                H_UPLOAD_BYTE: begin
                    if (!rx_fifo_empty && upload_ready) begin
                        upload_req <= 1'b1;
                        upload_data <= rx_fifo_data_out;
                        upload_source <= UPLOAD_SOURCE_ONEWIRE;
                        upload_valid <= 1'b1;

                        rx_fifo_rd_ptr <= rx_fifo_rd_ptr + 1;
                        rx_fifo_count <= rx_fifo_count - 1;
                    end

                    if (rx_fifo_empty) begin
                        handler_state <= H_IDLE;
                    end
                end

                default: handler_state <= H_IDLE;
            endcase
        end
    end

    // ==================== 1-Wire Master Instantiation ====================
    one_wire_master #(
        .CLK_FREQ(CLK_FREQ)
    ) u_one_wire_master (
        .clk(clk),
        .rst_n(rst_n),

        .start_reset(ow_start_reset),
        .start_write_bit(ow_start_write_bit),
        .start_read_bit(ow_start_read_bit),
        .write_bit_data(ow_write_bit_data),

        .busy(ow_busy),
        .done(ow_done),
        .read_bit_data(ow_read_bit_data),
        .presence_detected(ow_presence_detected),

        .onewire_io(onewire_io)
    );

endmodule
