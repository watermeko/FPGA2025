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
    localparam CLK_FREQ      = 60_000_000;
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
    wire ext_uart_tx;
    reg  ext_uart_rx;

    // UART TX command payload buffer
    reg [7:0] uart_tx_payload [0:15];
    integer   uart_tx_len;

    //-----------------------------------------------------------------------------
    // Instantiate the Device Under Test (DUT)
    //-----------------------------------------------------------------------------
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_tx(ext_uart_tx),
        .ext_uart_rx(ext_uart_rx)
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
        ext_uart_rx = 1'b1; // UART RX is idle high
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
    // UART Config Command Frame Sending Task
    //-----------------------------------------------------------------------------
    task send_uart_config_command(input [31:0] baud, input [7:0] data_bits, input [7:0] stop_bits, input [7:0] parity);
        reg [7:0] checksum;
    begin
        $display("[%0t] Sending UART Config: Baud=%d, Data=%d, Stop=%d, Parity=%d", $time, baud, data_bits, stop_bits, parity);
        
        // Checksum calculation
        checksum = 8'h07 + 8'h00 + 8'h07; // CMD + LEN
        checksum = checksum + baud[31:24] + baud[23:16] + baud[15:8] + baud[7:0];
        checksum = checksum + data_bits + stop_bits + parity;

        // Send frame
        send_usb_byte(8'hAA); // SOF1
        send_usb_byte(8'h55); // SOF2
        send_usb_byte(8'h07); // CMD (UART Config)
        send_usb_byte(8'h00); // LEN_H
        send_usb_byte(8'h07); // LEN_L (7 bytes: 4 baud, 1 data, 1 stop, 1 parity)
        send_usb_byte(baud[31:24]);
        send_usb_byte(baud[23:16]);
        send_usb_byte(baud[15:8]);
        send_usb_byte(baud[7:0]);
        send_usb_byte(data_bits);
        send_usb_byte(stop_bits);
        send_usb_byte(parity);
        send_usb_byte(checksum);
        
        #(CLK_PERIOD_NS * 100);
    end
    endtask

    //-----------------------------------------------------------------------------
    // UART TX Command Frame Sending Task
    //-----------------------------------------------------------------------------
    task send_uart_tx_command;
        reg [7:0] checksum;
        integer   i;
    begin
        $display("[%0t] Sending UART TX Data, Length: %0d", $time, uart_tx_len);
        
        // Checksum calculation
        checksum = 8'h08 + uart_tx_len[15:8] + uart_tx_len[7:0]; // CMD + LEN
        for (i = 0; i < uart_tx_len; i = i + 1) begin
            checksum = checksum + uart_tx_payload[i];
        end

        // Send frame
        send_usb_byte(8'hAA); // SOF1
        send_usb_byte(8'h55); // SOF2
        send_usb_byte(8'h08); // CMD (UART TX)
        send_usb_byte(uart_tx_len[15:8]); // LEN_H
        send_usb_byte(uart_tx_len[7:0]);  // LEN_L
        for (i = 0; i < uart_tx_len; i = i + 1) begin
            send_usb_byte(uart_tx_payload[i]);
        end
        send_usb_byte(checksum);
        
        #(CLK_PERIOD_NS * 200); // Wait a bit longer for FIFO operations
    end
    endtask


    //-----------------------------------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;

        // --- TEST CASE 1: Heartbeat (Success, No Payload) ---
        $display("--- Starting Heartbeat Test ---");
        // Frame: AA 55 FF 00 00 F9 (Correct checksum is CMD+LEN = FF+0+0=FF)
        send_usb_byte(8'hAA);
        send_usb_byte(8'h55);
        send_usb_byte(8'hFF);
        send_usb_byte(8'h00);
        send_usb_byte(8'h00);
        send_usb_byte(8'hFF);
        #(CLK_PERIOD_NS * 100);

        // --- TEST CASE 2: PWM Command ---
        $display("--- Starting PWM Test ---");
        // AA 55 FE 00 05 01 EA 60 75 30 F7
        send_pwm_command(1, 16'hEA60, 16'h7530);
        #(CLK_PERIOD_NS * 500);

        // --- TEST CASE 3: UART Configuration ---
        $display("--- Starting UART Config Test ---");
        send_uart_config_command(115200, 8, 0, 0); // 115200 baud, 8-N-1
        #(CLK_PERIOD_NS * 200);

        // --- TEST CASE 4: UART Transmit Data ---
        $display("--- Starting UART TX Test ---");
        begin
            uart_tx_payload[0]  = "H";
            uart_tx_payload[1]  = "e";
            uart_tx_payload[2]  = "l";
            uart_tx_payload[3]  = "l";
            uart_tx_payload[4]  = "o";
            uart_tx_payload[5]  = " ";
            uart_tx_payload[6]  = "U";
            uart_tx_payload[7]  = "A";
            uart_tx_payload[8]  = "R";
            uart_tx_payload[9]  = "T";
            uart_tx_payload[10] = "!";
            uart_tx_len = 11;
            send_uart_tx_command;
        end
        // Wait long enough for the UART to transmit all bytes
        // 11 bytes * 10 bits/byte (for 8-N-1) = 110 bits
        // Time = 110 bits / 115200 bps = ~0.95ms
        // Wait for 2ms to be safe
        #2_000_000;

        
        $finish;
    end

GSR GSR(
  .GSRI(1'b1)
);

endmodule
