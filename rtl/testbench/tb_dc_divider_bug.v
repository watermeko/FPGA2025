`timescale 1ns / 1ps

module tb_dc_handler_divider_bug;

    reg clk;
    reg rst_n;
    reg [7:0] dc_signal_in;

    // Command interface
    reg cmd_start;
    reg cmd_done;
    reg [7:0] cmd_type;
    reg [7:0] cmd_data;

    // Upload interface
    wire upload_req;
    wire [7:0] upload_data;
    wire upload_valid;
    reg upload_ready;

    // Clock generation
    initial begin
        clk = 0;
        forever #8.33 clk = ~clk; // 60 MHz
    end

    // DUT instantiation
    digital_capture_handler dut (
        .clk(clk),
        .rst_n(rst_n),
        .dc_signal_in(dc_signal_in),
        .cmd_start(cmd_start),
        .cmd_done(cmd_done),
        .cmd_type(cmd_type),
        .cmd_data(cmd_data),
        .upload_req(upload_req),
        .upload_data(upload_data),
        .upload_valid(upload_valid),
        .upload_ready(upload_ready)
    );

    // Test divider=6000 (10 kHz)
    initial begin
        // Initialize
        rst_n = 0;
        dc_signal_in = 8'h00;
        cmd_start = 0;
        cmd_done = 0;
        upload_ready = 1; // Always ready

        #100;
        rst_n = 1;
        #100;

        // Send START command with divider=6000
        cmd_type = 8'h0B; // DC_START
        cmd_data = 8'h17; // High byte
        cmd_start = 1;
        #20;
        cmd_start = 0;
        #20;

        cmd_data = 8'h70; // Low byte (6000 = 0x1770)
        #20;
        cmd_done = 1;
        #20;
        cmd_done = 0;

        // Change input signal periodically
        forever begin
            #100000; // 100 us
            dc_signal_in = dc_signal_in + 1;
        end
    end

    // Monitor for deadlock
    integer stuck_count = 0;
    reg [31:0] last_upload_count = 0;
    reg [31:0] upload_count = 0;

    always @(posedge clk) begin
        if (upload_valid && upload_ready) begin
            upload_count <= upload_count + 1;
        end
    end

    // Check every 1ms
    initial begin
        forever begin
            #1000000; // 1ms
            if (upload_count == last_upload_count) begin
                stuck_count = stuck_count + 1;
                $display("Time %0t: No upload for %0d ms", $time, stuck_count);

                if (stuck_count >= 3) begin
                    $display("ERROR: Upload stuck for 3ms!");
                    $display("  upload_req = %b", upload_req);
                    $display("  upload_valid = %b", upload_valid);
                    $display("  upload_ready = %b", upload_ready);
                    $display("  upload_state = %d", dut.upload_state);
                    $display("  new_sample_flag = %b", dut.new_sample_flag);
                    $finish;
                end
            end else begin
                stuck_count = 0;
            end
            last_upload_count = upload_count;
        end
    end

    // Dump waveform
    initial begin
        $dumpfile("dc_divider_bug.vcd");
        $dumpvars(0, tb_dc_handler_divider_bug);

        #10000000; // Run for 10ms
        $display("Test completed without deadlock");
        $finish;
    end

endmodule
