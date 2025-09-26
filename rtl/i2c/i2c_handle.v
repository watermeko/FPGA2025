// `timescale 1ns/1ps

// module i2c_handler (
//     // --- 指令接口 (与 uart_handler 类似) ---
//     input  wire        clk,
//     input  wire        rst_n,
//     input  wire [7:0]  cmd_type,
//     input  wire [15:0] cmd_length,
//     input  wire [7:0]  cmd_data,
//     input  wire [15:0] cmd_data_index,
//     input  wire        cmd_start,
//     input  wire        cmd_data_valid,
//     input  wire        cmd_done,
//     output wire        cmd_ready,

//     // --- I2C 物理接口 ---
//     inout  wire        scl,
//     inout  wire        sda,

//     // --- 数据上传接口 (与 uart_handler 类似) ---
//     output reg         upload_req,
//     output reg  [7:0]  upload_data,
//     output reg  [7:0]  upload_source,
//     output reg         upload_valid,
//     input  wire        upload_ready
// );

//     localparam CMD_I2C_WRITE = 8'h05; // 对应 CDC 协议的 I2C发送
//     localparam CMD_I2C_READ  = 8'h06; // 对应 CDC 协议的 I2C接收

//     // --- 数据源标识 ---
//     localparam UPLOAD_SOURCE_I2C = 8'h02;

//     // --- I2C Master 寄存器地址
//     localparam ADDR_PRESCALE_LO  = 8'h00; // 时钟预分频寄存器 低8位 [cite: 224]
//     localparam ADDR_PRESCALE_HI  = 8'h01; // 时钟预分频寄存器 高8位 [cite: 224]
//     localparam ADDR_CTRL         = 8'h02; // 控制寄存器 [cite: 224]
//     localparam ADDR_TX           = 8'h03; // 发送寄存器 (写) [cite: 224]
//     localparam ADDR_RX           = 8'h03; // 接收寄存器 (读) [cite: 224]
//     localparam ADDR_CMD          = 8'h04; // 指令寄存器 (写) [cite: 224]
//     localparam ADDR_STATUS       = 8'h04; // 状态寄存器 (读) [cite: 224]

//     // --- I2C Master 指令寄存器位定义  ---
//     localparam CMD_STA  = 8'h80; // (重复)开始 START [cite: 230]
//     localparam CMD_STO  = 8'h40; // 停止 STOP [cite: 230]
//     localparam CMD_RD   = 8'h20; // 读 READ [cite: 230]
//     localparam CMD_WR   = 8'h10; // 写 WRITE [cite: 230]
//     localparam CMD_ACK  = 8'h08; // 应答 ACK [cite: 230]
//     localparam CMD_IACK = 8'h01; // 中断应答 [cite: 230]

//     // --- I2C Master 状态寄存器位定义 ---
//     localparam STATUS_TIP = 1; // 传输进行标识位 [cite: 229]

//     // --- 状态机定义 ---
//     localparam S_IDLE              = 5'd0;
//     localparam S_RX_PAYLOAD        = 5'd1;
//     localparam S_INIT_PRESACLE     = 5'd2;
//     localparam S_INIT_ENABLE       = 5'd3;
//     localparam S_WRITE_START       = 5'd4;
//     localparam S_WRITE_ADDR        = 5'd5;
//     localparam S_WRITE_DATA        = 5'd6;
//     localparam S_WRITE_STOP        = 5'd7;
//     localparam S_READ_START        = 5'd8;
//     localparam S_READ_ADDR         = 5'd9;
//     localparam S_READ_RSTART       = 5'd10;
//     localparam S_READ_CMD          = 5'd11;
//     localparam S_READ_FETCH        = 5'd12;
//     localparam S_READ_STOP         = 5'd13;
//     localparam S_POLL_TIP          = 5'd14;
//     localparam S_UPLOAD_DATA       = 5'd15;

//     reg [4:0] state, next_state;

//     // --- I2C Master IP 核 SRAM 接口信号 ---
//     reg  i2c_tx_en;
//     reg  [2:0] i2c_waddr;
//     reg  [7:0] i2c_wdata;
//     reg  i2c_rx_en;
//     reg  [2:0] i2c_raddr;
//     wire [7:0] i2c_rdata;
//     wire i2c_error_flag;
//     wire i2c_interrupt;

