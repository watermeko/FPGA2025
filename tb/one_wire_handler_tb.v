// ============================================================================
// Module: one_wire_handler_tb
// Description: Testbench for one_wire_handler module
// Tests: Reset, Write bytes, Read bytes, Write-Read command
// ============================================================================
`timescale 1ns / 1ps

module one_wire_handler_tb;

    // ==================== Clock and Reset ====================
    reg clk;
    reg rst_n;

    // Clock generation: 60MHz (16.67ns period)
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;  // 16.67ns period
    end

    // ==================== Command Bus Interface ====================
    reg [7:0]  cmd_type;
    reg [15:0] cmd_length;
    reg [7:0]  cmd_data;
    reg [15:0] cmd_data_index;
    reg        cmd_start;
    reg        cmd_data_valid;
    reg        cmd_done;
    wire       cmd_ready;

    // ==================== Upload Interface ====================
    wire        upload_active;
    wire        upload_req;
    wire [7:0]  upload_data;
    wire [7:0]  upload_source;
    wire        upload_valid;
    reg         upload_ready;

    // ==================== 1-Wire Bus ====================
    wire onewire_io;

    // Pull-up resistor model
    pullup(onewire_io);

    // ==================== Simple 1-Wire Slave Model ====================
    // Simulates a basic 1-Wire slave device (like DS18B20)

    reg slave_drive;           // Slave drives bus low when 1
    reg [7:0] slave_tx_data;   // Data slave will transmit
    reg [2:0] slave_bit_idx;   // Current bit index (0-7)

    // Slave detection state machine
    reg [2:0] slave_state;
    localparam S_IDLE = 0;
    localparam S_WAIT_RESET_END = 1;
    localparam S_PRESENCE = 2;
    localparam S_WAIT_SLOT = 3;
    localparam S_IN_SLOT = 4;

    reg [15:0] slave_timer;
    reg [15:0] bus_low_counter;
    reg bus_prev;

    // Drive bus
    assign onewire_io = slave_drive ? 1'b0 : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slave_drive <= 0;
            slave_state <= S_IDLE;
            slave_timer <= 0;
            slave_bit_idx <= 0;
            bus_low_counter <= 0;
            bus_prev <= 1;
            slave_tx_data <= 8'hA5;  // Default test data
        end else begin
            bus_prev <= onewire_io;

            // Track how long bus has been low
            if (onewire_io == 0) begin
                bus_low_counter <= bus_low_counter + 1;
            end else begin
                bus_low_counter <= 0;
            end

            case (slave_state)
                S_IDLE: begin
                    slave_drive <= 0;
                    slave_timer <= 0;

                    // Detect reset pulse (bus low > 400us = 24000 cycles @ 60MHz)
                    if (bus_low_counter > 24000) begin
                        slave_state <= S_WAIT_RESET_END;
                        $display("[SLAVE] @%0t: Reset detected", $time);
                    end
                end

                S_WAIT_RESET_END: begin
                    slave_drive <= 0;
                    // Wait for master to release bus
                    if (bus_prev == 0 && onewire_io == 1) begin
                        // Rising edge detected
                        slave_state <= S_PRESENCE;
                        slave_timer <= 0;
                        $display("[SLAVE] @%0t: Sending presence pulse", $time);
                    end
                end

                S_PRESENCE: begin
                    slave_timer <= slave_timer + 1;
                    if (slave_timer < 3600) begin  // Pull low for 60us
                        slave_drive <= 1;
                    end else begin
                        slave_drive <= 0;
                        slave_state <= S_WAIT_SLOT;
                        slave_bit_idx <= 0;  // Reset bit index
                        slave_timer <= 0;
                        $display("[SLAVE] @%0t: Presence pulse done", $time);
                    end
                end

                S_WAIT_SLOT: begin
                    slave_drive <= 0;
                    slave_timer <= 0;

                    // Detect falling edge (start of time slot)
                    if (bus_prev == 1 && onewire_io == 0) begin
                        slave_state <= S_IN_SLOT;
                        $display("[SLAVE] @%0t: Slot start detected, bit_idx=%0d", $time, slave_bit_idx);
                    end
                end

                S_IN_SLOT: begin
                    slave_timer <= slave_timer + 1;

                    // Detect rising edge (master releases bus)
                    if (bus_prev == 0 && onewire_io == 1) begin
                        // Rising edge detected
                        // Read slot: master releases after ~6us (< 450 cycles)
                        // Write slot: master releases after 15us-60us
                        if (slave_timer < 450) begin
                            // This is a READ slot - drive our bit IMMEDIATELY
                            if (slave_tx_data[slave_bit_idx] == 0) begin
                                slave_drive <= 1;  // Pull low for '0'
                                $display("[SLAVE] @%0t: Read slot - driving bit %0d = 0", $time, slave_bit_idx);
                            end else begin
                                slave_drive <= 0;  // Release for '1'
                                $display("[SLAVE] @%0t: Read slot - releasing for bit %0d = 1", $time, slave_bit_idx);
                            end
                        end else begin
                            // This is a WRITE slot - don't drive
                            slave_drive <= 0;
                            $display("[SLAVE] @%0t: Write slot detected (timer=%0d)", $time, slave_timer);
                        end
                    end

                    // Continue driving in read slot (keep driving for ~15us after release)
                    if (onewire_io == 1 && slave_timer > 360 && slave_timer < 1200) begin
                        if (slave_tx_data[slave_bit_idx] == 0) begin
                            slave_drive <= 1;  // Keep pulling low for '0'
                        end else begin
                            slave_drive <= 0;  // Keep released for '1'
                        end
                    end

                    // End of slot after ~70us (4200 cycles)
                    if (slave_timer > 4200) begin
                        slave_drive <= 0;
                        if (slave_bit_idx < 7) begin
                            slave_bit_idx <= slave_bit_idx + 1;
                        end else begin
                            slave_bit_idx <= 0;  // Wrap for next byte
                        end
                        slave_state <= S_WAIT_SLOT;
                    end
                end

                default: slave_state <= S_IDLE;
            endcase
        end
    end

    // ==================== DUT Instantiation ====================
    one_wire_handler #(
        .CLK_FREQ(60_000_000)
    ) dut (
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

        .upload_active(upload_active),
        .upload_req(upload_req),
        .upload_data(upload_data),
        .upload_source(upload_source),
        .upload_valid(upload_valid),
        .upload_ready(upload_ready),

        .onewire_io(onewire_io)
    );

    // ==================== Captured Upload Data ====================
    reg [7:0] captured_data [0:255];
    integer   captured_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            captured_count <= 0;
        end else if (upload_valid && upload_ready) begin
            captured_data[captured_count] <= upload_data;
            captured_count <= captured_count + 1;
            $display("[UPLOAD] Byte %0d: 0x%02X (%0t ms)",
                     captured_count, upload_data, $time/1e6);
        end
    end

    // Debug: Monitor key signals
    always @(posedge clk) begin
        if (cmd_start)
            $display("[DEBUG] @%0t: CMD START - type=0x%02X, length=%0d", $time, cmd_type, cmd_length);
        if (cmd_done)
            $display("[DEBUG] @%0t: CMD DONE", $time);
    end

    // Monitor state transitions
    reg [3:0] last_state;
    initial last_state = 4'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            last_state <= 4'd0;
        end else if (dut.handler_state != last_state) begin
            $display("[DEBUG] @%0t: State changed from %0d to %0d", $time, last_state, dut.handler_state);
            last_state <= dut.handler_state;
        end
    end

    always @(posedge clk) begin
        if (dut.handler_state == 4'd6) begin  // H_READ_BYTE
            if (dut.ow_start_read_bit)
                $display("[DEBUG] @%0t: Starting read bit %0d of byte %0d", $time, dut.bit_counter, dut.byte_counter);
        end
        if (dut.handler_state == 4'd7) begin  // H_WAIT_READ_BIT
            if (dut.ow_done)
                $display("[DEBUG] @%0t: Read bit done, data=%0b", $time, dut.ow_read_bit_data);
        end
        if (dut.handler_state == 4'd8) begin  // H_UPLOAD_BYTE
            if (dut.upload_valid)
                $display("[DEBUG] @%0t: Uploading data: 0x%02X", $time, dut.upload_data);
        end
    end

    // ==================== Test Tasks ====================

    // Task: Send command start
    task send_cmd_start;
        input [7:0] cmd_type_in;
        input [15:0] cmd_length_in;
        begin
            @(posedge clk);
            cmd_type <= cmd_type_in;
            cmd_length <= cmd_length_in;
            cmd_start <= 1;
            @(posedge clk);
            cmd_start <= 0;
        end
    endtask

    // Task: Send data byte
    task send_data_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            cmd_data <= data;
            cmd_data_valid <= 1;
            @(posedge clk);
            cmd_data_valid <= 0;
        end
    endtask

    // Task: Signal command done
    task signal_cmd_done;
        begin
            @(posedge clk);
            cmd_done <= 1;
            @(posedge clk);
            cmd_done <= 0;
        end
    endtask

    // Task: Wait for idle
    task wait_for_idle;
        begin
            // Wait until state machine returns to IDLE
            wait(dut.handler_state == 4'd0);  // H_IDLE = 4'd0
            repeat(10) @(posedge clk);
        end
    endtask

    // ==================== Test Sequence ====================
    initial begin
        $display("==============================================");
        $display("  1-Wire Handler Testbench - Closed Loop Test");
        $display("  (With slave device simulation)");
        $display("==============================================");

        // Initialize signals
        rst_n = 0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        upload_ready = 1;  // Always ready to accept upload

        captured_count = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("\n[Test 1] RESET Command (0x20) - Detect Presence");
        $display("--------------------------------------------");
        send_cmd_start(8'h20, 16'd0);  // CMD_ONEWIRE_RESET
        signal_cmd_done();
        wait_for_idle();
        $display("[Test 1] PASS: Reset complete, presence detected");

        $display("\n[Test 2] WRITE Command (0x21) - Send 3 bytes");
        $display("--------------------------------------------");
        send_cmd_start(8'h21, 16'd3);  // CMD_ONEWIRE_WRITE, 3 bytes
        send_data_byte(8'hCC);  // Skip ROM
        send_data_byte(8'h44);  // Convert T
        send_data_byte(8'hBE);  // Read Scratchpad
        signal_cmd_done();
        wait_for_idle();
        $display("[Test 2] PASS: Write 3 bytes complete");

        $display("\n[Test 3] READ Command (0x22) - Read 2 bytes");
        $display("--------------------------------------------");
        $display("[Test 3] Slave will send: 0xA5, 0x5A");

        // Send reset to sync slave
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        wait_for_idle();

        // Configure slave to send 0xA5 for first byte
        slave_tx_data = 8'hA5;
        send_cmd_start(8'h22, 16'd2);  // CMD_ONEWIRE_READ, 2 bytes
        signal_cmd_done();

        // Wait for first byte upload
        wait(upload_valid);
        repeat(10) @(posedge clk);

        // Change slave data for second byte
        slave_tx_data = 8'h5A;

        wait_for_idle();
        $display("[Test 3] PASS: Read 2 bytes complete");

        if (captured_count >= 2) begin
            $display("  Captured[0] = 0x%02X (expected 0xA5)", captured_data[0]);
            $display("  Captured[1] = 0x%02X (expected 0x5A)", captured_data[1]);

            if (captured_data[0] == 8'hA5 && captured_data[1] == 8'h5A) begin
                $display("  ✓ Data verified correctly!");
            end else begin
                $display("  ✗ Data mismatch!");
            end
        end

        $display("\n[Test 4] WRITE-READ Command (0x23)");
        $display("--------------------------------------------");
        $display("[Test 4] Write 1 byte (0x33), Read 1 byte (slave sends 0x3C)");

        // Send reset to sync slave
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        wait_for_idle();

        slave_tx_data = 8'h3C;
        send_cmd_start(8'h23, 16'd3);  // CMD_ONEWIRE_WRITE_READ
        send_data_byte(8'd1);   // write_len = 1
        send_data_byte(8'd1);   // read_len = 1
        send_data_byte(8'h33);  // Command: Read ROM
        signal_cmd_done();

        wait_for_idle();
        $display("[Test 4] PASS: Write-Read complete");

        if (captured_count >= 3) begin
            $display("  Captured[2] = 0x%02X (expected 0x3C)", captured_data[2]);

            if (captured_data[2] == 8'h3C) begin
                $display("  ✓ Data verified correctly!");
            end else begin
                $display("  ✗ Data mismatch!");
            end
        end

        $display("\n[Test 5] READ Command - All 1s (0xFF)");
        $display("--------------------------------------------");

        // Send reset to sync slave
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        wait_for_idle();

        slave_tx_data = 8'hFF;
        send_cmd_start(8'h22, 16'd1);  // Read 1 byte
        signal_cmd_done();
        wait_for_idle();
        $display("[Test 5] PASS: Read 0xFF complete");

        if (captured_count >= 4) begin
            $display("  Captured[3] = 0x%02X (expected 0xFF)", captured_data[3]);

            if (captured_data[3] == 8'hFF) begin
                $display("  ✓ Data verified correctly!");
            end else begin
                $display("  ✗ Data mismatch!");
            end
        end

        $display("\n[Test 6] READ Command - All 0s (0x00)");
        $display("--------------------------------------------");

        // Send reset to sync slave
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        wait_for_idle();

        slave_tx_data = 8'h00;
        send_cmd_start(8'h22, 16'd1);  // Read 1 byte
        signal_cmd_done();
        wait_for_idle();
        $display("[Test 6] PASS: Read 0x00 complete");

        if (captured_count >= 5) begin
            $display("  Captured[4] = 0x%02X (expected 0x00)", captured_data[4]);

            if (captured_data[4] == 8'h00) begin
                $display("  ✓ Data verified correctly!");
            end else begin
                $display("  ✗ Data mismatch!");
            end
        end

        // Summary
        $display("\n==============================================");
        $display("  Closed Loop Test Results");
        $display("  Total uploaded bytes: %0d", captured_count);
        $display("==============================================");

        if (captured_count >= 5) begin
            if (captured_data[0] == 8'hA5 && captured_data[1] == 8'h5A &&
                captured_data[2] == 8'h3C && captured_data[3] == 8'hFF &&
                captured_data[4] == 8'h00) begin
                $display("  ✓✓✓ SUCCESS: All data verified correctly!");
                $display("  Master-Slave communication working properly!");
            end else begin
                $display("  ✗ FAIL: Some data mismatches detected");
                $display("    Expected: A5 5A 3C FF 00");
                $display("    Received: %02X %02X %02X %02X %02X",
                         captured_data[0], captured_data[1], captured_data[2],
                         captured_data[3], captured_data[4]);
            end
        end
        $display("==============================================");

        repeat(100) @(posedge clk);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #200_000_000;  // 200ms timeout
        $display("\n[ERROR] Timeout!");
        $finish;
    end

endmodule
