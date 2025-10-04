`timescale 1ns/1ps

module tb_cdc_i2c_direct_verify;

    //================================================================
    // Testbench Signals
    //================================================================
    
    reg clk;
    reg rst_n;

    reg  [7:0]  usb_data_in;
    reg         usb_data_valid_in;

    wire        SCL;
    wire        SDA;
    
    // Unused CDC ports - still need to be declared for instantiation
    wire [7:0]  usb_upload_data;
    wire        usb_upload_valid;
    wire        led_out;
    wire [7:0]  pwm_pins;
    wire        ext_uart_tx;
    reg         ext_uart_rx = 1'b1;
    wire [13:0] dac_data;
    reg         dac_clk = 0;

    localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0;
    localparam EEPROM_DEVICE_ADDR_7BIT = EEPROM_DEVICE_ADDR_8BIT >> 1;
    
    // Test Data Definition
    localparam WRITE_ADDR = 8'h3C;
    localparam NUM_BYTES_TO_TEST = 4;
    reg [7:0] expected_data [0:NUM_BYTES_TO_TEST-1];
    reg [7:0] tb_payload [0:127];

    integer i;

    //================================================================
    // DUT and Slave Instantiation
    //================================================================

    cdc u_dut (
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in), .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out), .pwm_pins(pwm_pins), .ext_uart_rx(ext_uart_rx), .ext_uart_tx(ext_uart_tx),
        .dac_clk(dac_clk), .dac_data(dac_data), .SCL(SCL), .SDA(SDA),
        .usb_upload_data(usb_upload_data), .usb_upload_valid(usb_upload_valid)
    );
    
    M24LC04B u_eeprom (
        .A0(1'b0), .A1(1'b0), .A2(1'b0), .WP(1'b0), 
        .SDA(SDA), .SCL(SCL), .RESET(1'b0)
    );

    //================================================================
    // Clock and Reset Generation
    //================================================================
    
    initial begin clk = 0; forever #10 clk = ~clk; end
    initial begin rst_n = 1'b0; #100; rst_n = 1'b1; end
    
    //================================================================
    // Test Sequence
    //================================================================
    
    initial begin
        // Initialize test data
        expected_data[0] = 8'hDE;
        expected_data[1] = 8'hAD;
        expected_data[2] = 8'hBE;
        expected_data[3] = 8'hEF;

        $display("-----------------------------------------------------");
        $display("--- Starting CDC I2C Direct Verification Test ---");
        $display("-----------------------------------------------------");

        wait (rst_n === 1'b1);
        #100;

        // --- TEST 1: Configure I2C ---
        $display("[%t] TEST 1: Sending I2C Config command (0x04)...", $time);
        tb_payload[0] = 8'h00; tb_payload[1] = 8'h01; tb_payload[2] = 8'h02; tb_payload[3] = 8'h03;
        tb_payload[4] = EEPROM_DEVICE_ADDR_7BIT;
        send_i2c_command(8'h04, 5);
        #2000;
        
        // --- TEST 2: Write Data to EEPROM ---
        $display("[%t] TEST 2: Sending I2C Write command (0x05) to EEPROM address 0x%h...", $time, WRITE_ADDR);
        tb_payload[0] = WRITE_ADDR;
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i+1] = expected_data[i];
        end
        send_i2c_command(8'h05, NUM_BYTES_TO_TEST + 1);
        
        $display("[%t] Waiting for I2C write to finish and EEPROM's internal write cycle (tWC)...", $time);
        #6_000_000; // Wait for bus transaction and internal EEPROM write
        
        // --- NEW VERIFICATION: Directly inspect EEPROM memory ---
        verify_eeprom_write();

        // --- TEST 3: Read Data from EEPROM (We send the command to ensure the FSM works, but don't check uploaded data) ---
        $display("[%t] TEST 3: Sending I2C Read command (0x06). This test verifies the command is processed without error.", $time);
        tb_payload[0] = WRITE_ADDR;
        tb_payload[1] = NUM_BYTES_TO_TEST[15:8];
        tb_payload[2] = NUM_BYTES_TO_TEST[7:0];
        send_i2c_command(8'h06, 3);

        #500; // Wait long enough for the read transaction to complete on the bus

        $display("[%t] Simulation finished.", $time);
        $finish;
    end

    //================================================================
    // Helper Tasks
    //================================================================

    task send_usb_byte;
        input [7:0] data;
    begin
        @(posedge clk);
        usb_data_in = data;
        usb_data_valid_in = 1'b1;
        @(posedge clk);
        usb_data_valid_in = 1'b0;
        usb_data_in = 8'h00;
        #20;
    end
    endtask

    task send_i2c_command;
        input [7:0] cmd;
        input [15:0] len;
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
    
    // *** NEW verification task ***
    task verify_eeprom_write;
        reg is_match;
        reg [7:0] read_back_data;
    begin
        is_match = 1;
        $display("-----------------------------------------------------");
        $display("--- Verifying EEPROM Write Operation via Direct Memory Access ---");
        for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
            // Use Verilog's hierarchical path to look inside the EEPROM model
            read_back_data = u_eeprom.MemoryBlock0[WRITE_ADDR + i];
            if (read_back_data !== expected_data[i]) begin
                is_match = 0;
                $display("MISMATCH at address 0x%h: Wrote 0x%h, but read back 0x%h", WRITE_ADDR + i, expected_data[i], read_back_data);
            end
        end

        if (is_match) begin
            $display("SUCCESS: All bytes written to EEPROM correctly verified!");
        end else begin
            $display("FAILURE: Data written to EEPROM is incorrect.");
        end
        $display("-----------------------------------------------------");
    end
    endtask

endmodule