// ============================================================================
// Testbench: seq_handler_tb
// Author:    Claude
// Date:      2025-10-24
//
// Description:
// Testbench for the sequence handler module with command protocol.
// Simulates USB-CDC command interface to configure sequence channels.
// ============================================================================
`timescale 1ns / 1ps

module seq_handler_tb;

    // Parameters
    parameter CLK_PERIOD = 16.67;  // 60MHz clock

    // Testbench signals
    reg         clk;
    reg         rst_n;
    reg  [7:0]  cmd_type;
    reg  [15:0] cmd_length;
    reg  [7:0]  cmd_data;
    reg  [15:0] cmd_data_index;
    reg         cmd_start;
    reg         cmd_data_valid;
    reg         cmd_done;
    wire        cmd_ready;
    wire [7:0]  seq_pins;

    // Instantiate the sequence handler
    seq_handler dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_type(cmd_type),
        .cmd_length(cmd_length),
        .cmd_data(cmd_data),
        .cmd_data_index(cmd_data_index),
        .cmd_start(cmd_start),
        .cmd_data_valid(cmd_data_valid),
        .cmd_done(cmd_done),
        .cmd_ready(cmd_ready),
        .seq_pins(seq_pins)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Task: Send command byte-by-byte
    task send_seq_command;
        input [7:0] channel;
        input [7:0] enable;
        input [15:0] freq_divider;
        input [6:0] sequence_length;
        input [63:0] sequence_data;
        integer i;
        reg [7:0] payload [0:12];
        begin
            // Build payload (13 bytes)
            payload[0] = channel;
            payload[1] = enable;
            payload[2] = freq_divider[15:8];   // High byte
            payload[3] = freq_divider[7:0];    // Low byte
            payload[4] = {1'b0, sequence_length};
            payload[5] = sequence_data[7:0];
            payload[6] = sequence_data[15:8];
            payload[7] = sequence_data[23:16];
            payload[8] = sequence_data[31:24];
            payload[9] = sequence_data[39:32];
            payload[10] = sequence_data[47:40];
            payload[11] = sequence_data[55:48];
            payload[12] = sequence_data[63:56];

            // Start command
            cmd_type = 8'hF0;
            cmd_length = 16'd13;
            cmd_start = 1;
            cmd_data_valid = 0;
            cmd_done = 0;
            @(posedge clk);
            cmd_start = 0;

            // Send payload bytes
            for (i = 0; i < 13; i = i + 1) begin
                @(posedge clk);
                cmd_data = payload[i];
                cmd_data_index = i;
                cmd_data_valid = 1;
            end

            // End command
            @(posedge clk);
            cmd_data_valid = 0;
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;

            $display("Command sent: CH=%0d, EN=%0d, DIV=%0d, LEN=%0d, DATA=0x%0h",
                     channel, enable, freq_divider, sequence_length, sequence_data);
        end
    endtask

    // Test sequence
    initial begin
        // Initialize signals
        rst_n = 0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;

        // Apply reset
        #200;
        rst_n = 1;
        #200;

        // ========================================
        // Test 1: Configure channel 0 with 10-bit pattern at 1MHz
        // ========================================
        $display("\n=== Test 1: Configure CH0 with 0101010101 @ 1MHz ===");
        send_seq_command(
            .channel(8'd0),
            .enable(8'd1),
            .freq_divider(16'd60),          // 60MHz/60 = 1MHz
            .sequence_length(7'd10),        // 10 bits
            .sequence_data(64'h0155)        // 0101010101
        );

        // Wait and observe output
        #100000;

        // ========================================
        // Test 2: Configure channel 1 with 8-bit pattern at 2MHz
        // ========================================
        $display("\n=== Test 2: Configure CH1 with 11001100 @ 2MHz ===");
        send_seq_command(
            .channel(8'd1),
            .enable(8'd1),
            .freq_divider(16'd30),          // 60MHz/30 = 2MHz
            .sequence_length(7'd8),         // 8 bits
            .sequence_data(64'hCC)          // 11001100
        );

        #50000;

        // ========================================
        // Test 3: Configure channel 2 with 16-bit pattern at 4MHz
        // ========================================
        $display("\n=== Test 3: Configure CH2 with 16-bit pattern @ 4MHz ===");
        send_seq_command(
            .channel(8'd2),
            .enable(8'd1),
            .freq_divider(16'd15),          // 60MHz/15 = 4MHz
            .sequence_length(7'd16),        // 16 bits
            .sequence_data(64'hAAF0)        // 1010101011110000
        );

        #40000;

        // ========================================
        // Test 4: Disable channel 0
        // ========================================
        $display("\n=== Test 4: Disable CH0 ===");
        send_seq_command(
            .channel(8'd0),
            .enable(8'd0),                  // Disable
            .freq_divider(16'd60),
            .sequence_length(7'd10),
            .sequence_data(64'h0155)
        );

        #20000;

        // ========================================
        // Test 5: Re-enable channel 0 with new pattern
        // ========================================
        $display("\n=== Test 5: Re-enable CH0 with new pattern ===");
        send_seq_command(
            .channel(8'd0),
            .enable(8'd1),
            .freq_divider(16'd120),         // 60MHz/120 = 500kHz
            .sequence_length(7'd4),         // 4 bits
            .sequence_data(64'h0A)          // 1010
        );

        #50000;

        // ========================================
        // Test 6: Configure all 8 channels simultaneously
        // ========================================
        $display("\n=== Test 6: Configure all 8 channels ===");
        send_seq_command(8'd3, 8'd1, 16'd60, 7'd2, 64'h3);    // CH3: "11"
        #5000;
        send_seq_command(8'd4, 8'd1, 16'd60, 7'd3, 64'h5);    // CH4: "101"
        #5000;
        send_seq_command(8'd5, 8'd1, 16'd60, 7'd4, 64'h9);    // CH5: "1001"
        #5000;
        send_seq_command(8'd6, 8'd1, 16'd60, 7'd5, 64'h15);   // CH6: "10101"
        #5000;
        send_seq_command(8'd7, 8'd1, 16'd60, 7'd6, 64'h2A);   // CH7: "101010"
        #5000;

        #100000;

        $display("\n=== Simulation completed ===");
        $finish;
    end

    // Monitor outputs
    initial begin
        $monitor("Time=%0t ns | seq_pins=%b | cmd_ready=%b",
                 $time, seq_pins, cmd_ready);
    end

    // Generate VCD for waveform viewing
    initial begin
        $dumpfile("seq_handler_tb.vcd");
        $dumpvars(0, seq_handler_tb);
    end

endmodule