//     // --- 内部寄存器和数据缓冲区 ---
//     reg [6:0] i2c_device_addr;
//     reg [7:0] i2c_reg_addr;
//     reg [15:0] op_len;
//     reg [15:0] data_ptr;
//     reg [7:0] read_data_buffer[0:255];
//     reg [7:0] write_data_buffer[0:255];

//     assign cmd_ready = (state == S_IDLE);

//     // --- 时序逻辑 ---
//     always @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             state <= S_IDLE;
//         end else begin
//             state <= next_state;
//         end
//     end

//     // --- 组合逻辑: 状态机 + SRAM接口驱动 ---
//     always @(*) begin
//         // 默认值
//         next_state    = state;
//         i2c_tx_en     = 1'b0;
//         i2c_waddr     = 3'b0;
//         i2c_wdata     = 8'h0;
//         i2c_rx_en     = 1'b0;
//         i2c_raddr     = 3'b0;
//         upload_req    = 1'b0;
//         upload_valid  = 1'b0;
//         upload_data   = 8'h00;
//         upload_source = UPLOAD_SOURCE_I2C;

//         case (state)
//             S_IDLE: begin
//                 if (cmd_start) begin
//                     data_ptr <= 0;
//                     op_len <= cmd_length;
//                     next_state <= S_RX_PAYLOAD;
//                 end
//             end

//             S_RX_PAYLOAD: begin
//                 if (cmd_data_valid) begin
//                     if(cmd_data_index == 0) i2c_device_addr <= cmd_data[6:0];
//                     else if(cmd_data_index == 1) i2c_reg_addr <= cmd_data;
//                     else if (cmd_type == CMD_I2C_WRITE) write_data_buffer[cmd_data_index-2] <= cmd_data;
//                 end
//                 if (cmd_done) begin
//                     next_state <= S_INIT_PRESACLE;
//                 end
//             end

//             // I2C 初始化流程: 设置时钟并使能模块
//             S_INIT_PRESACLE: begin
//                 // SCL = clk / (5 * (prescale+1))
//                 // clk=50MHz, SCL=100kHz
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_PRESCALE_LO;
//                 i2c_wdata <= 8'd99; // Prescale value low byte: 99 (0x63)
//                 // Hi byte is 0 (0x00), 99 < 256
//                 next_state <= S_INIT_ENABLE;
//             end
            
//             S_INIT_ENABLE: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_CTRL;
//                 i2c_wdata <= 8'h80; // 使能 I2C Master, 不使能中断 [cite: 226, 231]
//                 if (cmd_type == CMD_I2C_WRITE) next_state <= S_WRITE_START;
//                 else next_state <= S_READ_START;
//             end

//             // --- 写流程 ---

//             S_WRITE_START: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_TX;
//                 i2c_wdata <= {i2c_device_addr, 1'b0}; // 发送从机地址 + 写位'0' [cite: 227, 231]
//                 next_state <= S_WRITE_ADDR;
//             end
            
//             S_WRITE_ADDR: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_CMD;
//                 i2c_wdata <= CMD_STA | CMD_WR; // 产生Start信号并发送 
//                 next_state <= S_POLL_TIP;
//             end
            
//             S_WRITE_DATA: begin
//                 if (data_ptr < op_len - 2) begin // 检查是否还有数据要写
//                     i2c_tx_en <= 1'b1;
//                     if(data_ptr == 0) begin // 第一次写数据是寄存器地址
//                          i2c_waddr <= ADDR_TX;
//                          i2c_wdata <= i2c_reg_addr;
//                     end else begin
//                          i2c_waddr <= ADDR_TX;
//                          i2c_wdata <= write_data_buffer[data_ptr-1];
//                     end
//                     data_ptr <= data_ptr + 1;
//                     next_state <= S_WRITE_STOP;
//                 end else begin
//                     next_state <= S_IDLE; // 所有数据发送完毕
//                 end
//             end
            
//             S_WRITE_STOP: begin
//                  i2c_tx_en <= 1'b1;
//                  i2c_waddr <= ADDR_CMD;
//                  // 如果是最后一个字节，则发送数据后跟一个Stop信号
//                  if (data_ptr == op_len - 2) begin
//                     i2c_wdata <= CMD_WR | CMD_STO;// [cite: 231]
//                  end else begin
//                     i2c_wdata <= CMD_WR; // 仅发送数据
//                  end
//                  next_state <= S_POLL_TIP;
//             end
            
