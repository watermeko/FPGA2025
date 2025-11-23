// ============================================================================
// Module: one_wire_loopback_tb
// Description: Testbench using real one_wire.v slave to verify handler TX
// Adapted for one_wire.v: Single reset, continuous byte transmission
// ============================================================================
`timescale 1ns / 1ps

module one_wire_loopback_tb;

    // ==================== Clock and Reset ====================
    reg clk;
    reg rst_n;

    // Clock generation: 25MHz (40ns period) - matching slave's expected clock
    initial begin
        clk = 0;
        forever #20 clk = ~clk;  // 40ns period = 25MHz
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

    // Pull-up resistor model (active high when not driven low)
    pullup(onewire_io);

    // ==================== Slave Signals ====================
    wire [3:0]  slave_state_out;
    wire        slave_synchro_success;
    wire [7:0]  slave_data_byte;
    wire        slave_b_count;
    wire        slave_by_count;
    wire        slave_divided_clk;
    wire        slave_test_2_byte;
    wire        slave_test_synchro;
    wire [15:0] slave_mpcd;
    wire        slave_tocntr;
    wire        slave_error;

    // ==================== DUT: 1-Wire Handler (Master) ====================
    one_wire_handler #(
        .CLK_FREQ(25_000_000)  // 25MHz to match slave
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

    // ==================== Real Slave: one_wire.v ====================
    one_wire dut_slave (
        .led_port(onewire_io),
        .clk(clk),
        .state_out(slave_state_out),
        .synchro_success_out(slave_synchro_success),
        .ssss(slave_data_byte),
        .b_count(slave_b_count),
        .by_count(slave_by_count),
        .divided_clk(slave_divided_clk),
        .test_2_byte(slave_test_2_byte),
        .test_synchro(slave_test_synchro),
        .mpcd(slave_mpcd),
        .tocntr(slave_tocntr),
        .error(slave_error)
    );

    // ==================== Monitor Slave State ====================
    reg [3:0] last_slave_state;

    always @(posedge clk) begin
        if (slave_state_out != last_slave_state) begin
            case (slave_state_out)
                4'd0:  $display("[SLAVE] @%0t: State -> PRE_IDLE", $time);
                4'd1:  $display("[SLAVE] @%0t: State -> IDLE", $time);
                4'd2:  $display("[SLAVE] @%0t: State -> MASTER_PULSE (detecting reset)", $time);
                4'd3:  $display("[SLAVE] @%0t: State -> MASTER_PULSE_WAIT", $time);
                4'd4:  $display("[SLAVE] @%0t: State -> MASTER_DROP", $time);
                4'd5:  $display("[SLAVE] @%0t: State -> SLAVE_PRESENCE_PULSE", $time);
                4'd6:  $display("[SLAVE] @%0t: State -> WAITING_FOR_VCC", $time);
                4'd7:  $display("[SLAVE] @%0t: State -> WAITING_FOR_THE_BIT", $time);
                4'd8:  $display("[SLAVE] @%0t: State -> FIRST_HALF_TS", $time);
                4'd9:  $display("[SLAVE] @%0t: State -> SECOND_HALF_TS", $time);
                4'd10: $display("[SLAVE] @%0t: State -> END_BYTE", $time);
                4'd11: $display("[SLAVE] @%0t: State -> ERR", $time);
                default: $display("[SLAVE] @%0t: State -> UNKNOWN(%0d)", $time, slave_state_out);
            endcase
            last_slave_state <= slave_state_out;
        end
    end

    // Monitor slave received data
    reg [7:0] slave_received_bytes [0:9];
    integer slave_byte_count;
    reg [7:0] last_slave_data;

    // Monitor slave bit sampling
    reg [3:0] last_slave_bit_counter;
    always @(posedge clk) begin
        if (slave_state_out == 4'd8) begin  // FIRST_HALF_TS
            if (dut_slave.presence_first_counter == 14'd800) begin
                $display("[SLAVE] @%0t: Sampled bit[%0d] = %0d (bus=%0d)",
                         $time, dut_slave.bit_counter, onewire_io, onewire_io);
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            slave_byte_count <= 0;
            last_slave_data <= 8'd0;
        end else if (slave_state_out == 4'd10) begin  // END_BYTE state
            // Always display when entering END_BYTE
            $display("[SLAVE] @%0t: In END_BYTE state, data_byte=0x%02X, last=0x%02X",
                     $time, slave_data_byte, last_slave_data);
            if (slave_data_byte != last_slave_data) begin
                slave_received_bytes[slave_byte_count] <= slave_data_byte;
                $display("[SLAVE] @%0t: *** Received byte[%0d]: 0x%02X ***",
                         $time, slave_byte_count, slave_data_byte);
                slave_byte_count <= slave_byte_count + 1;
                last_slave_data <= slave_data_byte;
            end
        end
    end

    // Monitor slave error
    always @(posedge clk) begin
        if (slave_error) begin
            $display("[SLAVE] @%0t: *** ERROR detected! ***", $time);
        end
    end

    // ==================== Monitor Master State ====================
    reg [3:0] last_master_state;
    reg [3:0] last_ow_master_state;

    always @(posedge clk) begin
        if (dut_master.handler_state != last_master_state) begin
            $display("[MASTER] @%0t: Handler state %0d -> %0d",
                     $time, last_master_state, dut_master.handler_state);
            last_master_state <= dut_master.handler_state;
        end

        if (dut_master.u_one_wire_master.state != last_ow_master_state) begin
            $display("[OW_MASTER] @%0t: Core state %0d -> %0d (timer=%0d)",
                     $time, last_ow_master_state, dut_master.u_one_wire_master.state,
                     dut_master.u_one_wire_master.timer);
            last_ow_master_state <= dut_master.u_one_wire_master.state;
        end

        // Monitor master writing bits
        if (dut_master.ow_start_write_bit) begin
            $display("[MASTER] @%0t: Sending bit[%0d] = %0d (byte=0x%02X)",
                     $time, dut_master.bit_counter, dut_master.ow_write_bit_data,
                     dut_master.current_byte);
        end
    end

    // Monitor bus activity during critical sampling
    always @(posedge clk) begin
        // Monitor bus state when slave samples
        if (slave_state_out == 4'd8 && dut_slave.presence_first_counter == 14'd800) begin
            $display("[BUS DEBUG] @%0t: Slave sampling - bus=%0d, master_oe=%0d, master_out=%0d, slave_oe=%0d, slave_out=%0d",
                     $time, onewire_io,
                     dut_master.u_one_wire_master.oe,
                     dut_master.u_one_wire_master.output_val,
                     dut_slave.oe,
                     dut_slave.inout_reg);
        end

        // Monitor master state transitions during write
        if (dut_master.u_one_wire_master.state == 4'd5 && dut_master.u_one_wire_master.timer == 16'd0) begin
            $display("[BUS DEBUG] @%0t: Master ST_WRITE_LOW start - writing bit=%0d, oe will be 1",
                     $time, dut_master.ow_write_bit_data);
        end

        if (dut_master.u_one_wire_master.state == 4'd6 && dut_master.u_one_wire_master.timer == 16'd0) begin
            $display("[BUS DEBUG] @%0t: Master ST_WRITE_RECOVERY start - oe should be 0, bus should be released",
                     $time);
        end
    end

    // ==================== Test Tasks ====================

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

    task signal_cmd_done;
        begin
            @(posedge clk);
            cmd_done <= 1;
            @(posedge clk);
            cmd_done <= 0;
        end
    endtask

    task wait_for_master_idle;
        begin
            wait(dut_master.handler_state == 4'd0);
            repeat(100) @(posedge clk);
        end
    endtask

    task wait_for_slave_state;
        input [3:0] target_state;
        begin
            wait(slave_state_out == target_state);
            repeat(10) @(posedge clk);
        end
    endtask

    // ==================== Test Sequence ====================
    initial begin
        // Variable declarations (must come first in initial block)
        reg [7:0] expected_data [0:9];
        integer i;
        integer mismatch_count;

        $display("==============================================================");
        $display("  1-Wire Loopback Test: Handler (Master) <-> one_wire (Slave)");
        $display("  Clock: 25MHz");
        $display("  Test Strategy: Single Reset + Continuous Byte Transmission");
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
        last_slave_state = 4'd0;
        last_master_state = 4'd0;
        last_ow_master_state = 4'd0;
        last_slave_data = 8'd0;
        slave_byte_count = 0;

        // Reset
        repeat(100) @(posedge clk);
        rst_n = 1;
        $display("\n[TEST] System reset released, waiting for initialization...");

        // Wait for slave to reach IDLE state
        repeat(500) @(posedge clk);

        // ===================== Test 1: Initial Reset =====================
        $display("\n============================================");
        $display("[TEST 1] Initial RESET - Establish Communication");
        $display("============================================");
        $display("[TEST] Sending 1-Wire reset pulse...");

        send_cmd_start(8'h20, 16'd0);
        signal_cmd_done();

        // Wait for reset sequence to complete
        #1_000_000;  // 1ms for reset sequence
        wait_for_master_idle();

        if (slave_state_out == 4'd7) begin  // WAITING_FOR_THE_BIT
            $display("[TEST 1] PASS: Slave detected reset and ready to receive data!");
            $display("[TEST 1] Slave state: WAITING_FOR_THE_BIT (state 7)");
        end else if (slave_error) begin
            $display("[TEST 1] FAIL: Slave reported error!");
            $display("[TEST 1] Aborting test...");
            $finish;
        end else begin
            $display("[TEST 1] WARNING: Slave in unexpected state = %0d", slave_state_out);
        end

        // ===================== Test 2: Continuous Byte Transmission =====================
        $display("\n============================================");
        $display("[TEST 2] Continuous Byte Transmission (NO additional resets)");
        $display("============================================");
        $display("[TEST] Slave expects %0d bytes total (NUMBER_OF_BYTES)", 10);
        $display("[TEST] Sending test pattern: 0xAA, 0x55, 0xCC, 0x33, 0xF0, 0x0F, 0xFF, 0x00, 0xA5, 0x5A");

        // Send 10 bytes continuously (matching slave's NUMBER_OF_BYTES)
        send_cmd_start(8'h21, 16'd10);  // WRITE 10 bytes
        send_data_byte(8'hAA);
        send_data_byte(8'h55);
        send_data_byte(8'hCC);
        send_data_byte(8'h33);
        send_data_byte(8'hF0);
        send_data_byte(8'h0F);
        send_data_byte(8'hFF);
        send_data_byte(8'h00);
        send_data_byte(8'hA5);
        send_data_byte(8'h5A);
        signal_cmd_done();

        $display("[TEST] Master transmitting...");

        // Wait for all bytes to be transmitted
        #10_000_000;  // 10ms should be enough for 10 bytes
        wait_for_master_idle();

        $display("[TEST 2] Master transmission complete");

        // Give slave some time to process final byte
        repeat(1000) @(posedge clk);

        // ===================== Test 3: Verify Reception =====================
        $display("\n============================================");
        $display("[TEST 3] Verify Slave Reception");
        $display("============================================");

        $display("[SLAVE] Final state: %0d", slave_state_out);
        $display("[SLAVE] Error flag: %0d", slave_error);
        $display("[SLAVE] Total bytes received: %0d", slave_byte_count);

        // Initialize expected data
        expected_data[0] = 8'hAA;
        expected_data[1] = 8'h55;
        expected_data[2] = 8'hCC;
        expected_data[3] = 8'h33;
        expected_data[4] = 8'hF0;
        expected_data[5] = 8'h0F;
        expected_data[6] = 8'hFF;
        expected_data[7] = 8'h00;
        expected_data[8] = 8'hA5;
        expected_data[9] = 8'h5A;

        // Verify each byte
        mismatch_count = 0;

        $display("\n[VERIFICATION] Byte-by-byte comparison:");
        for (i = 0; i < 10; i = i + 1) begin
            if (i < slave_byte_count) begin
                if (slave_received_bytes[i] == expected_data[i]) begin
                    $display("  Byte[%0d]: 0x%02X == 0x%02X ✓",
                             i, slave_received_bytes[i], expected_data[i]);
                end else begin
                    $display("  Byte[%0d]: 0x%02X != 0x%02X ✗",
                             i, slave_received_bytes[i], expected_data[i]);
                    mismatch_count = mismatch_count + 1;
                end
            end else begin
                $display("  Byte[%0d]: NOT RECEIVED (expected 0x%02X) ✗",
                         i, expected_data[i]);
                mismatch_count = mismatch_count + 1;
            end
        end

        // ===================== Final Summary =====================
        $display("\n==============================================================");
        $display("  Test Summary");
        $display("==============================================================");
        $display("  Expected bytes: 10");
        $display("  Received bytes: %0d", slave_byte_count);
        $display("  Mismatches: %0d", mismatch_count);
        $display("  Slave final state: %0d", slave_state_out);
        $display("  Slave error flag: %0d", slave_error);
        $display("==============================================================");

        if (slave_byte_count == 10 && mismatch_count == 0 && !slave_error) begin
            $display("  ✓✓✓ TEST PASSED ✓✓✓");
            $display("  All 10 bytes transmitted and received correctly!");
        end else begin
            $display("  ✗✗✗ TEST FAILED ✗✗✗");
            if (slave_byte_count != 10)
                $display("  - Incomplete reception: %0d/10 bytes", slave_byte_count);
            if (mismatch_count > 0)
                $display("  - Data mismatches: %0d bytes", mismatch_count);
            if (slave_error)
                $display("  - Slave reported errors");
        end
        $display("==============================================================");

        repeat(1000) @(posedge clk);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50_000_000;  // 50ms timeout
        $display("\n[ERROR] Simulation timeout!");
        $display("  Slave state: %0d", slave_state_out);
        $display("  Master state: %0d", dut_master.handler_state);
        $display("  Bytes received: %0d/10", slave_byte_count);
        $finish;
    end

endmodule
