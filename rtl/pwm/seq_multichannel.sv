// ============================================================================
// Module:  seq_multi_channel
// Author:  Claude
// Date:    2025-10-24
//
// Description:
// Generates 8 independent custom sequence outputs. Each channel can have
// its own base frequency, sequence data, and sequence length.
// Provides a simple write interface to configure any channel.
// ============================================================================
module seq_multi_channel #(
    parameter NUM_CHANNELS  = 8,
    parameter DIVIDER_WIDTH = 16,
    parameter SEQ_MAX_BITS  = 64
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // --- Configuration Write Interface ---
    input  wire [2:0]                 config_ch_index_in,    // Channel to configure (0-7)
    input  wire [DIVIDER_WIDTH-1:0]   config_freq_div_in,    // Base frequency divider
    input  wire [63:0]                config_seq_data_in,    // Sequence bit pattern
    input  wire [6:0]                 config_seq_len_in,     // Sequence length (1-64 bits)
    input  wire                       config_enable_in,      // Enable/disable channel
    input  wire                       config_update_strobe,  // Latch new config (single-cycle pulse)

    // --- Sequence Outputs ---
    output wire [NUM_CHANNELS-1:0]    seq_out_vector
);

// Internal registers to store the configuration for each channel
reg [DIVIDER_WIDTH-1:0] freq_div_regs [0:NUM_CHANNELS-1];
reg [63:0]              seq_data_regs [0:NUM_CHANNELS-1];
reg [6:0]               seq_len_regs  [0:NUM_CHANNELS-1];
reg                     enable_regs   [0:NUM_CHANNELS-1];

integer i;

// Logic to update the configuration registers
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Reset all configurations
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
            freq_div_regs[i] <= 0;
            seq_data_regs[i] <= 64'h0;
            seq_len_regs[i]  <= 0;
            enable_regs[i]   <= 1'b0;
        end
    end else begin
        // If the update strobe is high, latch the new configuration
        // for the selected channel
        if (config_update_strobe) begin
            freq_div_regs[config_ch_index_in] <= config_freq_div_in;
            seq_data_regs[config_ch_index_in] <= config_seq_data_in;
            seq_len_regs[config_ch_index_in]  <= config_seq_len_in;
            enable_regs[config_ch_index_in]   <= config_enable_in;
        end
    end
end

// --- Generate 8 Sequence Generator Instances ---
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin: seq_instances
        // For each channel 'ch', create one seq_generator instance
        seq_generator #(
            .DIVIDER_WIDTH(DIVIDER_WIDTH),
            .SEQ_MAX_BITS(SEQ_MAX_BITS)
        ) u_seq_inst (
            .clk(clk),
            .rst_n(rst_n),
            // Connect inputs to the corresponding storage registers
            .freq_div(freq_div_regs[ch]),
            .seq_data(seq_data_regs[ch]),
            .seq_len(seq_len_regs[ch]),
            .enable(enable_regs[ch]),
            // Connect output to the corresponding bit in the output vector
            .seq_out(seq_out_vector[ch])
        );
    end
endgenerate

endmodule
