`timescale 1ns / 1ps

/*
* DDS Module Testbench
* Date: 2025-09-17
* Description: Comprehensive testbench for DDS module testing
* Tests multiple frequencies and phase offsets
*/

module dds_tb();

    // Testbench parameters
    parameter CLK_PERIOD = 10;          // 100MHz clock (10ns period)
    parameter OUTPUT_WIDTH = 12;        // DDS output width
    parameter PHASE_WIDTH = 32;         // Phase accumulator width
    
    // Test parameters
    parameter NUM_CYCLES = 1000;        // Number of clock cycles to simulate
    parameter FREQ_TEST_COUNT = 4;      // Number of different frequencies to test
    
    // Testbench signals
    reg                       clock;
    reg                       reset;
    reg  [PHASE_WIDTH-1:0]    fre_word;
    reg  [PHASE_WIDTH-1:0]    pha_word;
    wire [OUTPUT_WIDTH-1:0]   wave_sin;
    wire [OUTPUT_WIDTH-1:0]   wave_tri;
    wire [OUTPUT_WIDTH-1:0]   wave_saw;
    
    // Test control signals
    reg [31:0] test_counter;
    reg [2:0]  test_phase;
    reg [31:0] cycle_counter;
    
    // Test frequency values (frequency control words)
    // For 100MHz clock, fre_word = (desired_freq * 2^32) / 100MHz
    reg [PHASE_WIDTH-1:0] test_frequencies [0:FREQ_TEST_COUNT-1];
    reg [PHASE_WIDTH-1:0] test_phases [0:3];
    
    // Initialize test vectors
    initial begin
        // Test frequencies: 1MHz, 5MHz, 10MHz, 15MHz
        test_frequencies[0] = 32'h028F5C29; // ~1MHz
        test_frequencies[1] = 32'h0D49FB83; // ~5MHz  
        test_frequencies[2] = 32'h1A93F706; // ~10MHz
        test_frequencies[3] = 32'h26DDF485; // ~15MHz
        
        // Test phase offsets: 0°, 90°, 180°, 270°
        test_phases[0] = 32'h00000000;      // 0°
        test_phases[1] = 32'h40000000;      // 90°
        test_phases[2] = 32'h80000000;      // 180°
        test_phases[3] = 32'hC0000000;      // 270°
    end
    
    // DUT instantiation
    DDS #(
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .PHASE_WIDTH(PHASE_WIDTH)
    ) dut (
        .clock(clock),
        .reset(reset),
        .fre_word(fre_word),
        .pha_word(pha_word),
        .wave_sin(wave_sin),
        .wave_tri(wave_tri),
        .wave_saw(wave_saw)
    );
    
    // Clock generation
    initial begin
        clock = 0;
        forever #(CLK_PERIOD/2) clock = ~clock;
    end
    
    // Reset generation
    initial begin
        reset = 1;
        #(CLK_PERIOD * 5);
        reset = 0;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        fre_word = 0;
        pha_word = 0;
        test_counter = 0;
        test_phase = 0;
        cycle_counter = 0;
        
        // Wait for reset release
        wait(!reset);
        #(CLK_PERIOD * 2);
        
        $display("=== DDS Module Test Started ===");
        $display("Clock Period: %0d ns", CLK_PERIOD);
        $display("Output Width: %0d bits", OUTPUT_WIDTH);
        $display("Phase Width: %0d bits", PHASE_WIDTH);
        $display("Test Duration: %0d cycles", NUM_CYCLES);
        $display("=====================================");
        
        // Test Phase 1: Basic functionality test with fixed frequency
        test_phase = 1;
        $display("Phase 1: Basic functionality test (1MHz, 0° phase)");
        fre_word = test_frequencies[0];
        pha_word = test_phases[0];
        
        // Run for some cycles
        repeat(100) @(posedge clock);
        
        // Test Phase 2: Frequency sweep test
        test_phase = 2;
        $display("Phase 2: Frequency sweep test");
        for (integer i = 0; i < FREQ_TEST_COUNT; i++) begin
            $display("  Testing frequency %0d: fre_word = 0x%08h", i, test_frequencies[i]);
            fre_word = test_frequencies[i];
            pha_word = test_phases[0]; // 0° phase
            repeat(200) @(posedge clock);
        end
        
        // Test Phase 3: Phase offset test
        test_phase = 3;
        $display("Phase 3: Phase offset test (5MHz frequency)");
        fre_word = test_frequencies[1]; // 5MHz
        for (integer i = 0; i < 4; i++) begin
            $display("  Testing phase %0d: pha_word = 0x%08h", i*90, test_phases[i]);
            pha_word = test_phases[i];
            repeat(150) @(posedge clock);
        end
        
        // Test Phase 4: Combined frequency and phase test
        test_phase = 4;
        $display("Phase 4: Combined frequency and phase test");
        for (integer f = 0; f < FREQ_TEST_COUNT; f++) begin
            for (integer p = 0; p < 4; p++) begin
                $display("  Testing freq %0d, phase %0d°", f, p*90);
                fre_word = test_frequencies[f];
                pha_word = test_phases[p];
                repeat(100) @(posedge clock);
            end
        end
        
        // Test Phase 5: Reset test
        test_phase = 5;
        $display("Phase 5: Reset functionality test");
        fre_word = test_frequencies[2]; // 10MHz
        pha_word = test_phases[1];      // 90°
        repeat(50) @(posedge clock);
        
        reset = 1;
        repeat(5) @(posedge clock);
        reset = 0;
        repeat(50) @(posedge clock);
        
        $display("=== DDS Module Test Completed ===");
        $finish;
    end
    
    // Cycle counter
    always @(posedge clock) begin
        if (reset) begin
            cycle_counter <= 0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    // Output monitoring and validation
    // always @(posedge clock) begin
    //     if (!reset) begin
    //         // Check for valid output ranges (12-bit signed values: -2048 to 2047)
    //         if (wave_sin > 2047 || wave_sin < -2048) begin
    //             $warning("Time %0t: Sine wave output out of range: %d", $time, $signed(wave_sin));
    //         end
            
    //         if (wave_tri > 2047 || wave_tri < -2048) begin
    //             $warning("Time %0t: Triangle wave output out of range: %d", $time, $signed(wave_tri));
    //         end
            
    //         if (wave_saw > 2047 || wave_saw < -2048) begin
    //             $warning("Time %0t: Sawtooth wave output out of range: %d", $time, $signed(wave_saw));
    //         end
    //     end
    // end
    
    // Periodic status reporting
    // always @(posedge clock) begin
    //     if (!reset && (cycle_counter % 500 == 0) && (cycle_counter > 0)) begin
    //         $display("Time %0t: Cycle %0d - Sin: %d, Tri: %d, Saw: %d", 
    //                  $time, cycle_counter, wave_sin, wave_tri, wave_saw);
    //     end
    // end
    
    // VCD dump for waveform analysis
    initial begin
        $dumpfile("dds_tb.vcd");
        $dumpvars(0, dds_tb);
    end
    
    // Optional: Generate test report
    final begin
        $display("\n=== Test Summary ===");
        $display("Total simulation cycles: %0d", cycle_counter);
        $display("Simulation time: %0t", $time);
        $display("Final outputs - Sin: %d, Tri: %d, Saw: %d", wave_sin, wave_tri, wave_saw);
        $display("Test completed successfully!");
    end

endmodule