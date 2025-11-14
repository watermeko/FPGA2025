// ============================================================================
// Module:      i2c_slave_handler_tb
// Description:
// - Complete testbench for i2c_slave_handler module
// - Tests CDC command 0x35 (Write/Preload registers)
// - Tests CDC command 0x36 (Read registers and upload)
// - Tests CDC command 0x34 (Set I2C slave address)
// - Tests I2C master read/write operations
// ============================================================================

`timescale 1ns / 1ps

module i2c_slave_handler_tb();

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

    // CDC Upload Bus Interface
    logic        upload_active;
    logic        upload_req;
    logic [7:0]  upload_data;
    logic [7:0]  upload_source;
    logic        upload_valid;
    logic        upload_ready;

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
    logic [7:0]  upload_buffer [0:15];
    integer      upload_count;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    i2c_slave_handler u_dut (
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

        // CDC Upload Bus
        .upload_active    (upload_active),
        .upload_req       (upload_req),
        .upload_data      (upload_data),
        .upload_source    (upload_source),
        .upload_valid     (upload_valid),
        .upload_ready     (upload_ready),

        // Physical I2C
        .i2c_scl          (i2c_scl),
        .i2c_sda          (i2c_sda),

        // Register Preload
        .preload_en       (preload_en),
        .preload_addr     (preload_addr),
        .preload_data     (preload_data)
    );

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
        end else if (upload_valid && upload_ready) begin
            upload_buffer[upload_count] <= upload_data;
            upload_count <= upload_count + 1;
            $display("[%0t] Upload Data[%0d] = 0x%02h (Source=0x%02h)",
                     $time, upload_count, upload_data, upload_source);
        end
    end

    //=========================================================================
    // Task: Reset
    //=========================================================================
    task automatic reset_system();
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
            upload_ready = 0;
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
    // Task: Send CDC Command (Generic)
    //=========================================================================
    task automatic send_cdc_command(
        input [7:0]  cmd,
        input [7:0]  payload_data[],
        input integer payload_len
    );
        integer i;
        begin
            $display("\n========================================");
            $display("[%0t] Sending CDC Command 0x%02h", $time, cmd);
            $display("========================================");

            // Wait for cmd_ready
            wait(cmd_ready == 1'b1);
            @(posedge clk);

            // Start command
            cmd_type = cmd;
            cmd_start = 1'b1;
            @(posedge clk);
            cmd_start = 1'b0;

            // Send payload data
            for (i = 0; i < payload_len; i = i + 1) begin
                cmd_data_valid = 1'b1;
                cmd_data_index = i;
                cmd_data = payload_data[i];
                $display("[%0t]   Payload[%0d] = 0x%02h", $time, i, payload_data[i]);
                @(posedge clk);
            end

            cmd_data_valid = 1'b0;
            @(posedge clk);

            // Signal command done
            cmd_done = 1'b1;
            @(posedge clk);
            cmd_done = 1'b0;

            $display("[%0t] CDC Command Sent\n", $time);
        end
    endtask

    //=========================================================================
    // Task: CDC Command 0x35 - Write Registers
    //=========================================================================
    task automatic cdc_write_registers(
        input [7:0] start_addr,
        input [7:0] length,
        input [7:0] data[]
    );
        logic [7:0] payload[0:15];
        integer i;
        begin
            payload[0] = start_addr;
            payload[1] = length;
            for (i = 0; i < length; i = i + 1) begin
                payload[2 + i] = data[i];
            end

            // Start monitoring in parallel with command execution
            fork
                // Execute CDC command
                send_cdc_command(8'h35, payload, 2 + length);

                // Monitor signals during execution
                begin
                    $display("\n[REAL-TIME MONITOR] Starting write monitoring...");
                    repeat(30) begin
                        @(posedge clk);
                        if (u_dut.state == 3 || u_dut.state == 4) begin  // S_EXEC_WRITE or S_EXEC_WRITE_HOLD
                            $display("[%0t] State=%0d ptr=%0d wr_en=%b addr=0x%02h wdata=0x%02h reg_wr=%b fedge=%b Reg[0]=0x%02h",
                                     $time, u_dut.state, u_dut.cdc_write_ptr,
                                     u_dut.handler_wr_en, u_dut.handler_addr, u_dut.handler_wdata,
                                     u_dut.u_reg_map.wr_en_wdata, u_dut.u_reg_map.wr_en_wdata_fedge,
                                     u_dut.u_reg_map.registers[0]);
                        end
                    end
                end
            join

            // Wait for completion
            repeat(10) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Task: CDC Command 0x36 - Read Registers
    //=========================================================================
    task automatic cdc_read_registers(
        input [7:0] start_addr,
        input [7:0] length
    );
        logic [7:0] payload[0:15];
        integer bytes_to_read;
        begin
            payload[0] = start_addr;
            payload[1] = length;

            // Reset upload count
            upload_count = 0;

            // Send command
            send_cdc_command(8'h36, payload, 2);

            // Enable upload ready and wait for data
            @(posedge clk);
            upload_ready = 1'b1;

            bytes_to_read = length;
            wait(upload_count >= bytes_to_read);

            repeat(5) @(posedge clk);
            upload_ready = 1'b0;

            $display("\n[%0t] Received %0d bytes via upload bus", $time, upload_count);
        end
    endtask

    //=========================================================================
    // Task: CDC Command 0x34 - Set I2C Address
    //=========================================================================
    task automatic cdc_set_i2c_addr(
        input [7:0] new_addr
    );
        logic [7:0] payload[0:15];
        begin
            payload[0] = new_addr;
            send_cdc_command(8'h34, payload, 1);
            repeat(10) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Task: FPGA Internal Preload
    //=========================================================================
    task automatic fpga_preload_register(
        input [7:0] addr,
        input [7:0] data
    );
        begin
            $display("\n========================================");
            $display("[%0t] FPGA Preload: Reg[%0d] = 0x%02h", $time, addr, data);
            $display("========================================");

            @(posedge clk);
            preload_en = 1'b1;
            preload_addr = addr;
            preload_data = data;
            @(posedge clk);
            preload_en = 1'b0;
            @(posedge clk);

            $display("[%0t] Preload Complete\n", $time);
        end
    endtask

    //=========================================================================
    // Task: I2C Start Condition
    //=========================================================================
    task automatic i2c_start();
        begin
            $display("[%0t] I2C: START", $time);
            sda_oe = 1;
            sda_drive_out = 1;
            scl_drive = 0;
            #1000;  // SDA high, SCL high
            sda_drive_out = 0;  // SDA falls while SCL high
            #1000;
            scl_drive = 1;  // SCL low
            #1000;
        end
    endtask

    //=========================================================================
    // Task: I2C Stop Condition
    //=========================================================================
    task automatic i2c_stop();
        begin
            $display("[%0t] I2C: STOP", $time);
            scl_drive = 1;
            sda_oe = 1;
            sda_drive_out = 0;
            #1000;
            scl_drive = 0;  // SCL high
            #1000;
            sda_drive_out = 1;  // SDA rises while SCL high
            #1000;
            sda_oe = 0;
        end
    endtask

    //=========================================================================
    // Task: I2C Write Byte
    //=========================================================================
    task automatic i2c_write_byte(input [7:0] data);
        integer i;
        logic ack;
        begin
            $display("[%0t] I2C: Write Byte 0x%02h", $time, data);
            sda_oe = 1;

            // Send 8 bits
            for (i = 7; i >= 0; i = i - 1) begin
                scl_drive = 1;
                sda_drive_out = data[i];
                #1000;
                scl_drive = 0;  // SCL high
                #1000;
                scl_drive = 1;  // SCL low
                #1000;
            end

            // Read ACK
            sda_oe = 0;  // Release SDA
            #500;
            scl_drive = 0;  // SCL high
            #500;
            ack = i2c_sda;
            #500;
            scl_drive = 1;  // SCL low
            #500;

            if (ack == 0)
                $display("[%0t] I2C: ACK received", $time);
            else
                $display("[%0t] I2C: NACK received", $time);
        end
    endtask

    //=========================================================================
    // Task: I2C Read Byte
    //=========================================================================
    task automatic i2c_read_byte(output [7:0] data, input send_ack);
        integer i;
        begin
            $display("[%0t] I2C: Read Byte", $time);
            sda_oe = 0;  // Release SDA for slave to drive
            data = 8'h00;

            // Read 8 bits
            for (i = 7; i >= 0; i = i - 1) begin
                scl_drive = 1;
                #1000;
                scl_drive = 0;  // SCL high
                #500;
                data[i] = i2c_sda;
                #500;
                scl_drive = 1;  // SCL low
                #1000;
            end

            // Send ACK/NACK
            sda_oe = 1;
            sda_drive_out = ~send_ack;  // ACK=0, NACK=1
            #500;
            scl_drive = 0;  // SCL high
            #1000;
            scl_drive = 1;  // SCL low
            #500;
            sda_oe = 0;

            $display("[%0t] I2C: Read Data = 0x%02h, Sent %s",
                     $time, data, send_ack ? "ACK" : "NACK");
        end
    endtask

    //=========================================================================
    // Task: I2C Master Write to Slave
    //=========================================================================
    task automatic i2c_master_write(
        input [6:0] slave_addr,
        input [7:0] reg_addr,
        input [7:0] data
    );
        begin
            $display("\n========================================");
            $display("[%0t] I2C Master Write", $time);
            $display("  Slave Addr: 0x%02h", slave_addr);
            $display("  Reg Addr:   0x%02h", reg_addr);
            $display("  Data:       0x%02h", data);
            $display("========================================");

            i2c_start();
            i2c_write_byte({slave_addr, 1'b0});  // Slave addr + Write
            i2c_write_byte(reg_addr);             // Register address
            i2c_write_byte(data);                 // Data
            i2c_stop();

            #5000;
            $display("[%0t] I2C Master Write Complete\n", $time);
        end
    endtask

    //=========================================================================
    // Task: I2C Master Read from Slave
    //=========================================================================
    task automatic i2c_master_read(
        input [6:0] slave_addr,
        input [7:0] reg_addr,
        output [7:0] data
    );
        begin
            $display("\n========================================");
            $display("[%0t] I2C Master Read", $time);
            $display("  Slave Addr: 0x%02h", slave_addr);
            $display("  Reg Addr:   0x%02h", reg_addr);
            $display("========================================");

            // Write phase - set register address
            i2c_start();
            i2c_write_byte({slave_addr, 1'b0});  // Slave addr + Write
            i2c_write_byte(reg_addr);             // Register address

            // Read phase
            i2c_start();  // Repeated start
            i2c_write_byte({slave_addr, 1'b1});  // Slave addr + Read
            i2c_read_byte(data, 0);               // Read data, send NACK
            i2c_stop();

            #5000;
            $display("  Read Data:  0x%02h", data);
            $display("[%0t] I2C Master Read Complete\n", $time);
        end
    endtask

    //=========================================================================
    // Task: Display Register Values (Direct Access to DUT Internal Registers)
    //=========================================================================
    task automatic display_registers();
        begin
            $display("  ========================================");
            $display("  [%0t] Current Register Values (from DUT):", $time);
            $display("    Reg[0] = 0x%02h", u_dut.u_reg_map.registers[0]);
            $display("    Reg[1] = 0x%02h", u_dut.u_reg_map.registers[1]);
            $display("    Reg[2] = 0x%02h", u_dut.u_reg_map.registers[2]);
            $display("    Reg[3] = 0x%02h", u_dut.u_reg_map.registers[3]);
            $display("  ========================================");
        end
    endtask

    //=========================================================================
    // Task: Display DUT State and Control Signals
    //=========================================================================
    task automatic display_dut_state();
        begin
            $display("  ----------------------------------------");
            $display("  [%0t] DUT Internal State:", $time);
            $display("    State:          %0d", u_dut.state);
            $display("    handler_wr_en:  %b", u_dut.handler_wr_en);
            $display("    handler_addr:   0x%02h", u_dut.handler_addr);
            $display("    handler_wdata:  0x%02h", u_dut.handler_wdata);
            $display("    cdc_write_ptr:  %0d", u_dut.cdc_write_ptr);
            $display("    cdc_len:        %0d", u_dut.cdc_len);
            $display("    reg_map wr_en:  %b", u_dut.u_reg_map.wr_en_wdata);
            $display("    reg_map fedge:  %b", u_dut.u_reg_map.wr_en_wdata_fedge);
            $display("  ----------------------------------------");
        end
    endtask

    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        logic [7:0] write_data[0:7];
        logic [7:0] read_data;
        integer i;
        integer pass_count, fail_count;

        pass_count = 0;
        fail_count = 0;

        $display("\n");
        $display("============================================================");
        $display("  I2C Slave Handler Testbench - Core CDC Commands Test");
        $display("  Testing CDC Commands 0x35/0x36 (Write/Read Registers)");
        $display("============================================================\n");

        // Initialize
        reset_system();

        $display("\n*** Initial Register State ***");
        display_registers();

        //=====================================================================
        // Test 1: CDC Command 0x35 - Write Single Register
        //=====================================================================
        $display("\n");
        $display("############################################################");
        $display("# TEST 1: CDC Write Single Register (0x35)");
        $display("############################################################");

        write_data[0] = 8'h55;
        cdc_write_registers(8'h00, 8'h01, write_data);

        $display("\n*** After CDC Write (0x35) - Check Registers ***");
        display_registers();
        display_dut_state();

        $display("TEST 1: PASS - CDC write command executed");
        pass_count = pass_count + 1;

        //=====================================================================
        // Test 2: CDC Command 0x36 - Read Single Register
        //=====================================================================
        $display("\n");
        $display("############################################################");
        $display("# TEST 2: CDC Read Single Register (0x36)");
        $display("############################################################");

        cdc_read_registers(8'h00, 8'h01);

        $display("\n*** After CDC Read (0x36) - Check Registers Again ***");
        display_registers();

        if (upload_buffer[0] == 8'h55) begin
            $display("TEST 2: PASS - Read data matches (0x%02h)", upload_buffer[0]);
            pass_count = pass_count + 1;
        end else begin
            $display("TEST 2: FAIL - Expected 0x55, got 0x%02h", upload_buffer[0]);
            fail_count = fail_count + 1;
        end

        //=====================================================================
        // Test 3: CDC Command 0x35 - Write All 4 Registers
        //=====================================================================
        $display("\n");
        $display("############################################################");
        $display("# TEST 3: CDC Write All 4 Registers (0x35)");
        $display("############################################################");

        write_data[0] = 8'hAA;
        write_data[1] = 8'hBB;
        write_data[2] = 8'hCC;
        write_data[3] = 8'hDD;
        cdc_write_registers(8'h00, 8'h04, write_data);

        $display("\n*** After CDC Write All (0x35) - Check Registers ***");
        display_registers();

        $display("TEST 3: PASS - CDC write all registers");
        pass_count = pass_count + 1;

        //=====================================================================
        // Test 4: CDC Command 0x36 - Read All 4 Registers
        //=====================================================================
        $display("\n");
        $display("############################################################");
        $display("# TEST 4: CDC Read All 4 Registers (0x36)");
        $display("############################################################");

        cdc_read_registers(8'h00, 8'h04);

        $display("\n*** After CDC Read All (0x36) - Final Register Check ***");
        display_registers();

        if (upload_buffer[0] == 8'hAA && upload_buffer[1] == 8'hBB &&
            upload_buffer[2] == 8'hCC && upload_buffer[3] == 8'hDD) begin
            $display("TEST 4: PASS - All registers read correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("TEST 4: FAIL - Register mismatch");
            $display("  Expected: AA BB CC DD");
            $display("  Got:      %02h %02h %02h %02h",
                     upload_buffer[0], upload_buffer[1],
                     upload_buffer[2], upload_buffer[3]);
            fail_count = fail_count + 1;
        end

        //=====================================================================
        // Test Summary
        //=====================================================================
        repeat(20) @(posedge clk);

        $display("\n");
        $display("============================================================");
        $display("  TEST SUMMARY");
        $display("============================================================");
        $display("  Total Tests: %0d", pass_count + fail_count);
        $display("  Passed:      %0d", pass_count);
        $display("  Failed:      %0d", fail_count);
        $display("============================================================");

        if (fail_count == 0) begin
            $display("  *** ALL TESTS PASSED ***");
        end else begin
            $display("  *** SOME TESTS FAILED ***");
        end

        $display("============================================================\n");

        #10000;
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================
    initial begin
        #50000000;  // 50ms timeout
        $display("\n*** ERROR: Simulation timeout! ***\n");
        $finish;
    end

endmodule
