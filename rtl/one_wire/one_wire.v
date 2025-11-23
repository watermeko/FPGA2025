module one_wire(
    inout led_port,
    input wire clk,
    output wire [3 : 0] state_out,
    output synchro_success_out,
    output wire [0 : 7] ssss,
    output wire b_count,
    output wire by_count,
    output wire divided_clk,
    output wire test_2_byte,
    output wire test_synchro,
    output wire [0 : 15] mpcd,
    output wire tocntr,
    output wire error
);

// ============================================================================
// Register declarations (must come before assign statements)
// ============================================================================

// Description of bidir port
reg oe;
reg ctrl_reg;
reg inout_reg;

// Some counters
reg [13:0] presence_first_counter = 14'b0;
reg [7:0] write_bit_timeslot_counter = 8'd0;
reg [15:0] timeout_counter = 16'd0;
reg [2:0] bit_counter = 3'd0;
reg [3:0] byte_counter = 4'd0;

// Description of clock divider
reg [4:0] counter_divider = 5'd0;
reg reg_divided_clk = 0;

// Some registers
reg err_reg = 1'd0;
reg [15:0] out_reg;
reg [7:0] input_byte;

// State machine registers
reg [3:0] state = 4'd0;
reg synchro_success = 1'd0;

// Flags
reg [3:0] flag;
reg [15:0] control_register;

reg [6:0] quantity_of_bytes;

// test pins
reg test_start_synchro_pulse;

// ============================================================================
// Parameters and localparams
// ============================================================================

// States of state machine
localparam PRE_IDLE_STATE        = 4'd0;
localparam IDLE_STATE            = 4'd1;
localparam MASTER_PULSE          = 4'd2;
localparam MASTER_PULSE_WAIT     = 4'd3;
localparam MASTER_DROP           = 4'd4;
localparam SLAVE_PRESENCE_PULSE  = 4'd5;
localparam WAITING_FOR_VCC       = 4'd6;
localparam WAITING_FOR_THE_BIT   = 4'd7;
localparam FIRST_HALF_TS         = 4'd8;
localparam SECOND_HALF_TS        = 4'd9;
localparam END_BYTE              = 4'd10;
localparam ERR                   = 4'd11;

// Number of bytes
localparam NUMBER_OF_BYTES       = 4'd10;

// Timings in clock_periods (based on 25MHz clock)
localparam MASTER_PRESENCE_PULSE_TIMING = 14'd11500;  // ~460 us (allow some margin)
localparam PRESENCE_FREE_LINE_TIMING    = 14'd1125;   // 45 us
localparam SLAVE_PRESENCE_PULSE_TIMING  = 14'd6000;   // 240 us
localparam TIMEOUT                      = 16'd30000;  // 1.2ms
localparam LINE_SETUP_TIMING            = 14'd15;     // 15 clocks
localparam HALF_TIMESLOT_TIMING         = 14'd600;    // Timeout timing in clocks

localparam READ_OR_WRITE = 0;
parameter FIRST_BIT_OF_QUANTITY = 1;

// ============================================================================
// Assign statements (after all register declarations)
// ============================================================================

// Assigns to view in signalTap
assign mpcd = control_register;
assign state_out = state;
assign synchro_success_out = synchro_success;

// Assign to view data reg in signalTap
assign ssss[0] = input_byte[0];
assign ssss[1] = input_byte[1];
assign ssss[2] = input_byte[2];
assign ssss[3] = input_byte[3];
assign ssss[4] = input_byte[4];
assign ssss[5] = input_byte[5];
assign ssss[6] = input_byte[6];
assign ssss[7] = input_byte[7];

// Bidirectional port control
assign led_port = (oe) ? inout_reg : 1'bz;

assign divided_clk = reg_divided_clk;
assign b_count = bit_counter[0];
assign error = err_reg;

// ============================================================================
// Initial block
// ============================================================================

initial begin
    oe = 1'd0;
    flag = 4'd0;
    control_register = 16'd0;
    quantity_of_bytes = 7'd0;
end

// ============================================================================
// Clock divider for debug
// ============================================================================

