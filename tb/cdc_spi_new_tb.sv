`timescale 1ns / 1ps
// ============================================================================
// CDC SPI Testbench - Testing SPI functionality in the full CDC module
// ============================================================================

module cdc_spi_new_tb;

    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;

    // DUT Signals
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;

    wire       spi_clk;
    wire       spi_cs_n;
    wire       spi_mosi;
    reg        spi_miso;
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    wire [7:0] pwm_pins;
    wire       ext_uart_tx;
    wire       led_out;
    wire [13:0] dac_data;
    wire       dac_clk_out;
    wire       debug_out;

    integer i;

    // ========================================================================
    // DUT Instantiation - Full CDC module
    // ========================================================================
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(1'b1),
        .ext_uart_tx(ext_uart_tx),
        .dac_clk(clk),  // Use system clock for DAC
        .dac_data(dac_data),
        .spi_clk(spi_clk),
        .spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .dsm_signal_in(8'h00),  // DSM inputs tied to 0
        .debug_out(debug_out),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid),
        .dc_usb_upload_data(),
        .dc_usb_upload_valid()
    );

    // ========================================================================
    // SPI Slave Model (SPI Mode 0: CPOL=0, CPHA=0)
    // ========================================================================
    reg [7:0] spi_slave_tx_reg;
    reg [7:0] spi_slave_rx_reg;
    reg [2:0] spi_slave_bit_count;
    reg [7:0] spi_slave_byte_count;
    reg [7:0] spi_slave_read_mem [0:255];
    reg [7:0] spi_slave_total_tx_count;
    reg       spi_slave_miso_out;
    reg       spi_slave_miso_en;

    initial begin
        // Initialize SPI slave memory with test pattern
        for (i = 0; i < 256; i = i + 1)
            spi_slave_read_mem[i] = 8'h00 + i;

        spi_slave_read_mem[0] = 8'hA5;
        spi_slave_read_mem[1] = 8'h5A;
        spi_slave_read_mem[2] = 8'hB6;
        spi_slave_read_mem[3] = 8'h6B;
        spi_slave_read_mem[4] = 8'hDE;
        spi_slave_read_mem[5] = 8'hAD;
        spi_slave_read_mem[6] = 8'hBE;
        spi_slave_read_mem[7] = 8'hEF;

        spi_slave_total_tx_count = 0;
        spi_slave_bit_count = 0;
        spi_slave_byte_count = 0;
        spi_slave_miso_en = 0;
        spi_slave_miso_out = 0;
    end

    // Three-state MISO output
    assign spi_miso = spi_slave_miso_en ? spi_slave_miso_out : 1'bz;

    // CS edge detection and control
    always @(negedge spi_cs_n or posedge spi_cs_n) begin
        if (!spi_cs_n) begin
            // CS asserted: initialize transfer
            spi_slave_bit_count <= 0;
            spi_slave_byte_count <= 0;
            spi_slave_tx_reg <= spi_slave_read_mem[spi_slave_total_tx_count];
            spi_slave_miso_out <= spi_slave_read_mem[spi_slave_total_tx_count][7];
            spi_slave_miso_en <= 1'b1;
            $display("[%0t] SPI_SLAVE: CS asserted, preload byte[%0d]=0x%02x",
                     $time, spi_slave_total_tx_count,
                     spi_slave_read_mem[spi_slave_total_tx_count]);
        end else begin
            // CS deasserted: end transfer
            spi_slave_miso_en <= 1'b0;
            spi_slave_total_tx_count <= spi_slave_total_tx_count + spi_slave_byte_count;
            $display("[%0t] SPI_SLAVE: CS deasserted, received %0d bytes (total sent: %0d)",
                     $time, spi_slave_byte_count,
                     spi_slave_total_tx_count + spi_slave_byte_count);
        end
    end

    // Clock rising edge: sample MOSI
    always @(posedge spi_clk) begin
        if (!spi_cs_n) begin
            spi_slave_rx_reg <= {spi_slave_rx_reg[6:0], spi_mosi};
            spi_slave_bit_count <= spi_slave_bit_count + 1;
            if (spi_slave_bit_count == 7) begin
                $display("[%0t] SPI_SLAVE: Received byte[%0d]=0x%02x",
                         $time, spi_slave_byte_count,
                         {spi_slave_rx_reg[6:0], spi_mosi});
                spi_slave_byte_count <= spi_slave_byte_count + 1;
            end
        end
    end

    // Clock falling edge: output next MISO bit
    always @(negedge spi_clk) begin
        if (!spi_cs_n) begin
            if (spi_slave_bit_count == 0 && spi_slave_byte_count > 0) begin
                // Byte boundary: load next byte
                spi_slave_tx_reg <= spi_slave_read_mem[spi_slave_total_tx_count + spi_slave_byte_count];
                spi_slave_miso_out <= spi_slave_read_mem[spi_slave_total_tx_count + spi_slave_byte_count][7];
            end else if (spi_slave_bit_count != 0) begin
                // Shift out next bit
                spi_slave_miso_out <= spi_slave_tx_reg[7 - spi_slave_bit_count];
            end
        end
    end

    // ========================================================================
    // Clock and Reset Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        usb_data_in = 0;
        usb_data_valid_in = 0;
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    // ========================================================================
    // USB Data Send Task
    // ========================================================================
    task send_usb_byte(input [7:0] byte_to_send);
        begin
            @(posedge clk);
            usb_data_in = byte_to_send;
            usb_data_valid_in = 1'b1;
            @(posedge clk);
            usb_data_valid_in = 1'b0;
            #(CLK_PERIOD_NS * 2);
        end
    endtask

    // ========================================================================
    // SPI Command Send Task
    // Format: AA 55 11 LEN_H LEN_L WRITE_LEN READ_LEN [DATA...] CHECKSUM
    // ========================================================================
    task automatic send_spi_command(input [7:0] write_len, input [7:0] read_len);
        reg [7:0] checksum;
        integer payload_len, j;
        begin
            $display("\n[%0t] ======= Sending SPI Command: Write=%0d, Read=%0d =======",
                     $time, write_len, read_len);

            // Calculate payload length and checksum
            payload_len = 2 + write_len;
            checksum = 8'h11 + payload_len[15:8] + payload_len[7:0] + write_len + read_len;
            for (j = 0; j < write_len; j = j + 1)
                checksum = checksum + (8'hDE - j);

            // Send frame
            send_usb_byte(8'hAA);                    // Header 1
            send_usb_byte(8'h55);                    // Header 2
            send_usb_byte(8'h11);                    // Command: SPI Read/Write
            send_usb_byte(payload_len[15:8]);       // Length High
            send_usb_byte(payload_len[7:0]);        // Length Low
            send_usb_byte(write_len);               // Write length
            send_usb_byte(read_len);                // Read length

            // Send write data
            for (j = 0; j < write_len; j = j + 1)
                send_usb_byte(8'hDE - j);

            send_usb_byte(checksum);                // Checksum

            $display("[%0t] SPI Command sent (checksum=0x%02x)", $time, checksum);
        end
    endtask

    // ========================================================================
    // USB Upload Data Capture
    // ========================================================================
    reg [7:0] usb_received_data [0:255];
    integer   usb_received_count;

    always @(posedge clk) begin
        if (usb_upload_valid) begin
            $display("[%0t] USB UPLOAD [%0d] = 0x%02x",
                     $time, usb_received_count, usb_upload_data);
            usb_received_data[usb_received_count] = usb_upload_data;
            usb_received_count = usb_received_count + 1;
        end
    end

    // ========================================================================
    // Debug Monitors
    // ========================================================================
    always @(posedge clk) begin
        // Monitor SPI Handler upload signals
        if (dut.u_spi_handler.upload_valid) begin
            $display("[%0t] SPI_HANDLER: upload_valid=1, data=0x%02x, source=0x%02x, active=%b, req=%b, ready=%b",
                     $time, dut.u_spi_handler.upload_data, dut.u_spi_handler.upload_source,
                     dut.u_spi_handler.upload_active, dut.u_spi_handler.upload_req, dut.u_spi_handler.upload_ready);
        end

        // Monitor SPI Adapter output
        if (dut.u_spi_adapter.packer_upload_valid) begin
            $display("[%0t] SPI_ADAPTER: packer_valid=1, data=0x%02x, req=%b, ready=%b",
                     $time, dut.u_spi_adapter.packer_upload_data,
                     dut.u_spi_adapter.packer_upload_req, dut.u_spi_adapter.packer_upload_ready);
        end

        // Monitor Packer output (SPI channel - channel 1)
        if (dut.packed_valid[1]) begin
            $display("[%0t] PACKER[1]: valid=1, data=0x%02x, req=%b, ready=%b",
                     $time, dut.packed_data[15:8], dut.packed_req[1], dut.arbiter_ready[1]);
        end

        // Monitor merged upload to processor
        if (dut.merged_upload_valid) begin
            $display("[%0t] MERGED_UPLOAD: valid=1, data=0x%02x, source=0x%02x, req=%b, ready=%b",
                     $time, dut.merged_upload_data, dut.merged_upload_source,
                     dut.merged_upload_req, dut.processor_upload_ready);
        end
    end

    // ========================================================================
    // Verification Task
    // ========================================================================
    task verify_spi_test_results(input integer expected_read_len);
        integer errors;
        integer k;
        integer expected_total;
        begin
            errors = 0;
            expected_total = (expected_read_len > 0) ? (5 + expected_read_len + 1) : 0;
            #(CLK_PERIOD_NS * 30000);

            $display("\n--- VERIFICATION (Expected %0d data bytes) ---", expected_read_len);

            // Note: Upload frame includes header (AA44), source (03), length (2B), data, checksum
            // Frame format: AA 44 03 LEN_H LEN_L [DATA...] CHECKSUM

            if (usb_received_count != expected_total) begin
                $display("❌ FAIL: Byte count mismatch. Expected %0d, Received %0d.",
                         expected_total, usb_received_count);
                errors = errors + 1;
            end else if (expected_read_len > 0) begin
                $display("✅ PASS: Received correct number of bytes (%0d).", usb_received_count);

                // Verify frame structure
                if (usb_received_data[0] != 8'hAA) begin
                    $display("❌ FAIL: Header byte 0 incorrect: 0x%02x (expected 0xAA)",
                             usb_received_data[0]);
                    errors = errors + 1;
                end
                if (usb_received_data[1] != 8'h44) begin
                    $display("❌ FAIL: Header byte 1 incorrect: 0x%02x (expected 0x44)",
                             usb_received_data[1]);
                    errors = errors + 1;
                end
                if (usb_received_data[2] != 8'h03) begin
                    $display("❌ FAIL: Source byte incorrect: 0x%02x (expected 0x03)",
                             usb_received_data[2]);
                    errors = errors + 1;
                end

                // Verify data payload (starting at byte 5)
                for (k = 0; k < expected_read_len; k = k + 1) begin
                    if (usb_received_data[5 + k] != spi_slave_read_mem[k]) begin
                        $display("  [%0d] RX: 0x%02x vs EXP: 0x%02x  (❌ MISMATCH)",
                                 k, usb_received_data[5 + k], spi_slave_read_mem[k]);
                        errors = errors + 1;
                    end else begin
                        $display("  [%0d] RX: 0x%02x vs EXP: 0x%02x  (✅ Match)",
                                 k, usb_received_data[5 + k], spi_slave_read_mem[k]);
                    end
                end
            end else begin
                $display("✅ PASS: No upload expected, received %0d bytes.", usb_received_count);
            end

            if (errors == 0)
                $display("✅ FINAL RESULT: PASS");
            else
                $display("❌ FINAL RESULT: FAIL with %0d error(s).", errors);
            $display("-------------------------------------\n");
        end
    endtask

    // ========================================================================
    // Test Sequence
    // ========================================================================
    initial begin
        wait (rst_n == 1'b1);
        #(CLK_PERIOD_NS * 100);

        $display("\n========================================");
        $display("=== Starting CDC SPI Test Sequence ===");
        $display("========================================\n");

        // Test 1: Write 1 byte, Read 1 byte
        $display("\n### Test 1: Write 1 byte, Read 1 byte ###");
        usb_received_count = 0;
        send_spi_command(1, 1);
        verify_spi_test_results(1);

        // Test 2: Write 2 bytes, Read 4 bytes
        $display("\n### Test 2: Write 2 bytes, Read 4 bytes ###");
        usb_received_count = 0;
        send_spi_command(2, 4);
        verify_spi_test_results(4);

        // Test 3: Write only (no read)
        $display("\n### Test 3: Write 3 bytes, Read 0 bytes ###");
        usb_received_count = 0;
        send_spi_command(3, 0);
        verify_spi_test_results(0);

        // Test 4: Read only (no write)
        $display("\n### Test 4: Write 0 bytes, Read 2 bytes ###");
        usb_received_count = 0;
        send_spi_command(0, 2);
        verify_spi_test_results(2);

        // Test 5: Larger transfer
        $display("\n### Test 5: Write 4 bytes, Read 8 bytes ###");
        usb_received_count = 0;
        send_spi_command(4, 8);
        verify_spi_test_results(8);

        $display("\n========================================");
        $display("=== Test Sequence Complete ===");
        $display("========================================\n");

        #(CLK_PERIOD_NS * 1000);
        $finish;
    end

    // ========================================================================
    // Timeout Watchdog
    // ========================================================================
    initial begin
        #(CLK_PERIOD_NS * 5000000); // 5M cycles timeout
        $display("\n❌ ERROR: Simulation timeout!");
        $finish;
    end

endmodule
