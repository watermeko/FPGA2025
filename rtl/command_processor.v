// ============================================================================
// Module:  command_processor (UPDATED for Multi-Channel PWM)
// ============================================================================
module command_processor#(
        parameter PAYLOAD_ADDR_WIDTH = 8
    )(
        input  wire                           clk,
        input  wire                           rst_n,
        input  wire                           parse_done,
        input  wire [7:0]                     cmd_out,
        input  wire [7:0]                     payload_read_data,

        output reg                            led_out,
        output reg [PAYLOAD_ADDR_WIDTH-1:0]   payload_read_addr,

        // *** NEW: Interface to drive the multi-channel PWM module ***
        output reg [2:0]                      pwm_config_ch_index_out,
        output reg [15:0]                     pwm_config_period_out,
        output reg [15:0]                     pwm_config_duty_out,
        output reg                            pwm_config_update_strobe // The crucial pulse signal
    );

    // FSM States
    localparam S_IDLE        = 3'd0;
    localparam S_READ_CH     = 3'd1;
    localparam S_READ_PERIOD_H = 3'd2;
    localparam S_READ_PERIOD_L = 3'd3;
    localparam S_READ_DUTY_H   = 3'd4;
    localparam S_READ_DUTY_L   = 3'd5;
    localparam S_EXECUTE     = 3'd6;

    // Internal Registers
    reg [2:0]  state;
    reg [2:0]  ch_temp;       // To store the channel index
    reg [15:0] period_temp, duty_temp;

    // 在模块内部添加边沿检测
    reg parse_done_d1;
    wire parse_done_edge;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_done_d1 <= 1'b0;
        end
        else begin
            parse_done_d1 <= parse_done;
        end
    end

    assign parse_done_edge = parse_done & ~parse_done_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            led_out <= 1'b0;
            payload_read_addr <= 0;
            pwm_config_update_strobe <= 1'b0;
            pwm_config_ch_index_out <= 0;
            pwm_config_period_out <= 0;
            pwm_config_duty_out <= 0;
        end
        else begin
            // *** IMPORTANT: Strobe must be a single-cycle pulse ***
            // Default to low, only set high for one cycle in the S_EXECUTE state.
            pwm_config_update_strobe <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (parse_done_edge) begin
                        case (cmd_out)
                            8'hFF:
                                led_out <= ~led_out;
                            8'h04: begin
                                payload_read_addr <= 0; // Read address 0 (Channel)
                                state <= S_READ_CH;
                            end
                        endcase
                    end
                end

                S_READ_CH: begin
                    ch_temp <= payload_read_data[2:0]; // Latch the channel number (only 3 bits needed for 0-7)
                    payload_read_addr <= 1; // Set address to read Period High byte
                    state <= S_READ_PERIOD_H;
                end

                S_READ_PERIOD_H: begin
                    period_temp[15:8] <= payload_read_data;
                    payload_read_addr <= 2;
                    state <= S_READ_PERIOD_L;
                end

                S_READ_PERIOD_L: begin
                    period_temp[7:0] <= payload_read_data;
                    payload_read_addr <= 3;
                    state <= S_READ_DUTY_H;
                end

                S_READ_DUTY_H: begin
                    duty_temp[15:8] <= payload_read_data;
                    payload_read_addr <= 4;
                    state <= S_READ_DUTY_L;
                end

                S_READ_DUTY_L: begin
                    duty_temp[7:0] <= payload_read_data;
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    // All data is collected. Now, drive the PWM config interface for one cycle.
                    pwm_config_ch_index_out <= ch_temp;
                    pwm_config_period_out   <= period_temp;
                    pwm_config_duty_out     <= duty_temp;
                    pwm_config_update_strobe<= 1'b1; // Assert the strobe!

                    state <= S_IDLE; // Return to idle
                end
            endcase
        end
    end
endmodule
