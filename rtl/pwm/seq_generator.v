// ============================================================================
// Module:  seq_generator
// Author:  Claude
// Date:    2025-10-24
//
// Description:
// A custom sequence generator that outputs a user-defined bit pattern at
// a configurable base frequency. The sequence can be 1 to 64 bits long,
// and each bit is output at the base frequency rate.
//
// Example:
//   Base frequency = 1MHz (1us per bit)
//   Sequence = 10'b0101010101 (10 bits)
//   Output: Each bit held for 1us, full sequence repeats every 10us (100kHz)
// ============================================================================
module seq_generator #(
    parameter DIVIDER_WIDTH = 16,  // Base frequency divider width
    parameter SEQ_MAX_BITS  = 64   // Maximum sequence length in bits
)(
    input  wire                      clk,        // System clock (e.g., 60MHz)
    input  wire                      rst_n,      // Active-low reset

    // --- Configuration Inputs ---
    input  wire [DIVIDER_WIDTH-1:0]  freq_div,   // Clock divider for base frequency
    input  wire [63:0]               seq_data,   // Sequence data (up to 64 bits)
    input  wire [6:0]                seq_len,    // Sequence length in bits (1-64)
    input  wire                      enable,     // Enable sequence output

    // --- Sequence Output ---
    output reg                       seq_out     // Output sequence bit
);

    // Internal counters and registers
    reg [DIVIDER_WIDTH-1:0] clk_div_counter;    // Clock divider counter
    reg [6:0]               bit_index;          // Current bit position in sequence
    reg                     bit_clk_tick;       // Pulse at base frequency rate

    // Clock divider: generates a tick at the base frequency
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_counter <= 0;
            bit_clk_tick    <= 1'b0;
        end
        else if (!enable) begin
            clk_div_counter <= 0;
            bit_clk_tick    <= 1'b0;
        end
        else begin
            bit_clk_tick <= 1'b0;  // Default: no tick

            if (freq_div == 0) begin
                // Avoid division by zero: if freq_div=0, no output
                clk_div_counter <= 0;
            end
            else if (clk_div_counter < freq_div - 1) begin
                clk_div_counter <= clk_div_counter + 1;
            end
            else begin
                clk_div_counter <= 0;
                bit_clk_tick    <= 1'b1;  // Generate tick
            end
        end
    end

    // Sequence bit indexing and output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_index <= 0;
            seq_out   <= 1'b0;
        end
        else if (!enable) begin
            bit_index <= 0;
            seq_out   <= 1'b0;
        end
        else if (bit_clk_tick) begin
            // Move to next bit in sequence
            if (seq_len == 0) begin
                // Invalid sequence length: output 0
                bit_index <= 0;
                seq_out   <= 1'b0;
            end
            else begin
                // Output current bit from sequence
                seq_out <= seq_data[bit_index];

                // Increment bit index, wrap around at sequence length
                if (bit_index < seq_len - 1) begin
                    bit_index <= bit_index + 1;
                end
                else begin
                    bit_index <= 0;  // Wrap to start of sequence
                end
            end
        end
        // else: hold current output
    end

endmodule
