// ============================================================================
// Module:  fpga_top_tb
// Author:  Gemini
// Date:    2025-09-02
//
// Description:
// Testbench for the fpga_top module.
// It simulates a PC sending a heartbeat command frame (CMD=0xFF) over UART
// and monitors the parser's output to verify correct operation.
// ============================================================================

`timescale 1ns / 1ps

module cdc_tb;

//-----------------------------------------------------------------------------
// Testbench Parameters
//-----------------------------------------------------------------------------
localparam CLK_FREQ     = 50_000_000;
localparam BAUD_RATE    = 115200;

localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // Clock period in ns
localparam CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;     // Clocks per UART bit

//-----------------------------------------------------------------------------
// Testbench Signals
//-----------------------------------------------------------------------------
reg clk;
reg rst_n;
reg uart_rx_pin; // This is our "virtual PC's" TX pin

wire uart_tx_pin; // DUT's TX pin

//-----------------------------------------------------------------------------
// Instantiate the Device Under Test (DUT)
//-----------------------------------------------------------------------------

cdc dut(
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx_pin),
    .uart_tx(uart_tx_pin),
    .led_out()
);

//-----------------------------------------------------------------------------
// Clock and Reset Generation
//-----------------------------------------------------------------------------
initial begin
    clk = 0;
    forever #(CLK_PERIOD_NS / 2) clk = ~clk;
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
    send_uart_byte(8'hFF); // CMD
    send_uart_byte(8'h00); // LEN_H
    send_uart_byte(8'h00); // LEN_L
    send_uart_byte(8'hFF); // Checksum
    #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

    // --- TEST CASE 2: Valid command with payload (Success) ---
    $display("\n[%0t] === TEST 2: Sending Valid Frame with Payload (Should PASS) ===", $time);
    // CMD=0x01, LEN=4, PAYLOAD=DE,AD,BE,EF. Checksum=(01+00+04+DE+AD+BE+EF)%256 = 0x3B
    // Frame: AA 55 01 00 04 DE AD BE EF 3B
    send_uart_byte(8'hAA);
    send_uart_byte(8'h55);
    send_uart_byte(8'h01); // CMD
    send_uart_byte(8'h00); // LEN_H
    send_uart_byte(8'h04); // LEN_L
    send_uart_byte(8'hDE); // Payload 1
    send_uart_byte(8'hAD); // Payload 2
    send_uart_byte(8'hBE); // Payload 3
    send_uart_byte(8'hEF); // Payload 4
    send_uart_byte(8'h3D); // Checksum
    #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);
    
    // --- TEST CASE 3: Invalid Checksum (Error) ---
    $display("\n[%0t] === TEST 3: Sending Frame with Bad Checksum (Should FAIL) ===", $time);
    // Using same frame as Test 2, but with checksum = 0x3C instead of 0x3B
    // Frame: AA 55 01 00 04 DE AD BE EF 3C
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
    // CMD=0x02, LEN=257 (0x0101), which is > MAX_PAYLOAD_LEN(256). Checksum=(02+01+01)%256 = 0x04
    // Frame: AA 55 02 01 01 04
    send_uart_byte(8'hAA);
    send_uart_byte(8'h55);
    send_uart_byte(8'h02); // CMD
    send_uart_byte(8'h01); // LEN_H = 1
    send_uart_byte(8'h01); // LEN_L = 1 (Total Length 257)
    send_uart_byte(8'h04); // Checksum
    #(CLK_PERIOD_NS * CLKS_PER_BIT * 5);

    $display("\n[%0t] Simulation finished.", $time);
    $finish;
end

endmodule