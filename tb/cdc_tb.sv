// ============================================================================
// Module:      cdc_tb (Compilation Fixed Version)
// Author:      Gemini
// Date:        2025-10-11
// Description:
// - Fixed compilation errors by moving variable declarations to the top
//   of the initial block.
// - Corrected WRITE_ADDR to be explicitly 16-bit for clarity and correctness.
// ============================================================================

`timescale 1ns / 1ns

module cdc_tb;

    //-----------------------------------------------------------------------------
    // Testbench Parameters
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 50_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;
    
    //-----------------------------------------------------------------------------
    // I2C Test Parameters
    //-----------------------------------------------------------------------------
    localparam I2C_CONFIG_CMD = 8'h04;
    localparam I2C_WRITE_CMD  = 8'h05;
    localparam I2C_READ_CMD   = 8'h06;
    localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0;
    localparam EEPROM_DEVICE_ADDR_7BIT = EEPROM_DEVICE_ADDR_8BIT >> 1;
    
    // --- FIX 1: Defined WRITE_ADDR as 16-bit for clarity ---
    localparam WRITE_ADDR = 16'h003C; 
    
    localparam NUM_BYTES_TO_TEST = 4;
    localparam READ_TIMEOUT = 100_000;

    //-----------------------------------------------------------------------------
    // Testbench Signals
    //-----------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;
    wire SCL;
    wire SDA;
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    reg [7:0] tb_payload [0:127];
    reg [7:0] expected_data [0:NUM_BYTES_TO_TEST-1];
    integer i;
    pullup PUP(SDA);

    //-----------------------------------------------------------------------------
    // DUT and Slave Instantiation
    //-----------------------------------------------------------------------------
    cdc dut (
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in), .usb_data_valid_in(usb_data_valid_in),
        .SCL(SCL), .SDA(SDA), .usb_upload_data(usb_upload_data), .usb_upload_valid(usb_upload_valid)
        // Other ports omitted
    );
    
    M24LC04B u_eeprom (
        .A0(1'b0), .A1(1'b0), .A2(1'b0), .WP(1'b0), 
        .SDA(SDA), .SCL(SCL), .RESET(~rst_n) // Note: Using active-high reset for EEPROM model
    );
    
    //-----------------------------------------------------------------------------
    // Clock and Reset Generation
    //-----------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0; 
        #(CLK_PERIOD_NS * 20);
        rst_n = 1'b1;
    end

    //-----------------------------------------------------------------------------
    // Helper & Verification Tasks (No changes needed here)
    //-----------------------------------------------------------------------------
    task send_usb_byte(input [7:0] data);
        begin @(posedge clk); usb_data_in = data; usb_data_valid_in = 1'b1; @(posedge clk); usb_data_valid_in = 1'b0; end
    endtask

    task automatic send_i2c_command(input [7:0] cmd, input [15:0] len);
        reg [7:0] checksum = 0; // 现在这种初始化是合法的
        begin 
            // 任务的其余部分保持不变
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
    
    task automatic verify_single_read(input [7:0] expected_byte, input integer byte_index);
        reg timeout_l = 1'b0; reg [7:0] received_data;
        begin $display("  Verifying byte %0d...", byte_index); fork begin : v_thread while (dut.usb_upload_valid !== 1'b1) @(posedge clk); received_data = dut.usb_upload_data; if (received_data === expected_byte) $display("    -> SUCCESS: Expected 0x%h, Got 0x%h", expected_byte, received_data); else $error("    -> FAILURE: Expected 0x%h, Got 0x%h", expected_byte, received_data); @(posedge clk); end begin : t_thread #(READ_TIMEOUT); timeout_l = 1'b1; end join_any if(timeout_l) disable v_thread; else disable t_thread; if (timeout_l) $error("  -> FAILURE: Timeout waiting for byte %0d from DUT.", byte_index); end
    endtask

    //-----------------------------------------------------------------------------
    // Main Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        // --- FIX 2: All declarations MUST be at the beginning of the block ---
        reg [15:0] temp_addr;

        wait (rst_n === 1'b1);
        #1000;
        
        expected_data[0] = 8'hDE;
        expected_data[1] = 8'hAD;
        expected_data[2] = 8'hBE;
        expected_data[3] = 8'hEF;
        
        $display("=== Starting I2C EEPROM Verification (Sequential Single-Byte Read) ===");

        $display("[%0t] Step 1: Sending I2C Config command...", $time);
        tb_payload[0] = EEPROM_DEVICE_ADDR_7BIT;
        send_i2c_command(I2C_CONFIG_CMD, 1);
        #2000;

        $display("[%0t] Step 2: Sending I2C Write command to EEPROM address 0x%h...", $time, WRITE_ADDR);
        tb_payload[0] = WRITE_ADDR[15:8]; // Address High
        tb_payload[1] = WRITE_ADDR[7:0];  // Address Low
        for (i=0; i<NUM_BYTES_TO_TEST; i=i+1) begin
            tb_payload[i+2] = expected_data[i];
        end
        send_i2c_command(I2C_WRITE_CMD, NUM_BYTES_TO_TEST + 2);
        
        $display("[%0t] Waiting for I2C write to finish...", $time);
        #5_000_000;

        $display("[%0t] Step 4: Sending FOUR separate single-byte I2C Read commands...", $time);

        for (i = 0; i < NUM_BYTES_TO_TEST; i = i + 1) begin
            $display("-----------------------------------------------------");
            $display("[%0t] Issuing READ command for address 0x%h", $time, WRITE_ADDR + i);

            temp_addr = WRITE_ADDR + i;

            tb_payload[0] = temp_addr[15:8]; // Address High
            tb_payload[1] = temp_addr[7:0];  // Address Low
            tb_payload[2] = 8'h00;           // Length High = 0
            tb_payload[3] = 8'h01;           // Length Low  = 1

            send_i2c_command(I2C_READ_CMD, 4);

            verify_single_read(expected_data[i], i);
            
            #10000;
        end
        
        $display("-----------------------------------------------------");
        $display("=== I2C Test Complete ===");
        #5000;

        $display("[%0t] Simulation finished.", $time);
        #10000000;
        $stop;
    end

    // I2C Bus Monitor can remain unchanged
    
endmodule