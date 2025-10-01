`timescale 1ns / 1ps

module simple_spi_master (
    // 系统接口
    input                clk,       // 系统时钟
    input                rst_n,     // 异步复位, 低有效

    // 控制/数据接口
    input                i_start,   // 发起一次8位传输
    input        [7:0]   i_tx_byte, // 要发送的字节
    output reg   [7:0]   o_rx_byte, // 接收到的字节
    output reg           o_done,    // 传输完成信号 (单周期脉冲)
    output               o_busy,    // 模块忙碌信号

    // SPI 物理接口
    output reg           o_spi_clk,
    output reg           o_spi_cs_n,
    output reg           o_spi_mosi,
    input                i_spi_miso
);

    // 内部状态机
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_START_TX  = 3'd1;
    localparam STATE_SHIFT     = 3'd2;
    localparam STATE_CAPTURE   = 3'd3;
    localparam STATE_END_TX    = 3'd4;

    reg [2:0] state, next_state;

    // 内部寄存器和计数器
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;
    reg [3:0] bit_count; // 计数8个时钟周期, 外加一些准备时间
    
    // ==================== 修改开始 ====================
    // 异步逻辑确定下一状态
    always @(*) begin
        next_state = state;
        o_done = 1'b0;
        case (state)
            STATE_IDLE: begin
                if (i_start) begin
                    next_state = STATE_START_TX;
                end
            end
            
            STATE_START_TX: begin
                next_state = STATE_SHIFT;
            end

            STATE_SHIFT: begin
                if (bit_count == 4'd15) begin // 8个时钟周期 * 2 (高低电平) - 1
                    next_state = STATE_CAPTURE;
                end
            end

            STATE_CAPTURE: begin
                next_state = STATE_END_TX;
            end

            STATE_END_TX: begin
                o_done = 1'b1;
                next_state = STATE_IDLE;
            end

            default: begin
                next_state = STATE_IDLE;
            end
        endcase
    end
    // ==================== 修改结束 ====================

    // 同步逻辑更新状态和寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            bit_count <= 0;
            o_spi_clk <= 1'b0;  // Mode 0: SCLK空闲时为低
            o_spi_cs_n <= 1'b1; // CS空闲时为高
            o_spi_mosi <= 1'b0;
            o_rx_byte <= 8'h00;
        end else begin
            state <= next_state;
            
            // 根据状态执行动作
            case (state)
                STATE_IDLE: begin
                    o_spi_cs_n <= 1'b1;
                    o_spi_clk <= 1'b0;
                    if (i_start) begin
                        tx_shift_reg <= i_tx_byte; // 锁存待发送数据
                    end
                end

                STATE_START_TX: begin
                    o_spi_cs_n <= 1'b0; // 激活片选
                    bit_count <= 0;
                end

                STATE_SHIFT: begin
                    o_spi_clk <= ~o_spi_clk; // 产生时钟
                    bit_count <= bit_count + 1;

                    // 在时钟上升沿改变MOSI
                    if (o_spi_clk == 1'b0) begin // 即将变为上升沿
                        o_spi_mosi <= tx_shift_reg[7];
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                    // 在时钟下降沿采样MISO
                    else if (o_spi_clk == 1'b1) begin // 即将变为下降沿
                        rx_shift_reg <= {rx_shift_reg[6:0], i_spi_miso};
                    end
                end
                
                STATE_CAPTURE: begin
                    o_rx_byte <= rx_shift_reg; // 锁存接收到的数据
                end

                STATE_END_TX: begin
                    o_spi_cs_n <= 1'b1; // 释放片选
                end
            endcase
        end
    end

    // 忙碌信号
    assign o_busy = (state != STATE_IDLE);

endmodule