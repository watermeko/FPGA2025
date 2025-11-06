`timescale 1ns / 1ps

module spi_handler_tb;

    // ---------------- 参数 ----------------
    parameter CMD_SPI_CONFIG = 8'h10;
    parameter CMD_SPI_WRITE  = 8'h11;
    parameter CMD_SPI_READ   = 8'h12;

    // ---------------- 时钟/复位 ----------------
    reg        clk;
    reg        rst_n;

    // ---------------- 命令接口 ----------------
    reg  [7:0] cmd_type;
    reg [15:0] cmd_length;
    reg  [7:0] cmd_data;
    reg [15:0] cmd_data_index;
    reg        cmd_start;
    reg        cmd_data_valid;
    reg        cmd_done;
    wire       cmd_ready;

    // ---------------- SPI 接口 ----------------
    wire       spi_clk;
    wire       spi_cs_n;
    wire       spi_mosi;
    reg        spi_miso;

    // ---------------- 上传接口 ----------------
    wire       upload_active;
    wire       upload_req;
    wire [7:0] upload_data;
    wire [7:0] upload_source;
    wire       upload_valid;
    reg        upload_ready;

    // ------------------------------------------------------------------
    //  DUT 实例化
    // ------------------------------------------------------------------
    spi_handler uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_type         (cmd_type),
        .cmd_length       (cmd_length),
        .cmd_data         (cmd_data),
        .cmd_data_index   (cmd_data_index),
        .cmd_start        (cmd_start),
        .cmd_data_valid   (cmd_data_valid),
        .cmd_done         (cmd_done),
        .cmd_ready        (cmd_ready),
        .spi_clk          (spi_clk),
        .spi_cs_n         (spi_cs_n),
        .spi_mosi         (spi_mosi),
        .spi_miso         (spi_miso),
        .upload_active    (upload_active),
        .upload_req       (upload_req),
        .upload_data      (upload_data),
        .upload_source    (upload_source),
        .upload_valid     (upload_valid),
        .upload_ready     (upload_ready)
    );

    // ------------------------------------------------------------------
    // 60 MHz 时钟
    // ------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #8.33 clk = ~clk;
    end

    // ==================== SPI 从机模型 ====================
    reg [7:0] slave_tx_shift_reg;
    reg [7:0] slave_tx_next;
    reg [3:0] slave_bit_cnt;
    reg [7:0] slave_byte_cnt;
    reg [7:0] slave_rx_shift_reg;
    reg [7:0] slave_ram [0:255];
    reg [7:0] slave_read_mem [0:255];

    // 组合逻辑: 准备要回送的字节
    always @(*) begin
        if (spi_cs_n)
            slave_tx_next = 8'hFF;
        else
            case (slave_byte_cnt)
                0:  slave_tx_next = slave_read_mem[0];  // 0xA5
                1:  slave_tx_next = slave_read_mem[1];  // 0x5A
                2:  slave_tx_next = slave_read_mem[2];  // 0xB6
                3:  slave_tx_next = slave_read_mem[3];  // 0x6B
                default: slave_tx_next = 8'hFF;
            endcase
    end

    // SPI 从机时序逻辑 - 符合 SPI Mode 0 标准
    // 上升沿：采样 MOSI
    // 下降沿：更新 MISO

    always @(posedge spi_clk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            slave_bit_cnt      <= 4'd0;
            slave_byte_cnt     <= 8'd0;
            slave_rx_shift_reg <= 8'h00;
        end else begin
            // 在上升沿采样 MOSI
            slave_rx_shift_reg <= {slave_rx_shift_reg[6:0], spi_mosi};
            slave_bit_cnt <= slave_bit_cnt + 4'd1;

            // 字节接收完成
            if (slave_bit_cnt == 4'd7) begin
                slave_ram[slave_byte_cnt] <= {slave_rx_shift_reg[6:0], spi_mosi};
                $display("Time %t: SPI_SLAVE: Received byte[%0d]=0x%02x",
                         $time, slave_byte_cnt, {slave_rx_shift_reg[6:0], spi_mosi});
                slave_byte_cnt <= slave_byte_cnt + 8'd1;
            end
        end
    end

    // 发送逻辑 - 在下降沿更新 MISO（通过移位寄存器）
    always @(negedge spi_clk or posedge spi_cs_n) begin
        if (spi_cs_n) begin
            slave_tx_shift_reg <= 8'hFF;
        end else begin
            // 在下降沿移位并准备下一位
            slave_tx_shift_reg <= {slave_tx_shift_reg[6:0], 1'b0};
        end
    end

    // 在 CS 下降沿或第一个时钟下降沿加载新数据
    always @(negedge spi_cs_n) begin
        slave_tx_shift_reg <= slave_tx_next;
        $display("Time %t: SPI_SLAVE: Loading byte[%0d]=0x%02x",
                 $time, slave_byte_cnt, slave_tx_next);
    end
    
    // MISO驱动逻辑
    always @(*) begin
        if (spi_cs_n) begin
            spi_miso <= 1'bz;
        end else begin
            spi_miso <= slave_tx_shift_reg[7];
        end
    end

    // ==================== 监控和调试 ====================
    
    // 状态机监控
    reg [2:0] prev_state;
    initial prev_state = 0;
    
    always @(posedge clk) begin
        if (uut.state !== prev_state) begin
            $display("Time %t: SPI_HANDLER state %0d -> %0d", $time, prev_state, uut.state);
            case (uut.state)
                0: $display("Time %t: SPI_HANDLER: IDLE", $time);
                1: $display("Time %t: SPI_HANDLER: WAIT_HEADER", $time);
                2: $display("Time %t: SPI_HANDLER: TX_PHASE", $time);
                3: $display("Time %t: SPI_HANDLER: RX_PHASE", $time);
                4: $display("Time %t: SPI_HANDLER: WAIT_SPI_DONE", $time);
                5: $display("Time %t: SPI_HANDLER: UPLOAD_BYTE", $time);
                default: $display("Time %t: SPI_HANDLER: UNKNOWN (%0d)", $time, uut.state);
            endcase
            prev_state <= uut.state;
        end
    end

    // 内部信号监控
    always @(posedge clk) begin
        if (uut.spi_start) begin
            $display("Time %t: SPI_MASTER: Start transmission, tx_byte=0x%02x", $time, uut.current_tx_byte);
        end
        if (uut.spi_done) begin
            $display("Time %t: SPI_MASTER: Transmission done, rx_byte=0x%02x", $time, uut.spi_rx_byte);
        end

        // 监控数据接收
        if (cmd_data_valid) begin
            $display("Time %t: CMD_DATA_VALID: index=%0d, data=0x%02x",
                     $time, cmd_data_index, cmd_data);
        end
    end

    // 监控头部接收
    reg prev_header_received;
    initial prev_header_received = 0;
    always @(posedge clk) begin
        if (uut.header_byte_received && !prev_header_received) begin
            $display("Time %t: HEADER_PARSING: write_len=%0d",
                     $time, uut.write_len);
        end
        if (!uut.header_byte_received && prev_header_received) begin
            $display("Time %t: HEADER_PARSED: write_len=%0d, read_len=%0d",
                     $time, uut.write_len, uut.read_len);
        end
        prev_header_received <= uut.header_byte_received;
    end

    // SPI接口监控
    reg spi_cs_prev;
    initial spi_cs_prev = 1;
    
    always @(posedge clk) begin
        if (spi_cs_n !== spi_cs_prev) begin
            if (spi_cs_n) begin
                $display("Time %t: SPI_IF: CS Deasserted", $time);
            end else begin
                $display("Time %t: SPI_IF: CS Asserted", $time);
            end
            spi_cs_prev <= spi_cs_n;
        end
    end

    // ==================== 测试任务 ====================

    task send_cmd_data;
        input [15:0] index;
        input [7:0]  data;
        begin
            // 等待 handler 准备好接收数据（模拟真实的 command_processor 行为）
            wait(cmd_ready == 1);
            @(posedge clk);
            cmd_data_index = index;
            cmd_data       = data;
            cmd_data_valid = 1;
            @(posedge clk);
            cmd_data_valid = 0;
            @(posedge clk);  // 增加一个时钟周期间隔
        end
    endtask

    task send_spi_command;
        input [7:0] command_type;
        input [15:0] total_length;  // 总payload长度 = 2 + write_len
        input [7:0] write_len;      // 要写入的字节数
        input [7:0] read_len;       // 要读取的字节数
        integer i;
        begin
            $display("Time %t: === Starting SPI Command: Type=0x%02x, TotalLen=%0d (write_len=%0d, read_len=%0d) ===", 
                     $time, command_type, total_length, write_len, read_len);
            
            wait(cmd_ready == 1);
            @(posedge clk);
            
            // 发送命令开始
            cmd_type   = command_type;
            cmd_length = total_length;
            cmd_start  = 1;
            @(posedge clk);
            cmd_start  = 0;
            @(posedge clk);
            
            // 发送payload数据
            if (total_length > 0) begin
                // 前两个字节是write_len和read_len
                send_cmd_data(16'h0000, write_len);
                send_cmd_data(16'h0001, read_len);
                
                // 发送实际数据（如果有）
                for (i = 0; i < write_len; i = i + 1) begin
                    // 根据测试类型发送不同的测试数据
                    case (i)
                        0: send_cmd_data(16'h0002, 8'hDE);
                        1: send_cmd_data(16'h0003, 8'hAD);
                        2: send_cmd_data(16'h0004, 8'hBE);
                        3: send_cmd_data(16'h0005, 8'hEF);
                        4: send_cmd_data(16'h0006, 8'h11);
                        5: send_cmd_data(16'h0007, 8'h22);
                        default: send_cmd_data(16'h0002 + i, 8'h00 + i);
                    endcase
                end
            end
            
            // 发送命令完成
            @(posedge clk);
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            
            $display("Time %t: === SPI Command Frame Sent ===", $time);
        end
    endtask

    // ==================== 测试用例 ====================

    task test_spi_write_only;
        begin
            $display("--- TEST 1: SPI Write Only (4 bytes write, 0 bytes read) ---");
            // total_length = 2(header) + 4(data) = 6
            send_spi_command(CMD_SPI_WRITE, 16'h0006, 8'h04, 8'h00);
            
            // 等待完成
            wait(uut.state == 3'd0);
            #1000;
            $display("--- TEST 1 Complete ---");
        end
    endtask

    task test_spi_read_only;
        begin
            $display("--- TEST 2: SPI Read Only (0 bytes write, 4 bytes read) ---");
            // total_length = 2(header) + 0(data) = 2
            send_spi_command(CMD_SPI_READ, 16'h0002, 8'h00, 8'h04);
            
            // 等待上传完成
            wait(uut.state == 3'd0);
            #1000;
            $display("--- TEST 2 Complete ---");
        end
    endtask

    task test_spi_write_read;
        begin
            $display("--- TEST 3: SPI Write + Read (4 bytes write, 4 bytes read) ---");
            // total_length = 2(header) + 4(data) = 6
            send_spi_command(CMD_SPI_WRITE, 16'h0006, 8'h04, 8'h04);
            
            // 等待上传完成
            wait(uut.state == 3'd0);
            #1000;
            $display("--- TEST 3 Complete ---");
        end
    endtask

    task test_spi_simple;
        begin
            $display("--- TEST 4: Simple SPI (1 byte write, 1 byte read) ---");
            // total_length = 2(header) + 1(data) = 3
            send_spi_command(CMD_SPI_WRITE, 16'h0003, 8'h01, 8'h01);
            
            // 等待上传完成
            wait(uut.state == 3'd0);
            #1000;
            $display("--- TEST 4 Complete ---");
        end
    endtask

    // ==================== 主测试序列 ====================
    initial begin
        // 初始化
        rst_n          = 0;
        cmd_type       = 8'h00;
        cmd_length     = 16'h0000;
        cmd_data       = 8'h00;
        cmd_data_index = 16'h0000;
        cmd_start      = 0;
        cmd_data_valid = 0;
        cmd_done       = 0;
        upload_ready   = 1;

        // 预加载从机读取存储器
        slave_read_mem[0] = 8'hA5;
        slave_read_mem[1] = 8'h5A;
        slave_read_mem[2] = 8'hB6;
        slave_read_mem[3] = 8'h6B;

        #100;
        rst_n = 1;
        #50;

        $display("=== SPI Handler Testbench Start ===");
        $display("Testing SPI command format: [write_len, read_len, data...]");

        // 运行测试序列
        test_spi_simple();
        #2000;
        
        test_spi_write_only();
        #2000;
        
        test_spi_read_only();
        #2000;
        
        test_spi_write_read();
        #2000;

        $display("=== SPI Handler Testbench Complete ===");
        #1000;
        $finish;
    end

    // 上传数据监控
    integer upload_count;
    initial upload_count = 0;
    
    always @(posedge clk) begin
        if (upload_valid) begin
            $display("Time %t: UPLOAD[%0d]: Source=0x%02x, Data=0x%02x", 
                     $time, upload_count, upload_source, upload_data);
            upload_count <= upload_count + 1;
        end
    end

    // 从机接收数据验证
    initial begin
        #5000; // 等待第一个测试完成
        forever begin
            #10000;
            $display("Time %t: SLAVE_RAM contents: [0]=0x%02x, [1]=0x%02x, [2]=0x%02x, [3]=0x%02x",
                     $time, slave_ram[0], slave_ram[1], slave_ram[2], slave_ram[3]);
        end
    end

endmodule