// ============================================================================
// Module:  pwm_multi_channel
// Author:  Gemini
// Date:    2025-09-03
//
// Description:
// Generates 8 independent PWM channels. It contains 8 instances of a single
// PWM generator and provides a simple write interface to update the period
// and duty cycle for any specific channel.
// ============================================================================
module pwm_multi_channel #(
    parameter NUM_CHANNELS   = 8,
    parameter COUNTER_WIDTH  = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // --- Configuration Write Interface ---
    input  wire [2:0]                 config_ch_index_in,  // Channel to configure (0-7)
    input  wire [COUNTER_WIDTH-1:0]   config_period_in,    // New period value
    input  wire [COUNTER_WIDTH-1:0]   config_duty_in,      // New duty value
    input  wire                       config_update_strobe, // Latch new config (single-cycle pulse)

    // --- PWM Outputs ---
    output wire [NUM_CHANNELS-1:0]    pwm_out_vector
);

// Internal registers to store the configuration for each channel
reg [COUNTER_WIDTH-1:0] period_regs [0:NUM_CHANNELS-1];
reg [COUNTER_WIDTH-1:0] duty_regs   [0:NUM_CHANNELS-1];
integer i;

// Logic to update the configuration registers
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset all configurations to 0
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            period_regs[i] <= 0;
            duty_regs[i]   <= 0;
        end
    end else begin
        // If the update strobe is high, latch the new configuration
        // for the selected channel.
        if (config_update_strobe) begin
            period_regs[config_ch_index_in] <= config_period_in;
            duty_regs[config_ch_index_in]   <= config_duty_in;
        end
    end
end

// --- Generate 8 PWM Instances ---
// This is a powerful Verilog construct for creating repetitive hardware.
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin: pwm_instances
        // For each channel 'ch', create one pwm_generator instance
        pwm_generator #(
            .COUNTER_WIDTH(COUNTER_WIDTH)
        ) u_pwm_inst (
            .clk(clk),
            .rst_n(rst_n),
            // Connect its inputs to the corresponding storage register
            .period_in(period_regs[ch]),
            .duty_in(duty_regs[ch]),
            // Connect its output to the corresponding bit in the output vector
            .pwm_out(pwm_out_vector[ch])
        );
    end
endgenerate

endmodule