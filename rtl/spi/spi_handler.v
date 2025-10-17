`timescale 1ns / 1ps

module spi_handler #(
    parameter CLK_DIV = 2  // SPI时钟分频系数，传递给 simple_spi_master
)(
    input clk, input rst_n,
    input [7:0] cmd_type, input [15:0] cmd_length, input [7:0] cmd_data,
    input [15:0] cmd_data_index, input cmd_start, input cmd_data_valid,
    input cmd_done, output reg cmd_ready,
    output spi_clk, output spi_cs_n, output spi_mosi, input spi_miso,
    output wire upload_active,  // 上传活跃信号
    output reg upload_req, output reg [7:0] upload_data,
    output reg [7:0] upload_source, output reg upload_valid, input upload_ready
);

    parameter CMD_SPI_WRITE  = 8'h11;

    reg [2:0] state;
    parameter IDLE           = 3'd0;
    parameter WAIT_ALL_DATA  = 3'd1;
    parameter PARSE_AND_EXEC = 3'd2;
    parameter START_TRANSFER = 3'd3;
    parameter WAIT_DONE      = 3'd4;
    parameter UPLOAD         = 3'd5;

    // Upload state machine (仿照uart_handler)
    reg [1:0] upload_state;
    parameter UP_IDLE = 2'd0;
    parameter UP_SEND = 2'd1;
    parameter UP_WAIT = 2'd2;

    // *** 优化：将缓冲区从256字节减少到32字节 ***
    // 对于SPI通信，32字节足够覆盖绝大多数应用场景
    // 资源占用从 512*8=4096 FF 减少到 64*8=512 FF (节省87.5%)
    localparam BUFFER_SIZE = 32;

    reg [7:0] tx_buffer [0:BUFFER_SIZE-1];
    reg [7:0] rx_buffer [0:BUFFER_SIZE-1];
    reg [7:0] write_len, read_len;
    reg [7:0] byte_index;  // 从16位减少到8位（最大32）
    reg [15:0] data_received_count;
    reg [7:0] upload_index;  // 独立的上传索引

    reg spi_start;
    reg [7:0] spi_tx_byte;
    wire [7:0] spi_rx_byte;
    wire spi_done;

    // Upload active signal: 当处于UPLOAD状态时为高
    assign upload_active = (state == UPLOAD);

    // --- 调试代码：用于打印状态切换 ---
    reg [2:0] prev_state;
    initial prev_state = 0;
    always @(posedge clk) begin
        if (state != prev_state) begin
            $display("[%0t] SPI_HANDLER DEBUG: State Change %d -> %d", $time, prev_state, state);
            prev_state <= state;
        end
    end
    // --- 调试代码结束 ---
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready <= 1'b1; state <= IDLE; upload_req <= 1'b0;
            upload_valid <= 1'b0; byte_index <= 0; spi_start <= 1'b0;
            spi_tx_byte <= 8'h00; write_len <= 0; read_len <= 0;
            data_received_count <= 0;
            upload_state <= UP_IDLE;
            upload_index <= 0;
            upload_data <= 8'h00;
            upload_source <= 8'h03;
            // 移除for循环，小数组在复位时不需要清零
        end else begin
            spi_start <= 1'b0;
            
            if (state == IDLE || state == WAIT_ALL_DATA) begin
                cmd_ready <= 1'b1;
            end else begin
                cmd_ready <= 1'b0;
            end

            case (state)
                IDLE: begin
                    data_received_count <= 0;
                    if (cmd_start && cmd_type == CMD_SPI_WRITE && cmd_length >= 2) begin
                        state <= WAIT_ALL_DATA;
                        $display("[%0t] SPI_HANDLER DEBUG: cmd_start received. Expected payload length: %0d.", $time, cmd_length);
                    end
                end

                WAIT_ALL_DATA: begin
                    if (cmd_data_valid && cmd_data_index < BUFFER_SIZE) begin
                        tx_buffer[cmd_data_index] <= cmd_data;
                        data_received_count <= data_received_count + 1;
                        $display("[%0t] SPI_HANDLER DEBUG: Received data[%0d]=0x%02x. Total received count will be: %0d", $time, cmd_data_index, cmd_data, data_received_count + 1);
                    end else if (cmd_data_valid && cmd_data_index >= BUFFER_SIZE) begin
                        $display("[%0t] SPI_HANDLER ERROR: Buffer overflow! cmd_data_index=%0d >= BUFFER_SIZE=%0d", $time, cmd_data_index, BUFFER_SIZE);
                    end

                    if (cmd_done) begin
                        $display("[%0t] SPI_HANDLER DEBUG: cmd_done detected. Proceeding to parse.", $time);
                        // 直接跳转到 PARSE_AND_EXEC，因为 command_processor 保证所有数据都已发送
                        state <= PARSE_AND_EXEC;
                    end
                end
                
                PARSE_AND_EXEC: begin
                    $display("[%0t] SPI_HANDLER DEBUG: PARSING header from tx_buffer[0]=0x%02x, tx_buffer[1]=0x%02x", $time, tx_buffer[0], tx_buffer[1]);
                    write_len <= tx_buffer[0];
                    read_len  <= tx_buffer[1];
                    byte_index <= 0;
                    // 边界检查：write_len+2个数据必须在缓冲区内 (2字节头+write_len字节数据)
                    // read_len也不能超过缓冲区
                    if ((tx_buffer[0] + 2) > BUFFER_SIZE) begin
                        $display("[%0t] SPI_HANDLER ERROR: write_len=%0d exceeds buffer (max write_len=%0d)", $time, tx_buffer[0], BUFFER_SIZE - 2);
                        state <= IDLE;  // 错误处理：返回IDLE
                    end else if (tx_buffer[1] > BUFFER_SIZE) begin
                        $display("[%0t] SPI_HANDLER ERROR: read_len=%0d exceeds buffer size=%0d", $time, tx_buffer[1], BUFFER_SIZE);
                        state <= IDLE;  // 错误处理：返回IDLE
                    end else begin
                        state <= START_TRANSFER;
                    end
                end
                
                START_TRANSFER: begin
                    $display("[%0t] SPI_HANDLER DEBUG: In START_TRANSFER. byte_index=%0d, write_len=%0d, read_len=%0d", $time, byte_index, write_len, read_len);
                    if (byte_index >= (write_len + read_len)) begin
                        if (read_len > 0) begin
                            upload_index <= 0;  // 初始化上传索引
                            state <= UPLOAD;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        // 边界检查：确保访问tx_buffer不会越界 (byte_index + 2 < BUFFER_SIZE)
                        if (byte_index < write_len && (byte_index + 2) < BUFFER_SIZE) begin
                            spi_tx_byte <= tx_buffer[byte_index + 2];
                        end else begin
                            spi_tx_byte <= 8'h00;  // 读阶段或越界时发送0x00
                        end
                        spi_start <= 1'b1;
                        state <= WAIT_DONE;
                        $display("[%0t] SPI_HANDLER DEBUG: Asserting spi_start for byte #%0d", $time, byte_index);
                    end
                end

                WAIT_DONE: begin
                    if (spi_done) begin
                        if (byte_index >= write_len) $display("[%0t] SPI_HANDLER DEBUG: Captured rx_byte[%0d] = 0x%02x", $time, byte_index - write_len, spi_rx_byte);
                        // 边界检查：确保写入rx_buffer不会越界
                        if (byte_index >= write_len && (byte_index - write_len) < BUFFER_SIZE) begin
                            rx_buffer[byte_index - write_len] <= spi_rx_byte;
                        end
                        byte_index <= byte_index + 1;
                        state <= START_TRANSFER;
                    end
                end

                UPLOAD: begin
                    // 在UPLOAD状态下，等待上传完成
                    if (upload_index >= read_len) begin
                        // 所有数据上传完成
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase

            // Upload state machine (独立状态机，仿照uart_handler)
            case (upload_state)
                UP_IDLE: begin
                    if ((state == UPLOAD) && (upload_index < read_len) && upload_ready && upload_index < BUFFER_SIZE) begin
                        upload_req <= 1'b1;
                        upload_data <= rx_buffer[upload_index];
                        upload_source <= 8'h03;
                        upload_valid <= 1'b1;
                        upload_state <= UP_SEND;
                        $display("[%0t] SPI_HANDLER DEBUG: Upload byte[%0d] = 0x%02x", $time, upload_index, rx_buffer[upload_index]);
                    end else begin
                        upload_req <= 1'b0;
                        upload_valid <= 1'b0;
                    end
                end

                UP_SEND: begin
                    // valid已在UP_IDLE拉高一个周期，这里立即拉低避免重复发送
                    upload_valid <= 1'b0;
                    // 因为upload_ready永远是1，所以直接跳转
                    upload_index <= upload_index + 1;
                    upload_state <= UP_WAIT;
                    $display("[%0t] SPI_HANDLER DEBUG: Upload confirmed, index now %0d", $time, upload_index + 1);
                end

                UP_WAIT: begin
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                    // 等待一个周期后检查是否还有数据需要上传
                    if ((state == UPLOAD) && (upload_index < read_len) && upload_ready) begin
                        upload_state <= UP_IDLE;  // 继续上传下一个字节
                    end else if (upload_index >= read_len) begin
                        upload_state <= UP_IDLE;  // 上传完成
                    end
                end

                default: begin
                    upload_state <= UP_IDLE;
                    upload_req <= 1'b0;
                    upload_valid <= 1'b0;
                end
            endcase
        end
    end

    simple_spi_master #(
        .CLK_DIV(CLK_DIV)  // 传递分频参数
    ) u_spi (
        .clk(clk), .rst_n(rst_n), .i_start(spi_start), .i_tx_byte(spi_tx_byte),
        .o_rx_byte(spi_rx_byte), .o_done(spi_done), .o_busy(), .o_spi_clk(spi_clk),
        .o_spi_cs_n(spi_cs_n), .o_spi_mosi(spi_mosi), .i_spi_miso(spi_miso)
    );
endmodule