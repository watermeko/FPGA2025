`timescale 1ns/1ps

module digital_signal_measure_tb();

    // Test signal definitions
    reg clk;
    reg rst_n;
    reg measure_start;
    reg measure_pin;
    
    wire [15:0] high_time;
    wire [15:0] low_time;
    wire [15:0] period_time;
    wire [15:0] duty_cycle;
    wire measure_done;
    
    // Clock period parameter
    parameter CLK_PERIOD = 20; // 20ns = 50MHz
    
    // Instantiate DUT
    digital_signal_measure dut (
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
    
    // Task: Generate test signal with specified duty cycle and period
    task generate_test_signal;
        input [15:0] high_cycles;
        input [15:0] low_cycles;
        integer i;
        begin
            // Generate one complete period of test signal
            measure_pin = 1'b1;
            for (i = 0; i < high_cycles; i = i + 1) begin
                @(posedge clk);
            end
            
            measure_pin = 1'b0;
            for (i = 0; i < low_cycles; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask
    
    // Task: Wait for measurement completion and check results
    task check_results;
        input [15:0] expected_high;
        input [15:0] expected_low;
        input [15:0] expected_period;
        input [15:0] expected_duty;
        begin
            // Wait for measurement completion
            wait(measure_done == 1'b1);
            
            #(CLK_PERIOD * 2); // Wait two clock cycles to ensure result stability
            
            $display("=== Measurement Results ===");
            $display("Expected: high=%d, low=%d, period=%d, duty=%d%%", 
                     expected_high, expected_low, expected_period, expected_duty);
            $display("Actual:   high=%d, low=%d, period=%d, duty=%d%%", 
                     high_time, low_time, period_time, duty_cycle);
            
            // Check results (allow 1 clock cycle tolerance)
            if ((high_time >= expected_high - 1) && (high_time <= expected_high + 1))
                $display("✓ High time measurement PASS");
            else
                $display("✗ High time measurement FAIL");
                
            if ((low_time >= expected_low - 1) && (low_time <= expected_low + 1))
                $display("✓ Low time measurement PASS");
            else
                $display("✗ Low time measurement FAIL");
                
            if ((period_time >= expected_period - 2) && (period_time <= expected_period + 2))
                $display("✓ Period time measurement PASS");
            else
                $display("✗ Period time measurement FAIL");
                
            if ((duty_cycle >= expected_duty - 2) && (duty_cycle <= expected_duty + 2))
                $display("✓ Duty cycle measurement PASS");
            else
                $display("✗ Duty cycle measurement FAIL");
            
            $display("=============================\n");
        end
    endtask
    
    // Main test procedure
    initial begin
        // Initialize signals
        rst_n = 0;
        measure_start = 0;
        measure_pin = 0;
        
        $display("Starting Digital Signal Measurement Test");
        
        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        // Test 1: 50% duty cycle, 100 clock cycles period
        $display("\n--- Test 1: 50%% duty cycle, 100 clock cycles period ---");
        measure_start = 1;
        #(CLK_PERIOD * 2);
        
        fork
            // Generate test signal thread
            begin
                repeat(2) begin // Generate 2 periods to ensure complete measurement
                    generate_test_signal(50, 50);
                end
            end
            
            // Check results thread
            begin
                check_results(50, 50, 100, 50);
            end
        join
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        // Test 2: 25% duty cycle, 200 clock cycles period
        $display("\n--- Test 2: 25%% duty cycle, 200 clock cycles period ---");
        measure_start = 1;
        #(CLK_PERIOD * 2);
        
        fork
            begin
                repeat(2) begin
                    generate_test_signal(50, 150);
                end
            end
            
            begin
                check_results(50, 150, 200, 25);
            end
        join
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        // Test 3: 75% duty cycle, 80 clock cycles period
        $display("\n--- Test 3: 75%% duty cycle, 80 clock cycles period ---");
        measure_start = 1;
        #(CLK_PERIOD * 2);
        
        fork
            begin
                repeat(2) begin
                    generate_test_signal(60, 20);
                end
            end
            
            begin
                check_results(60, 20, 80, 75);
            end
        join
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        // Test 4: 10% duty cycle, 500 clock cycles period
        $display("\n--- Test 4: 10%% duty cycle, 500 clock cycles period ---");
        measure_start = 1;
        #(CLK_PERIOD * 2);
        
        fork
            begin
                repeat(2) begin
                    generate_test_signal(50, 450);
                end
            end
            
            begin
                check_results(50, 450, 500, 10);
            end
        join
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        // Test 5: 90% duty cycle, 60 clock cycles period
        $display("\n--- Test 5: 90%% duty cycle, 60 clock cycles period ---");
        measure_start = 1;
        #(CLK_PERIOD * 2);
        
        fork
            begin
                repeat(2) begin
                    generate_test_signal(54, 6);
                end
            end
            
            begin
                check_results(54, 6, 60, 90);
            end
        join
        
        measure_start = 0;
        #(CLK_PERIOD * 10);
        
        $display("All tests completed!");
        $finish;
    end
    
    // Monitor signal changes (optional)
    initial begin
        $monitor("Time=%0t, State=%b, measure_pin=%b, high_time=%d, low_time=%d, period_time=%d, duty_cycle=%d%%, done=%b", 
                 $time, dut.state, measure_pin, high_time, low_time, period_time, duty_cycle, measure_done);
    end
    
    // Generate waveform file
    initial begin
        $dumpfile("digital_signal_measure_tb.vcd");
        $dumpvars(0, digital_signal_measure_tb);
    end

endmodule