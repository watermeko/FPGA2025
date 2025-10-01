`timescale 1ns / 1ps

module spi_handler (
    input clk, input rst_n,
    input [7:0] cmd_type, input [15:0] cmd_length, input [7:0] cmd_data,
    input [15:0] cmd_data_index, input cmd_start, input cmd_data_valid,
    input cmd_done, output reg cmd_ready,
    output spi_clk, output spi_cs_n, output spi_mosi, input spi_miso,
    output reg upload_req, output reg [7:0] upload_data,
    output reg [7:0] upload_source, output reg upload_valid, input upload_ready
);

    parameter CMD_SPI_WRITE  = 8'h11;
    parameter CMD_SPI_READ   = 8'h12;

    reg [2:0] state;
    parameter IDLE           = 3'd0;
    parameter WAIT_ALL_DATA  = 3'd1;
    parameter PARSE_AND_EXEC = 3'd2;
    parameter START_TRANSFER = 3'd3;
    parameter WAIT_DONE      = 3'd4;
    parameter UPLOAD         = 3'd5;

    reg [7:0] tx_buffer [0:255], rx_buffer [0:255];
    reg [7:0] write_len, read_len;
    reg [15:0] byte_index;
    reg [15:0] total_len; 
    
    integer i; // 为 for 循环添加声明

    reg spi_start;
    reg [7:0] spi_tx_byte;
    wire [7:0] spi_rx_byte;
    wire spi_done;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_ready <= 1'b1; state <= IDLE; upload_req <= 1'b0;
            upload_valid <= 1'b0; byte_index <= 0; spi_start <= 1'b0;
            spi_tx_byte <= 8'h00; write_len <= 0; read_len <= 0;
            total_len <= 0;

            // --- *** 新增的初始化代码 *** ---
            // 在复位时清空两个缓冲区
            for (i = 0; i < 256; i = i + 1) begin
                tx_buffer[i] <= 8'h00;
                rx_buffer[i] <= 8'h00;
            end
            
        end else begin
            spi_start <= 1'b0;
            upload_valid <= 1'b0;
            cmd_ready <= 1'b0; 

            if (cmd_data_valid) begin
                tx_buffer[cmd_data_index] <= cmd_data;
            end

            case (state)
                IDLE: begin
                    cmd_ready <= 1'b1;
                    byte_index <= 0;
                    write_len <= 0;
                    read_len <= 0;
                    upload_req <= 1'b0; 
                    
                    if (cmd_start && (cmd_type == CMD_SPI_WRITE || cmd_type == CMD_SPI_READ) && cmd_length >= 2) begin
                        total_len <= cmd_length;
                        state <= WAIT_ALL_DATA;
                    end
                end
                
                WAIT_ALL_DATA: begin
                    cmd_ready <= 1'b1; 
                    if (cmd_done) begin
                        state <= PARSE_AND_EXEC;
                    end
                end
                
                PARSE_AND_EXEC: begin
                    write_len <= tx_buffer[0];
                    read_len  <= tx_buffer[1];
                    byte_index <= 0;
                    state <= START_TRANSFER;
                end
                
                START_TRANSFER: begin
                    if (byte_index >= (write_len + read_len)) begin
                        if (read_len > 0) begin
                            byte_index <= 0;
                            state <= UPLOAD;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        if (byte_index < write_len) begin
                            spi_tx_byte <= tx_buffer[byte_index + 2];
                        end else begin
                            spi_tx_byte <= 8'h00;
                        end
                        
                        spi_start <= 1'b1;
                        state <= WAIT_DONE;
                    end
                end

                WAIT_DONE: begin
                    if (spi_done) begin
                        if (byte_index >= write_len && byte_index < (write_len + read_len)) begin
                           rx_buffer[byte_index - write_len] <= spi_rx_byte;
                        end
                        byte_index <= byte_index + 1;
                        state <= START_TRANSFER;
                    end
                end

                UPLOAD: begin
                    upload_req <= 1'b1;
                    if (upload_ready) begin
                        if (byte_index < read_len) begin
                            upload_data <= rx_buffer[byte_index];
                            upload_source <= 8'h03;
                            upload_valid <= 1'b1;
                            byte_index <= byte_index + 1;
                        end else begin
                           state <= IDLE;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    simple_spi_master u_spi (
        .clk(clk), .rst_n(rst_n), .i_start(spi_start), .i_tx_byte(spi_tx_byte),
        .o_rx_byte(spi_rx_byte), .o_done(spi_done), .o_busy(), .o_spi_clk(spi_clk),
        .o_spi_cs_n(spi_cs_n), .o_spi_mosi(spi_mosi), .i_spi_miso(spi_miso)
    );

endmodule