`timescale 1ns / 1ps

module upload_packer_simple_tb();

    reg clk;
    reg rst_n;
    reg raw_upload_req;
    reg [7:0] raw_upload_data;
    reg [7:0] raw_upload_source;
    reg raw_upload_valid;
    wire raw_upload_ready;

    wire packed_upload_req;
    wire [7:0] packed_upload_data;
    wire [7:0] packed_upload_source;
    wire packed_upload_valid;
    reg packed_upload_ready;

    parameter CLK_PERIOD = 16.67;

    // DUT
    upload_packer_simple u_packer (
        .clk(clk),
        .rst_n(rst_n),
        .raw_upload_req(raw_upload_req),
        .raw_upload_data(raw_upload_data),
        .raw_upload_source(raw_upload_source),
        .raw_upload_valid(raw_upload_valid),
        .raw_upload_ready(raw_upload_ready),
        .packed_upload_req(packed_upload_req),
        .packed_upload_data(packed_upload_data),
        .packed_upload_source(packed_upload_source),
        .packed_upload_valid(packed_upload_valid),
        .packed_upload_ready(packed_upload_ready)
    );

    // Clock
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Monitor
    integer bytes_received = 0;
    reg [3:0] last_state = 0;
    always @(posedge clk) begin
        if (packed_upload_valid && packed_upload_ready) begin
            bytes_received = bytes_received + 1;
            $display("[%0t] PACKED: 0x%02x (total=%0d)", $time, packed_upload_data, bytes_received);
        end

        // Debug state changes
        if (u_packer.state != last_state) begin
            $display("[%0t] STATE: %0d -> %0d, data_count=%0d, data_index=%0d, checksum=0x%02x",
                $time, last_state, u_packer.state, u_packer.data_count, u_packer.data_index, u_packer.checksum);
            last_state = u_packer.state;
        end
    end

    // Test
    initial begin
        rst_n = 0;
        raw_upload_req = 0;
        raw_upload_data = 0;
        raw_upload_source = 8'h01;
        raw_upload_valid = 0;
        packed_upload_ready = 1;

        $display("========================================");
        $display("Simple Upload Packer Test");
        $display("========================================");

        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);

        // 发送3字节
        $display("\nSending 3 bytes: A1 A2 A3");
        bytes_received = 0;
        raw_upload_req = 1;

        @(posedge clk);
        wait(raw_upload_ready);
        raw_upload_data = 8'hA1;
        raw_upload_valid = 1;
        @(posedge clk);
        raw_upload_valid = 0;

        @(posedge clk);
        wait(raw_upload_ready);
        raw_upload_data = 8'hA2;
        raw_upload_valid = 1;
        @(posedge clk);
        raw_upload_valid = 0;

        @(posedge clk);
        wait(raw_upload_ready);
        raw_upload_data = 8'hA3;
        raw_upload_valid = 1;
        @(posedge clk);
        raw_upload_valid = 0;

        @(posedge clk);
        raw_upload_req = 0;

        #(CLK_PERIOD * 20);

        if (bytes_received == 9)
            $display("\nTEST PASS! (9 bytes received)");
        else
            $display("\nTEST FAIL! (expected 9, got %0d)", bytes_received);

        #(CLK_PERIOD * 10);
        $finish;
    end

    initial begin
        $dumpfile("upload_packer_simple_tb.vcd");
        $dumpvars(0, upload_packer_simple_tb);
    end

endmodule
