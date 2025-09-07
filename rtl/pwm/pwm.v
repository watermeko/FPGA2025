// ============================================================================
// Module:  pwm_generator
// Author:  Gemini
// Date:    2025-09-03
//
// Description:
// A simple PWM signal generator. It uses a counter and compares it against
// the period and duty cycle values to generate a PWM waveform.
// ============================================================================
module pwm_generator #(
        parameter COUNTER_WIDTH = 16
    )(
        input  wire                       clk,
        input  wire                       rst_n,

        // --- Configuration Inputs ---
        input  wire [COUNTER_WIDTH-1:0]   period_in, // PWM period in clock cycles
        input  wire [COUNTER_WIDTH-1:0]   duty_in,   // PWM high-time in clock cycles

        // --- PWM Output ---
        output reg                        pwm_out
    );

    // Internal counter
    reg [COUNTER_WIDTH-1:0] counter_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_reg <= 0;
            pwm_out     <= 1'b0;
        end
        else begin
            // Counter logic: count up to the period, then reset
            if (counter_reg < period_in - 1) begin
                counter_reg <= counter_reg + 1;
            end
            else begin
                counter_reg <= 0;
            end

            // PWM output logic: high when counter is less than the duty value
            if (counter_reg < duty_in) begin
                pwm_out <= 1'b1;
            end
            else begin
                pwm_out <= 1'b0;
            end
        end
    end

endmodule
