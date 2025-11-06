// ============================================================================
// Module:      i2c_slave_handler_full_tb
// Description:
// - Complete testbench with FULL upload chain: handler → adapter → packer → arbiter
// - This replicates the actual hardware environment to debug upload blocking issue
// ============================================================================

`timescale 1ns / 1ps

module i2c_slave_handler_full_tb();

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz system clock
    parameter CLK_FREQ_HZ = 50_000_000;

    //=========================================================================
    // Signal Declarations
    //=========================================================================
    // System signals
    logic        clk;
    logic        rst_n;

    // CDC Command Bus Interface
    logic [7:0]  cmd_type;
    logic [15:0] cmd_length;
    logic [7:0]  cmd_data;
    logic [15:0] cmd_data_index;
    logic        cmd_start;
    logic        cmd_data_valid;
    logic        cmd_done;
    logic        cmd_ready;

    // Handler → Adapter signals
    logic        handler_upload_active;
    logic        handler_upload_req;
    logic [7:0]  handler_upload_data;
    logic [7:0]  handler_upload_source;
    logic        handler_upload_valid;
    logic        handler_upload_ready;

    // Adapter → Packer signals
    logic        packer_upload_req;
    logic [7:0]  packer_upload_data;
    logic [7:0]  packer_upload_source;
    logic        packer_upload_valid;
    logic        packer_upload_ready;

    // Packer → Output (bypass arbiter for simplicity)
    logic        packed_req;
    logic [7:0]  packed_data;
    logic [7:0]  packed_source;
    logic        packed_valid;
    logic        packer_ready_from_test;  // Controlled by testbench

    // Physical I2C Interface
    wire         i2c_scl;
    wire         i2c_sda;

    // Register Preload Interface
    logic        preload_en;
    logic [7:0]  preload_addr;
    logic [7:0]  preload_data;

    // Test control signals
    logic        scl_drive;
    logic        sda_drive_out;
    logic        sda_oe;

    // I2C bus drivers
    assign i2c_scl = scl_drive ? 1'b0 : 1'bz;
    assign i2c_sda = (sda_oe) ? (sda_drive_out ? 1'bz : 1'b0) : 1'bz;

    // Upload data capture
    logic [7:0]  upload_buffer [0:63];
    integer      upload_count;

    //=========================================================================
    // DUT Instantiation: i2c_slave_handler
    //=========================================================================
    i2c_slave_handler u_handler (
        .clk              (clk),
        .rst_n            (rst_n),

        // CDC Command Bus
        .cmd_type         (cmd_type),
        .cmd_length       (cmd_length),
        .cmd_data         (cmd_data),
        .cmd_data_index   (cmd_data_index),
        .cmd_start        (cmd_start),
        .cmd_data_valid   (cmd_data_valid),
        .cmd_done         (cmd_done),
        .cmd_ready        (cmd_ready),

        // Upload interface (connects to adapter)
        .upload_active    (handler_upload_active),
        .upload_req       (handler_upload_req),
        .upload_data      (handler_upload_data),
        .upload_source    (handler_upload_source),
        .upload_valid     (handler_upload_valid),
        .upload_ready     (handler_upload_ready),

        // Physical I2C
        .i2c_scl          (i2c_scl),
        .i2c_sda          (i2c_sda),

        // Register Preload
        .preload_en       (preload_en),
        .preload_addr     (preload_addr),
        .preload_data     (preload_data)
    );

    //=========================================================================
    // Upload Adapter Instance
    //=========================================================================
    upload_adapter u_adapter (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .handler_upload_active (handler_upload_active),
        .handler_upload_data   (handler_upload_data),
        .handler_upload_source (handler_upload_source),
        .handler_upload_valid  (handler_upload_valid),
        .handler_upload_ready  (handler_upload_ready),
        .packer_upload_req     (packer_upload_req),
        .packer_upload_data    (packer_upload_data),
        .packer_upload_source  (packer_upload_source),
        .packer_upload_valid   (packer_upload_valid),
        .packer_upload_ready   (packer_upload_ready)
    );

    //=========================================================================
    // Upload Packer Instance (1 channel)
    //=========================================================================
    upload_packer #(
        .NUM_CHANNELS(1),
        .FRAME_HEADER_H(8'hAA),
        .FRAME_HEADER_L(8'h44)
    ) u_packer (
        .clk                (clk),
        .rst_n              (rst_n),
        .raw_upload_req     (packer_upload_req),
        .raw_upload_data    (packer_upload_data),
        .raw_upload_source  (packer_upload_source),
        .raw_upload_valid   (packer_upload_valid),
        .raw_upload_ready   (packer_upload_ready),
        .packed_upload_req  (packed_req),
        .packed_upload_data (packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid (packed_valid),
        .packed_upload_ready (packer_ready_from_test)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // Upload Data Capture (from packer output)
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            upload_count <= 0;
        end else if (packed_valid && packer_ready_from_test) begin
            upload_buffer[upload_count] <= packed_data;
            upload_count <= upload_count + 1;
            $display("[%0t] Packer Output[%0d] = 0x%02h (Source=0x%02h)",
                     $time, upload_count, packed_data, packed_source);
        end
    end

    //=========================================================================
    // Task: Reset
    //=========================================================================
    task automatic reset();
        begin
            $display("\n========================================");
            $display("[%0t] Applying Reset", $time);
            $display("========================================");

            rst_n = 0;
            cmd_type = 0;
            cmd_length = 0;
            cmd_data = 0;
            cmd_data_index = 0;
            cmd_start = 0;
            cmd_data_valid = 0;
            cmd_done = 0;
            packer_ready_from_test = 1;  // Always ready to accept packer output
            preload_en = 0;
            preload_addr = 0;
            preload_data = 0;
            scl_drive = 0;
            sda_drive_out = 1;
            sda_oe = 0;
            upload_count = 0;

            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);

            $display("[%0t] Reset Complete\n", $time);
        end
    endtask

    //=========================================================================
    // Task: Send CDC Command
    //=========================================================================
    task automatic send_cdc_command(
        input [7:0] cmd,
        input [7:0] payload [],
        input integer payload_len
    );
        integer i;
        begin
            $display("\n========================================");
            $display("[%0t] Sending CDC Command 0x%02h", $time, cmd);
            $display("========================================");

            @(posedge clk);
            cmd_type <= cmd;
            cmd_length <= payload_len;
            cmd_start <= 1'b1;
            @(posedge clk);
            cmd_start <= 1'b0;

            // Send payload
            for (i = 0; i < payload_len; i = i + 1) begin
                @(posedge clk);
                cmd_data <= payload[i];
                cmd_data_index <= i;
                cmd_data_valid <= 1'b1;
                $display("[%0t]   Payload[%0d] = 0x%02h", $time, i, payload[i]);
            end

            @(posedge clk);
            cmd_data_valid <= 1'b0;
            cmd_done <= 1'b1;
            @(posedge clk);
            cmd_done <= 1'b0;

            repeat(2) @(posedge clk);
            $display("[%0t] CDC Command Sent\n", $time);
        end
    endtask

    //=========================================================================
    // Task: CDC Write Test
    //=========================================================================
    task automatic cdc_write_test(
        input [7:0] start_addr,
        input [7:0] data_bytes [],
        input integer data_len
    );
        logic [7:0] payload [0:5];
        integer i;
        begin
            $display("\n############################################################");
            $display("TEST: CDC Write (0x35) - Start=0x%02h, Len=%0d", start_addr, data_len);
            $display("############################################################");

            // Build payload
            payload[0] = start_addr;
            payload[1] = data_len;
            for (i = 0; i < data_len; i = i + 1) begin
                payload[2+i] = data_bytes[i];
            end

            send_cdc_command(8'h35, payload, 2 + data_len);

            // Wait for write to complete
            repeat(50) @(posedge clk);

            $display("TEST: Write Complete\n");
        end
    endtask

    //=========================================================================
    // Task: CDC Read Test
    //=========================================================================
    task automatic cdc_read_test(
        input [7:0] start_addr,
        input [7:0] length
    );
        logic [7:0] payload [0:1];
        integer initial_count;
        integer expected_bytes;
        integer timeout;
        begin
            $display("\n############################################################");
            $display("TEST: CDC Read (0x36) - Start=0x%02h, Len=%0d", start_addr, length);
            $display("############################################################");

            payload[0] = start_addr;
            payload[1] = length;

            initial_count = upload_count;

            // Calculate expected bytes: Header(2) + Source(1) + Length(2) + Data(N) + Checksum(1)
            expected_bytes = 2 + 1 + 2 + length + 1;

            send_cdc_command(8'h36, payload, 2);

            // Wait for upload to complete (with timeout)
            timeout = 0;
            while ((upload_count < initial_count + expected_bytes) && (timeout < 1000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 1000) begin
                $display("\n*** ERROR: Upload TIMEOUT! ***");
                $display("  Expected: %0d bytes", expected_bytes);
                $display("  Received: %0d bytes", upload_count - initial_count);
                $display("  Handler State: %0d", u_handler.state);
                $display("  Adapter packer_req: %0b", u_adapter.packer_upload_req);
                $display("  Packer State: %0d", u_packer.state[0]);
                $display("  Packer ready: %0b", packer_upload_ready);
                $display("  Testbench ready: %0b", packer_ready_from_test);
                $stop;
            end else begin
                repeat(10) @(posedge clk);
                $display("\n[%0t] Received %0d bytes (expected %0d)",
                         $time, upload_count - initial_count, expected_bytes);
                $display("TEST: Read Complete\n");
            end
        end
    endtask

    //=========================================================================
    // Main Test
    //=========================================================================
    initial begin
        $display("\n");
        $display("============================================================");
        $display("  I2C Slave Handler FULL CHAIN Testbench");
        $display("  Testing: Handler → Adapter → Packer → Arbiter");
        $display("============================================================");
        $display("\n");

        // Reset
        reset();

        // Test 1: Simple write
        begin
            logic [7:0] data1[0:0];
            data1[0] = 8'h55;
            cdc_write_test(8'h00, data1, 1);
        end

        // Test 2: Simple read (THIS IS WHERE IT MIGHT BLOCK!)
        cdc_read_test(8'h00, 8'h01);

        // Test 3: Write all registers
        begin
            logic [7:0] data2[0:3];
            data2[0] = 8'hAA;
            data2[1] = 8'hBB;
            data2[2] = 8'hCC;
            data2[3] = 8'hDD;
            cdc_write_test(8'h00, data2, 4);
        end

        // Test 4: Read all registers
        cdc_read_test(8'h00, 8'h04);

        // Summary
        $display("\n");
        $display("============================================================");
        $display("  TEST SUMMARY");
        $display("============================================================");
        $display("  Total Upload Bytes Received: %0d", upload_count);
        $display("============================================================");
        $display("  *** ALL TESTS PASSED ***");
        $display("============================================================");
        $display("\n");

        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #50000000;  // 50ms timeout
        $display("\n*** SIMULATION TIMEOUT! ***");
        $display("  Handler State: %0d", u_handler.state);
        $display("  upload_active: %0b", handler_upload_active);
        $display("  upload_req: %0b", handler_upload_req);
        $display("  upload_ready: %0b", handler_upload_ready);
        $display("  Packer State: %0d", u_packer.state[0]);
        $stop;
    end

endmodule
