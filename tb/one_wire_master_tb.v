// ============================================================================
// Testbench: one_wire_master_tb
// Description: Simple testbench for one_wire_master module
// ============================================================================
`timescale 1ns / 1ps

module one_wire_master_tb;

    // Clock and reset
    reg clk;
    reg rst_n;

    // Control signals
    reg start_reset;
    reg start_write_bit;
    reg start_read_bit;
    reg write_bit_data;

    // Status signals
    wire busy;
    wire done;
    wire read_bit_data;
    wire presence_detected;

    // 1-Wire bus
    wire onewire_io;
    reg  onewire_drive;
    reg  onewire_value;

    // Bus simulation: pull-up resistor + open-drain driver
    assign onewire_io = onewire_drive ? onewire_value : 1'bz;
    pullup(onewire_io);  // 模拟上拉电阻

    // ==================== DUT Instantiation ====================
    one_wire_master #(
        .CLK_FREQ(60_000_000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_reset(start_reset),
        .start_write_bit(start_write_bit),
        .start_read_bit(start_read_bit),
        .write_bit_data(write_bit_data),
        .busy(busy),
        .done(done),
        .read_bit_data(read_bit_data),
        .presence_detected(presence_detected),
        .onewire_io(onewire_io)
    );

    // ==================== Clock Generation ====================
    initial begin
        clk = 0;
        forever #8.33 clk = ~clk;  // 60MHz clock (period = 16.67ns)
    end

    // ==================== 1-Wire Slave Simulator ====================
    // 简单模拟从机应答行为
    task simulate_slave_presence;
        begin
            // 等待主机拉低总线（复位脉冲）
            @(negedge onewire_io);
            $display("[%0t] Slave: Detected reset pulse", $time);

            // 等待主机释放总线
            @(posedge onewire_io);
            $display("[%0t] Slave: Master released bus", $time);

            // 等待 30us 后发送应答脉冲
            #30000;
            onewire_drive = 1'b1;
            onewire_value = 1'b0;
            $display("[%0t] Slave: Sending presence pulse", $time);

            // 应答脉冲持续 120us
            #120000;
            onewire_drive = 1'b0;
            $display("[%0t] Slave: Presence pulse complete", $time);
        end
    endtask

    // 模拟从机读取位（发送位给主机）
    task simulate_slave_read_bit(input bit_value);
        begin
            // 等待主机拉低总线
            @(negedge onewire_io);

            // 等待主机释放总线
            @(posedge onewire_io);

            // 如果要发送 0，在采样窗口内拉低总线
            if (bit_value == 0) begin
                #1000;  // 稍微延迟
                onewire_drive = 1'b1;
                onewire_value = 1'b0;
                #20000;  // 保持低电平
                onewire_drive = 1'b0;
            end
            // 如果发送 1，保持总线为高（不拉低）
        end
    endtask

    // ==================== Test Sequence ====================
    initial begin
        // Initialize signals
        rst_n = 0;
        start_reset = 0;
        start_write_bit = 0;
        start_read_bit = 0;
        write_bit_data = 0;
        onewire_drive = 0;
        onewire_value = 1;

        $display("========================================");
        $display("  1-Wire Master Testbench");
        $display("========================================");

        // Reset
        #100;
        rst_n = 1;
        #100;

        // ==================== Test 1: Reset and Presence Detection ====================
        $display("\n[Test 1] Reset and Presence Detection");

        // 启动从机应答模拟
        fork
            simulate_slave_presence();
        join_none

        // 发起复位
        #1000;
        start_reset = 1;
        @(posedge clk);
        start_reset = 0;

        // 等待完成
        @(posedge done);
        #100;

        if (presence_detected)
            $display("[%0t] PASS: Presence detected", $time);
        else
            $display("[%0t] FAIL: No presence detected", $time);

        #10000;

        // ==================== Test 2: Write Bit 0 ====================
        $display("\n[Test 2] Write Bit 0");
        write_bit_data = 0;
        start_write_bit = 1;
        @(posedge clk);
        start_write_bit = 0;

        @(posedge done);
        $display("[%0t] Write bit 0 complete", $time);
        #10000;

        // ==================== Test 3: Write Bit 1 ====================
        $display("\n[Test 3] Write Bit 1");
        write_bit_data = 1;
        start_write_bit = 1;
        @(posedge clk);
        start_write_bit = 0;

        @(posedge done);
        $display("[%0t] Write bit 1 complete", $time);
        #10000;

        // ==================== Test 4: Read Bit (Slave sends 0) ====================
        $display("\n[Test 4] Read Bit (expect 0)");

        fork
            simulate_slave_read_bit(0);
        join_none

        start_read_bit = 1;
        @(posedge clk);
        start_read_bit = 0;

        @(posedge done);
        #100;

        if (read_bit_data == 0)
            $display("[%0t] PASS: Read bit = 0", $time);
        else
            $display("[%0t] FAIL: Read bit = %b (expected 0)", $time, read_bit_data);

        #10000;

        // ==================== Test 5: Read Bit (Slave sends 1) ====================
        $display("\n[Test 5] Read Bit (expect 1)");

        fork
            simulate_slave_read_bit(1);
        join_none

        start_read_bit = 1;
        @(posedge clk);
        start_read_bit = 0;

        @(posedge done);
        #100;

        if (read_bit_data == 1)
            $display("[%0t] PASS: Read bit = 1", $time);
        else
            $display("[%0t] FAIL: Read bit = %b (expected 1)", $time, read_bit_data);

        // ==================== Test Complete ====================
        #50000;
        $display("\n========================================");
        $display("  All Tests Complete");
        $display("========================================");
        $finish;
    end

    // ==================== Waveform Dump ====================
    initial begin
        $dumpfile("one_wire_master_tb.vcd");
        $dumpvars(0, one_wire_master_tb);
    end

    // Timeout watchdog
    initial begin
        #10_000_000;  // 10ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
