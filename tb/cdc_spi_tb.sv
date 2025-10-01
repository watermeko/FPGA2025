`timescale 1ns / 1ps

module cdc_spi_tb;

    //-----------------------------------------------------------------------------
    // Testbench Parameters
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 60_000_000;
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ;

    //-----------------------------------------------------------------------------
    // Testbench Signals
    //-----------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;
    
    // Wires to monitor the DUT's outputs
    wire       spi_clk;
    wire       spi_cs_n;
    wire       spi_mosi;
    reg        spi_miso;
    wire [7:0] usb_upload_data;
    wire       usb_upload_valid;
    
    integer i;

    //-----------------------------------------------------------------------------
    // DUT Instantiation
    //-----------------------------------------------------------------------------
    cdc_spi dut(
        .clk(clk), .rst_n(rst_n), .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in), .led_out(), .pwm_pins(), 
        .ext_uart_rx(1'b1), .ext_uart_tx(), .dac_clk(1'b0), .dac_data(),
        .spi_clk(spi_clk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );
    
    //-----------------------------------------------------------------------------
    // Monitoring Signals
    //-----------------------------------------------------------------------------
    reg parser_prev_done;
    reg cmd_proc_prev_start;
    reg cmd_proc_prev_done;
    reg [3:0] cp_state_prev;
    reg [2:0] spi_handler_prev_state;

    //-----------------------------------------------------------------------------
    // SPI Slave Model (FINAL CORRECTED VERSION)
    //-----------------------------------------------------------------------------
    reg [7:0] spi_slave_tx_reg;
    reg [7:0] spi_slave_rx_reg;
    reg [3:0] spi_slave_bit_count;
    reg [7:0] spi_slave_byte_count;
    reg [7:0] spi_slave_read_mem [0:255];

    // 最终修正了所有时序问题的从机模型
    always @(posedge spi_clk or negedge spi_cs_n) begin
        if (!spi_cs_n) begin
            // --- 接收逻辑 (在上升沿采样 MOSI) ---
            spi_slave_rx_reg <= {spi_slave_rx_reg[6:0], spi_mosi};

            // --- 发送逻辑 (在上升沿更新 MISO) ---
            spi_miso <= spi_slave_tx_reg[7];

            // --- 关键修正：用 if-else 解决驱动冲突 ---
            if (spi_slave_bit_count == 7) begin
                // 一个字节的末尾：加载下一个字节的数据
                $display("[%0t] SPI_SLAVE: Received byte[%0d]=0x%02x", $time, spi_slave_byte_count, {spi_slave_rx_reg[6:0], spi_mosi});
                spi_slave_byte_count <= spi_slave_byte_count + 1;
                spi_slave_tx_reg <= spi_slave_read_mem[spi_slave_byte_count + 1];
            end else begin
                // 一个字节的中途：将发送寄存器左移一位
                spi_slave_tx_reg <= {spi_slave_tx_reg[6:0], 1'b0};
            end
            spi_slave_bit_count <= spi_slave_bit_count + 1;

        end else begin // CS为高，复位状态
            spi_miso <= 1'bz; 
            spi_slave_bit_count <= 0;
            spi_slave_byte_count <= 0;
            // 预加载第一个要发送的字节
            spi_slave_tx_reg <= spi_slave_read_mem[0]; 
        end
    end

    //-----------------------------------------------------------------------------
    // Clock and Reset Generation
    //-----------------------------------------------------------------------------
    initial begin clk = 0; forever #(CLK_PERIOD_NS / 2) clk = ~clk; end
    initial begin rst_n = 1'b0; #(CLK_PERIOD_NS * 20); rst_n = 1'b1; end

    //-----------------------------------------------------------------------------
    // Tasks
    //-----------------------------------------------------------------------------
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
            end else if (expected_read_len > 0 || (expected_read_len == 0 && usb_received_count == 0)) begin
                $display("✅ PASS: Received correct number of bytes (%0d).", usb_received_count);
            end
            for (i = 0; i < usb_received_count; i = i + 1) begin
                if (usb_received_data[i] != spi_slave_read_mem[i]) begin
                    $display("  [%0d] RX: 0x%02x vs EXP: 0x%02x  (❌ MISMATCH)", i, usb_received_data[i], spi_slave_read_mem[i]);
                    errors = errors + 1;
                end
            end
            if (errors == 0) $display("✅ FINAL RESULT: PASS");
            else $display("❌ FINAL RESULT: FAIL with %0d error(s).", errors);
            $display("-------------------------------------\n");
        end
    endtask

    //-----------------------------------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------------------------------
    initial begin
        // --- *** 关键修正：添加集中的、全面的初始化块 *** ---
        $display("[%0t] Initializing all testbench signals...", $time);
        usb_data_in = 8'h00;
        usb_data_valid_in = 1'b0;
        spi_miso = 1'b0;
        usb_received_count = 0;
        parser_prev_done = 0;
        cmd_proc_prev_start = 0;
        cmd_proc_prev_done = 0;
        cp_state_prev = 4'dx;
        spi_handler_prev_state = 3'dx;
        spi_slave_tx_reg = 0;
        spi_slave_rx_reg = 0;
        spi_slave_bit_count = 0;
        spi_slave_byte_count = 0;
        for (i = 0; i < 256; i = i + 1) spi_slave_read_mem[i] = 8'h00 + i;
        spi_slave_read_mem[0] = 8'hA5;
        spi_slave_read_mem[1] = 8'h5A;
        spi_slave_read_mem[2] = 8'hB6;
        spi_slave_read_mem[3] = 8'h6B;
        
        wait (rst_n == 1'b1);
        #1000;
        
        $display("\n=== Starting CDC_SPI Test Sequence ===\n");
        
        usb_received_count = 0; 
        send_spi_command(1, 1); 
        verify_spi_test_results(1);

        usb_received_count = 0; 
        send_spi_command(4, 4); 
        verify_spi_test_results(4);

        usb_received_count = 0; 
        send_spi_command(2, 0); 
        verify_spi_test_results(0);

        usb_received_count = 0; 
        send_spi_command(0, 2); 
        verify_spi_test_results(2);

        $display("\n=== Test Sequence Complete ===\n");
        #(CLK_PERIOD_NS * 1000); $finish;
    end
    
    // --- Helper Functions for Logging ---
    function string get_cp_state_name(input [3:0] state);
        case(state)
            4'b0001: return "IDLE"; 4'b0010: return "SET_ADDR";
            4'b0100: return "WAIT_DATA_1"; 4'b1000: return "WAIT_DATA_2";
            4'b1001: return "GET_DATA"; default: return "UNKNOWN";
        endcase
    endfunction
    
    function string get_spi_state_name(input [2:0] state);
        case(state)
            3'd0: return "IDLE"; 3'd1: return "WAIT_ALL_DATA";
            3'd2: return "PARSE_AND_EXEC"; 3'd3: return "START_TRANSFER";
            3'd4: return "WAIT_DONE"; 3'd5: return "UPLOAD";
            default: return "UNKNOWN";
        endcase
    endfunction

endmodule