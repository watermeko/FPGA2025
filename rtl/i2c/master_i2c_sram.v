// ====================================================================
// 负责 CDC 命令解析和 I2C 读写时序
// ====================================================================
module master_i2c_sram (
    // --- 指令接口 ---
    input  wire         clk,
    input  wire         rst_n,
    input  wire [7:0]   cmd_type,
    input  wire [15:0]  cmd_length,
    input  wire [7:0]   cmd_data,
    input  wire [15:0]  cmd_data_index,
    input  wire         cmd_start,
    input  wire         cmd_data_valid,
    input  wire         cmd_done,
    output wire         cmd_ready,

    // --- 数据上传接口 ---
    output reg          upload_req,
    output reg  [7:0]   upload_data,
    output reg  [7:0]   upload_source,
    output reg          upload_valid,
    input  wire         upload_ready,
    
    // --- SRAM 接口 输出 (I2C_MASTER 的输入) ---
    output reg   I_TX_EN,
    output reg  [2:0] I_WADDR,
    output reg  [7:0] I_WDATA,
    output reg   I_RX_EN,
    output reg  [2:0] I_RADDR,
    input wire [7:0] O_RDATA,
    input wire ERROR_FLAG,       // 错误标志 (未使用，保留)
    input wire INTERRUPT,        // 中断信号 (未使用，保留)
    input wire CSTATE_FLAG       // 状态标志 (未使用，保留)
);

    // --- CDC 协议指令定义 ---
    localparam CMD_I2C_WRITE = 8'h05; 
    localparam CMD_I2C_READ  = 8'h06; 

    // --- 数据源标识 ---
    localparam UPLOAD_SOURCE_I2C = 8'h02;

    // --- I2C Master 寄存器地址 ---
    localparam ADDR_PRESCALE_LO  = 3'h0;
    localparam ADDR_PRESCALE_HI  = 3'h1; 
    localparam ADDR_CTRL         = 3'h2; 
    localparam ADDR_TX           = 3'h3; 
    localparam ADDR_RX           = 3'h3; 
    localparam ADDR_CMD          = 3'h4; 
    localparam ADDR_STATUS       = 3'h4; 

    // --- I2C Master 指令寄存器位定义  ---
    localparam CMD_STA   = 8'h80; 
    localparam CMD_STO   = 8'h40; 
    localparam CMD_RD    = 8'h20; 
    localparam CMD_WR    = 8'h10; 
    localparam CMD_ACK   = 8'h08; 
    localparam CMD_IACK  = 8'h01; 

    // --- I2C Master 状态寄存器位定义 ---
    localparam STATUS_TIP = 1; 

    // --- 状态机定义 ---
    localparam S_IDLE              = 5'd0;
    localparam S_RX_PAYLOAD        = 5'd1;
    localparam S_INIT_PRESACLE_HI  = 5'd2; 
    localparam S_INIT_PRESACLE_LO  = 5'd3; 
    localparam S_INIT_ENABLE       = 5'd4;
    localparam S_WRITE_START       = 5'd5;
    localparam S_WRITE_ADDR        = 5'd6;
    localparam S_WRITE_DATA        = 5'd7;
    localparam S_WRITE_STOP        = 5'd8;
    localparam S_READ_START        = 5'd9;
    localparam S_READ_ADDR         = 5'd10;
    localparam S_READ_RSTART       = 5'd11;
    localparam S_READ_CMD          = 5'd12;
    localparam S_READ_FETCH        = 5'd13; 
    localparam S_READ_STOP         = 5'd14; 
    localparam S_READ_FETCH_CMD    = 5'd15; 
    localparam S_READ_FETCH_DATA   = 5'd16; 
    localparam S_POLL_TIP          = 5'd17;
    localparam S_UPLOAD_DATA       = 5'd18;

    reg [4:0] state, next_state;

    // --- 内部寄存器和数据缓冲区 ---
    reg [6:0] i2c_device_addr;
    reg [7:0] i2c_reg_addr;
    
    // 【新增】用于在组合逻辑中计算下一时钟周期的 I2C 地址
    reg [6:0] next_i2c_device_addr;
    reg [7:0] next_i2c_reg_addr;
    
    // 【修正 EX3791】: 扩展位宽到 17 位 [16:0] 以避免截断警告
    reg [16:0] op_len;
    reg [16:0] data_ptr; 
    reg [16:0] next_data_ptr; 
    
    // 【新增】用于同步写入读写数据缓冲区的控制信号
    reg write_data_wren;
    reg [7:0] write_data_wdata;
    reg [15:0] write_data_waddr;
    
    reg read_data_wren;
    reg [7:0] read_data_wdata;
    reg [16:0] read_data_waddr; // 使用 17 位地址

    reg [7:0] read_data_buffer[0:255];
    reg [7:0] write_data_buffer[0:255];

    assign cmd_ready = (state == S_IDLE);

    // --- 时序逻辑 1: 状态机、计数器和配置寄存器更新 (解决 EX2420) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            data_ptr <= 17'd0;
            op_len <= 17'd0;
            // 初始化配置寄存器
            i2c_device_addr <= 7'd0;
            i2c_reg_addr <= 8'd0;
        end else begin
            state <= next_state;
            data_ptr <= next_data_ptr;
            // 同步更新配置寄存器
            i2c_device_addr <= next_i2c_device_addr;
            i2c_reg_addr <= next_i2c_reg_addr;

            // 只有在 S_IDLE 收到 cmd_start 时更新 op_len
            if (state == S_IDLE && cmd_start) begin
                op_len <= {1'b0, cmd_length}; // 扩展 cmd_length 到 17 位
            end
        end
    end

    // --- 时序逻辑 2: 数据缓冲区写入 ---
    always @(posedge clk) begin
        // 写入写数据缓冲区
        if (write_data_wren) begin
            write_data_buffer[write_data_waddr] <= write_data_wdata;
        end
        // 写入读数据缓冲区
        if (read_data_wren) begin
            read_data_buffer[read_data_waddr[7:0]] <= read_data_wdata; // 256 size buffer only needs 8 bits
        end
    end
    
    // --- 组合逻辑: 状态机 + SRAM接口驱动 ---
    always @(*) begin
        // 默认值
        next_state      = state;
        I_TX_EN         = 1'b0;
        I_WADDR         = 3'b0;
        I_WDATA         = 8'h0;
        I_RX_EN         = 1'b0;
        I_RADDR         = 3'b0;
        upload_req      = 1'b0;
        upload_valid    = 1'b0;
        upload_data     = 8'h00;
        upload_source   = UPLOAD_SOURCE_I2C;
        
        // 【修正 EX2664】: 为 next_data_ptr 设置默认值 (防止锁存器)
        next_data_ptr = data_ptr; 

        // 【新增】: 异步地址寄存器 next 默认值 (默认保持不变)
        next_i2c_device_addr = i2c_device_addr;
        next_i2c_reg_addr = i2c_reg_addr;

        // 【新增】: 存储器写入控制信号默认值
        write_data_wren  = 1'b0;
        write_data_wdata = 8'h0;
        write_data_waddr = 16'd0;
        
        read_data_wren   = 1'b0;
        read_data_wdata  = 8'h0;
        read_data_waddr  = 17'd0; // 17位

        case (state)
            S_IDLE: begin
                if (cmd_start) begin
                    next_data_ptr = 17'd0; 
                    // op_len 在时序逻辑中更新
                    next_state <= S_INIT_PRESACLE_HI; 
                end
            end

            // 1. 接收命令数据 (I2C地址, 寄存器地址, 写入数据)
            S_RX_PAYLOAD: begin
                if (cmd_data_valid) begin
                    // FIX: 改为对 next_ 信号进行组合赋值，避免锁存器
                    if(cmd_data_index == 0) next_i2c_device_addr = cmd_data[6:0];
                    else if(cmd_data_index == 1) next_i2c_reg_addr = cmd_data;
                    else if (cmd_type == CMD_I2C_WRITE) begin
                        // 设置写入控制信号，在时序逻辑中完成写入
                        write_data_wren = 1'b1;
                        write_data_wdata = cmd_data;
                        write_data_waddr = cmd_data_index - 16'd2; // cmd_data_index 是 16 位
                    end
                end
                if (cmd_done) begin
                    next_state <= S_INIT_PRESACLE_LO; 
                end
            end

            // 2. I2C 初始化流程: 设置时钟预分频高8位
            S_INIT_PRESACLE_HI: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_PRESCALE_HI;
                I_WDATA <= 8'd0; 
                next_state <= S_RX_PAYLOAD;
            end
            
            // 3. I2C 初始化流程: 设置时钟预分频低8位
            S_INIT_PRESACLE_LO: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_PRESCALE_LO;
                I_WDATA <= 8'd99; 
                next_state <= S_INIT_ENABLE;
            end
            
            // 4. I2C 初始化流程: 使能模块
            S_INIT_ENABLE: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_CTRL;
                I_WDATA <= 8'h80; 
                if (cmd_type == CMD_I2C_WRITE) next_state <= S_WRITE_START;
                else next_state <= S_READ_START;
            end

            // --- 写流程 ---

            // 5. 写: 发送 Start 信号前的准备 (从机地址+W)
            S_WRITE_START: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_TX;
                I_WDATA <= {i2c_device_addr, 1'b0}; 
                next_state <= S_WRITE_ADDR;
            end
            
            // 6. 写: 发送 Start 命令
            S_WRITE_ADDR: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_CMD;
                I_WDATA <= CMD_STA | CMD_WR; 
                next_state <= S_POLL_TIP;
            end
            
            // 7. 写: 发送数据 (寄存器地址 + Payload)
            S_WRITE_DATA: begin
                if (data_ptr < op_len - 1) begin 
                    I_TX_EN <= 1'b1;
                    I_WADDR <= ADDR_TX;
                    
                    if(data_ptr == 17'd0) begin 
                        I_WDATA <= i2c_reg_addr;
                    end else begin 
                        // data_ptr-1 至少为 16 位，这里直接用 [7:0] 地址访问 256 大小的数组是安全的
                        I_WDATA <= write_data_buffer[data_ptr[7:0] - 17'd1]; 
                    end
                    // 【修正 EX3791】: next_data_ptr 是 17 位，加法安全
                    next_data_ptr = data_ptr + 17'd1;
                    next_state <= S_WRITE_STOP; 
                end else begin
                    next_state <= S_IDLE; 
                end
            end
            
            // 8. 写: 发送 Write 命令 (可能带 Stop)
            S_WRITE_STOP: begin
                     I_TX_EN <= 1'b1;
                     I_WADDR <= ADDR_CMD;
                     // 如果是最后一个字节 (data_ptr == op_len-1)，则发送 Stop
                     if (data_ptr == op_len - 1) begin
                         I_WDATA <= CMD_WR | CMD_STO;
                     end else begin
                         I_WDATA <= CMD_WR; 
                     end
                     next_state <= S_POLL_TIP;
            end
            
            // --- 读流程 (阶段一：写寄存器地址) ---

            // 9. 读: 阶段一 Start 信号准备 (从机地址+W)
            S_READ_START: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_TX;
                I_WDATA <= {i2c_device_addr, 1'b0}; 
                next_state <= S_READ_ADDR;
            end
            
            // 10. 读: 阶段一 发送 Start 命令
            S_READ_ADDR: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_CMD;
                I_WDATA <= CMD_STA | CMD_WR; 
                next_state <= S_POLL_TIP;
            end

            // 11. 读: 阶段一 (TIP 轮询后) 发送要读取的寄存器地址
            S_READ_RSTART: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_TX;
                I_WDATA <= i2c_reg_addr; 
                next_state <= S_READ_CMD;
            end

            // 12. 读: 阶段一 发送 Write 命令
            S_READ_CMD: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_CMD;
                I_WDATA <= CMD_WR; 
                next_state <= S_POLL_TIP;
            end
            
            // 13. 读: 阶段二 Start 信号准备 (从机地址+R)
            S_READ_FETCH: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_TX;
                I_WDATA <= {i2c_device_addr, 1'b1}; 
                next_state <= S_READ_STOP;
            end
            
            // 14. 读: 阶段二 发送 Repeated Start 命令
            S_READ_STOP: begin
                I_TX_EN <= 1'b1;
                I_WADDR <= ADDR_CMD;
                I_WDATA <= CMD_STA | CMD_WR; 
                next_state <= S_POLL_TIP;
            end

            // 15. 读: 阶段二 (TIP 轮询后) 循环发送 Read 命令
            S_READ_FETCH_CMD: begin
                // op_len-2 是要读取的字节数 (op_len 17位)
                if (data_ptr < op_len - 17'd2) begin 
                    I_TX_EN <= 1'b1;
                    I_WADDR <= ADDR_CMD;
                    
                    // 读取最后一个字节时，发送 NACK + STOP
                    if (data_ptr == op_len - 17'd3) begin
                        I_WDATA <= CMD_RD | CMD_STO; // ACK=0 NACK, 包含 STOP
                    end else begin
                        I_WDATA <= CMD_RD | CMD_ACK; // ACK=1 ACK
                    end
                    
                    next_state <= S_POLL_TIP;
                end else begin
                    // 重置指针准备上传
                    next_data_ptr = 17'd0; 
                    next_state <= S_UPLOAD_DATA;
                end
            end
            
            // 16. 读: 阶段二 接收数据 (在 S_POLL_TIP 结束后跳转)
            S_READ_FETCH_DATA: begin
                I_RX_EN <= 1'b1;
                I_RADDR <= ADDR_RX;
                
                // 设置写入控制信号，在时序逻辑中完成写入
                read_data_wren = 1'b1;
                read_data_wdata = O_RDATA;
                read_data_waddr = data_ptr;
                
                // 【修正 EX3791】: next_data_ptr 是 17 位，加法安全
                next_data_ptr = data_ptr + 17'd1;
                next_state <= S_READ_FETCH_CMD;
            end

            // 17. 通用状态：轮询 TIP 位，等待传输完成
            S_POLL_TIP: begin
                I_RX_EN <= 1'b1;
                I_RADDR <= ADDR_STATUS;
                if (~O_RDATA[STATUS_TIP]) begin // TIP位为0表示传输结束
                    case(state)
                        S_WRITE_ADDR     : next_state <= S_WRITE_DATA;
                        S_WRITE_STOP     : next_state <= S_WRITE_DATA;
                        S_READ_ADDR      : next_state <= S_READ_RSTART;
                        S_READ_CMD       : next_state <= S_READ_FETCH;
                        S_READ_STOP      : next_state <= S_READ_FETCH_CMD;
                        S_READ_FETCH_CMD : next_state <= S_READ_FETCH_DATA;
                    endcase
                end
            end

            // --- 上传数据 ---
            S_UPLOAD_DATA: begin
                if (upload_ready) begin
                    // op_len-2 是要上传的数据总数 (17位)
                    if (data_ptr < op_len - 17'd2) begin 
                        upload_req <= 1'b1;
                        upload_valid <= 1'b1;
                        upload_data <= read_data_buffer[data_ptr[7:0]];
                        // 【修正 EX3791】: next_data_ptr 是 17 位，加法安全
                        next_data_ptr = data_ptr + 17'd1;
                    end else begin
                        upload_req <= 1'b0; 
                        upload_valid <= 1'b0;
                        next_state <= S_IDLE; 
                    end
                end
            end
        endcase
    end
endmodule
