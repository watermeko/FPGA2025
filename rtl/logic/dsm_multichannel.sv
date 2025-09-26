module dsm_multichannel #(
    parameter NUM_CHANNELS   = 8
) (
    input  wire                       clk,
    input  wire                       rst_n,
    
    // Control signals for each channel
    input  wire [NUM_CHANNELS-1:0]    measure_start,
    input  wire [NUM_CHANNELS-1:0]    measure_pin,
    
    // Output results for each channel
    output wire [NUM_CHANNELS*16-1:0] high_time,
    output wire [NUM_CHANNELS*16-1:0] low_time, 
    output wire [NUM_CHANNELS*16-1:0] period_time,
    output wire [NUM_CHANNELS*16-1:0] duty_cycle,
    output wire [NUM_CHANNELS-1:0]    measure_done
);

// Internal signal arrays
wire [15:0] high_time_array   [NUM_CHANNELS-1:0];
wire [15:0] low_time_array    [NUM_CHANNELS-1:0];
wire [15:0] period_time_array [NUM_CHANNELS-1:0];
wire [15:0] duty_cycle_array  [NUM_CHANNELS-1:0];

// --- Generate 8 dsm Instances ---
genvar ch;
generate
    for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin: dsm_instances
        digital_signal_measure dsm_inst (
            .clk           (clk),
            .rst_n         (rst_n),
            .measure_start (measure_start[ch]),
            .measure_pin   (measure_pin[ch]),
            
            .high_time     (high_time_array[ch]),
            .low_time      (low_time_array[ch]),
            .period_time   (period_time_array[ch]),
            .duty_cycle    (duty_cycle_array[ch]),
            .measure_done  (measure_done[ch])
        );
        
        // Pack array outputs into flattened output vectors
        assign high_time[(ch+1)*16-1:ch*16]   = high_time_array[ch];
        assign low_time[(ch+1)*16-1:ch*16]    = low_time_array[ch];
        assign period_time[(ch+1)*16-1:ch*16] = period_time_array[ch];
        assign duty_cycle[(ch+1)*16-1:ch*16]  = duty_cycle_array[ch];
    end
endgenerate

endmodule