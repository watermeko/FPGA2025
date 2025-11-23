// ============================================================================
// Module: one_wire_master
// Description: 1-Wire bus master controller
// ============================================================================
module one_wire_master #(
    parameter CLK_FREQ = 60_000_000  // System clock frequency in Hz
)(
    input  wire        clk,
    input  wire        rst_n,

    // Control interface
    input  wire        start_reset,     // Start reset pulse
    input  wire        start_write_bit, // Start write bit operation
    input  wire        start_read_bit,  // Start read bit operation
    input  wire        write_bit_data,  // Data bit to write (0 or 1)

    output reg         busy,            // Operation in progress
    output reg         done,            // Operation completed
    output reg         read_bit_data,   // Data bit read from bus
    output reg         presence_detected, // Presence pulse detected

    // 1-Wire bus (bidirectional)
    inout  wire        onewire_io
);

    // ==================== Timing Parameters (in clock cycles) ====================
    // Dynamically calculated based on CLK_FREQ parameter
    // Standard 1-Wire timings (Dallas/Maxim specification)
    // Note: Use integer division carefully to avoid overflow

    // Calculate cycles for each timing requirement
    localparam RESET_LOW_TIME      = (CLK_FREQ / 1000 * 480 / 1000) - 1;  // 480µs
    localparam RESET_WAIT_TIME     = (CLK_FREQ / 1000 * 70 / 1000) - 1;   // 70µs
    localparam PRESENCE_SAMPLE_TIME = (CLK_FREQ / 1000 * 8 / 1000) - 1;   // 8µs
    localparam RECOVERY_TIME       = (CLK_FREQ / 1000 * 40 / 1000) - 1;   // 40µs

    localparam WRITE_0_LOW_TIME    = (CLK_FREQ / 1000 * 60 / 1000) - 1;   // 60µs
    localparam WRITE_1_LOW_TIME    = (CLK_FREQ / 1000 * 6 / 1000) - 1;    // 6µs
    localparam WRITE_SLOT_TIME     = (CLK_FREQ / 1000 * 65 / 1000) - 1;   // 65µs total slot time
    // Recovery time = slot_time - low_time (calculated dynamically in state machine)

    localparam READ_LOW_TIME       = (CLK_FREQ / 1000 * 6 / 1000) - 1;    // 6µs
    localparam READ_SAMPLE_TIME    = (CLK_FREQ / 1000 * 9 / 1000) - 1;    // 9µs
    localparam READ_RECOVERY       = (CLK_FREQ / 1000 * 55 / 1000) - 1;   // 55µs

    // ==================== State Machine ====================
    localparam ST_IDLE            = 4'd0;
    localparam ST_RESET_LOW       = 4'd1;
    localparam ST_RESET_WAIT      = 4'd2;
    localparam ST_RESET_SAMPLE    = 4'd3;
    localparam ST_RESET_RECOVERY  = 4'd4;
    localparam ST_WRITE_LOW       = 4'd5;
    localparam ST_WRITE_RECOVERY  = 4'd6;
    localparam ST_READ_LOW        = 4'd7;
    localparam ST_READ_SAMPLE     = 4'd8;
    localparam ST_READ_RECOVERY   = 4'd9;

    reg [3:0]  state;
    reg [15:0] timer;

    // ==================== I/O Control ====================
    reg        oe;              // Output enable: 1=drive low, 0=release (pull-up)
    reg        output_val;      // Output value when oe=1

    // Bidirectional port control
    assign onewire_io = oe ? output_val : 1'bz;

    // ==================== Main State Machine ====================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            timer <= 16'd0;
            busy <= 1'b0;
            done <= 1'b0;
            read_bit_data <= 1'b0;
            presence_detected <= 1'b0;
            oe <= 1'b0;
            output_val <= 1'b0;
        end else begin
            // Default: clear done pulse
            done <= 1'b0;

            case (state)
                // ==================== IDLE State ====================
                ST_IDLE: begin
                    busy <= 1'b0;
                    oe <= 1'b0;  // Release bus
                    timer <= 16'd0;

                    if (start_reset) begin
                        state <= ST_RESET_LOW;
                        busy <= 1'b1;
                        presence_detected <= 1'b0;
                    end else if (start_write_bit) begin
                        state <= ST_WRITE_LOW;
                        busy <= 1'b1;
                    end else if (start_read_bit) begin
                        state <= ST_READ_LOW;
                        busy <= 1'b1;
                    end
                end

                // ==================== RESET Sequence ====================
                ST_RESET_LOW: begin
                    oe <= 1'b1;
                    output_val <= 1'b0;  // Pull bus low
                    timer <= timer + 1;

                    if (timer >= RESET_LOW_TIME) begin
                        state <= ST_RESET_WAIT;
                        timer <= 16'd0;
                        oe <= 1'b0;  // Release bus
                    end
                end

                ST_RESET_WAIT: begin
                    oe <= 1'b0;  // Release bus for slave to respond
                    timer <= timer + 1;

                    if (timer >= RESET_WAIT_TIME) begin
                        state <= ST_RESET_SAMPLE;
                        timer <= 16'd0;
                    end
                end

                ST_RESET_SAMPLE: begin
                    timer <= timer + 1;

                    // Sample bus during presence window
                    if (!onewire_io) begin
                        presence_detected <= 1'b1;
                    end

                    if (timer >= PRESENCE_SAMPLE_TIME) begin
                        state <= ST_RESET_RECOVERY;
                        timer <= 16'd0;
                    end
                end

                ST_RESET_RECOVERY: begin
                    timer <= timer + 1;

                    if (timer >= RECOVERY_TIME) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                    end
                end

                // ==================== WRITE Bit Sequence ====================
                ST_WRITE_LOW: begin
                    oe <= 1'b1;
                    output_val <= 1'b0;  // Pull bus low
                    timer <= timer + 1;

                    // Determine low time based on bit value
                    if (write_bit_data == 1'b0) begin
                        // Write 0: long low pulse (60µs) - entire slot time
                        if (timer >= WRITE_0_LOW_TIME) begin
                            state <= ST_WRITE_RECOVERY;
                            timer <= timer;  // Keep cumulative timer running
                            oe <= 1'b0;  // Release bus
                        end
                    end else begin
                        // Write 1: short low pulse (6µs), then release
                        if (timer >= WRITE_1_LOW_TIME) begin
                            state <= ST_WRITE_RECOVERY;
                            timer <= timer;  // Keep cumulative timer running
                            oe <= 1'b0;  // Release bus
                        end
                    end
                end

                ST_WRITE_RECOVERY: begin
                    oe <= 1'b0;  // Keep bus released
                    timer <= timer + 1;

                    // Wait until full slot time has passed (65µs from slot start)
                    if (timer >= WRITE_SLOT_TIME) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                    end
                end

                // ==================== READ Bit Sequence ====================
                ST_READ_LOW: begin
                    oe <= 1'b1;
                    output_val <= 1'b0;  // Pull bus low briefly
                    timer <= timer + 1;

                    if (timer >= READ_LOW_TIME) begin
                        state <= ST_READ_SAMPLE;
                        timer <= 16'd0;
                        oe <= 1'b0;  // Release bus immediately
                    end
                end

                ST_READ_SAMPLE: begin
                    oe <= 1'b0;  // Keep bus released
                    timer <= timer + 1;

                    if (timer >= READ_SAMPLE_TIME) begin
                        // Sample the bus
                        read_bit_data <= onewire_io;
                        // Debug output: record bus level at sampling time
                        $display("[MASTER SAMPLE] @%0t: Sampled bit = %b (bus=%b)",
                                 $time, onewire_io, onewire_io);
                        state <= ST_READ_RECOVERY;
                        timer <= 16'd0;
                    end
                end

                ST_READ_RECOVERY: begin
                    timer <= timer + 1;

                    if (timer >= READ_RECOVERY) begin
                        state <= ST_IDLE;
                        done <= 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
