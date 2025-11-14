// ============================================================================
// Testbench: seq_generator_tb
// Author:    Claude
// Date:      2025-10-24
//
// Description:
// Testbench for the custom sequence generator module.
// Tests various sequence patterns and base frequencies.
// ============================================================================
`timescale 1ns / 1ps

module seq_generator_tb;

    // Parameters
    parameter CLK_PERIOD = 16.67;  // 60MHz clock (16.67ns period)

    // Testbench signals
    reg         clk;
    reg         rst_n;
    reg  [15:0] freq_div;
    reg  [63:0] seq_data;
    reg  [6:0]  seq_len;
    reg         enable;
    wire        seq_out;

    // Instantiate the sequence generator
    seq_generator #(
        .DIVIDER_WIDTH(16),
        .SEQ_MAX_BITS(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .freq_div(freq_div),
        .seq_data(seq_data),
        .seq_len(seq_len),
        .enable(enable),
        .seq_out(seq_out)
    );

    // Clock generation: 60MHz
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Test sequence
    initial begin
        // Initialize signals
        rst_n    = 0;
        freq_div = 0;
        seq_data = 0;
        seq_len  = 0;
        enable   = 0;

        // Apply reset
        #100;
        rst_n = 1;
        #100;

        // ========================================
        // Test 1: 10-bit sequence 0101010101 at 1MHz base frequency
        // ========================================
        $display("=== Test 1: 10-bit alternating pattern at 1MHz ===");
        $display("System clock: 60MHz");
        $display("Base frequency: 1MHz (freq_div = 60)");
        $display("Sequence: 0101010101 (10 bits)");
        $display("Expected output frequency: 100kHz (10us period)");

        freq_div = 16'd60;           // 60MHz / 60 = 1MHz
        seq_data = 64'h0000000000000155;  // 0101010101 in hex (LSB: bit 0)
        seq_len  = 7'd10;            // 10 bits
        enable   = 1;

        // Run for 100us to see ~10 complete sequences
        #100000;

        // ========================================
        // Test 2: 8-bit sequence 11001100 at 2MHz base frequency
        // ========================================
        $display("\n=== Test 2: 8-bit pattern at 2MHz ===");
        $display("Base frequency: 2MHz (freq_div = 30)");
        $display("Sequence: 11001100 (8 bits)");
        $display("Expected output frequency: 250kHz (4us period)");

        enable   = 0;
        #1000;

        freq_div = 16'd30;           // 60MHz / 30 = 2MHz
        seq_data = 64'h00000000000000CC;  // 11001100
        seq_len  = 7'd8;             // 8 bits
        enable   = 1;

        #50000;

        // ========================================
        // Test 3: Single bit toggle (1-bit sequence) at 500kHz
        // ========================================
        $display("\n=== Test 3: 1-bit sequence (simple toggle) ===");
        $display("Base frequency: 500kHz (freq_div = 120)");
        $display("Sequence: 1 (1 bit)");
        $display("Expected output frequency: 500kHz");

        enable   = 0;
        #1000;

        freq_div = 16'd120;          // 60MHz / 120 = 500kHz
        seq_data = 64'h0000000000000001;  // Just '1'
        seq_len  = 7'd1;             // 1 bit
        enable   = 1;

        #30000;

        // ========================================
        // Test 4: 16-bit sequence at 4MHz
        // ========================================
        $display("\n=== Test 4: 16-bit pattern at 4MHz ===");
        $display("Base frequency: 4MHz (freq_div = 15)");
        $display("Sequence: 1010101011110000 (16 bits)");
        $display("Expected output frequency: 250kHz (4us period)");

        enable   = 0;
        #1000;

        freq_div = 16'd15;           // 60MHz / 15 = 4MHz
        seq_data = 64'h000000000000AAF0;  // 1010101011110000
        seq_len  = 7'd16;            // 16 bits
        enable   = 1;

        #40000;

        // ========================================
        // Test 5: Disable test
        // ========================================
        $display("\n=== Test 5: Disable output ===");
        enable = 0;
        #10000;

        // ========================================
        // Test 6: Maximum 64-bit sequence
        // ========================================
        $display("\n=== Test 6: 64-bit maximum length sequence ===");
        $display("Base frequency: 6MHz (freq_div = 10)");
        $display("Sequence length: 64 bits");

        freq_div = 16'd10;           // 60MHz / 10 = 6MHz
        seq_data = 64'hA5A5A5A5C3C3C3C3;  // Random pattern
        seq_len  = 7'd64;            // 64 bits (max)
        enable   = 1;

        #200000;

        // End simulation
        $display("\n=== Simulation completed ===");
        $finish;
    end

    // Monitor output changes
    initial begin
        $monitor("Time=%0t ns | seq_out=%b | freq_div=%0d | seq_len=%0d",
                 $time, seq_out, freq_div, seq_len);
    end

    // Optional: Generate VCD file for waveform viewing
    initial begin
        $dumpfile("seq_generator_tb.vcd");
        $dumpvars(0, seq_generator_tb);
    end

endmodule