always @(posedge clk) begin
    ctrl_reg <= led_port;
    counter_divider <= counter_divider + 5'd1;
    if ((reg_divided_clk) && (counter_divider == 5'd10)) begin
        counter_divider <= 5'd0;
        reg_divided_clk <= 0;
    end
    if ((!reg_divided_clk) && (counter_divider == 5'd10)) begin
        counter_divider <= 5'd0;
        reg_divided_clk <= 1;
    end
end

// ============================================================================
// FSM synchro_pulse - Main state machine
// ============================================================================

always @(posedge clk) begin
    case (state)
        PRE_IDLE_STATE: begin  // State 0 - Wait for bus to be high
            oe <= 1'd0;
            if (ctrl_reg) begin
                presence_first_counter <= presence_first_counter + 14'd1;
                if (presence_first_counter == 14'd100) begin
                    presence_first_counter <= 14'd0;
                    state <= IDLE_STATE;
                end
            end
            else begin
                state <= PRE_IDLE_STATE;
            end
        end

        IDLE_STATE: begin  // State 1 - Idle, waiting for master reset pulse
            oe <= 1'd0;
            presence_first_counter <= 14'd0;
            if (!ctrl_reg & !synchro_success)
                state <= MASTER_PULSE;
        end

        MASTER_PULSE: begin  // State 2 - Detecting master reset pulse
            oe <= 1'd0;
            presence_first_counter <= presence_first_counter + 14'd1;
            if (presence_first_counter == MASTER_PRESENCE_PULSE_TIMING) begin
                state <= MASTER_PULSE_WAIT;
                presence_first_counter <= 14'd0;
            end
            else begin
                if (ctrl_reg) begin  // If bus goes high too early, restart
                    state <= IDLE_STATE;
                    presence_first_counter <= 14'd0;
                end
            end
        end

        MASTER_PULSE_WAIT: begin  // State 3 - Wait for master to release bus
            oe <= 1'd0;
            presence_first_counter <= presence_first_counter + 14'd1;
            if (ctrl_reg) begin
                presence_first_counter <= 14'd0;
                state <= MASTER_DROP;
            end
            else begin
                if (presence_first_counter == TIMEOUT) begin  // Timeout - go to error
                    state <= ERR;
                    presence_first_counter <= 14'd0;
                end
            end
        end

        MASTER_DROP: begin  // State 4 - Master released bus, wait before presence pulse
            oe <= 1'd0;
            presence_first_counter <= presence_first_counter + 14'd1;
            if (presence_first_counter == PRESENCE_FREE_LINE_TIMING) begin
                state <= SLAVE_PRESENCE_PULSE;
                presence_first_counter <= 14'd0;
            end
            if ((presence_first_counter != PRESENCE_FREE_LINE_TIMING) && !led_port) begin
                state <= ERR;
                presence_first_counter <= 14'd0;
            end
        end

        SLAVE_PRESENCE_PULSE: begin  // State 5 - Send presence pulse
            oe <= 1'd1;
            inout_reg <= 1'd0;
            presence_first_counter <= presence_first_counter + 14'd1;
            if (presence_first_counter == SLAVE_PRESENCE_PULSE_TIMING) begin
                state <= WAITING_FOR_VCC;
                presence_first_counter <= 14'd0;
                oe <= 1'd0;
            end
        end

        WAITING_FOR_VCC: begin  // State 6 - Wait for bus to go high
            presence_first_counter <= presence_first_counter + 14'd1;
            oe <= 1'd0;
            if (ctrl_reg) begin
                state <= WAITING_FOR_THE_BIT;
                presence_first_counter <= 14'd0;
            end
            if (!ctrl_reg) begin
                if (presence_first_counter == TIMEOUT) begin
                    state <= ERR;
                    presence_first_counter <= 14'd0;
                end
                else begin
                    state <= WAITING_FOR_VCC;
                end
            end
        end

        WAITING_FOR_THE_BIT: begin  // State 7 - Wait for start of bit slot
            oe <= 1'd0;
            if (!ctrl_reg) begin
                presence_first_counter <= 14'd0;
                state <= FIRST_HALF_TS;
            end
        end

        FIRST_HALF_TS: begin  // State 8 - First half of time slot
            presence_first_counter <= presence_first_counter + 14'd1;
            if (presence_first_counter != 14'd800) begin
                state <= FIRST_HALF_TS;
            end
            if (presence_first_counter == 14'd800) begin
                presence_first_counter <= 14'd0;
                input_byte[7 - bit_counter] <= led_port;
                if (ctrl_reg) begin
                    bit_counter <= bit_counter + 3'd1;
                    if (bit_counter == 3'd7) begin
                        state <= END_BYTE;
                    end
                    else begin
                        state <= WAITING_FOR_VCC;
                    end
                end
                else begin
                    state <= SECOND_HALF_TS;
                end
            end
        end

        SECOND_HALF_TS: begin  // State 9 - Second half of time slot
            presence_first_counter <= presence_first_counter + 14'd1;
            if (ctrl_reg) begin
                bit_counter <= bit_counter + 3'd1;
                presence_first_counter <= 14'd0;
                if (bit_counter == 3'd7) begin
                    state <= END_BYTE;
                    byte_counter <= byte_counter + 4'd1;
                end
                else begin
                    state <= WAITING_FOR_VCC;
                end
            end
            if (presence_first_counter == 14'd1000) begin
                presence_first_counter <= 14'd0;
                state <= ERR;
            end
        end

        END_BYTE: begin  // State 10 - End of byte received
            presence_first_counter <= presence_first_counter + 14'd1;
            if (presence_first_counter == 14'd100) begin
                if (flag == 4'd0) begin
                    flag <= 4'd1;
                    control_register[READ_OR_WRITE] <= input_byte[READ_OR_WRITE];
                    control_register[7:1] <= input_byte[7:1];
                end
                if (flag == 4'd1) begin
                    flag <= 4'd2;
                    control_register[15:8] <= input_byte[7:0];
                end

                byte_counter <= byte_counter + 4'd1;
                bit_counter <= 3'd0;
                if (byte_counter == NUMBER_OF_BYTES) begin
                    byte_counter <= 4'd0;
                    state <= PRE_IDLE_STATE;
                    synchro_success <= 1'd0;
                    presence_first_counter <= 14'd0;
                end
                else begin
                    state <= WAITING_FOR_VCC;
                    presence_first_counter <= 14'd0;
                end
            end
        end

        ERR: begin  // State 11 - Error state
            err_reg <= 1'd1;
            state <= PRE_IDLE_STATE;
        end

        default: begin
            state <= PRE_IDLE_STATE;
        end
    endcase
end

endmodule
