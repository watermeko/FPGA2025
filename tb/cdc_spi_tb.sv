`timescale 1ns / 1ps

module cdc_spi_tb;

    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;

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
    
    integer i;

    cdc_spi dut(
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in), .led_out(), .pwm_pins(), 
        .ext_uart_rx(1'b1), .ext_uart_tx(), .dac_clk(1'b0), .dac_data(),
        .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    //-----------------------------------------------------------------------------
    // SPI Slave Model (SPI Mode 0: CPOL=0, CPHA=0)
    // - Master在上升沿改变MOSI，从机在上升沿采样MOSI
    // - 从机在下降沿改变MISO，主机在下降沿采样MISO
    //-----------------------------------------------------------------------------
    reg [7:0] spi_slave_tx_reg;
    reg [7:0] spi_slave_rx_reg;
    reg [2:0] spi_slave_bit_count;
    reg [7:0] spi_slave_byte_count;
    reg [7:0] spi_slave_read_mem [0:255];
    reg [7:0] spi_slave_total_tx_count;  // 跨CS周期的累计发送字节数
    reg       spi_slave_miso_out;        // MISO输出数据寄存器
    reg       spi_slave_miso_en;         // MISO输出使能

    initial begin
        for (i = 0; i < 256; i = i + 1) spi_slave_read_mem[i] = 8'h00 + i;
        spi_slave_read_mem[0] = 8'hA5;
        spi_slave_read_mem[1] = 8'h5A;
        spi_slave_read_mem[2] = 8'hB6;
        spi_slave_read_mem[3] = 8'h6B;
        spi_slave_total_tx_count = 0;
        spi_slave_bit_count = 0;
        spi_slave_byte_count = 0;
        spi_slave_miso_en = 0;
        spi_slave_miso_out = 0;
    end

    // 三态输出：只有在CS有效时才驱动MISO
    assign spi_miso = spi_slave_miso_en ? spi_slave_miso_out : 1'bz;

    // CS边沿检测和控制逻辑
    always @(negedge spi_cs_n or posedge spi_cs_n) begin
        if (!spi_cs_n) begin
            // CS下降沿：初始化传输
            spi_slave_bit_count <= 0;
            spi_slave_byte_count <= 0;
            spi_slave_tx_reg <= spi_slave_read_mem[spi_slave_total_tx_count];
            spi_slave_miso_out <= spi_slave_read_mem[spi_slave_total_tx_count][7];
            spi_slave_miso_en <= 1'b1;
            $display("[%0t] SPI_SLAVE: CS asserted, preload byte[%0d]=0x%02x", $time, spi_slave_total_tx_count, spi_slave_read_mem[spi_slave_total_tx_count]);
        end else begin
            // CS上升沿：结束传输
            spi_slave_miso_en <= 1'b0;
            spi_slave_total_tx_count <= spi_slave_total_tx_count + spi_slave_byte_count;
            $display("[%0t] SPI_SLAVE: CS deasserted, received %0d bytes (total sent: %0d)", $time, spi_slave_byte_count, spi_slave_total_tx_count + spi_slave_byte_count);
        end
    end

    // 时钟上升沿：采样MOSI
    always @(posedge spi_clk) begin
        if (!spi_cs_n) begin
            spi_slave_rx_reg <= {spi_slave_rx_reg[6:0], spi_mosi};
            spi_slave_bit_count <= spi_slave_bit_count + 1;
            if (spi_slave_bit_count == 7) begin
                $display("[%0t] SPI_SLAVE: Received byte[%0d]=0x%02x", $time, spi_slave_byte_count, {spi_slave_rx_reg[6:0], spi_mosi});
                spi_slave_byte_count <= spi_slave_byte_count + 1;
            end
        end
    end

    // 时钟下降沿：输出MISO下一位
    always @(negedge spi_clk) begin
        if (!spi_cs_n) begin
            if (spi_slave_bit_count == 0 && spi_slave_byte_count > 0) begin
                // 字节边界：加载下一个字节
                spi_slave_tx_reg <= spi_slave_read_mem[spi_slave_total_tx_count + spi_slave_byte_count];
                spi_slave_miso_out <= spi_slave_read_mem[spi_slave_total_tx_count + spi_slave_byte_count][7];
            end else if (spi_slave_bit_count != 0) begin
                // 移位输出下一位
                spi_slave_miso_out <= spi_slave_tx_reg[7 - spi_slave_bit_count];
            end
        end
    end
    
    //-----------------------------------------------------------------------------
    // Clock, Reset, Tasks, and Test Sequence
    //-----------------------------------------------------------------------------
    initial begin clk = 0; forever #(CLK_PERIOD_NS / 2) clk = ~clk; end
    initial begin rst_n = 1'b0; usb_data_in=0; usb_data_valid_in=0; #(CLK_PERIOD_NS * 20); rst_n = 1'b1; end

    task send_usb_byte(input [7:0] byte_to_send);
        begin @(posedge clk); usb_data_in = byte_to_send; usb_data_valid_in = 1'b1;
              @(posedge clk); usb_data_valid_in = 1'b0; #(CLK_PERIOD_NS * 2); end
    endtask

    task automatic send_spi_command(input [7:0] write_len, input [7:0] read_len);
        reg [7:0] checksum; integer payload_len, j;
        begin
            $display("\n[%0t] ======= Sending SPI Command: Write=%0d, Read=%0d =======", $time, write_len, read_len);
            payload_len = 2 + write_len;
            checksum = 8'h11 + payload_len[15:8] + payload_len[7:0] + write_len + read_len;
            for (j = 0; j < write_len; j = j + 1) checksum = checksum + (8'hDE - j);
            send_usb_byte(8'hAA); send_usb_byte(8'h55); send_usb_byte(8'h11);
            send_usb_byte(payload_len[15:8]); send_usb_byte(payload_len[7:0]);
            send_usb_byte(write_len); send_usb_byte(read_len);
            for (j = 0; j < write_len; j = j + 1) send_usb_byte(8'hDE - j);
            send_usb_byte(checksum);
        end
    endtask

    reg [7:0] usb_received_data [0:255];
    integer   usb_received_count;
    
    always @(posedge clk) begin
        if (usb_upload_valid) begin
            $display("[%0t] ======= USB UPLOAD [%0d] = 0x%02x =======", $time, usb_received_count, usb_upload_data);
            usb_received_data[usb_received_count] = usb_upload_data;
            usb_received_count = usb_received_count + 1;
        end
    end

    task verify_spi_test_results(input integer expected_read_len);
        integer errors;
        begin
            errors = 0;
            #(CLK_PERIOD_NS * 20000); 
            $display("--- VERIFICATION (Expected %0d bytes) ---", expected_read_len);
            if (usb_received_count != expected_read_len) begin
                $display("❌ FAIL: Byte count mismatch. Expected %0d, Received %0d.", expected_read_len, usb_received_count);
                errors = errors + 1;
            end else if (expected_read_len >= 0) begin
                $display("✅ PASS: Received correct number of bytes (%0d).", usb_received_count);
            end
            for (i = 0; i < usb_received_count; i = i + 1) begin
                if (usb_received_data[i] != spi_slave_read_mem[i]) begin
                    $display("  [%0d] RX: 0x%02x vs EXP: 0x%02x  (❌ MISMATCH)", i, usb_received_data[i], spi_slave_read_mem[i]);
                end else begin
                     $display("  [%0d] RX: 0x%02x vs EXP: 0x%02x  (✅ Match)", i, usb_received_data[i], spi_slave_read_mem[i]);
                end
            end
            if (errors == 0) $display("✅ FINAL RESULT: PASS");
            else $display("❌ FINAL RESULT: FAIL with %0d error(s).", errors);
            $display("-------------------------------------\n");
        end
    endtask

    initial begin
        wait (rst_n == 1'b1); #1000;
        $display("\n=== Starting CDC_SPI Test Sequence ===\n");
        usb_received_count = 0; send_spi_command(1, 1); verify_spi_test_results(1);
        usb_received_count = 0; send_spi_command(4, 4); verify_spi_test_results(4);
        usb_received_count = 0; send_spi_command(2, 0); verify_spi_test_results(0);
        usb_received_count = 0; send_spi_command(0, 2); verify_spi_test_results(2);
        $display("\n=== Test Sequence Complete ===\n");
        #(CLK_PERIOD_NS * 1000); $finish;
    end
endmodule