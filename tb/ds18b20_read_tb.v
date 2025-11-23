// ============================================================================
// Module: ds18b20_read_tb
// Description: Testbench to verify one_wire_handler READ functionality
//              with DS18B20 behavioral model
// ============================================================================
`timescale 1ns / 1ps

module ds18b20_read_tb;

    // ==================== Clock and Reset ====================
    reg clk;
    reg rst_n;

    // Clock generation: 25MHz (40ns period)
    initial begin
        clk = 0;
        forever #20 clk = ~clk;
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

    // ==================== DUT: 1-Wire Handler (Master) ====================
    one_wire_handler #(
        .CLK_FREQ(25_000_000)
    ) dut_master (
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

    // ==================== DS18B20 Model ====================
    ds18b20_simple_model ds18b20 (
        .dq(onewire_io)
    );

    // ==================== Capture Upload Data ====================
    reg [7:0] received_data [0:15];
    integer received_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            received_count <= 0;
        end else if (upload_valid && upload_ready) begin
            received_data[received_count] <= upload_data;
            $display("[UPLOAD] @%0t: Received byte[%0d] = 0x%02X", $time, received_count, upload_data);
            received_count <= received_count + 1;
        end
    end

    // ==================== Monitor Handler State ====================
    reg [3:0] last_handler_state;
    always @(posedge clk) begin
        if (dut_master.handler_state != last_handler_state) begin
            $display("[HANDLER] @%0t: State %0d -> %0d", $time, last_handler_state, dut_master.handler_state);
            last_handler_state <= dut_master.handler_state;
        end
    end

    // ==================== Test Tasks ====================
    task automatic send_cmd_start;
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

    task automatic send_data_byte;
        input [7:0] data;
        begin
            @(posedge clk);
            cmd_data <= data;
            cmd_data_valid <= 1;
            @(posedge clk);
            cmd_data_valid <= 0;
        end
    endtask

    task automatic signal_cmd_done;
        begin
            @(posedge clk);
            cmd_done <= 1;
            @(posedge clk);
            cmd_done <= 0;
        end
    endtask

    task automatic wait_for_idle;
        begin
            wait(dut_master.handler_state == 4'd0);
            repeat(100) @(posedge clk);
        end
    endtask

    // ==================== Test Sequence ====================
    initial begin
        $display("==============================================================");
        $display("  DS18B20 Read Test: one_wire_handler READ functionality");
        $display("  Clock: 25MHz");
        $display("==============================================================");

        // Initialize signals
        rst_n = 0;
        cmd_type = 0;
        cmd_length = 0;
        cmd_data = 0;
        cmd_data_index = 0;
        cmd_start = 0;
        cmd_data_valid = 0;
        cmd_done = 0;
        upload_ready = 1;
        last_handler_state = 0;

        // Reset
        repeat(100) @(posedge clk);
        rst_n = 1;
        $display("\n[TEST] System reset released\n");

        repeat(500) @(posedge clk);

        // ===================== Test 1: Reset =====================
        $display("\n============================================");
        $display("[TEST 1] 1-Wire Reset");
        $display("============================================");

        send_cmd_start(8'h20, 16'd0);  // CMD_ONEWIRE_RESET
        signal_cmd_done();

        #2_000_000;  // 2ms for reset sequence
        wait_for_idle();

        $display("[TEST 1] Reset complete, presence detected: %b", dut_master.ow_presence_detected);

        // ===================== Test 2: Read ROM =====================
        $display("\n============================================");
        $display("[TEST 2] Read ROM (0x33) - Write 1 byte, Read 8 bytes");
        $display("============================================");

        received_count = 0;

        // Reset first
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // CMD_ONEWIRE_WRITE_READ (0x23): write_len=1, read_len=8, data=0x33
        send_cmd_start(8'h23, 16'd3);  // Length = write_len + read_len + data
        send_data_byte(8'd1);   // write_len = 1
        send_data_byte(8'd8);   // read_len = 8
        send_data_byte(8'h33);  // Read ROM command
        signal_cmd_done();

        $display("[TEST 2] Waiting for Read ROM response...");
        #15_000_000;  // 15ms timeout
        wait_for_idle();

        $display("\n[TEST 2] Results:");
        $display("  Received %0d bytes", received_count);
        if (received_count >= 8) begin
            $display("  ROM ID: %02X %02X %02X %02X %02X %02X %02X %02X",
                     received_data[0], received_data[1], received_data[2], received_data[3],
                     received_data[4], received_data[5], received_data[6], received_data[7]);
            $display("  Family Code: 0x%02X (expected 0x28 for DS18B20)", received_data[0]);

            if (received_data[0] == 8'h28) begin
                $display("[TEST 2] PASS: Family code matches DS18B20!");
            end else begin
                $display("[TEST 2] FAIL: Family code mismatch!");
            end
        end else begin
            $display("[TEST 2] FAIL: Did not receive 8 bytes!");
        end

        // ===================== Test 3: Read Temperature =====================
        $display("\n============================================");
        $display("[TEST 3] Read Temperature (Skip ROM + Convert T + Read Scratchpad)");
        $display("============================================");

        received_count = 0;

        // Step 1: Reset
        $display("[TEST 3.1] Reset...");
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // Step 2: Skip ROM (0xCC)
        $display("[TEST 3.2] Skip ROM (0xCC)...");
        send_cmd_start(8'h21, 16'd1);  // CMD_ONEWIRE_WRITE
        send_data_byte(8'hCC);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // Step 3: Convert T (0x44)
        $display("[TEST 3.3] Convert T (0x44)...");
        send_cmd_start(8'h21, 16'd1);
        send_data_byte(8'h44);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // Step 4: Reset again
        $display("[TEST 3.4] Reset again...");
        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // Step 5: Skip ROM
        $display("[TEST 3.5] Skip ROM (0xCC)...");
        send_cmd_start(8'h21, 16'd1);
        send_data_byte(8'hCC);
        signal_cmd_done();
        #2_000_000;
        wait_for_idle();

        // Step 6: Read Scratchpad (0xBE) - read 9 bytes
        $display("[TEST 3.6] Read Scratchpad (0xBE)...");
        send_cmd_start(8'h23, 16'd3);  // CMD_ONEWIRE_WRITE_READ
        send_data_byte(8'd1);   // write_len = 1
        send_data_byte(8'd9);   // read_len = 9
        send_data_byte(8'hBE);  // Read Scratchpad command
        signal_cmd_done();

        $display("[TEST 3.6] Waiting for Scratchpad response...");
        #20_000_000;  // 20ms timeout
        wait_for_idle();

        $display("\n[TEST 3] Results:");
        $display("  Received %0d bytes", received_count);
        if (received_count >= 2) begin
            $display("  Scratchpad: %02X %02X %02X %02X %02X %02X %02X %02X %02X",
                     received_data[0], received_data[1], received_data[2], received_data[3],
                     received_data[4], received_data[5], received_data[6], received_data[7],
                     received_count >= 9 ? received_data[8] : 8'hXX);

            // Parse temperature (LSB first)
            begin
                reg signed [15:0] temp_raw;
                real temperature;

                temp_raw = {received_data[1], received_data[0]};
                temperature = temp_raw / 16.0;

                $display("  Temperature raw: 0x%04X", temp_raw);
                $display("  Temperature: %.4f C (expected 25.0 C)", temperature);

                if (temperature > 24.9 && temperature < 25.1) begin
                    $display("[TEST 3] PASS: Temperature is correct!");
                end else begin
                    $display("[TEST 3] FAIL: Temperature mismatch!");
                end
            end
        end else begin
            $display("[TEST 3] FAIL: Did not receive temperature data!");
        end

        // ===================== Summary =====================
        $display("\n==============================================================");
        $display("  Test Complete");
        $display("==============================================================");

        repeat(1000) @(posedge clk);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100_000_000;  // 100ms timeout
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