//             // --- 读流程 ---

//             // 读操作第一步: 用写操作发送要读取的寄存器地址
//             S_READ_START: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_TX;
//                 i2c_wdata <= {i2c_device_addr, 1'b0}; // 发送从机地址 + 写位'0' 
//                 next_state <= S_READ_ADDR;
//             end
            
//             S_READ_ADDR: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_CMD;
//                 i2c_wdata <= CMD_STA | CMD_WR; // Start + Write
//                 next_state <= S_POLL_TIP;
//             end

//             // 发送完寄存器地址后，重新开始，切换为读模式
//             S_READ_RSTART: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_TX;
//                 i2c_wdata <= {i2c_device_addr, 1'b1}; // 发送从机地址 + 读位'1' [cite: 227, 232]
//                 next_state <= S_READ_CMD;
//             end

//             S_READ_CMD: begin
//                 i2c_tx_en <= 1'b1;
//                 i2c_waddr <= ADDR_CMD;
//                 i2c_wdata <= CMD_STA | CMD_WR; // Repeated Start + Write 
//                 next_state <= S_POLL_TIP;
//             end

//             S_READ_FETCH: begin
//                 if (data_ptr < op_len - 2) begin // op_len-2 是要读取的字节数
//                     i2c_tx_en <= 1'b1;
//                     i2c_waddr <= ADDR_CMD;
//                     // 读取最后一个字节时，ACK=0 (NACK), 并发送STO
//                     if (data_ptr == op_len - 3) begin
//                         i2c_wdata <= CMD_RD | CMD_STO; // NACK is implicit when ACK bit is 0 [cite: 233]
//                     end else begin
//                         i2c_wdata <= CMD_RD | CMD_ACK;// [cite: 232]
//                     end
//                     next_state <= S_POLL_TIP;
//                 end else begin
//                     data_ptr <= 0; // 重置指针准备上传
//                     next_state <= S_UPLOAD_DATA;
//                 end
//             end
            
//             S_READ_STOP: begin
//                 i2c_rx_en <= 1'b1;
//                 i2c_raddr <= ADDR_RX;
//                 read_data_buffer[data_ptr] <= i2c_rdata;
//                 data_ptr <= data_ptr + 1;
//                 next_state <= S_READ_FETCH;
//             end

//             // 通用状态：轮询TIP位，等待传输完成
//             S_POLL_TIP: begin
//                 i2c_rx_en <= 1'b1;
//                 i2c_raddr <= ADDR_STATUS;
//                 if (~i2c_rdata[STATUS_TIP]) begin // TIP位为0表示传输结束 [cite: 229]
//                     case(state)
//                         S_WRITE_ADDR  : next_state <= S_WRITE_DATA;
//                         S_WRITE_STOP  : next_state <= S_WRITE_DATA;
//                         S_READ_ADDR   : next_state <= S_READ_RSTART;
//                         S_READ_CMD    : next_state <= S_READ_FETCH;
//                         S_READ_FETCH  : next_state <= S_READ_STOP;
//                     endcase
//                 end
//             end

//             // --- 上传数据 ---
//             S_UPLOAD_DATA: begin
//                 if (upload_ready) begin
//                     if (data_ptr < op_len - 2) begin
//                         upload_req <= 1'b1;
//                         upload_valid <= 1'b1;
//                         upload_data <= read_data_buffer[data_ptr];
//                         data_ptr <= data_ptr + 1;
//                     end else begin
//                         next_state <= S_IDLE; // 上传完毕
//                     end
//                 end
//             end
//         endcase
//     end

//     // --- 实例化 Gowin I2C IP 核的顶层模块 ---
//     I2C u_i2c (
//         .clk        (clk),   // 假设系统时钟满足IP核要求或已做适配
//         .rst_n      (rst_n),
//         .key2       (1'b0),  // 不再使用key2触发，改为SRAM接口控制

//         // I2C 物理总线
//         .scl        (scl),
//         .sda        (sda),

//         // 状态与中断信号
//         .scl_pull   (),
//         .sda_pull   (),
//         .error_flag (i2c_error_flag),
//         .interrupt  (i2c_interrupt),
//         .cstate_flag()
//     );

// endmodule