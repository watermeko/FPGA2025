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
    
    // USB upload interface wires
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    
    // DAC interface wires
    wire [13:0] dac_data;
    reg         dac_clk;
    
    // Debug signals for DAC module (updated to match actual dac_handler)
    wire dac_cmd_ready = dut.u_dac_handler.cmd_ready;
    wire [1:0] dac_wave_type = dut.u_dac_handler.wave_type;  // 恢复到2位
    wire [31:0] dac_freq_word = dut.u_dac_handler.frequency_word;
    wire [31:0] dac_phase_word = dut.u_dac_handler.phase_word;
    wire [1:0] dac_handler_state = dut.u_dac_handler.handler_state;

    // UART TX command payload buffer
    reg [7:0] uart_tx_payload [0:15];
    integer   uart_tx_len;
    
    // UART RX simulation signals  
    reg uart_rx_busy;
    
    // DAC output monitoring signals
    reg [13:0] dac_data_prev;
    integer dac_transitions;
    integer dac_cycle_count;
    real dac_freq_measured;

    // Global integer for loops
    integer i;

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
        .ext_uart_rx(ext_uart_rx),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid),
        .dac_clk(dac_clk),
        .dac_data(dac_data)
    );

    //-----------------------------------------------------------------------------
    // Clock and Reset Generation
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever
            #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    // DAC Clock Generation (200MHz for DDS)
    initial begin
        dac_clk = 0;
        forever
            #2.5 dac_clk = ~dac_clk;  // 200MHz = 5ns period
    end

    initial begin
        rst_n = 1'b0; // Assert reset
        usb_data_in = 8'h00;
        usb_data_valid_in = 1'b0;
        ext_uart_rx = 1'b1; // UART RX is idle high
        uart_rx_busy = 1'b0;
        dac_data_prev = 0;
        dac_transitions = 0;
        dac_cycle_count = 0;
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
    // DAC Command Frame Sending Task (Updated to match actual protocol)
    //-----------------------------------------------------------------------------
    task send_dac_command(
        input [1:0]  wave_type,      // 波形类型: 0=正弦波, 1=三角波, 2=锯齿波, 3=方波
        input [31:0] freq_word,      // 频率控制字
        input [31:0] phase_word      // 相位控制字
    );
        reg [7:0] checksum;
        begin
            $display("[%0t] Sending DAC command: Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                     $time, wave_type, freq_word, phase_word);
            
            // Calculate checksum: CMD + LEN + all data bytes
            checksum = 8'hFD + 8'h00 + 8'h09;  // CMD + LEN_H + LEN_L (9 bytes payload)
            checksum = checksum + {6'b0, wave_type};
            checksum = checksum + freq_word[31:24] + freq_word[23:16] + freq_word[15:8] + freq_word[7:0];
            checksum = checksum + phase_word[31:24] + phase_word[23:16] + phase_word[15:8] + phase_word[7:0];
            
            // Send frame
            send_usb_byte(8'hAA); // SOF1
            send_usb_byte(8'h55); // SOF2
            send_usb_byte(8'hFD); // CMD (DAC command)
            send_usb_byte(8'h00); // LEN_H
            send_usb_byte(8'h09); // LEN_L (9 bytes payload)
            
            // Wave type
            send_usb_byte({6'b0, wave_type});  // 恢复到2位，高位补0
            
            // Frequency word (32-bit, big-endian)
            send_usb_byte(freq_word[31:24]);
            send_usb_byte(freq_word[23:16]);
            send_usb_byte(freq_word[15:8]);
            send_usb_byte(freq_word[7:0]);
            
            // Phase word (32-bit, big-endian)
            send_usb_byte(phase_word[31:24]);
            send_usb_byte(phase_word[23:16]);
            send_usb_byte(phase_word[15:8]);
            send_usb_byte(phase_word[7:0]);
            
            // Checksum
            send_usb_byte(checksum);
            
            // Wait for processing
            #(CLK_PERIOD_NS * 200);
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
    // UART RX Command Frame Sending Task
    //-----------------------------------------------------------------------------
    task send_uart_rx_command;
        reg [7:0] checksum;
    begin
        $display("[%0t] Sending UART RX Command", $time);
        
        // Checksum calculation for UART RX command (no payload)
        checksum = 8'h09; // CMD only (length is 0)

        // Send frame
        send_usb_byte(8'hAA); // SOF1
        send_usb_byte(8'h55); // SOF2
        send_usb_byte(8'h09); // CMD (UART RX)
        send_usb_byte(8'h00); // LEN_H (0 - no payload)
        send_usb_byte(8'h00); // LEN_L
        send_usb_byte(checksum);
        
        #(CLK_PERIOD_NS * 100);
    end
    endtask

    //-----------------------------------------------------------------------------
    // UART Byte Transmission Task (simulates external UART device)
    //-----------------------------------------------------------------------------
    task send_uart_byte(input [7:0] data);
        integer bit_time;
    begin
        bit_time = CLKS_PER_BIT * CLK_PERIOD_NS;
        
        $display("[%0t] Sending UART byte: 0x%02X ('%c')", $time, data, 
                 (data >= 32 && data <= 126) ? data : ".");
        
        uart_rx_busy = 1'b1;
        
        // Start bit
        ext_uart_rx = 1'b0;
        #bit_time;
        
        // Data bits (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            ext_uart_rx = data[i];
            #bit_time;
        end
        
        // Stop bit
        ext_uart_rx = 1'b1;
        #bit_time;
        
        uart_rx_busy = 1'b0;
        
        // Inter-byte delay
        #(bit_time * 2);
    end
    endtask

    //-----------------------------------------------------------------------------
    // UART String Transmission Task (Improved)
    //-----------------------------------------------------------------------------
    task send_uart_string_simple(input [8*32-1:0] str, input integer len);
        reg [7:0] char;
    begin
        $display("[%0t] Sending UART string of length %0d", $time, len);
        
        for (i = 0; i < len; i = i + 1) begin
            char = str[8*(len-1-i) +: 8];
            $display("  Sending char[%0d]: 0x%02X ('%c')", i, char, 
                     (char >= 32 && char <= 126) ? char : ".");
            send_uart_byte(char);
        end
    end
    endtask

    // Alternative task for predefined strings
    task send_uart_text(input [8*20-1:0] text_data, input integer text_len);
        reg [7:0] byte_data;
    begin
        $display("[%0t] Sending text: length %0d", $time, text_len);
        for (i = 0; i < text_len; i = i + 1) begin
            byte_data = text_data >> (8 * (text_len - 1 - i));
            send_uart_byte(byte_data);
        end
    end
    endtask

    //-----------------------------------------------------------------------------
    // USB Data Monitor Task (monitors USB output for received data)
    //-----------------------------------------------------------------------------
    reg [7:0] usb_received_data [0:255];
    integer usb_received_count;
    
    // Monitor for USB upload data (simplified - monitors internal signals)
    always @(posedge clk) begin
        if (usb_upload_valid) begin
            usb_received_data[usb_received_count] = usb_upload_data;
            $display("[%0t] USB Upload: 0x%02X ('%c')", $time, usb_upload_data, 
                     (usb_upload_data >= 32 && usb_upload_data <= 126) ? usb_upload_data : ".");
            usb_received_count = usb_received_count + 1;
        end
    end
    
    // Debug monitor for DAC configuration
    // always @(posedge clk) begin
    //     // Monitor DAC command state changes
    //     if (dac_cmd_state != 3'b000) begin // Not IDLE
    //         $display("[%0t] DAC Debug: State=%0d, Ready=%0d, Type=%0d, Freq=0x%08X, Enable=%0d", 
    //                  $time, dac_cmd_state, dac_cmd_ready, dac_wave_type, dac_freq_word, dac_output_enable);
    //     end
        
    //     // Monitor DAC internal signals every 1000 cycles when enabled
    //     if (dac_output_enable && (($time / 16) % 1000 == 0)) begin
    //         $display("[%0t] DAC Internal: DDS_Sin=%0d, Selected=%0d, Scaled=%0d, Amp=%0d, DC=%0d", 
    //                  $time, $signed(dac_dds_sin), $signed(dac_selected_wave), dac_scaled_wave, 
    //                  dac_amplitude, dac_dc_offset);
    //     end
        
    //     // Monitor when DAC output changes significantly
    //     if (dac_valid && (dac_data != 0) && (($time / 16) % 100 == 0)) begin
    //         $display("[%0t] DAC Output: Data=0x%04X (%0d), Valid=%0d", 
    //                  $time, dac_data, dac_data, dac_valid);
    //     end
    // end
    
    //-----------------------------------------------------------------------------
    // DAC Output Monitoring
    //-----------------------------------------------------------------------------
    // Monitor DAC output for waveform validation
    always @(posedge clk) begin
        if (rst_n) begin
            dac_data_prev <= dac_data;
            dac_cycle_count <= dac_cycle_count + 1;
            
            // Count zero crossings for frequency measurement
            if (dac_data_prev < 14'h2000 && dac_data >= 14'h2000) begin
                dac_transitions <= dac_transitions + 1;
            end
        end
    end
    
    // Task to measure DAC frequency over a period
    task measure_dac_frequency(input integer measurement_cycles);
        integer start_transitions, end_transitions;
        integer start_time, end_time;
        real freq_hz;
    begin
        $display("[%0t] Starting DAC frequency measurement for %0d cycles", $time, measurement_cycles);
        start_transitions = dac_transitions;
        start_time = $time;
        
        // Wait for measurement period
        repeat(measurement_cycles) @(posedge clk);
        
        end_transitions = dac_transitions;
        end_time = $time;
        
        // Calculate frequency
        freq_hz = (end_transitions - start_transitions) * 1000000000.0 / (end_time - start_time);
        dac_freq_measured = freq_hz;
        
        $display("[%0t] DAC Frequency measured: %.2f Hz (%0d transitions in %0d ns)", 
                 $time, freq_hz, end_transitions - start_transitions, end_time - start_time);
    end
    endtask
    
    // Task to verify DAC waveform characteristics
    task verify_dac_waveform(input [1:0] expected_wave_type, input integer check_cycles);  // 恢复到2位
        reg [13:0] min_val, max_val;
        integer zero_crossings;
        integer i;
        reg signed [13:0] signed_data;
    begin
        $display("[%0t] Verifying DAC waveform type %0d for %0d cycles", $time, expected_wave_type, check_cycles);
        
        min_val = 14'h3FFF;
        max_val = 0;
        zero_crossings = 0;
        
        for (i = 0; i < check_cycles; i = i + 1) begin
            @(posedge clk);
            // Track min/max
            if (dac_data < min_val) min_val = dac_data;
            if (dac_data > max_val) max_val = dac_data;
            
            // Count zero crossings
            signed_data = $signed(dac_data - 14'h2000); // Convert to signed, centered at 0
            if (i > 0 && 
                (($signed(dac_data_prev - 14'h2000) < 0 && signed_data >= 0) ||
                 ($signed(dac_data_prev - 14'h2000) >= 0 && signed_data < 0))) begin
                zero_crossings = zero_crossings + 1;
            end
        end
        
        $display("[%0t] Waveform Analysis: Min=0x%04X, Max=0x%04X, Range=%0d, Zero-crossings=%0d", 
                 $time, min_val, max_val, max_val - min_val, zero_crossings);
        
        // Basic waveform validation
        case (expected_wave_type)
            2'd0: begin // Sine wave
                if (zero_crossings >= 2) 
                    $display("✅ Sine wave: Zero crossings detected");
                else 
                    $display("❌ Sine wave: No zero crossings found");
            end
            2'd1: begin // Triangle wave
                if (zero_crossings >= 2) 
                    $display("✅ Triangle wave: Transitions detected");
                else 
                    $display("❌ Triangle wave: No transitions found");
            end
            2'd2: begin // Sawtooth wave
                if (zero_crossings >= 1) 
                    $display("✅ Sawtooth wave: Transitions detected");
                else 
                    $display("❌ Sawtooth wave: No transitions found");
            end
            2'd3: begin // Square wave
                if (zero_crossings >= 2) 
                    $display("✅ Square wave: Transitions detected");
                else 
                    $display("❌ Square wave: No transitions found");
            end
            default: begin
                $display("ℹ️  Waveform type %0d analysis complete", expected_wave_type);
            end
        endcase
    end
    endtask

    //-----------------------------------------------------------------------------
    // Test Results Verification
    //-----------------------------------------------------------------------------
    task verify_test_results;
    begin
        $display("");
        $display("=== Test Results Verification ===");
        
        if (usb_received_count == 0) begin
            $display("❌ FAIL: No USB data received");
        end else begin
            $display("✅ SUCCESS: Received %0d bytes via USB", usb_received_count);
            
            // Check if we received expected characters
            if (usb_received_count >= 5) begin
                if (usb_received_data[0] == 8'h48 && // 'H'
                    usb_received_data[1] == 8'h65 && // 'e'  
                    usb_received_data[2] == 8'h6C && // 'l'
                    usb_received_data[3] == 8'h6C && // 'l'
                    usb_received_data[4] == 8'h6F) begin // 'o'
                    $display("✅ SUCCESS: 'Hello' pattern detected correctly");
                end else begin
                    $display("❌ FAIL: 'Hello' pattern not found in first 5 bytes");
                end
            end
        end
        
        $display("");
        $display("Received data summary:");
        for (i = 0; i < usb_received_count && i < 32; i = i + 1) begin
            $display("  [%2d]: 0x%02X ('%c')", i, usb_received_data[i], 
                     (usb_received_data[i] >= 32 && usb_received_data[i] <= 126) ? usb_received_data[i] : ".");
        end
        
        if (usb_received_count > 32) begin
            $display("  ... (%0d more bytes)", usb_received_count - 32);
        end
    end
    endtask


    //-----------------------------------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;
        
        // Initialize USB received data counter
        usb_received_count = 0;

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

        // --- TEST CASE 4: DAC Signal Generator Tests ---
        $display("=== Starting DAC Signal Generator Tests ===");
        
        // 4.1: Test Sine Wave (1MHz)
        $display("--- TEST 4.1: DAC Sine Wave (1MHz) ---");
        send_dac_command(
            2'b00,                   // Wave type: Sine wave
            32'd21474836,             // Frequency word for 1MHz at 200MHz DAC clock
            32'd0                     // Phase word: 0 degrees
        );
        #(CLK_PERIOD_NS * 1000);
        
        // Monitor DAC configuration
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // Verify DAC waveform for sine wave
        verify_dac_waveform(2'b00, 2000);
        
        // 4.2: Test Triangle Wave (500kHz, 90° phase)
        $display("--- TEST 4.2: DAC Triangle Wave (500kHz, 90° phase) ---");
        send_dac_command(
            2'b01,                   // Wave type: Triangle wave
            32'd10737418,             // Frequency word for 500kHz
            32'd1073741824            // Phase word: 90 degrees (2^32/4)
        );
        #(CLK_PERIOD_NS * 1000);
        
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // Verify DAC waveform for triangle wave
        verify_dac_waveform(2'b01, 2000);
        
        // 4.3: Test Sawtooth Wave (2MHz)
        $display("--- TEST 4.3: DAC Sawtooth Wave (2MHz) ---");
        send_dac_command(
            2'b10,                   // Wave type: Sawtooth wave
            32'd42949673,             // Frequency word for 2MHz
            32'd0                     // Phase word: 0 degrees
        );
        #(CLK_PERIOD_NS * 1000);
        
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // Verify DAC waveform for sawtooth wave
        verify_dac_waveform(2'b10, 2000);
        
        // 4.4: Test Square Wave (100kHz, 180° phase)
        $display("--- TEST 4.4: DAC Square Wave (100kHz, 180° phase) ---");
        send_dac_command(
            2'b11,                   // Wave type: Square wave
            32'd2147484,              // Frequency word for 100kHz
            32'd2147483648            // Phase word: 180 degrees (2^32/2)
        );
        #(CLK_PERIOD_NS * 1000);
        
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // Verify DAC waveform for square wave
        verify_dac_waveform(2'b11, 2000);
        
        // 4.5: Test High Frequency Sine Wave (10MHz)
        $display("--- TEST 4.5: DAC High Frequency Sine Wave (10MHz) ---");
        send_dac_command(
            2'b00,                   // Wave type: Sine wave
            32'd214748365,            // Frequency word for 10MHz
            32'd0                     // Phase word: 0 degrees
        );
        #(CLK_PERIOD_NS * 1000);
        
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // Verify DAC waveform for high frequency sine wave
        verify_dac_waveform(2'b00, 1000);
        
        // 4.6: Test Low Frequency Square Wave (1kHz)
        $display("--- TEST 4.6: DAC Low Frequency Square Wave (1kHz) ---");
        send_dac_command(
            2'b11,                   // Wave type: Square wave
            32'd21475,                // Frequency word for 1kHz
            32'd0                     // Phase word: 0 degrees
        );
        #(CLK_PERIOD_NS * 1000);
        
        $display("[%0t] DAC Config: Ready=%0d, State=%0d, Type=%0d, Freq=0x%08X, Phase=0x%08X", 
                 $time, dac_cmd_ready, dac_handler_state, dac_wave_type, dac_freq_word, dac_phase_word);
        
        // For low frequency, monitor for longer period
        verify_dac_waveform(2'b11, 5000);
        
        $display("=== DAC Signal Generator Tests Complete ===");
        #(CLK_PERIOD_NS * 500);

        // --- TEST CASE 5: UART Transmit Data ---
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
        #2_000_000;

        // --- TEST CASE 6: UART Receive Data Test ---
        $display("=== Starting UART RX Data Test ===");
        
        // 6.1: Send UART RX command to enable receive mode
        $display("--- Step 1: Sending UART RX Command ---");
        send_uart_rx_command;
        #(CLK_PERIOD_NS * 100);
        
        // 6.2: Send test data via UART RX
        $display("--- Step 2: Sending Test Data via UART ---");
        
        // Send "Hello" using individual bytes for clarity
        $display("Sending 'Hello':");
        send_uart_byte(8'h48); // 'H'
        send_uart_byte(8'h65); // 'e' 
        send_uart_byte(8'h6C); // 'l'
        send_uart_byte(8'h6C); // 'l'
        send_uart_byte(8'h6F); // 'o'
        #(CLK_PERIOD_NS * 1000);
        
        // 5.3: Send more test data
        send_uart_byte(8'h41); // 'A'
        send_uart_byte(8'h42); // 'B'
        send_uart_byte(8'h43); // 'C'
        #(CLK_PERIOD_NS * 1000);
        
        // 5.4: Send binary data
        $display("--- Step 3: Sending Binary Data ---");
        send_uart_byte(8'h00);
        send_uart_byte(8'hFF);
        send_uart_byte(8'h55);
        send_uart_byte(8'hAA);
        #(CLK_PERIOD_NS * 1000);
        
        // --- TEST CASE 7: Multiple UART RX Sessions ---
        $display("=== Starting Multiple UART RX Sessions Test ===");
        
        // 7.1: Second RX session
        send_uart_rx_command;
        #(CLK_PERIOD_NS * 50);
        
        $display("Sending 'Test123':");
        send_uart_byte(8'h54); // 'T'
        send_uart_byte(8'h65); // 'e'
        send_uart_byte(8'h73); // 's'
        send_uart_byte(8'h74); // 't'
        send_uart_byte(8'h31); // '1'
        send_uart_byte(8'h32); // '2'
        send_uart_byte(8'h33); // '3'
        #(CLK_PERIOD_NS * 1000);
        
        // 7.2: Third RX session with longer data
        send_uart_rx_command;
        #(CLK_PERIOD_NS * 50);
        
        $display("Sending 'FPGA':");
        send_uart_byte(8'h46); // 'F'
        send_uart_byte(8'h50); // 'P'
        send_uart_byte(8'h47); // 'G'
        send_uart_byte(8'h41); // 'A'
        #(CLK_PERIOD_NS * 1000);
        
        // --- Final Results ---
        $display("=== Test Complete ===");
        $display("Total USB data received: %0d bytes", usb_received_count);
        
        // Use verification task instead of manual display
        verify_test_results;
        
        #(CLK_PERIOD_NS * 1000);
        $finish;
    end

GSR GSR(
  .GSRI(1'b1)
);

endmodule
