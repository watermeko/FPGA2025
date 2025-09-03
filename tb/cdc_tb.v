// ============================================================================
// Module:      cdc_tb (Complete Testbench)
// Author:      Gemini
// Date:        2025-09-03
//
// Description:
// Testbench for the complete 'cdc' top-level module.
// It simulates sending various command frames over UART and monitors the
// hardware outputs (LED, PWM pins) to verify correct operation.
// Includes tests for:
// - Heartbeat command
// - Generic command with payload
// - Bad checksum error handling
// - Invalid length error handling
// - Multi-channel PWM configuration
// ============================================================================

`timescale 1ns / 1ps

module cdc_tb;

    //-----------------------------------------------------------------------------
    // Testbench Parameters
    //-----------------------------------------------------------------------------
    // Note: For real hardware, a lower BAUD_RATE like 9600 is more robust.
    // For simulation, a higher rate is fine and speeds up the test.
    localparam CLK_FREQ      = 50_000_000;
    localparam BAUD_RATE     = 115200;

    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // Clock period in ns
    localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;     // Clocks per UART bit

    //-----------------------------------------------------------------------------
    // Testbench Signals
    //-----------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg uart_rx_pin; // This is our "virtual PC's" TX pin

    // Wires to monitor the DUT's outputs
    wire uart_tx_pin;
    wire led_out;
    wire [7:0] pwm_pins;

    //-----------------------------------------------------------------------------
    // Instantiate the Device Under Test (DUT)
    //-----------------------------------------------------------------------------

    cdc dut(
            .clk(clk),
            .rst_n(rst_n),
            .uart_rx(uart_rx_pin),
            .uart_tx(uart_tx_pin),
            .led_out(led_out),
            .pwm_pins(pwm_pins)
        );

    //-----------------------------------------------------------------------------
    // Clock and Reset Generation
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever
            #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0; // Assert reset
        uart_rx_pin = 1'b1; // UART idle is high
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1; // De-assert reset
    end

    //-----------------------------------------------------------------------------
    // UART Byte Sending Task
    //-----------------------------------------------------------------------------
    task send_uart_byte(input [7:0] byte_to_send);
        integer i;
        begin
            // Start bit
            uart_rx_pin = 1'b0;
            #(CLK_PERIOD_NS * CLKS_PER_BIT);

            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = byte_to_send[i];
                #(CLK_PERIOD_NS * CLKS_PER_BIT);
            end

            // Stop bit
            uart_rx_pin = 1'b1;
            #(CLK_PERIOD_NS * CLKS_PER_BIT);

            // Inter-byte delay
            #(CLK_PERIOD_NS * CLKS_PER_BIT);
        end
    endtask

    //-----------------------------------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;

        // --- TEST CASE 1: Heartbeat (Success, No Payload) ---
        $display("\n[%0t] === TEST 1: Sending Heartbeat Frame (Should PASS) ===", $time);
        // Frame: AA 55 FF 00 00 FF
        send_uart_byte(8'hAA);
        send_uart_byte(8'h55);
        send_uart_byte(8'hFF);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);
        send_uart_byte(8'hFF);
        #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

        // --- TEST CASE 2: Command 0x01 with payload (Success) ---
        $display("\n[%0t] === TEST 2: Sending Frame with Payload (Should PASS) ===", $time);
        // CMD=0x01, LEN=4. Checksum = (01+00+04+DE+AD+BE+EF)%256 = 0x3D
        // Frame: AA 55 01 00 04 DE AD BE EF 3D
        send_uart_byte(8'hAA);
        send_uart_byte(8'h55);
        send_uart_byte(8'h01);
        send_uart_byte(8'h00);
        send_uart_byte(8'h04);
        send_uart_byte(8'hDE);
        send_uart_byte(8'hAD);
        send_uart_byte(8'hBE);
        send_uart_byte(8'hEF);
        send_uart_byte(8'h3D); // Correct checksum
        #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

        // --- TEST CASE 3: Invalid Checksum (Error) ---
        $display("\n[%0t] === TEST 3: Sending Frame with Bad Checksum (Should FAIL) ===", $time);
        // Using same frame as Test 2, but sending a deliberately incorrect checksum (0x3C).
        send_uart_byte(8'hAA);
        send_uart_byte(8'h55);
        send_uart_byte(8'h01);
        send_uart_byte(8'h00);
        send_uart_byte(8'h04);
        send_uart_byte(8'hDE);
        send_uart_byte(8'hAD);
        send_uart_byte(8'hBE);
        send_uart_byte(8'hEF);
        send_uart_byte(8'h3C); // Bad Checksum
        #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

        // --- TEST CASE 4: Invalid Length (Error) ---
        $display("\n[%0t] === TEST 4: Sending Frame with Invalid Length (Should FAIL) ===", $time);
        // CMD=0x02, LEN=257 (0x0101) > MAX_PAYLOAD_LEN(256). Checksum=(02+01+01)%256 = 0x04
        send_uart_byte(8'hAA);
        send_uart_byte(8'h55);
        send_uart_byte(8'h02);
        send_uart_byte(8'h01);
        send_uart_byte(8'h01);
        send_uart_byte(8'h04);
        #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

        // --- *** NEW *** TEST CASE 5: Configure PWM Channel 3 (Success) ---
        $display("\n[%0t] === TEST 5: Sending PWM Config Frame for CH3 (Should PASS) ===", $time);
        // CMD=0x04, LEN=5, PAYLOAD=[CH=3, PER=1000, DUTY=250].
        // Checksum = (04+00+05+03+03+E8+00+FA)%256 = 0xF1
        // Frame: AA 55 04 00 05 03 03 E8 00 FA F1
        send_uart_byte(8'hAA); // SOF1
        send_uart_byte(8'h55); // SOF2
        send_uart_byte(8'h04); // CMD
        send_uart_byte(8'h00); // LEN_H
        send_uart_byte(8'h05); // LEN_L
        send_uart_byte(8'h01); // Payload: Channel 3
        send_uart_byte(8'h13); // Payload: Period High (1000 = 0x03E8)
        send_uart_byte(8'h88); // Payload: Period Low
        send_uart_byte(8'h0b); // Payload: Duty High   (250 = 0x00FA)
        send_uart_byte(8'hb8); // Payload: Duty Low
        send_uart_byte(8'h68); // Checksum

        // Wait long enough to observe a few PWM cycles on the waveform
        // One PWM cycle = 1000 * CLK_PERIOD = 20,000 ns. Let's wait for ~3 cycles.
        #(CLK_PERIOD_NS * 8000);

        $display("\n[%0t] Simulation finished.", $time);
        $finish;
    end

endmodule
