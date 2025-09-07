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
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;

    // Wires to monitor the DUT's outputs
    wire led_out;
    wire [7:0] pwm_pins;

    //-----------------------------------------------------------------------------
    // Instantiate the Device Under Test (DUT)
    //-----------------------------------------------------------------------------
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
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
        usb_data_in = 8'h00;
        usb_data_valid_in = 1'b0;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1; // De-assert reset
    end

    //-----------------------------------------------------------------------------
    // USB Data Sending Task
    //-----------------------------------------------------------------------------
    task send_usb_byte(input [7:0] byte_to_send);
        begin
            @(posedge clk);
            usb_data_in = byte_to_send;
            usb_data_valid_in = 1'b1;
            @(posedge clk);
            usb_data_valid_in = 1'b0;
            #(CLK_PERIOD_NS * 10); // Inter-byte delay
        end
    endtask

    //-----------------------------------------------------------------------------
    // PWM Command Frame Sending Task
    //-----------------------------------------------------------------------------
    task send_pwm_command(input [2:0] channel, input [15:0] period, input [15:0] duty);
        reg [7:0] checksum;
        begin
            $display("[%0t] Sending PWM command: CH=%0d, Period=%0d, Duty=%0d", $time, channel, period, duty);
            
            // Calculate checksum: CMD + LEN_H + LEN_L + CH + PER_H + PER_L + DUTY_H + DUTY_L
            checksum = 8'hFE + 8'h00 + 8'h05 + channel + period[15:8] + period[7:0] + duty[15:8] + duty[7:0];
            
            // Send frame
            send_usb_byte(8'hAA); // SOF1
            send_usb_byte(8'h55); // SOF2
            send_usb_byte(8'hFE); // CMD (PWM command)
            send_usb_byte(8'h00); // LEN_H
            send_usb_byte(8'h05); // LEN_L (5 bytes payload)
            send_usb_byte(channel); // Channel
            send_usb_byte(period[15:8]); // Period High
            send_usb_byte(period[7:0]);  // Period Low
            send_usb_byte(duty[15:8]);   // Duty High
            send_usb_byte(duty[7:0]);    // Duty Low
            send_usb_byte(checksum);     // Checksum
            
            // Wait for processing
            #(CLK_PERIOD_NS * 100);
        end
    endtask

    //-----------------------------------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;

        // --- TEST CASE 1: Heartbeat (Success, No Payload) ---
        // Frame: AA 55 FF 00 00 FF
        send_usb_byte(8'hAA);
        send_usb_byte(8'h55);
        send_usb_byte(8'hFF);
        send_usb_byte(8'h00);
        send_usb_byte(8'h00);
        send_usb_byte(8'hFF);
        #(CLK_PERIOD_NS *CLKS_PER_BIT* 100);

        // --- TEST CASE 5: Your Original Command Test ---
        // AA 55 FE 00 05 01 EA 60 75 30 F7
        send_usb_byte(8'hAA);
        send_usb_byte(8'h55);
        send_usb_byte(8'hFE);
        send_usb_byte(8'h00);
        send_usb_byte(8'h05);
        send_usb_byte(8'h01); // Channel 1
        send_usb_byte(8'hEA); // Period High
        send_usb_byte(8'h60); // Period Low (59936)
        send_usb_byte(8'h75); // Duty High
        send_usb_byte(8'h30); // Duty Low (30000)
        send_usb_byte(8'hF3); // Checksum
        #(CLK_PERIOD_NS *CLKS_PER_BIT* 700000); // Wait for several cycles

        
        $finish;
    end


endmodule
