// ============================================================================
// Module: test_command_processor
// Description: Test the exact timing of command_processor for zero-length commands
// ============================================================================
`timescale 1ns / 1ps

module test_command_processor;

    reg clk;
    reg rst_n;

    // Clock: 60MHz
    initial begin
        clk = 0;
        forever #8.333 clk = ~clk;
    end

    // Parser interface
    reg parse_done;
    reg [7:0] cmd_out;
    reg [15:0] len_out;
    reg [7:0] payload_read_data;
    wire [9:0] payload_read_addr;

    // Command bus outputs
    wire [7:0]  cmd_type_out;
    wire [15:0] cmd_length_out;
    wire [7:0]  cmd_data_out;
    wire [15:0] cmd_data_index_out;
    wire        cmd_start_out;
    wire        cmd_data_valid_out;
    wire        cmd_done_out;

    // Handler ready signal (simulated)
    reg cmd_ready_in;

    // Upload interface (not used in this test)
    wire upload_ready_out;
    wire [7:0] usb_upload_data_out;
    wire usb_upload_valid_out;

    // DUT: command_processor
    command_processor #(
        .PAYLOAD_ADDR_WIDTH(10)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .parse_done(parse_done),
        .cmd_out(cmd_out),
        .len_out(len_out),
        .payload_read_data(payload_read_data),
        .led_out(),
        .payload_read_addr(payload_read_addr),
        .cmd_type_out(cmd_type_out),
        .cmd_length_out(cmd_length_out),
        .cmd_data_out(cmd_data_out),
        .cmd_data_index_out(cmd_data_index_out),
        .cmd_start_out(cmd_start_out),
        .cmd_data_valid_out(cmd_data_valid_out),
        .cmd_done_out(cmd_done_out),
        .cmd_ready_in(cmd_ready_in),
        .upload_req_in(1'b0),
        .upload_data_in(8'h00),
        .upload_source_in(8'h00),
        .upload_valid_in(1'b0),
        .upload_ready_out(upload_ready_out),
        .usb_upload_data_out(usb_upload_data_out),
        .usb_upload_valid_out(usb_upload_valid_out)
    );

    // Monitor for cmd_start and cmd_done
    reg cmd_start_seen;
    reg cmd_done_seen;
    reg both_seen_same_cycle;

    always @(posedge clk) begin
        cmd_start_seen <= cmd_start_out;
        cmd_done_seen <= cmd_done_out;

        if (cmd_start_out && cmd_done_out) begin
            $display("[%0t] *** cmd_start AND cmd_done BOTH HIGH in same cycle ***", $time);
            both_seen_same_cycle <= 1;
        end

        if (cmd_start_out) begin
            $display("[%0t] cmd_start = 1, cmd_type = 0x%02X, cmd_length = %0d",
                     $time, cmd_type_out, cmd_length_out);
        end

        if (cmd_done_out) begin
            $display("[%0t] cmd_done = 1", $time);
        end
    end

    // Test sequence
    initial begin
        $display("\n==============================================");
        $display("  Command Processor Timing Test");
        $display("  Testing zero-length command (RESET 0x20)");
        $display("==============================================\n");

        // Initialize
        rst_n = 0;
        parse_done = 0;
        cmd_out = 0;
        len_out = 0;
        payload_read_data = 0;
        cmd_ready_in = 1;  // Handler is ready
        cmd_start_seen = 0;
        cmd_done_seen = 0;
        both_seen_same_cycle = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(10) @(posedge clk);

        $display("[%0t] Test: Sending parse_done for RESET command (0x20, length=0)", $time);

        // Simulate parser completing a zero-length command
        @(posedge clk);
        cmd_out <= 8'h20;      // RESET command
        len_out <= 16'd0;      // Zero length
        parse_done <= 1;       // Parser done
        $display("[%0t] parse_done = 1, cmd = 0x20, len = 0", $time);

        @(posedge clk);
        parse_done <= 0;       // Clear parse_done

        // Wait a few cycles
        repeat(5) @(posedge clk);

        // Check results
        $display("\n==============================================");
        $display("  Test Results");
        $display("==============================================");
        if (both_seen_same_cycle) begin
            $display("✓ CONFIRMED: cmd_start and cmd_done are HIGH in the SAME cycle");
            $display("  This is the EXPECTED behavior for zero-length commands.");
        end else begin
            $display("✗ UNEXPECTED: cmd_start and cmd_done were NOT both high in same cycle");
        end

        $display("\nThis means the handler has only ONE clock cycle to respond!");
        $display("The handler must capture cmd_start in that single cycle.\n");

        #100;
        $finish;
    end

endmodule
