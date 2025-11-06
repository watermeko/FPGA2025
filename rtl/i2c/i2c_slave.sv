//
// File: i2c_slave.sv (Modified Version for Dynamic Address)
// Description:
//   The SLAVE_ID parameter has been replaced with a 'slave_id' input port
//   to allow the slave address to be configured dynamically at runtime.
//
module i2c_slave
// #( parameter SLAVE_ID = 7'h24 ) // <<< STEP 1: REMOVED
(
  // <<< STEP 1: ADDED DYNAMIC ADDRESS INPUT >>>
  input  logic       clk,        // <<< NEW: 必须传入高速系统时钟
  input  logic [6:0] slave_id,

  input  logic       rst_n,      // asynchronous active low reset
  input  logic       scl,        // sample on posedge, drive on negedge
  input  logic       sda_in,     // data in
  output logic       sda_out,    // data out
  // general purpose i2c slave outputs
  output logic       i2c_active, // High between a Start and Stop condition
  output logic       rd_en,      // Slave ID matched and current transfer is a read
  output logic       wr_en,      // Slave ID matched and current transfer is a write
  // regmap specific outputs
  input  logic [7:0] rdata,      // regmap read data
  output logic [7:0] addr,       // regmap read or write address
  output logic [7:0] wdata,      // regmap write data
  output logic       wr_en_wdata // wr_en when wdata is valid, it pulses
);


   localparam P_ACK  = 1'b0;     // I2C ACK
   localparam P_NACK = 1'b1;     // I2C NACK

   logic       start;
   logic       stop;
   logic [3:0] bit_counter;
   logic       check_id;
   logic       rst_start_stop_n;
   logic       rst_stop_n;           
   logic       bit_count_eq_9;
   logic       valid_id;
   logic       rst_start_n;                 
   logic       start_detect;
   logic       start_detect_hold;
   logic [7:0] shift_reg;
   logic       wdata_ready;
   logic       next_data_is_addr;
   logic       multi_cycle;


    // --- 实例化边沿检测器 ---
    logic scl_posedge_tick, scl_negedge_tick;
    logic sda_posedge_tick, sda_negedge_tick;

    // 用系统时钟 clk 来检测 scl 的边沿
    edge_detector scl_edge_detect (
        .clk(clk), .rst_n(rst_n), .signal_in(scl),
        .posedge_tick(scl_posedge_tick), .negedge_tick(scl_negedge_tick)
    );
    // 用系统时钟 clk 来检测 sda 的边沿
    edge_detector sda_edge_detect (
        .clk(clk), .rst_n(rst_n), .signal_in(sda_in),
        .posedge_tick(sda_posedge_tick), .negedge_tick(sda_negedge_tick)
    );

    // --- 同步化 SCL 和 SDA 信号 ---
    logic scl_sync, sda_sync;
    synchronizer scl_sync_inst (.clk(clk), .rst_n(rst_n), .data_in(scl), .data_out(scl_sync));
    synchronizer sda_sync_inst (.clk(clk), .rst_n(rst_n), .data_in(sda_in), .data_out(sda_sync));

   // 使用同步化的信号和边沿检测器来检测START和STOP条件
   // START条件：SCL为高时，SDA下降沿
   logic start_cond_detect;
   always_ff @(posedge clk, negedge rst_n)
     if (!rst_n)
       start_cond_detect <= 1'b0;
     else
       start_cond_detect <= sda_negedge_tick && scl_sync;

   // 将START信号同步到SCL域以便后续逻辑使用
   always_ff @(posedge clk, negedge rst_n)
     if (!rst_n)
       start_detect <= 1'b0;
     else if (start_cond_detect)
       start_detect <= 1'b1;
     else if (scl_posedge_tick)
       start_detect <= 1'b0;

   always_ff @(posedge clk, negedge rst_n)
     if (!rst_n)
       start_detect_hold <= 1'b0;
     else if (scl_posedge_tick)
       start_detect_hold <= start_detect;

   // rising edge detect
   assign start = start_detect && (!start_detect_hold) && scl_posedge_tick;

   // combined reset and scl only used for STOP condition clearing
   assign rst_start_n = rst_n & scl_sync;

   // STOP条件：SCL为高时，SDA上升沿
   always_ff @(posedge clk, negedge rst_start_n)
      if (!rst_start_n)
        stop <= 1'b0;
      else if (sda_posedge_tick && scl_sync)
        stop <= 1'b1;
      else if (start_cond_detect)
        stop <= 1'b0;

   assign rst_stop_n       = (rst_n & (~stop));
   assign rst_start_stop_n = (rst_n & (~start) & (~stop));

   // 同步的i2c_active指示器
   always_ff @(posedge clk, negedge rst_n)
     if (!rst_n)
       i2c_active <= 1'b0;
     else if (start)
       i2c_active <= 1'b1;
     else if (stop)
       i2c_active <= 1'b0;

   assign bit_count_eq_9 = (bit_counter == 4'd9);

   // 将SCL时钟域的逻辑改为系统时钟+SCL边沿检测
   always_ff @(posedge clk, negedge rst_start_stop_n)
      if (!rst_start_stop_n)
        bit_counter <= 4'd2; // extra cycle from delayed reset
      else if (scl_posedge_tick) begin
        if ((!check_id) && (!wr_en) && (!rd_en))
          bit_counter <= 4'd0;
        else if (bit_count_eq_9)
          bit_counter <= 4'd1;
        else
          bit_counter <= bit_counter + 4'd1;
      end

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            check_id <= 1'b0;
        end else if (scl_posedge_tick) begin
            if (start) begin
                check_id <= 1'b1;
            end else if (stop || bit_count_eq_9) begin
                check_id <= 1'b0;
            end
            // 在其他情况下，check_id 保持其值
        end
    end

   // it is very important to check when the bit_counter is equal to 8!!!!
   always_ff @(posedge clk, negedge rst_start_stop_n)
     if (!rst_start_stop_n)
       valid_id <= 1'b0;
     else if (scl_posedge_tick) begin
       // <<< STEP 2: UPDATED LOGIC to compare with the input port 'slave_id' >>>
       if (check_id && (bit_counter == 4'd8) && (shift_reg[6:0] == slave_id))
         valid_id <= 1'b1;
       else
         valid_id <= 1'b0;
     end

   // Sets the write or read state flags depending on what is received during
   // the 8th data bit of the Slave ID field. Otherwise they reset if there is a NACK.
   always_ff @(posedge clk, negedge rst_start_stop_n)
      if (!rst_start_stop_n) begin
         wr_en  <= 1'b0;
         rd_en  <= 1'b0;
      end
     else if (scl_posedge_tick) begin
       if (bit_count_eq_9 && valid_id && check_id) begin
           wr_en <= ~shift_reg[0];
           rd_en <=  shift_reg[0];
       end
       else if (bit_count_eq_9 && (sda_sync == P_NACK)) begin
           wr_en  <= 1'b0;
           rd_en  <= 1'b0;
       end
     end

   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        shift_reg <= 8'b0000_0000;
      else if (scl_posedge_tick) begin
        if ((shift_reg[0] && valid_id) || (rd_en && bit_count_eq_9))
          shift_reg <= rdata;
        else
          shift_reg <= {shift_reg[6:0], sda_sync};
      end

   // Registered data out. It only outputs data whenever
   //   a) we ACK a correct Slave ID
   //   b) we ACK the receipt of a data byte
   //   b) we are in read mode and outputting data, except during the Master ACK/NACK
   always_ff @(posedge clk, negedge rst_n)
     if (!rst_n)
       sda_out <= P_NACK;
     else if (scl_negedge_tick) begin
       if ( (bit_count_eq_9  && wr_en) || valid_id)
         sda_out <= P_ACK;
       else if ((!bit_count_eq_9) && rd_en)
         sda_out <= shift_reg[7];
       else
         sda_out <= P_NACK;
     end

  // THE FOLLOWING CODE IS NOT PART OF THE I2C_SLAVE, but is custom for the regmap
  // it is convenient to put it here, it assumes a single byte address
  // auto-incrementing address for multi-byte reads and writes.

  assign wdata_ready = wr_en && bit_count_eq_9;

   // the first data in a write cycle is the address, all following is write data
   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        next_data_is_addr <= 1'b1;
      else if (scl_posedge_tick) begin
        if (start)
          next_data_is_addr <= 1'b1; // clear when start is seen
        else if (wdata_ready)
          next_data_is_addr <= 1'b0;
      end

   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        multi_cycle <= 1'b0;
      else if (scl_posedge_tick) begin
        if (start)
          multi_cycle <= 1'b0;
        else if (rd_en || (wr_en && bit_count_eq_9 && (!next_data_is_addr)))
          multi_cycle <= 1'b1;
      end

   // this pulse signals that wdata is stable
   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        wr_en_wdata <= 1'b0;
      else if (scl_posedge_tick)
        wr_en_wdata <= wdata_ready && (~next_data_is_addr);

   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        addr <= 8'd0;
      else if (scl_posedge_tick) begin
        if (wdata_ready && next_data_is_addr)
          addr <= shift_reg[7:0];
        else if ((bit_counter == 4'd8) && multi_cycle)
          addr <= addr + 'd1;
      end

   //
   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n)
        wdata <= 8'd0;
      else if (scl_posedge_tick && wdata_ready && (!next_data_is_addr))
        wdata <= shift_reg[7:0];

endmodule
