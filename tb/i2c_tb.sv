`timescale 1ns / 1ps

module tb_cdc;

    // ============================================================================
    // Signals
    // ============================================================================
    logic           clk;
    logic           rst_n;
    logic   [7:0]   usb_data_in;
    logic           usb_data_valid_in;
    logic           led_out;
    logic   [7:0]   pwm_pins;
    logic           ext_uart_rx;
    logic           ext_uart_tx;
    logic           dac_clk;
    logic   [13:0]  dac_data;
    wire            SCL;
    wire            SDA;
    logic   [7:0]   usb_upload_data;
    logic           usb_upload_valid;
    
    // For I2C bus pull-up simulation
    pullup(SCL);
    pullup(SDA);

    // ============================================================================
    // DUT Instantiation
    // ============================================================================
    cdc u_cdc (
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_rx(ext_uart_rx),
        .ext_uart_tx(ext_uart_tx),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .SCL(SCL),
        .SDA(SDA),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    // ============================================================================
    // I2C Slave Model Instantiation
    // ============================================================================
    M24LC04B M24LC04B(
		.A0(0), 
		.A1(0), 
		.A2(0), 
		.WP(0), 
		.SDA(SDA), 
		.SCL(SCL), 
		.RESET(~rst_n)
	);
    
    // ============================================================================
    // Clock and Reset Generation
    // ============================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    initial begin
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
    end

    // ============================================================================
    // Test Tasks
    // ============================================================================

    // Task to send a single byte over the simulated USB interface
    task send_usb_byte(input [7:0] data);
        @(posedge clk);
        usb_data_in <= data;
        usb_data_valid_in <= 1'b1;
        @(posedge clk);
        usb_data_valid_in <= 1'b0;
        #10; // Small delay between bytes
    endtask

    // Task to construct and send a full command packet
    // FINAL FIX: Replaced all 'byte' types with 'logic [7:0]' for maximum compatibility
    // NOTE: I changed the input 'byte unsigned payload[]' to 'logic [7:0] payload[]' for consistency.
    task automatic send_usb_packet(input [7:0] cmd, input logic [7:0] payload[]);
        // Declare all local variables first, before any procedural assignments.
        logic [7:0] packet[];
        logic [7:0] checksum;
        int len;
        
        logic [7:0] len_high;
        logic [7:0] len_low;
        logic [7:0] temp_packet[]; // This variable declaration is now correctly placed.

        // Now, perform initializations and procedural assignments
        checksum = 8'h00;
        len = payload.size();
        
        len_high = (len >> 8) & 8'hFF;
        len_low  = len & 8'hFF;
        
        $display("\n[TB] Sending command 0x%h with payload size %0d", cmd, len);

        // This temporary packet holds all data used for checksum calculation
        temp_packet = {8'hAA, 8'h55, cmd, len_high, len_low, payload};

        // Calculate Checksum over the temp_packet
        for (int i = 0; i < temp_packet.size(); i++) begin
            checksum = checksum + temp_packet[i];
        end
        
        // Construct the final packet with checksum and status byte
        packet = {temp_packet, checksum, 8'h00};

        // Send the final packet byte by byte
        for (int i = 0; i < packet.size(); i++) begin
            send_usb_byte(packet[i]);
        end
        $display("[TB] Packet sent.");
    endtask

    // ============================================================================
    // Test Sequence
    // ============================================================================
    initial begin
        // --- Wait for reset to finish ---
        @(posedge rst_n);
        #100;

        // --- Test 1: Configure I2C ---
        // Payload: Freq(4B, dummy), Slave Addr(1B)
        $display("-------------------------------------------");
        $display("--- Test 1: Configure I2C (Addr 0x5A) ---");
        $display("-------------------------------------------");
        send_usb_packet(8'h04, '{'h00, 'h01, 'h86, 'hA0, 8'h50}); // Freq, 7-bit slave address
        #1000;

        // --- Test 2: Write a byte to the I2C slave ---
        // Payload: Reg Addr(1B), Data(1B)
        $display("-------------------------------------------");
        $display("--- Test 2: Write 0xDE to reg 0x10 ---");
        $display("-------------------------------------------");
        send_usb_packet(8'h05, '{8'h10, 8'hDE});
        #5000; // Allow time for I2C transaction

        // --- Test 3: Read a byte from the I2C slave ---
        // Slave memory at 0x20 is pre-loaded with 0xAB
        // Payload: Reg Addr(1B), Read Len(2B)
        $display("-------------------------------------------");
        $display("--- Test 3: Read 1 byte from reg 0x20 ---");
        $display("-------------------------------------------");
        send_usb_packet(8'h06, '{8'h20, 8'h00, 8'h01});
        
        // // Wait for the uploaded data
        // wait (usb_upload_valid);
        $display("[TB] Received uploaded data!");
        if (usb_upload_data == 8'hAB) begin
            $display("[TB] SUCCESS: Read data matches expected value (0x%h).", usb_upload_data);
        end else begin
            $error("[TB] FAILED: Read data 0x%h does not match expected 0xAB.", usb_upload_data);
        end

        #5000;
        
        $display("\n--- All tests completed. ---");
        $finish;
    end

endmodule