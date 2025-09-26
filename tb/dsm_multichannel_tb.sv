`timescale 1ns/1ps

module dsm_multichannel_tb();

    // Parameters
    parameter NUM_CHANNELS = 8;
    parameter CLK_PERIOD = 20; // 20ns = 50MHz
    
    // Test signal definitions
    reg clk;
    reg rst_n;
    reg [NUM_CHANNELS-1:0] measure_start;
    reg [NUM_CHANNELS-1:0] measure_pin;
    
    wire [NUM_CHANNELS*16-1:0] high_time;
    wire [NUM_CHANNELS*16-1:0] low_time;
    wire [NUM_CHANNELS*16-1:0] period_time;
    wire [NUM_CHANNELS*16-1:0] duty_cycle;
    wire [NUM_CHANNELS-1:0] measure_done;
    
    // Helper arrays for easier access
    wire [15:0] high_time_ch   [NUM_CHANNELS-1:0];
    wire [15:0] low_time_ch    [NUM_CHANNELS-1:0];
    wire [15:0] period_time_ch [NUM_CHANNELS-1:0];
    wire [15:0] duty_cycle_ch  [NUM_CHANNELS-1:0];
    
    // Unpack flattened outputs to arrays
    genvar i;
    generate
        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin: unpack_outputs
            assign high_time_ch[i]   = high_time[(i+1)*16-1:i*16];
            assign low_time_ch[i]    = low_time[(i+1)*16-1:i*16];
            assign period_time_ch[i] = period_time[(i+1)*16-1:i*16];
            assign duty_cycle_ch[i]  = duty_cycle[(i+1)*16-1:i*16];
        end
    endgenerate
    
    // Instantiate DUT
    dsm_multichannel #(
        .NUM_CHANNELS(NUM_CHANNELS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .measure_start(measure_start),
        .measure_pin(measure_pin),
        .high_time(high_time),
        .low_time(low_time),
        .period_time(period_time),
        .duty_cycle(duty_cycle),
        .measure_done(measure_done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Task: Generate test signal for specific channel
    task generate_test_signal_ch;
        input integer channel;
        input [15:0] high_cycles;
        input [15:0] low_cycles;
        integer i;
        begin
            // Generate one complete period of test signal
            measure_pin[channel] = 1'b1;
            for (i = 0; i < high_cycles; i = i + 1) begin
                @(posedge clk);
            end
            
            measure_pin[channel] = 1'b0;
            for (i = 0; i < low_cycles; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask
    
    // Task: Wait for specific channel measurement completion and check results
    task check_channel_results;
        input integer channel;
        input [15:0] expected_high;
        input [15:0] expected_low;
        input [15:0] expected_period;
        input [15:0] expected_duty;
        begin
            // Wait for measurement completion
            wait(measure_done[channel] == 1'b1);
            
            #(CLK_PERIOD * 2); // Wait two clock cycles to ensure result stability
            
            $display("=== Channel %0d Measurement Results ===", channel);
            $display("Expected: high=%d, low=%d, period=%d, duty=%d%%", 
                     expected_high, expected_low, expected_period, expected_duty);
            $display("Actual:   high=%d, low=%d, period=%d, duty=%d%%", 
                     high_time_ch[channel], low_time_ch[channel], 
                     period_time_ch[channel], duty_cycle_ch[channel]);
            
            // Check results (allow 1-2 clock cycle tolerance)
            if ((high_time_ch[channel] >= expected_high - 1) && (high_time_ch[channel] <= expected_high + 1))
                $display("✓ Channel %0d High time measurement PASS", channel);
            else
                $display("✗ Channel %0d High time measurement FAIL", channel);
                
            if ((low_time_ch[channel] >= expected_low - 1) && (low_time_ch[channel] <= expected_low + 1))
                $display("✓ Channel %0d Low time measurement PASS", channel);
            else
                $display("✗ Channel %0d Low time measurement FAIL", channel);
                
            if ((period_time_ch[channel] >= expected_period - 2) && (period_time_ch[channel] <= expected_period + 2))
                $display("✓ Channel %0d Period time measurement PASS", channel);
            else
                $display("✗ Channel %0d Period time measurement FAIL", channel);
                
            if ((duty_cycle_ch[channel] >= expected_duty - 2) && (duty_cycle_ch[channel] <= expected_duty + 2))
                $display("✓ Channel %0d Duty cycle measurement PASS", channel);
            else
                $display("✗ Channel %0d Duty cycle measurement FAIL", channel);
            
            $display("==========================================\n");
        end
    endtask
    
    // Task: Test single channel
    task test_single_channel;
        input integer channel;
        input [15:0] high_cycles;
        input [15:0] low_cycles;
        input [15:0] expected_duty;
        begin
            $display("\n--- Testing Channel %0d: %0d%% duty cycle, %0d clock cycles period ---", 
                     channel, expected_duty, high_cycles + low_cycles);
            
            measure_start[channel] = 1;
            #(CLK_PERIOD * 2);
            
            fork
                // Generate test signal thread
                begin
                    repeat(2) begin // Generate 2 periods to ensure complete measurement
                        generate_test_signal_ch(channel, high_cycles, low_cycles);
                    end
                end
                
                // Check results thread
                begin
                    check_channel_results(channel, high_cycles, low_cycles, 
                                        high_cycles + low_cycles, expected_duty);
                end
            join
            
            measure_start[channel] = 0;
            #(CLK_PERIOD * 10);
        end
    endtask
    
    // Main test procedure
    initial begin
        // Initialize signals
        rst_n = 0;
        measure_start = 0;
        measure_pin = 0;
        
        $display("Starting Multi-Channel Digital Signal Measurement Test");
        $display("Number of channels: %0d", NUM_CHANNELS);
        
        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        // Test each channel individually with different parameters
        test_single_channel(0, 50, 50, 50);   // 50% duty cycle
        test_single_channel(1, 25, 75, 25);   // 25% duty cycle
        test_single_channel(2, 75, 25, 75);   // 75% duty cycle
        test_single_channel(3, 10, 90, 10);   // 10% duty cycle
        test_single_channel(4, 90, 10, 90);   // 90% duty cycle
        test_single_channel(5, 40, 60, 40);   // 40% duty cycle
        test_single_channel(6, 60, 40, 60);   // 60% duty cycle
        test_single_channel(7, 80, 20, 80);   // 80% duty cycle
        
        // Test multiple channels simultaneously
        $display("\n=== Multi-Channel Simultaneous Test ===");
        
        // Start all channels
        measure_start = 8'hFF; // All channels
        #(CLK_PERIOD * 2);
        
        // Generate different signals on each channel simultaneously
        fork
            begin // Channel 0: 50% duty
                repeat(3) generate_test_signal_ch(0, 100, 100);
            end
            begin // Channel 1: 25% duty
                repeat(3) generate_test_signal_ch(1, 50, 150);
            end
            begin // Channel 2: 75% duty
                repeat(3) generate_test_signal_ch(2, 150, 50);
            end
            begin // Channel 3: 33% duty
                repeat(3) generate_test_signal_ch(3, 60, 120);
            end
            begin // Channel 4: 66% duty
                repeat(3) generate_test_signal_ch(4, 120, 60);
            end
            begin // Channel 5: 20% duty
                repeat(3) generate_test_signal_ch(5, 40, 160);
            end
            begin // Channel 6: 80% duty
                repeat(3) generate_test_signal_ch(6, 160, 40);
            end
            begin // Channel 7: 90% duty
                repeat(3) generate_test_signal_ch(7, 180, 20);
            end
        join
        
        // Wait for all channels to complete
        wait(&measure_done == 1'b1); // Wait for all bits to be 1
        #(CLK_PERIOD * 5);
        
        // Display all results
        $display("\n=== All Channels Results Summary ===");
        for (int ch = 0; ch < NUM_CHANNELS; ch++) begin
            $display("Channel %0d: high=%d, low=%d, period=%d, duty=%d%%, done=%b", 
                     ch, high_time_ch[ch], low_time_ch[ch], 
                     period_time_ch[ch], duty_cycle_ch[ch], measure_done[ch]);
        end
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        $display("\nAll multi-channel tests completed!");
        $finish;
    end
    
    // Monitor important signals
    initial begin
        $monitor("Time=%0t, measure_start=%b, measure_done=%b", 
                 $time, measure_start, measure_done);
    end
    
    // Generate waveform file
    initial begin
        $dumpfile("dsm_multichannel_tb.vcd");
        $dumpvars(0, dsm_multichannel_tb);
    end

endmodule