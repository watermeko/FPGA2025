// ============================================================================
// Module:  pulse_stretcher
// Author:  Gemini
// Date:    2025-09-02
//
// Description:
// Detects a single-cycle input pulse and stretches it into a longer,
// multi-cycle high signal. The duration is configurable.
// ============================================================================
module pulse_stretcher #(
    // Parameter to define how many clock cycles the output should remain high.
    // Defaulting to 25 million, which is 0.5 seconds for a 50MHz clock.
    parameter STRETCH_CYCLES = 25_000_000
)(
    input  wire                           clk,
    input  wire                           rst_n,

    input  wire                           pulse_in,           // The 1-cycle pulse input
    output wire                           stretched_pulse_out // The extended pulse output
);

// Use $clog2 to automatically calculate the required counter width.
localparam COUNTER_WIDTH = $clog2(STRETCH_CYCLES);

// Internal counter register
reg [COUNTER_WIDTH-1:0] counter_reg;

// The output is high whenever the counter is not zero.
assign stretched_pulse_out = (counter_reg > 0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter_reg <= 0;
    end else begin
        if (pulse_in) begin
            // When the input pulse is detected, load the counter.
            counter_reg <= STRETCH_CYCLES - 1;
        end else if (counter_reg > 0) begin
            // If the counter is already running, just count down.
            counter_reg <= counter_reg - 1;
        end
    end
end

endmodule