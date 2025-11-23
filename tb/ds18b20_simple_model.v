// ============================================================================
// Module: ds18b20_simple_model
// Description: Simplified DS18B20 behavioral model for simulation
// Uses continuous monitoring instead of edge-triggered events
// ============================================================================
`timescale 1ns / 1ps

module ds18b20_simple_model (
    inout wire dq  // 1-Wire data line
);

    // ROM ID: Family(28) + Serial(6 bytes) + CRC
    parameter [63:0] ROM_ID = 64'hE7_12345A0C00_28;

    // Temperature: 25.0°C = 0x0190
    parameter [15:0] TEMPERATURE = 16'h0190;

    // Output control
    reg drive_low = 0;
    assign dq = drive_low ? 1'b0 : 1'bz;

    // State
    reg [3:0] state = 0;
    reg [7:0] cmd = 0;
    reg [2:0] bit_cnt = 0;
    reg [3:0] byte_cnt = 0;
    reg [7:0] tx_byte = 0;
    reg [3:0] tx_bytes_remaining = 0;
    reg sending_data = 0;
    reg sending_scratchpad = 0;  // Flag: 0=ROM, 1=Scratchpad

    // Timing counters
    integer low_time = 0;
    integer sample_delay = 0;

    // Data buffers
    reg [7:0] rom_data [0:7];
    reg [7:0] scratchpad [0:8];
    reg [3:0] data_idx = 0;

    // Initialize data
    initial begin
        // ROM ID (LSB first order)
        rom_data[0] = ROM_ID[7:0];    // Family code 0x28
        rom_data[1] = ROM_ID[15:8];
        rom_data[2] = ROM_ID[23:16];
        rom_data[3] = ROM_ID[31:24];
        rom_data[4] = ROM_ID[39:32];
        rom_data[5] = ROM_ID[47:40];
        rom_data[6] = ROM_ID[55:48];
        rom_data[7] = ROM_ID[63:56];  // CRC

        // Scratchpad
        scratchpad[0] = TEMPERATURE[7:0];   // Temp LSB
        scratchpad[1] = TEMPERATURE[15:8];  // Temp MSB
        scratchpad[2] = 8'h4B;  // TH
        scratchpad[3] = 8'h46;  // TL
        scratchpad[4] = 8'h7F;  // Config
        scratchpad[5] = 8'hFF;
        scratchpad[6] = 8'h00;
        scratchpad[7] = 8'h10;
        scratchpad[8] = 8'hC4;  // CRC
    end

    localparam S_IDLE = 0;
    localparam S_RESET_DETECT = 1;
    localparam S_PRESENCE_WAIT = 2;
    localparam S_PRESENCE_PULSE = 3;
    localparam S_RECV_CMD = 4;
    localparam S_RECV_BIT_WAIT = 5;
    localparam S_SEND_DATA = 6;
    localparam S_SEND_BIT = 7;

    // Measure low pulse duration
    reg dq_prev = 1;
    time fall_time = 0;
    time rise_time = 0;
    integer pulse_width = 0;

    always @(dq) begin
        if (dq == 0 && dq_prev == 1) begin
            // Falling edge
            fall_time = $time;
        end
        else if (dq == 1 && dq_prev == 0) begin
            // Rising edge
            rise_time = $time;
            pulse_width = (rise_time - fall_time) / 1000;  // Convert to µs

            case (state)
                S_IDLE: begin
                    // Check for reset pulse (> 480µs)
                    if (pulse_width >= 400) begin
                        $display("[DS18B20] @%0t: Reset pulse detected (%0d µs)", $time, pulse_width);
                        state <= S_PRESENCE_WAIT;
                    end
                end

                S_RECV_CMD, S_RECV_BIT_WAIT: begin
                    // Ignore pulses > 100µs (they are probably reset pulses, not data)
                    if (pulse_width > 100) begin
                        $display("[DS18B20] @%0t: Ignoring long pulse (%0d µs) - likely reset", $time, pulse_width);
                        // Check if it's a reset
                        if (pulse_width >= 400) begin
                            state <= S_PRESENCE_WAIT;
                            bit_cnt <= 0;
                            cmd <= 0;
                        end
                    end else begin
                        // Receiving command bit (LSB first)
                        // Short pulse = 1, Long pulse = 0
                        if (pulse_width < 20) begin
                            // Short pulse = 1
                            cmd[bit_cnt] <= 1'b1;  // LSB first - store at bit_cnt position
                            $display("[DS18B20] @%0t: Recv bit[%0d] = 1 (%0d µs)", $time, bit_cnt, pulse_width);
                        end else begin
                            // Long pulse = 0
                            cmd[bit_cnt] <= 1'b0;  // LSB first - store at bit_cnt position
                            $display("[DS18B20] @%0t: Recv bit[%0d] = 0 (%0d µs)", $time, bit_cnt, pulse_width);
                        end
                        bit_cnt <= bit_cnt + 1;

                        if (bit_cnt == 7) begin
                            // Construct final byte with correct bit ordering
                            begin
                                reg [7:0] final_cmd;
                                final_cmd[0] = cmd[0];
                                final_cmd[1] = cmd[1];
                                final_cmd[2] = cmd[2];
                                final_cmd[3] = cmd[3];
                                final_cmd[4] = cmd[4];
                                final_cmd[5] = cmd[5];
                                final_cmd[6] = cmd[6];
                                final_cmd[7] = (pulse_width < 20) ? 1'b1 : 1'b0;

                                $display("[DS18B20] @%0t: Command byte: 0x%02X", $time, final_cmd);
                                bit_cnt <= 0;
                                cmd <= 0;

                                // Process command
                                case (final_cmd)
                                    8'h33: begin  // Read ROM
                                        $display("[DS18B20] @%0t: READ ROM command", $time);
                                        tx_bytes_remaining <= 8;
                                        data_idx <= 0;
                                        tx_byte <= rom_data[0];
                                        sending_scratchpad <= 0;  // Sending ROM data
                                        state <= S_SEND_DATA;
                                    end
                                    8'hCC: begin  // Skip ROM
                                        $display("[DS18B20] @%0t: SKIP ROM command", $time);
                                        state <= S_RECV_CMD;
                                    end
                                    8'h44: begin  // Convert T
                                        $display("[DS18B20] @%0t: CONVERT T command", $time);
                                        state <= S_IDLE;
                                    end
                                    8'hBE: begin  // Read Scratchpad
                                        $display("[DS18B20] @%0t: READ SCRATCHPAD command", $time);
                                        tx_bytes_remaining <= 9;
                                        data_idx <= 0;
                                        tx_byte <= scratchpad[0];
                                        sending_scratchpad <= 1;  // Sending scratchpad data
                                        state <= S_SEND_DATA;
                                    end
                                    default: begin
                                        $display("[DS18B20] @%0t: Unknown command 0x%02X", $time, final_cmd);
                                        state <= S_IDLE;
                                    end
                                endcase
                            end
                        end else begin
                            state <= S_RECV_BIT_WAIT;
                        end
                    end
                end
            endcase
        end
        dq_prev <= dq;
    end

    // Presence pulse and data transmission (time-based)
    always @(posedge (state == S_PRESENCE_WAIT)) begin
        // Wait 30µs after reset release, then send presence pulse
        #30_000;
        if (state == S_PRESENCE_WAIT) begin
            $display("[DS18B20] @%0t: Sending presence pulse", $time);
            drive_low <= 1;
            state <= S_PRESENCE_PULSE;
            #120_000;  // 120µs presence pulse
            drive_low <= 0;
            // Reset bit counter and command buffer after presence pulse
            #10_000;  // Small delay after releasing
            bit_cnt <= 0;
            cmd <= 0;
            state <= S_RECV_CMD;
            $display("[DS18B20] @%0t: Ready for commands", $time);
        end
    end

    // Busy flag to prevent multiple concurrent responses
    reg tx_busy = 0;

    // Data transmission - respond to master read slots
    // Must wait for master to release bus before responding
    always @(negedge dq) begin
        if (state == S_SEND_DATA && !tx_busy) begin
            tx_busy <= 1;  // Lock to prevent re-entry
            // Master initiates read slot by pulling low
            // We need to wait for master to release, then respond within the time window
            fork
                begin
                    // Capture current bit info at the moment of falling edge
                    reg [2:0] current_bit;
                    reg [3:0] current_byte_idx;
                    reg [7:0] current_tx_byte;
                    time slot_start;

                    slot_start = $time;
                    current_bit = bit_cnt;
                    current_byte_idx = data_idx;
                    current_tx_byte = tx_byte;

                    // Wait for master to release bus (max 15µs per spec)
                    // Master typically releases after 1-6µs
                    wait(dq == 1'b1 || dq === 1'bz);  // Wait for bus release

                    // Small delay after master releases (response must be within 15µs of slot start)
                    #200;  // 0.2µs delay

                    // Only drive low for '0' bit, release for '1' bit
                    if (current_tx_byte[current_bit] == 0) begin
                        // Send 0: hold bus low
                        drive_low <= 1;
                        $display("[DS18B20] @%0t: Send bit[%0d] of byte[%0d] = 0 (byte=0x%02X)",
                                 $time, current_bit, current_byte_idx, current_tx_byte);
                        #20_000;  // Hold for 20µs (must hold past master sample at ~15µs)
                        drive_low <= 0;
                    end else begin
                        // Send 1: keep released (bus pulled high by pullup)
                        drive_low <= 0;
                        $display("[DS18B20] @%0t: Send bit[%0d] of byte[%0d] = 1 (byte=0x%02X)",
                                 $time, current_bit, current_byte_idx, current_tx_byte);
                    end

                    // Advance bit counter immediately (don't wait for slot end)
                    if (current_bit == 7) begin
                        $display("[DS18B20] @%0t: Sent byte[%0d] = 0x%02X", $time, current_byte_idx, current_tx_byte);
                        bit_cnt <= 0;
                        data_idx <= current_byte_idx + 1;
                        tx_bytes_remaining <= tx_bytes_remaining - 1;

                        if (tx_bytes_remaining <= 1) begin
                            $display("[DS18B20] @%0t: All data sent", $time);
                            state <= S_IDLE;
                        end else begin
                            // Load next byte based on what we're sending
                            if (sending_scratchpad) begin
                                // Sending scratchpad data
                                case (current_byte_idx + 1)
                                    0: tx_byte <= scratchpad[0];
                                    1: tx_byte <= scratchpad[1];
                                    2: tx_byte <= scratchpad[2];
                                    3: tx_byte <= scratchpad[3];
                                    4: tx_byte <= scratchpad[4];
                                    5: tx_byte <= scratchpad[5];
                                    6: tx_byte <= scratchpad[6];
                                    7: tx_byte <= scratchpad[7];
                                    8: tx_byte <= scratchpad[8];
                                endcase
                            end else begin
                                // Sending ROM data
                                case (current_byte_idx + 1)
                                    0: tx_byte <= rom_data[0];
                                    1: tx_byte <= rom_data[1];
                                    2: tx_byte <= rom_data[2];
                                    3: tx_byte <= rom_data[3];
                                    4: tx_byte <= rom_data[4];
                                    5: tx_byte <= rom_data[5];
                                    6: tx_byte <= rom_data[6];
                                    7: tx_byte <= rom_data[7];
                                endcase
                            end
                        end
                    end else begin
                        bit_cnt <= current_bit + 1;
                    end

                    // Release busy flag immediately so we're ready for next slot
                    tx_busy <= 0;
                end
            join_none
        end
    end

endmodule
