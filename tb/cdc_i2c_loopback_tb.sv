`timescale 1ns / 1ns

module cdc_tb;

    //-----------------------------------------------------------------------------
    // Testbench Parameters
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 50_000_000;
    localparam BAUD_RATE     = 115200;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    // *** NEW: UART bit period for the receiver task ***
    localparam UART_BIT_PERIOD = 1_000_000_000 / BAUD_RATE;

    //-----------------------------------------------------------------------------
    // Command Definitions
    //-----------------------------------------------------------------------------
    // *** NEW: Assuming 0x01 is the command to send data via UART ***
    localparam UART_SEND_CMD  = 8'h07; 
    localparam I2C_CONFIG_CMD = 8'h04;
    localparam I2C_WRITE_CMD  = 8'h05;
    localparam I2C_READ_CMD   = 8'h06;
    
    localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0;
    localparam EEPROM_DEVICE_ADDR_7BIT = EEPROM_DEVICE_ADDR_8BIT >> 1;
    
    localparam WRITE_ADDR = 8'h3C;
    localparam NUM_BYTES_TO_TEST = 4;
    localparam READ_TIMEOUT = 100_000; // 100us timeout for read verification

    //-----------------------------------------------------------------------------
    // Testbench Signals
    //-----------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;

    wire led_out;
    wire [7:0] pwm_pins;
    wire ext_uart_tx; // This will be monitored
    reg  ext_uart_rx;
    wire SCL;
    wire SDA;

    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    
    wire [13:0] dac_data;
    reg         dac_clk;

    reg [7:0] tb_payload [0:127];
    reg [7:0] expected_data [0:NUM_BYTES_TO_TEST-1];
    
    integer i;
    pullup PUP(SDA);
    //-----------------------------------------------------------------------------
    // DUT and Slave Instantiation
    //-----------------------------------------------------------------------------
    cdc dut (
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in), .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out), .pwm_pins(pwm_pins), .ext_uart_rx(ext_uart_rx), .ext_uart_tx(ext_uart_tx),
        .dac_clk(dac_clk), .dac_data(dac_data), .SCL(SCL), .SDA(SDA),
        .usb_upload_data(usb_upload_data), .usb_upload_valid(usb_upload_valid)
    );
    
    M24LC04B u_eeprom (
        .A0(1'b0), .A1(1'b0), .A2(1'b0), .WP(1'b0), 
        .SDA(SDA), .SCL(SCL), .RESET(~rst_n)
    );
    
    //-----------------------------------------------------------------------------
    // Clock and Reset Generation
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        dac_clk = 0;
        forever #2.5 dac_clk = ~dac_clk;  // 200MHz
    end

    initial begin
        rst_n = 1'b0; 
        usb_data_in = 8'h00;
        usb_data_valid_in = 1'b0;
        ext_uart_rx = 1'b1; // Keep UART RX idle
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    //-----------------------------------------------------------------------------
    // Helper Tasks
    //-----------------------------------------------------------------------------
    // This is a generic command sender, not just for I2C
    task send_usb_command(input [7:0] cmd, input [15:0] len);
        reg [7:0] checksum;
    begin
        checksum = 0;
        send_usb_byte(8'hAA); send_usb_byte(8'h55);
        send_usb_byte(cmd); checksum = checksum + cmd;
        send_usb_byte(len[15:8]); checksum = checksum + len[15:8];
        send_usb_byte(len[7:0]); checksum = checksum + len[7:0];
        for (i = 0; i < len; i = i + 1) begin
            send_usb_byte(tb_payload[i]);
            checksum = checksum + tb_payload[i];
        end
        send_usb_byte(checksum);
    end
    endtask

    task send_usb_byte(input [7:0] data);
    begin
        @(posedge clk);
        usb_data_in = data;
        usb_data_valid_in = 1'b1;
        @(posedge clk);
        usb_data_valid_in = 1'b0;
        usb_data_in = 8'h00;
        #(CLK_PERIOD_NS * 5);
    end
    endtask
    
    // MODIFIED: Added 'automatic' keyword to fix compilation error.
    task automatic verify_eeprom_write;
        reg is_match = 1'b1;
        reg [7:0] read_back_data;
    begin
        $display("-----------------------------------------------------");
        $display("--- Verifying EEPROM Write (Direct Memory Access) ---");
        for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
            read_back_data = u_eeprom.MemoryBlock0[WRITE_ADDR + i];
            if (read_back_data !== expected_data[i]) begin
                is_match = 0;
                $display("  MISMATCH at address 0x%h: Wrote 0x%h, but read back 0x%h", WRITE_ADDR + i, expected_data[i], read_back_data);
            end
        end

        if (is_match) $display("  SUCCESS: EEPROM internal memory correctly written!");
        else $error("  FAILURE: Data written to EEPROM is incorrect.");
        $display("-----------------------------------------------------");
    end
    endtask

    // MODIFIED: Added 'automatic' keyword to fix compilation error.
    task automatic verify_dut_read;
        reg [7:0] received_data;
        reg all_match = 1'b1;
        reg timeout_l = 1'b0;
    begin
        $display("-----------------------------------------------------");
        $display("--- Verifying DUT I2C Read via USB Upload Port ---");
        $display("  Waiting to receive %0d bytes from DUT...", NUM_BYTES_TO_TEST);

        fork
            begin : verification_loop
                for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
                    while (dut.usb_upload_valid !== 1'b1) @(posedge clk);
                    received_data = dut.usb_upload_data;
                    if (received_data === expected_data[i]) begin
                        $display("    Byte %0d: OKAY.  Expected 0x%h, Got 0x%h", i, expected_data[i], received_data);
                    end else begin
                        $display("    Byte %0d: FAIL. Expected 0x%h, Got 0x%h", i, expected_data[i], received_data);
                        all_match = 1'b0;
                    end
                    @(posedge clk); 
                end
            end
            
            begin : timeout_counter
                #(READ_TIMEOUT);
                timeout_l = 1'b1;
            end
        join_any

        if(timeout_l) disable verification_loop;
        else disable timeout_counter;

        if (timeout_l) begin
            $error("  FAILURE: Timeout waiting for data from DUT. Test failed.");
            all_match = 1'b0;
        end

        if (all_match) $display("  SUCCESS: All bytes read back from DUT correctly verified!");
        else $error("  FAILURE: Data read back from DUT is incorrect.");
        $display("-----------------------------------------------------");
    end
    endtask

    // *** NEW: UART Byte Receiver Task ***
    task automatic uart_receive_byte;
        output reg [7:0] received_byte;
        reg framing_error;
    begin
        framing_error = 1'b0;
        // 1. Wait for start bit (high to low transition)
        @(negedge dut.ext_uart_tx);

        // 2. Wait half a bit period to sample in the middle of the start bit
        #(UART_BIT_PERIOD / 2);

        // 3. Loop 8 times to receive data bits (LSB first)
        for (integer bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            #(UART_BIT_PERIOD);
            received_byte[bit_idx] = dut.ext_uart_tx;
        end

        // 4. Wait for stop bit
        #(UART_BIT_PERIOD);
        if (dut.ext_uart_tx !== 1'b1) begin
            framing_error = 1'b1;
        end
    end
    endtask

    // *** NEW: UART Echo Verification Task ***
    task automatic verify_uart_echo;
        reg [7:0] received_byte_uart;
        reg all_match = 1'b1;
    begin
        $display("-----------------------------------------------------");
        $display("--- Verifying UART Echo via ext_uart_tx Pin ---");
        $display("  Waiting to receive %0d bytes from UART...", NUM_BYTES_TO_TEST);

        for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
            // Call the receiver task to get one byte
            uart_receive_byte(received_byte_uart);

            if (received_byte_uart === expected_data[i]) begin
                $display("    Byte %0d: OKAY.  Expected 0x%h, Got 0x%h via UART", i, expected_data[i], received_byte_uart);
            end else begin
                $display("    Byte %0d: FAIL. Expected 0x%h, Got 0x%h via UART", i, expected_data[i], received_byte_uart);
                all_match = 1'b0;
            end
        end

        if (all_match) $display("  SUCCESS: All bytes echoed via UART correctly verified!");
        else $error("  FAILURE: Data echoed via UART is incorrect.");
        $display("-----------------------------------------------------");
    end
    endtask


    //-----------------------------------------------------------------------------
    // Main Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n === 1'b1);
        #1000;
        
        expected_data[0] = 8'hDE;
        expected_data[1] = 8'hAD;
        expected_data[2] = 8'hBE;
        expected_data[3] = 8'hEF;
        
        $display("=== Starting Full Loopback Verification ===");

        // --- STEP 1: Configure I2C ---
        $display("[%0t] Step 1: Sending I2C Config command (0x%h)...", $time, I2C_CONFIG_CMD);
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        send_usb_command(I2C_CONFIG_CMD, 1);
        #2000;

        // --- STEP 2: Write data to EEPROM ---
        $display("[%0t] Step 2: Sending I2C Write command (0x%h) to EEPROM address 0x%h...", $time, I2C_WRITE_CMD, WRITE_ADDR);
        tb_payload[0] = 8'h00;
        tb_payload[1] = WRITE_ADDR;
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i+2] = expected_data[i];
        end
        send_usb_command(I2C_WRITE_CMD, NUM_BYTES_TO_TEST + 2);
        
        $display("[%0t] Waiting for I2C write to finish and EEPROM's internal write cycle...", $time);
        #5_000_000; 

        // --- STEP 3: Verify EEPROM write directly ---
        verify_eeprom_write();

        // --- STEP 4: Command DUT to read from EEPROM ---
        $display("[%0t] Step 4: Sending I2C Read command (0x%h)...", $time, I2C_READ_CMD);
        tb_payload[0] = 8'h00;
        tb_payload[1] = WRITE_ADDR;
        tb_payload[2] = 8'h00;
        tb_payload[3] = NUM_BYTES_TO_TEST;
        send_usb_command(I2C_READ_CMD, 4);

        // --- STEP 5: Verify DUT uploaded the correct data via USB ---
        verify_dut_read();
        
        // *** NEW: STEP 6: Send the verified data back to be echoed on UART ***
        $display("[%0t] Step 6: Echoing verified data back to DUT for UART transmission (CMD 0x%h)...", $time, UART_SEND_CMD);
        // The data to send is already in expected_data, which we just verified.
        // We load it into tb_payload to use the send_usb_command task.
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i] = expected_data[i];
        end
        send_usb_command(UART_SEND_CMD, NUM_BYTES_TO_TEST);
        
        // *** NEW: STEP 7: Verify the data was correctly transmitted on ext_uart_tx ***
        verify_uart_echo();
        
        $display("=== Full Loopback Test Complete ===");
        #5000;

        $display("[%0t] Simulation finished.", $time);
        $finish;
    end
    
    // I2C Monitor is omitted for brevity but can be kept in your file.
    
endmodule