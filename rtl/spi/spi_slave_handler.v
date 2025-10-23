`timescale 1ns / 1ps

//==============================================================================
// SPI Slave Handler Module
//==============================================================================
// 功能：SPI从机Handler，对接命令处理器
// 特性：
//   - 作为SPI从机接收主机数据
//   - 根据命令配置发送缓冲区
//   - 自动上传接收到的数据
//   - 支持连续传输（主机控制CS）
//
// 功能码：
//   0x14: 配置从机发送缓冲区（主机将读取的数据）
//   0x15: 启用/禁用从机接收数据上传
//
// 数据上传源标识：0x14
//==============================================================================

module spi_slave_handler (
    input clk,
    input rst_n,

    // 命令总线接口
    input [7:0]  cmd_type,
    input [15:0] cmd_length,
    input [7:0]  cmd_data,
    input [15:0] cmd_data_index,
    input        cmd_start,
    input        cmd_data_valid,
    input        cmd_done,
    output reg   cmd_ready,

    // SPI从机物理接口
    input        spi_clk,
    input        spi_cs_n,
    input        spi_mosi,
    output       spi_miso,

    // 上传接口（仿照uart_handler/spi_handler）
    output wire  upload_active,
    output reg   upload_req,
    output reg [7:0] upload_data,
    output reg [7:0] upload_source,
    output reg   upload_valid,
    input        upload_ready
);

    //==========================================================================
    // 参数定义
    //==========================================================================
    parameter CMD_SPI_SLAVE_WRITE = 8'h14;  // 配置从机发送缓冲区
    parameter CMD_SPI_SLAVE_CTRL  = 8'h15;  // 控制从机上传使能

    localparam BUFFER_SIZE = 256;  // 发送和接收缓冲区大小

    //==========================================================================
    // 内部寄存器和信号
    //==========================================================================
    // 缓冲区
    reg [7:0] tx_buffer [0:BUFFER_SIZE-1];  // 从机发送缓冲（主机读取）
    reg [7:0] rx_buffer [0:BUFFER_SIZE-1];  // 从机接收缓冲（主机写入）

    // 缓冲区控制
    reg [7:0] tx_write_ptr;     // 命令写入tx_buffer的指针
    reg [7:0] tx_read_ptr;      // SPI读取tx_buffer的指针
    reg [7:0] tx_buffer_len;    // tx_buffer有效数据长度
    reg       tx_buffer_ready;  // tx_buffer已准备好
    reg       tx_buffer_reset;  // tx_buffer重置请求标志

    reg [7:0] rx_write_ptr;     // SPI写入rx_buffer的指针
    reg [7:0] rx_read_ptr;      // 上传读取rx_buffer的指针
    reg       rx_upload_enable; // 接收数据上传使能

    // 主状态机
    reg [2:0] state;
    parameter IDLE             = 3'd0;
    parameter WAIT_ALL_DATA    = 3'd1;
    parameter UPDATE_TX_BUFFER = 3'd2;

    // 上传状态机
    reg [1:0] upload_state;
    parameter UP_IDLE = 2'd0;
    parameter UP_SEND = 2'd1;
    parameter UP_WAIT = 2'd2;

    // SPI从机接口信号
    wire [7:0] spi_rx_byte;
    wire       spi_byte_received;
    wire       spi_req_next_byte;
    reg  [7:0] spi_tx_byte;
    reg        spi_tx_ready;

    // Upload active: 当有数据待上传时激活
    wire has_data_to_upload = (rx_write_ptr != rx_read_ptr);
    assign upload_active = rx_upload_enable & has_data_to_upload;

    //==========================================================================
    // 调试输出
    //==========================================================================
    reg [2:0] prev_state;
    initial prev_state = 0;
    always @(posedge clk) begin
        if (state != prev_state) begin
            $display("[%0t] SPI_SLAVE_HANDLER: State %d -> %d", $time, prev_state, state);
            prev_state <= state;
        end
    end

    //==========================================================================
    // 主状态机：处理命令
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready        <= 1'b1;
            state            <= IDLE;
            tx_write_ptr     <= 8'd0;
            tx_buffer_len    <= 8'd0;
            tx_buffer_ready  <= 1'b0;
            tx_buffer_reset  <= 1'b0;
            rx_upload_enable <= 1'b0;
        end else begin
            // 清除reset标志（自动清除，持续一个周期）
            tx_buffer_reset <= 1'b0;

            // cmd_ready控制
            if (state == IDLE || state == WAIT_ALL_DATA) begin
                cmd_ready <= 1'b1;
            end else begin
                cmd_ready <= 1'b0;
            end

            case (state)
                //--------------------------------------------------------------
                // IDLE: 等待命令
                //--------------------------------------------------------------
                IDLE: begin
                    if (cmd_start) begin
                        case (cmd_type)
                            // 0x12: 配置从机发送缓冲区
                            CMD_SPI_SLAVE_WRITE: begin
                                if (cmd_length > 0 && cmd_length <= BUFFER_SIZE) begin
                                    tx_write_ptr <= 8'd0;
                                    tx_buffer_len <= cmd_length[7:0];
                                    tx_buffer_ready <= 1'b0;
                                    state <= WAIT_ALL_DATA;
                                    $display("[%0t] SPI_SLAVE: Config TX buffer, length=%0d",
                                             $time, cmd_length);
                                end else begin
                                    $display("[%0t] SPI_SLAVE ERROR: Invalid length=%0d",
                                             $time, cmd_length);
                                end
                            end

                            // 0x13: 控制上传使能
                            CMD_SPI_SLAVE_CTRL: begin
                                if (cmd_length >= 1) begin
                                    state <= WAIT_ALL_DATA;
                                    $display("[%0t] SPI_SLAVE: Control command received", $time);
                                end
                            end

                            default: begin
                                // 不是本模块的命令，保持IDLE
                            end
                        endcase
                    end
                end

                //--------------------------------------------------------------
                // WAIT_ALL_DATA: 接收命令数据
                //--------------------------------------------------------------
                WAIT_ALL_DATA: begin
                    if (cmd_data_valid) begin
                        case (cmd_type)
                            CMD_SPI_SLAVE_WRITE: begin
                                if (cmd_data_index < BUFFER_SIZE) begin
                                    tx_buffer[cmd_data_index] <= cmd_data;
                                    $display("[%0t] SPI_SLAVE: TX buf[%0d]=0x%02x",
                                             $time, cmd_data_index, cmd_data);
                                end
                            end

                            CMD_SPI_SLAVE_CTRL: begin
                                if (cmd_data_index == 0) begin
                                    rx_upload_enable <= cmd_data[0];
                                    $display("[%0t] SPI_SLAVE: Upload enable=%0d",
                                             $time, cmd_data[0]);
                                end
                            end
                        endcase
                    end

                    if (cmd_done) begin
                        $display("[%0t] SPI_SLAVE: cmd_done, processing...", $time);
                        if (cmd_type == CMD_SPI_SLAVE_WRITE) begin
                            state <= UPDATE_TX_BUFFER;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                //--------------------------------------------------------------
                // UPDATE_TX_BUFFER: 更新发送缓冲区并返回IDLE
                //--------------------------------------------------------------
                UPDATE_TX_BUFFER: begin
                    tx_buffer_ready <= 1'b1;
                    tx_buffer_reset <= 1'b1;  // 请求重置读指针
                    $display("[%0t] SPI_SLAVE: TX buffer ready, len=%0d",
                             $time, tx_buffer_len);
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    //==========================================================================
    // SPI从机数据准备
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_tx_byte  <= 8'hFF;
            spi_tx_ready <= 1'b0;
            tx_read_ptr  <= 8'd0;
        end else begin
            // 响应主状态机的reset请求
            if (tx_buffer_reset) begin
                tx_read_ptr <= 8'd0;
                // 同时准备第一个字节（不递增指针，由CS下降沿触发）
                if (tx_buffer_ready && tx_buffer_len > 0) begin
                    spi_tx_byte  <= tx_buffer[8'd0];
                    spi_tx_ready <= 1'b1;
                    $display("[%0t] SPI_SLAVE_TX: RESET - Prepared first byte=0x%02x, len=%0d",
                             $time, tx_buffer[8'd0], tx_buffer_len);
                end else begin
                    spi_tx_byte  <= 8'hFF;
                    spi_tx_ready <= 1'b1;
                    $display("[%0t] SPI_SLAVE_TX: RESET - No data, sending 0xFF", $time);
                end
            end
            // SPI传输逻辑
            else if (spi_req_next_byte) begin
                // 请求下一个发送字节
                if (tx_buffer_ready && tx_read_ptr < tx_buffer_len) begin
                    spi_tx_byte  <= tx_buffer[tx_read_ptr];
                    spi_tx_ready <= 1'b1;
                    tx_read_ptr  <= tx_read_ptr + 1;
                    $display("[%0t] SPI_SLAVE_TX: REQ_NEXT - Sending buf[%0d]=0x%02x, next_ptr=%0d",
                             $time, tx_read_ptr, tx_buffer[tx_read_ptr], tx_read_ptr + 1);
                end else begin
                    // 没有数据，发送默认值0xFF
                    spi_tx_byte  <= 8'hFF;
                    spi_tx_ready <= 1'b1;
                    $display("[%0t] SPI_SLAVE_TX: REQ_NEXT - No more data (ptr=%0d, len=%0d), sending 0xFF",
                             $time, tx_read_ptr, tx_buffer_len);
                end
            end else if (~spi_cs_n && ~spi_tx_ready) begin
                // CS刚拉低，准备一个字节（可能是第一个或下一个）
                if (tx_buffer_ready && tx_read_ptr < tx_buffer_len) begin
                    spi_tx_byte  <= tx_buffer[tx_read_ptr];
                    spi_tx_ready <= 1'b1;
                    $display("[%0t] SPI_SLAVE_TX: CS_LOW - Preparing buf[%0d]=0x%02x",
                             $time, tx_read_ptr, tx_buffer[tx_read_ptr]);
                end else begin
                    spi_tx_byte  <= 8'hFF;
                    spi_tx_ready <= 1'b1;
                    $display("[%0t] SPI_SLAVE_TX: CS_LOW - No data (ptr=%0d, len=%0d), sending 0xFF",
                             $time, tx_read_ptr, tx_buffer_len);
                end
            end else if (spi_cs_n) begin
                // CS拉高，清除tx_ready标志（但不重置tx_read_ptr）
                spi_tx_ready <= 1'b0;
                $display("[%0t] SPI_SLAVE_TX: CS_HIGH - Clear tx_ready, ptr=%0d", $time, tx_read_ptr);
            end
            // 否则保持spi_tx_byte和spi_tx_ready不变（锁存）
        end
    end

    //==========================================================================
    // SPI从机数据接收
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_write_ptr <= 8'd0;
        end else begin
            if (spi_byte_received) begin
                // 接收到一个字节，存入rx_buffer
                rx_buffer[rx_write_ptr] <= spi_rx_byte;
                rx_write_ptr <= rx_write_ptr + 1;
                $display("[%0t] SPI_SLAVE: RX byte[%0d]=0x%02x",
                         $time, rx_write_ptr, spi_rx_byte);
            end

            // CS拉高后重置写指针（可选，根据应用需求）
            // if (spi_cs_n) begin
            //     rx_write_ptr <= 8'd0;
            // end
        end
    end

    //==========================================================================
    // 上传状态机：将接收数据上传到USB
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            upload_state  <= UP_IDLE;
            upload_req    <= 1'b0;
            upload_data   <= 8'h00;
            upload_source <= 8'h14;  // SPI从机源标识
            upload_valid  <= 1'b0;
            rx_read_ptr   <= 8'd0;
        end else begin
            case (upload_state)
                //--------------------------------------------------------------
                // UP_IDLE: 检查是否有数据待上传
                //--------------------------------------------------------------
                UP_IDLE: begin
                    if (rx_upload_enable && has_data_to_upload && upload_ready) begin
                        upload_req    <= 1'b1;
                        upload_data   <= rx_buffer[rx_read_ptr];
                        upload_source <= 8'h14;
                        upload_valid  <= 1'b1;
                        upload_state  <= UP_SEND;
                        $display("[%0t] SPI_SLAVE: Upload byte[%0d]=0x%02x",
                                 $time, rx_read_ptr, rx_buffer[rx_read_ptr]);
                    end else begin
                        upload_req   <= 1'b0;
                        upload_valid <= 1'b0;
                    end
                end

                //--------------------------------------------------------------
                // UP_SEND: 等待上传确认
                //--------------------------------------------------------------
                UP_SEND: begin
                    upload_valid <= 1'b0;
                    rx_read_ptr  <= rx_read_ptr + 1;
                    upload_state <= UP_WAIT;
                end

                //--------------------------------------------------------------
                // UP_WAIT: 等待一个周期后继续
                //--------------------------------------------------------------
                UP_WAIT: begin
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;

                    if (rx_upload_enable && has_data_to_upload && upload_ready) begin
                        upload_state <= UP_IDLE;  // 继续上传
                    end else begin
                        upload_state <= UP_IDLE;  // 回到空闲
                    end
                end

                default: begin
                    upload_state <= UP_IDLE;
                    upload_req   <= 1'b0;
                    upload_valid <= 1'b0;
                end
            endcase
        end
    end

    //==========================================================================
    // 实例化SPI从机物理层
    //==========================================================================
    simple_spi_slave u_spi_slave (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_tx_byte        (spi_tx_byte),
        .o_rx_byte        (spi_rx_byte),
        .o_byte_received  (spi_byte_received),
        .i_tx_ready       (spi_tx_ready),
        .o_req_next_byte  (spi_req_next_byte),
        .i_spi_clk        (spi_clk),
        .i_spi_cs_n       (spi_cs_n),
        .i_spi_mosi       (spi_mosi),
        .o_spi_miso       (spi_miso)
    );

endmodule
