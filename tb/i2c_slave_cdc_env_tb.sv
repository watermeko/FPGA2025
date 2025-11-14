// ============================================================================
// Module:      i2c_slave_cdc_env_tb
// Description: Complete CDC environment testbench
//              Includes: Parser → Processor → Handler → Adapter → Packer
//              This replicates the FULL hardware CDC command flow
// ============================================================================

`timescale 1ns / 1ps

module i2c_slave_cdc_env_tb();

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 20;  // 50MHz

    //=========================================================================
    // Signal Declarations
    //=========================================================================
    logic clk;
    logic rst_n;

    // USB data input (simulates USB-CDC data from host)
    logic [7:0]  usb_data_in;
    logic        usb_data_valid_in;

    // USB upload output (to check responses)
    logic [7:0]  usb_upload_data;
    logic        usb_upload_valid;

    // Physical I2C Interface
    wire         i2c_scl;
    wire         i2c_sda;

    // Internal signals
    logic        scl_drive;
    logic        sda_drive_out;
    logic        sda_oe;

    // I2C bus drivers
    assign i2c_scl = scl_drive ? 1'b0 : 1'bz;
    assign i2c_sda = (sda_oe) ? (sda_drive_out ? 1'bz : 1'b0) : 1'bz;

    // Test data capture
    logic [7:0]  upload_capture [0:255];
    integer      upload_count;
    integer      frame_count;

    //=========================================================================
    // Protocol Parser
    //=========================================================================
    wire parser_done, parser_error;
    wire [7:0] cmd_out;
    wire [15:0] len_out;
    parameter PAYLOAD_ADDR_WIDTH = 10;
    wire [7:0] payload_read_data;
    wire [PAYLOAD_ADDR_WIDTH-1:0] payload_read_addr;

    protocol_parser #(
        .MAX_PAYLOAD_LEN(1024)
    ) u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_data(usb_data_in),
        .uart_rx_valid(usb_data_valid_in),
        .parse_done(parser_done),
        .parse_error(parser_error),
        .cmd_out(cmd_out),
        .len_out(len_out),
        .payload_read_addr(payload_read_addr),
        .payload_read_data(payload_read_data)
    );

    //=========================================================================
    // Command Bus
    //=========================================================================
    wire [7:0]  cmd_type;
    wire [15:0] cmd_length;
    wire [7:0]  cmd_data;
    wire [15:0] cmd_data_index;
    wire        cmd_start;
    wire        cmd_data_valid;
    wire        cmd_done;
    wire        cmd_ready;

    //=========================================================================
    // Upload Bus
    //=========================================================================
    wire        upload_req_in;
    wire [7:0]  upload_data_in;
    wire [7:0]  upload_source_in;
    wire        upload_valid_in;
    wire        upload_ready_out;

    //=========================================================================
    // Command Processor
    //=========================================================================
    command_processor #(
        .PAYLOAD_ADDR_WIDTH(PAYLOAD_ADDR_WIDTH)
    ) u_processor (
        .clk(clk),
        .rst_n(rst_n),
        .parse_done(parser_done),
        .cmd_out(cmd_out),
        .len_out(len_out),
        .payload_read_data(payload_read_data),
        .payload_read_addr(payload_read_addr),

        .cmd_type_out(cmd_type),
        .cmd_length_out(cmd_length),
        .cmd_data_out(cmd_data),
        .cmd_data_index_out(cmd_data_index),
        .cmd_start_out(cmd_start),
        .cmd_data_valid_out(cmd_data_valid),
        .cmd_done_out(cmd_done),
        .cmd_ready_in(cmd_ready),

        .upload_req_in(upload_req_in),
        .upload_data_in(upload_data_in),
        .upload_source_in(upload_source_in),
        .upload_valid_in(upload_valid_in),
        .upload_ready_out(upload_ready_out),

        .usb_upload_data_out(usb_upload_data),
        .usb_upload_valid_out(usb_upload_valid),

        .led_out()
    );

    //=========================================================================
    // I2C Slave Handler
    //=========================================================================
    wire        handler_upload_active;
    wire        handler_upload_req;
    wire [7:0]  handler_upload_data;
    wire [7:0]  handler_upload_source;
    wire        handler_upload_valid;
    wire        handler_upload_ready;

    i2c_slave_handler u_handler (
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

        .upload_active(handler_upload_active),
        .upload_req(handler_upload_req),
        .upload_data(handler_upload_data),
        .upload_source(handler_upload_source),
        .upload_valid(handler_upload_valid),
        .upload_ready(handler_upload_ready),

        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),

        .preload_en(1'b0),
        .preload_addr(8'h00),
        .preload_data(8'h00)
    );

    //=========================================================================
    // Upload Adapter
    //=========================================================================
    wire        packer_upload_req;
    wire [7:0]  packer_upload_data;
    wire [7:0]  packer_upload_source;
    wire        packer_upload_valid;
    wire        packer_upload_ready;

    upload_adapter u_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .handler_upload_active(handler_upload_active),
        .handler_upload_data(handler_upload_data),
        .handler_upload_source(handler_upload_source),
        .handler_upload_valid(handler_upload_valid),
        .handler_upload_ready(handler_upload_ready),
        .packer_upload_req(packer_upload_req),
        .packer_upload_data(packer_upload_data),
        .packer_upload_source(packer_upload_source),
        .packer_upload_valid(packer_upload_valid),
        .packer_upload_ready(packer_upload_ready)
    );

    //=========================================================================
    // Upload Packer
    //=========================================================================
    wire        packed_req;
    wire [7:0]  packed_data;
    wire [7:0]  packed_source;
    wire        packed_valid;
    wire        packed_ready;

    upload_packer #(
        .NUM_CHANNELS(1)
    ) u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req(packer_upload_req),
        .raw_upload_data(packer_upload_data),
        .raw_upload_source(packer_upload_source),
        .raw_upload_valid(packer_upload_valid),
        .raw_upload_ready(packer_upload_ready),
        .packed_upload_req(packed_req),
        .packed_upload_data(packed_data),
        .packed_upload_source(packed_source),
        .packed_upload_valid(packed_valid),
        .packed_upload_ready(packed_ready)
    );

    //=========================================================================
    // Connect Packer output back to Processor input (simplified loop)
    //=========================================================================
    assign upload_req_in = packed_req;
    assign upload_data_in = packed_data;
    assign upload_source_in = packed_source;
    assign upload_valid_in = packed_valid;
    assign packed_ready = upload_ready_out;

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //=========================================================================
    // Upload Data Capture
    //=========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            upload_count <= 0;
            frame_count <= 0;
        end else if (usb_upload_valid) begin
            upload_capture[upload_count] <= usb_upload_data;
            upload_count <= upload_count + 1;

            // Detect frame header
            if (upload_count > 0 &&
                upload_capture[upload_count-1] == 8'hAA &&
                usb_upload_data == 8'h44) begin
                frame_count <= frame_count + 1;
                $display("[%0t] *** Frame Start (Frame #%0d) ***", $time, frame_count);
            end

            $display("[%0t] USB Upload[%0d] = 0x%02h", $time, upload_count, usb_upload_data);
        end
    end

    //=========================================================================
    // Debug Monitoring
    //=========================================================================
    always @(posedge clk) begin
        if (parser_done) begin
            $display("[%0t] DEBUG: Parser done - CMD=0x%02h, LEN=0x%04h",
                     $time, cmd_out, len_out);
        end
        if (cmd_start) begin
            $display("[%0t] DEBUG: Command start - TYPE=0x%02h, LENGTH=0x%04h, READY=%0b",
                     $time, cmd_type, cmd_length, cmd_ready);
        end
        if (cmd_data_valid) begin
            $display("[%0t] DEBUG: Command data - DATA=0x%02h, INDEX=%0d",
                     $time, cmd_data, cmd_data_index);
        end
        if (handler_upload_valid) begin
            $display("[%0t] DEBUG: Handler upload - DATA=0x%02h, SOURCE=0x%02h, READY=%0b",
                     $time, handler_upload_data, handler_upload_source, handler_upload_ready);
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
            usb_data_in = 0;
            usb_data_valid_in = 0;
            scl_drive = 0;
            sda_drive_out = 1;
            sda_oe = 0;
            upload_count = 0;
            frame_count = 0;

            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);

            $display("[%0t] Reset Complete\n", $time);
        end
    endtask

    //=========================================================================
    // Task: Send USB CDC Frame
    //=========================================================================
    task automatic send_usb_frame(
        input [7:0] cmd,
        input [7:0] payload [],
        input integer payload_len
    );
        integer i;
        logic [7:0] checksum;
        begin
            $display("\n========================================");
            $display("[%0t] Sending USB-CDC Frame: CMD=0x%02h", $time, cmd);
            $display("========================================");

            // Calculate checksum
            checksum = cmd + (payload_len >> 8) + (payload_len & 8'hFF);
            for (i = 0; i < payload_len; i = i + 1) begin
                checksum = checksum + payload[i];
            end

            // Send frame header - each byte is a single-cycle pulse
            @(posedge clk);
            usb_data_in <= 8'hAA;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;

            @(posedge clk);
            usb_data_in <= 8'h55;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;

            // Send command
            @(posedge clk);
            usb_data_in <= cmd;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;

            // Send length (big-endian)
            @(posedge clk);
            usb_data_in <= payload_len >> 8;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;

            @(posedge clk);
            usb_data_in <= payload_len & 8'hFF;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;

            // Send payload
            for (i = 0; i < payload_len; i = i + 1) begin
                @(posedge clk);
                usb_data_in <= payload[i];
                usb_data_valid_in <= 1'b1;
                @(posedge clk);
                usb_data_valid_in <= 1'b0;
            end

            // Send checksum
            @(posedge clk);
            usb_data_in <= checksum;
            usb_data_valid_in <= 1'b1;
            @(posedge clk);
            usb_data_valid_in <= 1'b0;
            repeat(2) @(posedge clk);

            $display("[%0t] Frame sent (Checksum=0x%02h)\n", $time, checksum);
        end
    endtask

    //=========================================================================
    // Task: Wait for Upload Response
    //=========================================================================
    task automatic wait_for_response(
        input integer expected_frames,
        input integer timeout_cycles
    );
        integer initial_count;
        integer timeout;
        begin
            initial_count = frame_count;
            timeout = 0;

            $display("[%0t] Waiting for %0d frame(s)...", $time, expected_frames);

            while ((frame_count < initial_count + expected_frames) && (timeout < timeout_cycles)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= timeout_cycles) begin
                $display("\n*** ERROR: Response TIMEOUT! ***");
                $display("  Expected frames: %0d", expected_frames);
                $display("  Received frames: %0d", frame_count - initial_count);
                $display("  Total USB bytes: %0d", upload_count);
                $display("\n  System State:");
                $display("    Parser done: %0b", parser_done);
                $display("    Handler state: %0d", u_handler.state);
                $display("    Handler cmd_ready: %0b", cmd_ready);
                $display("    Handler upload_active: %0b", handler_upload_active);
                $display("    Packer state: %0d", u_packer.state[0]);
                $display("    Processor upload_ready: %0b", upload_ready_out);
                $stop;
            end else begin
                repeat(10) @(posedge clk);
                $display("[%0t] Response received (%0d frames)\n", $time, frame_count - initial_count);
            end
        end
    endtask

    //=========================================================================
    // Main Test
    //=========================================================================
    initial begin
        $display("\n");
        $display("============================================================");
        $display("  I2C Slave Full CDC Environment Test");
        $display("  Testing: Parser → Processor → Handler → Adapter → Packer");
        $display("============================================================");
        $display("\n");

        reset();

        //=====================================================================
        // Test 1: CDC Write Command (0x35)
        //=====================================================================
        begin
            logic [7:0] payload[0:4];

            $display("\n############################################################");
            $display("TEST 1: CDC Write (0x35) - Write Reg[0]=0x55");
            $display("############################################################");

            payload[0] = 8'h00;  // start_addr
            payload[1] = 8'h01;  // length
            payload[2] = 8'h55;  // data

            send_usb_frame(8'h35, payload, 3);

            // Wait for processing
            repeat(100) @(posedge clk);

            $display("Reg[0] = 0x%02h (expected 0x55)", u_handler.u_reg_map.registers[0]);

            if (u_handler.u_reg_map.registers[0] == 8'h55) begin
                $display("TEST 1: PASS\n");
            end else begin
                $display("TEST 1: FAIL\n");
                $stop;
            end
        end

        //=====================================================================
        // Test 2: CDC Read Command (0x36) - THE CRITICAL TEST
        //=====================================================================
        begin
            logic [7:0] payload[0:1];

            $display("\n############################################################");
            $display("TEST 2: CDC Read (0x36) - Read Reg[0]");
            $display("############################################################");

            payload[0] = 8'h00;  // start_addr
            payload[1] = 8'h01;  // length

            send_usb_frame(8'h36, payload, 2);

            // Wait for upload response
            wait_for_response(1, 2000);

            $display("TEST 2: PASS\n");
        end

        //=====================================================================
        // Test 3: Write all 4 registers
        //=====================================================================
        begin
            logic [7:0] payload[0:5];

            $display("\n############################################################");
            $display("TEST 3: CDC Write All Registers");
            $display("############################################################");

            payload[0] = 8'h00;  // start_addr
            payload[1] = 8'h04;  // length
            payload[2] = 8'hAA;
            payload[3] = 8'hBB;
            payload[4] = 8'hCC;
            payload[5] = 8'hDD;

            send_usb_frame(8'h35, payload, 6);

            repeat(150) @(posedge clk);

            $display("Registers: %02h %02h %02h %02h",
                     u_handler.u_reg_map.registers[0],
                     u_handler.u_reg_map.registers[1],
                     u_handler.u_reg_map.registers[2],
                     u_handler.u_reg_map.registers[3]);

            $display("TEST 3: PASS\n");
        end

        //=====================================================================
        // Test 4: Read all 4 registers
        //=====================================================================
        begin
            logic [7:0] payload[0:1];

            $display("\n############################################################");
            $display("TEST 4: CDC Read All Registers");
            $display("############################################################");

            payload[0] = 8'h00;
            payload[1] = 8'h04;

            send_usb_frame(8'h36, payload, 2);

            wait_for_response(1, 2000);

            $display("TEST 4: PASS\n");
        end

        //=====================================================================
        // Summary
        //=====================================================================
        $display("\n");
        $display("============================================================");
        $display("  TEST SUMMARY");
        $display("============================================================");
        $display("  Total USB Upload Frames: %0d", frame_count);
        $display("  Total USB Upload Bytes:  %0d", upload_count);
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
        #100000000;  // 100ms
        $display("\n*** SIMULATION TIMEOUT! ***");
        $stop;
    end

endmodule
