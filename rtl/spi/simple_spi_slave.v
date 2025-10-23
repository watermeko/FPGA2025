`timescale 1ns / 1ps

//==============================================================================
// SPI Slave Module (Mode 0: CPOL=0, CPHA=0)
//==============================================================================
// 功能：SPI从机物理层实现
// 特性：
//   - SPI Mode 0: 时钟空闲为低，上升沿采样，下降沿改变
//   - 全双工通信
//   - 自动检测CS边沿启动/停止传输
//   - 支持连续多字节传输
//==============================================================================

module simple_spi_slave (
    // 系统接口
    input                clk,           // 系统时钟（需要远高于SPI时钟，建议>4倍）
    input                rst_n,         // 异步复位, 低有效

    // 数据接口
    input        [7:0]   i_tx_byte,     // 要发送的字节（由上层模块准备）
    output reg   [7:0]   o_rx_byte,     // 接收到的字节
    output reg           o_byte_received, // 字节接收完成信号（单周期脉冲）
    input                i_tx_ready,    // 发送数据已准备好
    output reg           o_req_next_byte, // 请求下一个发送字节（提前1字节请求）

    // SPI 物理接口（从机侧）
    input                i_spi_clk,     // SPI时钟（来自主机）
    input                i_spi_cs_n,    // 片选（低有效）
    input                i_spi_mosi,    // 主机输出从机输入
    output reg           o_spi_miso     // 主机输入从机输出
);

    //==========================================================================
    // 信号同步（跨时钟域处理）
    //==========================================================================
    reg [2:0] spi_clk_sync;
    reg [2:0] spi_cs_sync;
    reg [2:0] spi_mosi_sync;

    wire spi_clk_s  = spi_clk_sync[2];
    wire spi_cs_n_s = spi_cs_sync[2];
    wire spi_mosi_s = spi_mosi_sync[2];

    // 三级寄存器同步器（防止亚稳态）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_sync  <= 3'b000;
            spi_cs_sync   <= 3'b111;  // CS默认高电平
            spi_mosi_sync <= 3'b000;
        end else begin
            spi_clk_sync  <= {spi_clk_sync[1:0],  i_spi_clk};
            spi_cs_sync   <= {spi_cs_sync[1:0],   i_spi_cs_n};
            spi_mosi_sync <= {spi_mosi_sync[1:0], i_spi_mosi};
        end
    end

    //==========================================================================
    // 边沿检测
    //==========================================================================
    reg spi_clk_d1, spi_cs_n_d1;
    wire spi_clk_posedge = (~spi_clk_d1) & spi_clk_s;   // 上升沿检测
    wire spi_clk_negedge = spi_clk_d1 & (~spi_clk_s);   // 下降沿检测
    wire spi_cs_falling  = spi_cs_n_d1 & (~spi_cs_n_s); // CS下降沿（传输开始）
    wire spi_cs_rising   = (~spi_cs_n_d1) & spi_cs_n_s; // CS上升沿（传输结束）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_clk_d1  <= 1'b0;
            spi_cs_n_d1 <= 1'b1;
        end else begin
            spi_clk_d1  <= spi_clk_s;
            spi_cs_n_d1 <= spi_cs_n_s;
        end
    end

    //==========================================================================
    // 状态机
    //==========================================================================
    localparam STATE_IDLE  = 2'd0;
    localparam STATE_SHIFT = 2'd1;
    localparam STATE_DONE  = 2'd2;

    reg [1:0] state;
    reg [2:0] bit_count;
    reg [7:0] rx_shift_reg;
    reg [7:0] tx_shift_reg;
    reg       byte_start;      // 标记刚开始新字节传输

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= STATE_IDLE;
            bit_count        <= 3'd0;
            rx_shift_reg     <= 8'h00;
            tx_shift_reg     <= 8'h00;
            o_rx_byte        <= 8'h00;
            o_byte_received  <= 1'b0;
            o_req_next_byte  <= 1'b0;
            o_spi_miso       <= 1'b0;
            byte_start       <= 1'b0;
        end else begin
            // 默认值
            o_byte_received  <= 1'b0;
            o_req_next_byte  <= 1'b0;
            // byte_start在下降沿处理后清零，不在这里清零

            case (state)
                //--------------------------------------------------------------
                // IDLE: 等待CS拉低
                //--------------------------------------------------------------
                STATE_IDLE: begin
                    bit_count <= 3'd0;
                    if (spi_cs_falling) begin
                        // CS拉低，加载第一个发送字节
                        if (i_tx_ready) begin
                            tx_shift_reg <= i_tx_byte;
                            o_spi_miso   <= i_tx_byte[7]; // 立即输出最高位
                        end else begin
                            tx_shift_reg <= 8'hFF; // 默认发送0xFF
                            o_spi_miso   <= 1'b1;
                        end
                        byte_start <= 1'b1;  // 标记新字节开始
                        state <= STATE_SHIFT;
                    end else begin
                        o_spi_miso <= 1'b0; // 空闲时MISO保持低
                    end
                end

                //--------------------------------------------------------------
                // SHIFT: 移位收发数据
                //--------------------------------------------------------------
                STATE_SHIFT: begin
                    // CS拉高，立即终止传输
                    if (spi_cs_rising) begin
                        state <= STATE_IDLE;
                    end
                    // SPI Mode 0: 上升沿采样MOSI
                    else if (spi_clk_posedge) begin
                        rx_shift_reg <= {rx_shift_reg[6:0], spi_mosi_s};
                        bit_count    <= bit_count + 1;

                        // 接收完一个字节
                        if (bit_count == 3'd7) begin
                            state <= STATE_DONE;
                        end
                    end
                    // SPI Mode 0: 下降沿更新MISO（提前准备好，以便主机在下一个上升沿采样）
                    else if (spi_clk_negedge) begin
                        if (byte_start) begin
                            // 第一个下降沿：移位并输出bit[6]
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            o_spi_miso   <= tx_shift_reg[6];
                            byte_start   <= 1'b0;
                        end else if (bit_count <= 3'd7) begin
                            // 后续下降沿：移位并输出下一位（包括第8位bit[0]）
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            o_spi_miso   <= tx_shift_reg[6];
                        end
                    end
                end

                //--------------------------------------------------------------
                // DONE: 字节接收完成，准备下一个字节
                //--------------------------------------------------------------
                STATE_DONE: begin
                    // 锁存接收到的字节（rx_shift_reg已经包含完整的8位）
                    o_rx_byte       <= rx_shift_reg;
                    o_byte_received <= 1'b1; // 产生接收完成脉冲

                    // 请求下一个发送字节
                    o_req_next_byte <= 1'b1;

                    // 加载下一个发送字节（如果CS仍然有效）
                    if (~spi_cs_n_s) begin
                        bit_count <= 3'd0;
                        if (i_tx_ready) begin
                            tx_shift_reg <= i_tx_byte;
                            o_spi_miso   <= i_tx_byte[7];  // 立即输出最高位
                        end else begin
                            tx_shift_reg <= 8'hFF;
                            o_spi_miso   <= 1'b1;
                        end
                        byte_start <= 1'b1;  // 标记新字节开始
                        state <= STATE_SHIFT;
                    end else begin
                        // CS已拉高，返回IDLE
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
