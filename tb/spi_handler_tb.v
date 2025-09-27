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
    wire       spi_miso;

    // ---------------- 上传接口 ----------------
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

    // ------------------------------------------------------------------
    //  新版 SPI 从机（Mode 0，与 spi_clk 上升沿对齐，0 延迟）
    // ------------------------------------------------------------------
    reg [7:0] slave_tx_shift_reg;
    reg [7:0] slave_tx_next;
    reg [3:0] slave_bit_cnt;
    reg [7:0] slave_byte_cnt;
    reg [7:0] slave_rx_shift_reg;
    reg [7:0] slave_ram [0:255];
 
    // 提前准备要回送的字节
    always @(*) begin
        if (spi_cs_n)
            slave_tx_next = 8'hFF;
        else
            case (slave_byte_cnt)
                0:  slave_tx_next = slave_ram[0];  // 第 1 字节
                1:  slave_tx_next = slave_ram[1];  // 第 2 字节
                2:  slave_tx_next = slave_ram[2];  // 第 3 字节
                default: slave_tx_next = 8'hFF;
            endcase
    end

    assign spi_miso = (spi_cs_n) ? 1'bz : slave_tx_shift_reg[7];

    // 仅改 1 处：提前加载
always @(posedge spi_clk or posedge spi_cs_n) begin
    if (spi_cs_n) begin
        slave_bit_cnt      <= 4'd0;
        slave_byte_cnt     <= 8'd0;
        slave_tx_shift_reg <= 8'hFF;
        slave_rx_shift_reg <= 8'h00;
    end
    else begin
        slave_rx_shift_reg <= {slave_rx_shift_reg[6:0], spi_mosi};

        // 字节边界：立即加载下一个字节
        if (slave_bit_cnt == 4'd7) begin
            slave_ram[slave_byte_cnt] <= {slave_rx_shift_reg[6:0], spi_mosi};
            slave_tx_shift_reg        <= slave_tx_next;  // <--提前加载
            slave_byte_cnt            <= slave_byte_cnt + 8'd1;
            slave_bit_cnt             <= 4'd0;
        end
        else begin
            slave_tx_shift_reg <= {slave_tx_shift_reg[6:0], 1'b0};
            slave_bit_cnt      <= slave_bit_cnt + 4'd1;
        end
    end
end

    always @(posedge spi_clk)
        if (!spi_cs_n && slave_bit_cnt == 4'd7)
            $display("Time %t: [SPI_SLAVE] Byte %d complete. RX: %02h",
                     $time, slave_byte_cnt, {slave_rx_shift_reg[6:0], spi_mosi});

    always @(posedge spi_cs_n)
        $display("Time %t: [SPI_SLAVE] CS Inactive. Resetting state.", $time);

    // ------------------------------------------------------------------
    //  任务定义
    // ------------------------------------------------------------------
    task setup_slave_for_write;
        begin
            slave_byte_cnt = 0;
            slave_bit_cnt  = 0;
            $display("Time %t: [SPI_SLAVE] Setup for WRITE+READ test. Will cache & echo.", $time);
        end
    endtask

    task setup_slave_for_read;
        begin
            slave_byte_cnt = 0;
            slave_bit_cnt  = 0;
            $display("Time %t: [SPI_SLAVE] Setup for READ test. Will echo cached data.", $time);
        end
    endtask

    task send_cmd_data;
        input [15:0] index;
        input [7:0]  data;
        begin
            cmd_data_index = index;
            cmd_data       = data;
            cmd_data_valid = 1;
            @(posedge clk);
            cmd_data_valid = 0;
            @(posedge clk);
        end
    endtask

    task test_spi_config;
        begin
            $display("--- Testing SPI Config Command (0x10) ---");
            wait(cmd_ready == 1);
            @(posedge clk);
            cmd_type   = 8'h10;
            cmd_length = 16'h01;
            cmd_start  = 1;
            @(posedge clk);
            cmd_start  = 0;
            @(posedge clk);
            send_cmd_data(16'h0003, 8'h88);
            @(posedge clk);
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            $display("SPI Config Command Completed");
        end
    endtask

    task test_spi_write;
        begin
            $display("--- Testing SPI Write Command (0x11) ---");
            wait(cmd_ready == 1);
            @(posedge clk);
            cmd_type   = 8'h11;
            cmd_length = 16'h03;
            cmd_start  = 1;
            @(posedge clk);
            cmd_start  = 0;
            @(posedge clk);
            send_cmd_data(16'h0000, 8'h3a);
            send_cmd_data(16'h0001, 8'h4b);
            send_cmd_data(16'h0002, 8'h5c);
            @(posedge clk);
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            $display("SPI Write Command Completed");
        end
    endtask

    task test_spi_read;
        begin
            $display("--- Testing SPI Read Command (0x12) ---");
            $display("Time %t: [TB] Slave ram0=%02h ram1=%02h ram2=%02h",
                     $time, slave_ram[0], slave_ram[1], slave_ram[2]);
            wait(cmd_ready == 1);
            @(posedge clk);
            cmd_type   = 8'h12;
            cmd_length = 16'h03;
            cmd_start  = 1;
            @(posedge clk);
            cmd_start  = 0;
            @(posedge clk);
            // 发 3 个 dummy 字节，产生 3×8 个 SCLK
            send_cmd_data(16'h0000, 8'h00);
            send_cmd_data(16'h0001, 8'h00);
            send_cmd_data(16'h0002, 8'h00);
            @(posedge clk);
            cmd_done = 1;
            @(posedge clk);
            cmd_done = 0;
            $display("SPI Read Command Completed");
        end
    endtask

    // ------------------------------------------------------------------
    //  主流程
    // ------------------------------------------------------------------
    initial begin
        rst_n          = 0;
        cmd_type       = 8'h00;
        cmd_length     = 16'h0000;
        cmd_data       = 8'h00;
        cmd_data_index = 16'h0000;
        cmd_start      = 0;
        cmd_data_valid = 0;
        cmd_done       = 0;
        upload_ready   = 1;

        #100;
        rst_n = 1;
        #50;

        $display("=== SPI Handler Testbench Start ===");

        test_spi_config();
        #50000;

        setup_slave_for_write();
        test_spi_write();
        #50000;

        setup_slave_for_read();
        test_spi_read();
        #50000;

        $display("=== SPI Handler Testbench Complete ===");
        #10000;
        $stop;
    end

    // ------------------------------------------------------------------
    //  调试打印
    // ------------------------------------------------------------------
    always @(posedge cmd_start)
        $display("Time %t: CMD_START - Type=0x%02x, Length=%d", $time, cmd_type, cmd_length);

    always @(posedge cmd_data_valid)
        $display("Time %t: CMD_DATA - Index=%d, Data=0x%02x", $time, cmd_data_index, cmd_data);

    always @(posedge clk)
        if (upload_valid)
            $display("Time %t: UPLOAD_DATA - Source=0x%02x, Data=0x%02x", $time, upload_source, upload_data);

    always @(spi_cs_n or spi_mosi)
        if (spi_cs_n !== 1'bx && spi_mosi !== 1'bx)
            $display("Time %t: SPI - CS_N=%b, MOSI=%b", $time, spi_cs_n, spi_mosi);

endmodule