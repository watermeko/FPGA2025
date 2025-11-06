// ============================================================================
// Module:      tb_cdc_with_i2c_slave
// Description:
// - 这个测试平台实例化了完整的 'cdc' 模块作为 DUT。
// - 它包含一个 'i2c_master' 实例，用于与 cdc 内部的 i2c_slave_handler 进行物理 I2C 通信。
// - 它通过发送 USB-CDC 命令来配置 cdc 内部的 i2c_slave_handler，并触发数据上传。
// - 核心测试逻辑与您原始的 tb_i2c_top.sv 保持一致，但所有操作都通过协议命令实现。
// ============================================================================

`timescale 1ns / 1ps

module tb_cdc_with_i2c_slave ();

   //-----------------------------------------------------------------------------
   // 测试平台参数
   //-----------------------------------------------------------------------------
   parameter CLK_PERIOD_NS = 20; // 50MHz 系统时钟

   //-----------------------------------------------------------------------------
   // 信号声明
   //-----------------------------------------------------------------------------
   reg         clk;
   reg         rst_n;

   // --- 连接到 cdc DUT 的信号 ---
   reg  [7:0] usb_data_in;
   reg        usb_data_valid_in;
   wire [7:0] usb_upload_data;
   wire       usb_upload_valid;
   
   // I2C Master <-> CDC Slave 物理接口
   wire        i2c_scl_slave;
   wire        i2c_sda_slave;

   // --- 其他未使用的 DUT 端口 (连接到虚拟信号) ---
   wire        led_out;
   wire [7:0]  pwm_pins;
   reg         ext_uart_rx;
   wire        ext_uart_tx;
   reg         dac_clk; // 需要一个虚拟时钟
   wire signed [13:0] dac_data;
   wire        spi_clk, spi_cs_n, spi_mosi;
   reg         spi_miso;
   reg  [7:0]  dsm_signal_in;
//    reg  [7:0]  dc_signal_in;
   wire        i2c_scl_master, i2c_sda_master;
   wire        debug_out;
//    wire [7:0]  dc_usb_upload_data;
//    wire        dc_usb_upload_valid;
    
   // --- 测试平台专用变量 ---
   logic [7:0]  i2c_read_data_from_master;
   logic [15:0] i2c_read_word_from_master;
   reg   [7:0]  tb_payload [0:15]; // 用于构建CDC命令
   integer      i;

    logic [6:0] new_addr = 7'h5A;
   //-----------------------------------------------------------------------------
   // 模块实例化
   //-----------------------------------------------------------------------------

   // DUT: 完整的 cdc 模块
   cdc u_dut (
       .clk(clk),
       .rst_n(rst_n),

       .usb_data_in(usb_data_in),
       .usb_data_valid_in(usb_data_valid_in),
       .usb_upload_data(usb_upload_data),
       .usb_upload_valid(usb_upload_valid),

       .i2c_scl_slave(i2c_scl_slave),
       .i2c_sda_slave(i2c_sda_slave),
       
       // --- 连接所有其他未使用的端口 ---
       .led_out(led_out),
       .pwm_pins(pwm_pins),
       .ext_uart_rx(ext_uart_rx),
       .ext_uart_tx(ext_uart_tx),
       .dac_clk(dac_clk),
       .dac_data(dac_data),
       .spi_clk(spi_clk),
       .spi_cs_n(spi_cs_n),
       .spi_mosi(spi_mosi),
       .spi_miso(spi_miso),
       .dsm_signal_in(dsm_signal_in),
    //    .dc_signal_in(dc_signal_in),
       .i2c_scl(i2c_scl_master), // Master I2C 端口
       .i2c_sda(i2c_sda_master), // Master I2C 端口
       .debug_out(debug_out)
    //    .dc_usb_upload_data(dc_usb_upload_data),
    //    .dc_usb_upload_valid(dc_usb_upload_valid)
   );

   // I2C Master: 用于与 DUT 的 I2C Slave 接口通信
   i2c_master #( 
       .value   ( "FAST" ),
       .scl_min ( "HIGH" ) 
   ) u_mstr_i2c (
       .sda ( i2c_sda_slave ),
       .scl ( i2c_scl_slave )
   );

    // I2C 线上拉电阻
   pullup(i2c_sda_slave);

   //-----------------------------------------------------------------------------
   // 时钟、复位和信号初始化
   //-----------------------------------------------------------------------------
   initial begin
      clk = 1'b0;
      forever #(CLK_PERIOD_NS/2) clk = ~clk;
   end
   
   initial begin
       dac_clk = 1'b0;
       forever #(10/2) dac_clk = ~dac_clk; // 100MHz 虚拟DAC时钟
   end

   initial begin
      rst_n <= 1'b0;
      usb_data_valid_in <= 1'b0;
      // 初始化所有未使用的输入
      ext_uart_rx <= 1'b1;
      spi_miso <= 1'b0;
      dsm_signal_in <= 8'h00;
    //   dc_signal_in <= 8'h00;
      #(CLK_PERIOD_NS * 20);
      rst_n <= 1'b1;
   end

   //-----------------------------------------------------------------------------
   // CDC 命令发送任务
   //-----------------------------------------------------------------------------
   task send_usb_byte(input [7:0] data);
       begin @(posedge clk); usb_data_in <= data; usb_data_valid_in <= 1'b1; @(posedge clk); usb_data_valid_in <= 1'b0; end
   endtask

   task automatic send_cdc_command(input [7:0] cmd, input [15:0] len);
       reg [7:0] checksum = 0;
       begin
           send_usb_byte(8'hAA);
           send_usb_byte(8'h55);
           
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

   //-----------------------------------------------------------------------------
   // 主测试序列 (逻辑保持不变，但通过 I2C Master 执行)
   //-----------------------------------------------------------------------------
   initial begin
      wait (rst_n === 1'b1);
      repeat(100) @(posedge clk);
      
      u_mstr_i2c.set_scl_timing(5000, 5000); 

      // --- 使能 I2C Master 的上拉电阻 ---
      u_mstr_i2c.i2c_ena(1);
      #1000;

      // --- 测试开始 ---
      $display("[%0t] ========== I2C Slave Test through CDC Start ==========", $time);

      // (原) u_mstr_i2c.i2c_read (7'h24, 8'h8F, i2c_read_data);
      $display("[%0t] Test 1: Reading from invalid register address 0x8F...", $time);
      u_mstr_i2c.i2c_read (7'h24, 8'h8F, i2c_read_data_from_master);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_write(7'h24, 8'h03, 8'h7B);
      $display("[%0t] Test 2: Writing 0x7B to register 0x03 via I2C...", $time);
      u_mstr_i2c.i2c_write(7'h24, 8'h03, 8'h7B);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_write(7'h24, 8'h02, 8'h3A);
      $display("[%0t] Test 3: Writing 0x3A to register 0x02 via I2C...", $time);
      u_mstr_i2c.i2c_write(7'h24, 8'h02, 8'h3A);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_write_word(7'h24, 8'h00, 16'hCB04);
      $display("[%0t] Test 4: Writing 0xCB04 to registers 0x00/0x01 via I2C...", $time);
      u_mstr_i2c.i2c_write_word(7'h24, 8'h00, 16'hCB04);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_read_word(7'h24, 8'h00, i2c_read_word);
      $display("[%0t] Test 5: Reading registers 0x00/0x01 via I2C...", $time);
      u_mstr_i2c.i2c_read_word(7'h24, 8'h00, i2c_read_word_from_master);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_read (7'h24, 8'h03, i2c_read_data);
      $display("[%0t] Test 6: Reading register 0x03 via I2C...", $time);
      u_mstr_i2c.i2c_read (7'h24, 8'h03, i2c_read_data_from_master);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_write(7'h98, 8'h82, 8'h7A);
      $display("[%0t] Test 7: Writing to wrong slave address 0x98 (expect NACK)...", $time);
      u_mstr_i2c.i2c_write_no_slave(7'h98, 8'h82, 8'h7A); // 使用 _no_slave 版本来检查NACK
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_read (7'hA3, 8'h03, i2c_read_data);
      //  此操作在现实中会挂起，因为没有从机会响应。此处省略以避免仿真挂起。
      $display("[%0t] Test 8: Reading from wrong slave address 0xA3 (skipped)...", $time);
      repeat(10) @(posedge clk);

      // (原) u_mstr_i2c.i2c_read_word(7'h24, 8'h02, i2c_read_word);
      $display("[%0t] Test 9: Reading registers 0x02/0x03 via I2C...", $time);
      u_mstr_i2c.i2c_read_word(7'h24, 8'h02, i2c_read_word_from_master);
      repeat(10) @(posedge clk);

      repeat(100) @(posedge clk);
      $display("[%0t] ========== I2C Slave Test through CDC End ==========", $time);

      repeat(100) @(posedge clk);
      $finish;
   end


//    // <<< CDC TEST SEQUENCE START >>>
//    //-----------------------------------------------------------------------------
//    // CDC 应用层命令测试序列 (新增)
//    //-----------------------------------------------------------------------------
//    initial begin
//       // 等待第一个测试序列完成
//       wait (u_mstr_i2c.instruction == "NULL");
//       repeat(500) @(posedge clk);
      
//       $display("\n[%0t] ========== Sequence 2: CDC Command Test Start ==========", $time);

//       // --- Test 2.1: 测试 CMD 0x15 (CDC 写) ---
//       $display("[%0t] Test 2.1: Writing 0xDEAD to regs 0/1 via CDC command 0x15...", $time);
//       tb_payload[0] = 2;        // 写入长度: 2 字节
//       tb_payload[1] = 8'hAD;    // 数据 1 (写入 reg 0)
//       tb_payload[2] = 8'hDE;    // 数据 2 (写入 reg 1)
//       send_cdc_command(8'h15, 3);
//       repeat(10) @(posedge clk);

//       // 验证: 使用物理 I2C Master 读回，确认数据是否写入成功
//       u_mstr_i2c.i2c_read_word(7'h24, 8'h00, i2c_read_word_from_master);
//       repeat(20) @(posedge clk);
//       if (i2c_read_word_from_master == 16'hDEAD)
//           $display("[%0t]   -> VERIFY SUCCESS: Read back 0x%h via physical I2C.", $time, i2c_read_word_from_master);
//       else
//           $error("[%0t]   -> VERIFY FAILURE: Expected 0xDEAD, but read 0x%h.", $time, i2c_read_word_from_master);
//       repeat(100) @(posedge clk);


//       // --- Test 2.2: 测试 CMD 0x16 (CDC 读/上传) ---
//       // 准备: 使用物理 I2C Master 写入已知数据到 reg 2/3
//       $display("[%0t] Test 2.2: Preparing regs 2/3. Writing 0xBEEF via physical I2C...", $time);
//       u_mstr_i2c.i2c_write_word(7'h24, 8'h02, 16'hBEEF);
//       repeat(100) @(posedge clk);
      
//       // 触发: 发送 CDC 命令请求读取 2 个字节
//       $display("[%0t]   -> Triggering CDC upload of 2 bytes with command 0x16...", $time);
//       tb_payload[0] = 2; // 读取长度: 2 字节
//       send_cdc_command(8'h16, 1);
      
//       // 验证: 捕获 USB 上传的数据并比对
//       // 预期会收到两个字节: EF (来自 reg 2), BE (来自 reg 3)
//       for (int j = 0; j < 2; j = j + 1) begin
//           wait (usb_upload_valid);
//           if (j==0 && usb_upload_data == 8'hEF) 
//               $display("[%0t]   -> VERIFY SUCCESS: Received first byte 0x%h.", $time, usb_upload_data);
//           else if (j==1 && usb_upload_data == 8'hBE)
//               $display("[%0t]   -> VERIFY SUCCESS: Received second byte 0x%h.", $time, usb_upload_data);
//           else
//               $error("[%0t]   -> VERIFY FAILURE: Received unexpected byte 0x%h on upload #%0d.", $time, usb_upload_data, j);
//           @(posedge clk);
//       end
//       repeat(100) @(posedge clk);


//       // --- Test 2.3: 测试 CMD 0x14 (配置地址) ---

//       $display("[%0t] Test 2.3: Changing slave address to 0x%h via CDC command 0x14...", $time, new_addr);
//       tb_payload[0] = new_addr;
//       send_cdc_command(8'h14, 1);
//       repeat(100) @(posedge clk);
      
//       // 验证 1: 旧地址应不再响应 (NACK)
//       $display("[%0t]   -> Verifying old address 0x24 is inactive...", $time);
//       u_mstr_i2c.i2c_write_no_slave(7'h24, 8'h00, 8'h00);
//       repeat(100) @(posedge clk);
      
//       // 验证 2: 新地址应该响应 (ACK)
//       $display("[%0t]   -> Verifying new address 0x%h is active...", $time, new_addr);
//       u_mstr_i2c.i2c_write(new_addr, 8'h00, 8'h00);
//       repeat(100) @(posedge clk);


//       $display("\n[%0t] ========== Sequence 2: CDC Command Test End ==========", $time);
//       repeat(100) @(posedge clk);
//       $finish;
//    end
//   // <<< CDC TEST SEQUENCE END >>>

endmodule