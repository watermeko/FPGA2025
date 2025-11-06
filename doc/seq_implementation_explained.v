// ============================================================================
// 自定义序列输出 - 详细注释版本
// 说明核心实现原理
// ============================================================================

module seq_generator_explained (
    input  wire        clk,         // 60MHz系统时钟
    input  wire        rst_n,
    input  wire [15:0] freq_div,    // 频率分频器 (例: 60)
    input  wire [63:0] seq_data,    // 序列数据 (例: 64'h0155 = 0101010101)
    input  wire [6:0]  seq_len,     // 序列长度 (例: 10位)
    input  wire        enable,
    output reg         seq_out
);

    reg [15:0] clk_div_counter;
    reg [6:0]  bit_index;
    reg        bit_clk_tick;

    // ========================================================================
    // 第一步: 时钟分频 - 产生"基准频率"的时钟脉冲
    // ========================================================================
    // 目标: 从60MHz系统时钟产生1MHz的脉冲信号
    //
    // 工作原理:
    //   - clk_div_counter 从0数到59 (共60个周期)
    //   - 数到59时产生一个tick脉冲，然后重置
    //   - tick脉冲的频率 = 60MHz / 60 = 1MHz
    //
    // 例子: freq_div = 60
    //   周期0:  counter=0,  tick=0
    //   周期1:  counter=1,  tick=0
    //   ...
    //   周期59: counter=59, tick=1  ← 产生脉冲！
    //   周期60: counter=0,  tick=0  ← 重置
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_counter <= 0;
            bit_clk_tick <= 0;
        end
        else if (!enable) begin
            clk_div_counter <= 0;
            bit_clk_tick <= 0;
        end
        else begin
            // 默认不产生tick
            bit_clk_tick <= 0;

            if (freq_div == 0) begin
                // 防止除以0
                clk_div_counter <= 0;
            end
            else if (clk_div_counter < freq_div - 1) begin
                // 正在计数中...
                clk_div_counter <= clk_div_counter + 1;
            end
            else begin
                // 计数到达目标值！
                clk_div_counter <= 0;        // 重置计数器
                bit_clk_tick <= 1;           // 产生1个时钟周期的脉冲

                // 此时已经过了 freq_div 个系统时钟周期
                // 时间间隔 = freq_div / 60MHz
                // 例: freq_div=60 → 间隔 = 60/60MHz = 1us
            end
        end
    end

    // ========================================================================
    // 第二步: 序列输出 - 根据bit_clk_tick切换输出位
    // ========================================================================
    // 目标: 每次tick时，输出序列的下一位
    //
    // 数据结构:
    //   seq_data[63:0] 存储序列数据 (LSB优先)
    //   seq_data[0] = 第1个输出位
    //   seq_data[1] = 第2个输出位
    //   ...
    //   seq_data[9] = 第10个输出位 (如果长度是10)
    //
    // 例子: seq_data = 64'h0155 = 0b0000...0101010101
    //       seq_len = 10
    //
    //   时刻0: bit_index=0, seq_out=seq_data[0]=0  (输出第1位)
    //   等待1us (60个系统时钟周期)...
    //   时刻1: bit_index=1, seq_out=seq_data[1]=1  (输出第2位)
    //   等待1us...
    //   时刻2: bit_index=2, seq_out=seq_data[2]=0  (输出第3位)
    //   ...
    //   时刻9: bit_index=9, seq_out=seq_data[9]=1  (输出第10位)
    //   等待1us...
    //   时刻10: bit_index=0, seq_out=seq_data[0]=0 (循环！)
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_index <= 0;
            seq_out <= 0;
        end
        else if (!enable) begin
            bit_index <= 0;
            seq_out <= 0;
        end
        else if (bit_clk_tick) begin
            // bit_clk_tick=1 表示该切换到下一位了

            if (seq_len == 0) begin
                // 无效配置: 没有序列
                bit_index <= 0;
                seq_out <= 0;
            end
            else begin
                // 从seq_data中读取当前位并输出
                seq_out <= seq_data[bit_index];

                // 示例: 如果 bit_index=3, seq_data[3]=1
                //       则 seq_out 变为 1

                // 移动到下一位
                if (bit_index < seq_len - 1) begin
                    bit_index <= bit_index + 1;
                    // 例: bit_index 从3变成4
                end
                else begin
                    bit_index <= 0;  // 到达末尾，循环回到开头
                    // 例: 如果seq_len=10, 当bit_index=9时
                    //     下一次变成0 (循环！)
                end
            end
        end
        else begin
            // 没有tick，保持当前输出不变
            // seq_out 保持原值
            // bit_index 保持原值
        end
    end

    // ========================================================================
    // 完整时序示例
    // ========================================================================
    // 配置: freq_div=60, seq_data=0x0155, seq_len=10
    //
    // 时间 | clk_div | tick | bit_idx | seq_data[idx] | seq_out
    // -----|---------|------|---------|---------------|--------
    // 0ns  |    0    |  0   |    0    |       0       |   0
    // 17ns |    1    |  0   |    0    |       0       |   0
    // 34ns |    2    |  0   |    0    |       0       |   0
    // ...  |   ...   |  0   |    0    |       0       |   0
    // 983ns|   59    |  1   |    0→1  |       0→1     |   0→1
    // 1.0us|    0    |  0   |    1    |       1       |   1
    // 1.02us|   1    |  0   |    1    |       1       |   1
    // ...  |   ...   |  0   |    1    |       1       |   1
    // 1.98us|  59    |  1   |    1→2  |       1→0     |   1→0
    // 2.0us|    0    |  0   |    2    |       0       |   0
    // ...  |   ...   | ...  |   ...   |      ...      |  ...
    // 9.0us|    0    |  0   |    9    |       1       |   1
    // 9.98us|  59    |  1   |    9→0  |       1→0     |   1→0  ← 循环!
    // 10.0us|   0    |  0   |    0    |       0       |   0
    // ========================================================================

endmodule
