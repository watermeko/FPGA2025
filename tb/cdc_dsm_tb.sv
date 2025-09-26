`timescale 1ns / 1ps
`include "./utils.sv"
`define DSM_DEBUG  
module cdc_dsm_tb;

    //-----------------------------------------------------------------------------
    // Testbench Parameters
    //-----------------------------------------------------------------------------
    localparam CLK_FREQ      = 60_000_000;  // 60MHz system clock
    localparam CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ; // Clock period in ns
    
    // DSM测试参数
    localparam NUM_CHANNELS = 8;

    //-----------------------------------------------------------------------------
    // Testbench Signals
    //-----------------------------------------------------------------------------
    reg clk;
    reg rst_n;
    reg [7:0] usb_data_in;
    reg usb_data_valid_in;

    // DSM信号输入
    reg [7:0] dsm_signal_in;

    // 监控cdc模块输出  
    wire led_out;
    wire [7:0] pwm_pins;
    wire ext_uart_tx;
    wire [13:0] dac_data;
    wire [7:0] usb_upload_data;
    wire usb_upload_valid;
    
    // 其他接口信号（测试中未使用但需要连接）
    reg ext_uart_rx;
    reg dac_clk;

    // USB数据接收缓冲区  
    reg [7:0] usb_received_data [0:255];
    integer usb_received_count;
    integer usb_valid_pulse_count;  // 计数valid脉冲总数
    
    // DSM测量结果解析缓冲区
    typedef struct {
        reg [7:0]  channel;
        reg [15:0] high_time;
        reg [15:0] low_time; 
        reg [15:0] period_time;
        reg [15:0] duty_cycle;
    } dsm_result_t;
    
    dsm_result_t dsm_results [0:7];  // 最多8个通道的结果
    integer dsm_result_count;
    
    // 测试信号生成参数
    reg [7:0] test_signals_active;  // 哪些通道正在生成测试信号
    integer test_high_cycles [0:7]; // 每个通道的高电平周期数
    integer test_low_cycles [0:7];  // 每个通道的低电平周期数

    //-----------------------------------------------------------------------------
    // 实例化被测模块 (DUT)
    //-----------------------------------------------------------------------------
    cdc dut(
        .clk(clk),
        .rst_n(rst_n),
        .usb_data_in(usb_data_in),
        .usb_data_valid_in(usb_data_valid_in),
        .led_out(led_out),
        .pwm_pins(pwm_pins),
        .ext_uart_tx(ext_uart_tx),
        .ext_uart_rx(ext_uart_rx),
        .dac_clk(dac_clk),
        .dac_data(dac_data),
        .dsm_signal_in(dsm_signal_in),
        .usb_upload_data(usb_upload_data),
        .usb_upload_valid(usb_upload_valid)
    );

    //-----------------------------------------------------------------------------
    // 时钟和复位生成
    //-----------------------------------------------------------------------------
    import SimSrcGen::*;
    initial GenClk(clk, 0, CLK_PERIOD_NS);
    // DAC时钟生成（200MHz，在本测试中不重要但需要提供）
    initial GenClk(dac_clk, 0, 5ns);
    initial GenRstN(clk, rst_n, 0, 100);

    //-----------------------------------------------------------------------------
    // DSM测试信号生成任务
    //-----------------------------------------------------------------------------
    task generate_dsm_signal(input integer channel, input integer high_cycles, input integer low_cycles, input integer periods);
        integer p, i;
        begin
            if (channel >= 0 && channel < 8) begin
                $display("[%0t] 开始在通道%0d生成测试信号: 高电平=%0d周期, 低电平=%0d周期, 重复%0d次", 
                         $time, channel, high_cycles, low_cycles, periods);
                
                test_signals_active[channel] = 1'b1;
                test_high_cycles[channel] = high_cycles;
                test_low_cycles[channel] = low_cycles;
                
                // 确保信号从低电平开始
                dsm_signal_in[channel] = 1'b0;
                repeat(5) @(posedge clk); // 等待几个时钟周期确保稳定
                
                for (p = 0; p < periods; p = p + 1) begin
                    // 高电平
                    dsm_signal_in[channel] = 1'b1;
                    for (i = 0; i < high_cycles; i = i + 1) begin
                        @(posedge clk);
                    end
                    
                    // 低电平
                    dsm_signal_in[channel] = 1'b0;
                    for (i = 0; i < low_cycles; i = i + 1) begin
                        @(posedge clk);
                    end
                end
                
                dsm_signal_in[channel] = 1'b0;
                test_signals_active[channel] = 1'b0;
                $display("[%0t] 通道%0d测试信号生成完成", $time, channel);
            end
        end
    endtask

    //-----------------------------------------------------------------------------
    // 并发多通道信号生成任务
    //-----------------------------------------------------------------------------
    task generate_multi_channel_signals;
        begin
            $display("[%0t] 开始生成多通道测试信号", $time);
            
            fork
                generate_dsm_signal(0, 50, 50, 5);   // 50% 占空比
                generate_dsm_signal(1, 25, 75, 4);   // 25% 占空比  
                generate_dsm_signal(2, 75, 25, 4);   // 75% 占空比
                generate_dsm_signal(3, 30, 70, 4);   // 30% 占空比
                generate_dsm_signal(4, 80, 20, 3);   // 80% 占空比
            join
            
            $display("[%0t] 多通道测试信号生成完成", $time);
        end
    endtask

    //-----------------------------------------------------------------------------
    // USB上传数据监控
    //-----------------------------------------------------------------------------
    always @(posedge clk) begin
        if (usb_upload_valid) begin
            usb_valid_pulse_count = usb_valid_pulse_count + 1;
            usb_received_data[usb_received_count] = usb_upload_data;
            $display("[%0t] USB接收数据[%0d]: 0x%02X (valid脉冲#%0d)", $time, usb_received_count, usb_upload_data, usb_valid_pulse_count);
            usb_received_count = usb_received_count + 1;
        end
    end

    //-----------------------------------------------------------------------------
    // DSM结果解析任务
    //-----------------------------------------------------------------------------
    task parse_dsm_results;
        integer i, result_idx;
        dsm_result_t current_result;
        begin
            $display("\n=== 解析DSM测量结果 ===");
            $display("接收到的总字节数: %0d", usb_received_count);
            $display("USB valid脉冲总数: %0d", usb_valid_pulse_count);
            
            if (usb_received_count != usb_valid_pulse_count) begin
                $display("⚠️  警告: USB数据字节数(%0d) != valid脉冲数(%0d)", usb_received_count, usb_valid_pulse_count);
            end
            
            result_idx = 0;
            i = 0;
            
            while (i + 8 < usb_received_count && result_idx < 8) begin
                // 解析一个通道的9字节数据
                current_result.channel = usb_received_data[i];
                current_result.high_time = {usb_received_data[i+1], usb_received_data[i+2]};
                current_result.low_time = {usb_received_data[i+3], usb_received_data[i+4]};
                current_result.period_time = {usb_received_data[i+5], usb_received_data[i+6]};
                current_result.duty_cycle = {usb_received_data[i+7], usb_received_data[i+8]};
                
                dsm_results[result_idx] = current_result;
                
                $display("通道%0d结果:", current_result.channel);
                $display("  高电平时间: %0d 时钟周期", current_result.high_time);
                $display("  低电平时间: %0d 时钟周期", current_result.low_time);
                $display("  周期时间:   %0d 时钟周期", current_result.period_time);
                $display("  占空比:     %0d%%", current_result.duty_cycle);
                
                result_idx = result_idx + 1;
                i = i + 9;
            end
            
            dsm_result_count = result_idx;
            $display("成功解析 %0d 个通道的测量结果", dsm_result_count);
        end
    endtask

    //-----------------------------------------------------------------------------
    // 结果验证任务
    //-----------------------------------------------------------------------------
    task verify_dsm_results;
        integer i;
        integer expected_high, expected_low, expected_duty;
        automatic integer tolerance_cycles = 2; // 允许的时钟周期误差
        automatic integer tolerance_duty = 3;   // 允许的占空比误差(%)
        begin
            $display("\n=== DSM测量结果验证 ===");
            
            for (i = 0; i < dsm_result_count; i = i + 1) begin
                // 根据通道号获取预期值
                case (dsm_results[i].channel)
                    0: begin expected_high = 50; expected_low = 50; expected_duty = 50; end
                    1: begin expected_high = 25; expected_low = 75; expected_duty = 25; end
                    2: begin expected_high = 75; expected_low = 25; expected_duty = 75; end
                    3: begin expected_high = 30; expected_low = 70; expected_duty = 30; end
                    4: begin expected_high = 80; expected_low = 20; expected_duty = 80; end
                    default: begin 
                        expected_high = 0; expected_low = 0; expected_duty = 0; 
                        $display("Warning: 未知通道 %0d", dsm_results[i].channel);
                    end
                endcase
                
                $display("\n通道%0d验证:", dsm_results[i].channel);
                
                // 验证高电平时间
                if (dsm_results[i].high_time >= expected_high - tolerance_cycles && 
                    dsm_results[i].high_time <= expected_high + tolerance_cycles) begin
                    $display("  ✅ 高电平时间测量正确: %0d (预期: %0d±%0d)", 
                             dsm_results[i].high_time, expected_high, tolerance_cycles);
                end else begin
                    $display("  ❌ 高电平时间测量错误: %0d (预期: %0d±%0d)", 
                             dsm_results[i].high_time, expected_high, tolerance_cycles);
                end
                
                // 验证低电平时间
                if (dsm_results[i].low_time >= expected_low - tolerance_cycles && 
                    dsm_results[i].low_time <= expected_low + tolerance_cycles) begin
                    $display("  ✅ 低电平时间测量正确: %0d (预期: %0d±%0d)", 
                             dsm_results[i].low_time, expected_low, tolerance_cycles);
                end else begin
                    $display("  ❌ 低电平时间测量错误: %0d (预期: %0d±%0d)", 
                             dsm_results[i].low_time, expected_low, tolerance_cycles);
                end
                
                // 验证占空比
                if (dsm_results[i].duty_cycle >= expected_duty - tolerance_duty && 
                    dsm_results[i].duty_cycle <= expected_duty + tolerance_duty) begin
                    $display("  ✅ 占空比测量正确: %0d%% (预期: %0d%%±%0d%%)", 
                             dsm_results[i].duty_cycle, expected_duty, tolerance_duty);
                end else begin
                    $display("  ❌ 占空比测量错误: %0d%% (预期: %0d%%±%0d%%)", 
                             dsm_results[i].duty_cycle, expected_duty, tolerance_duty);
                end
            end
        end
    endtask

    //-----------------------------------------------------------------------------
    // 主测试序列
    //-----------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        #1000;
        
        $display("===============================================");
        $display("       CDC DSM功能专项测试开始");
        $display("===============================================");
        
        //--- 多通道DSM测试 ---
        $display("\n--- 多通道DSM测量测试 ---");
        usb_received_count = 0;
        usb_valid_pulse_count = 0;
        dsm_result_count = 0;
        
        // 确保所有DSM信号初始为0
        dsm_signal_in = 8'h00;
        #(CLK_PERIOD_NS * 200);
        
        // 发送多通道DSM命令，启用通道0-4 - 使用utils.sv中的任务
        $display("[%0t] 发送多通道DSM命令", $time);
        USB::SendDSMCommand(clk, usb_data_in, usb_data_valid_in, 8'b00011111, CLK_PERIOD_NS);
        
        // 等待命令处理完成
        #(CLK_PERIOD_NS * 500);
        $display("[%0t] 命令处理等待完成，开始生成多通道测试信号", $time);
        
        // 生成多通道测试信号 - 使用fork并行生成
        fork
            // 通道0: 50% 占空比
            begin
                $display("[%0t] 通道0开始生成信号", $time);
                dsm_signal_in[0] = 1'b0;
                repeat(10) @(posedge clk);
                repeat(6) begin  // 6个完整周期
                    dsm_signal_in[0] = 1'b1;
                    repeat(50) @(posedge clk);
                    dsm_signal_in[0] = 1'b0;
                    repeat(50) @(posedge clk);
                end
                dsm_signal_in[0] = 1'b0;
                $display("[%0t] 通道0信号生成完成", $time);
            end
            
            // 通道1: 25% 占空比
            begin
                $display("[%0t] 通道1开始生成信号", $time);
                dsm_signal_in[1] = 1'b0;
                repeat(15) @(posedge clk);  // 错开启动时间
                repeat(5) begin  // 5个完整周期
                    dsm_signal_in[1] = 1'b1;
                    repeat(25) @(posedge clk);
                    dsm_signal_in[1] = 1'b0;
                    repeat(75) @(posedge clk);
                end
                dsm_signal_in[1] = 1'b0;
                $display("[%0t] 通道1信号生成完成", $time);
            end
            
            // 通道2: 75% 占空比
            begin
                $display("[%0t] 通道2开始生成信号", $time);
                dsm_signal_in[2] = 1'b0;
                repeat(20) @(posedge clk);  // 错开启动时间
                repeat(4) begin  // 4个完整周期
                    dsm_signal_in[2] = 1'b1;
                    repeat(75) @(posedge clk);
                    dsm_signal_in[2] = 1'b0;
                    repeat(25) @(posedge clk);
                end
                dsm_signal_in[2] = 1'b0;
                $display("[%0t] 通道2信号生成完成", $time);
            end
            
            // 通道3: 30% 占空比
            begin
                $display("[%0t] 通道3开始生成信号", $time);
                dsm_signal_in[3] = 1'b0;
                repeat(25) @(posedge clk);  // 错开启动时间
                repeat(5) begin  // 5个完整周期
                    dsm_signal_in[3] = 1'b1;
                    repeat(30) @(posedge clk);
                    dsm_signal_in[3] = 1'b0;
                    repeat(70) @(posedge clk);
                end
                dsm_signal_in[3] = 1'b0;
                $display("[%0t] 通道3信号生成完成", $time);
            end
            
            // 通道4: 80% 占空比
            begin
                $display("[%0t] 通道4开始生成信号", $time);
                dsm_signal_in[4] = 1'b0;
                repeat(30) @(posedge clk);  // 错开启动时间
                repeat(4) begin  // 4个完整周期
                    dsm_signal_in[4] = 1'b1;
                    repeat(80) @(posedge clk);
                    dsm_signal_in[4] = 1'b0;
                    repeat(20) @(posedge clk);
                end
                dsm_signal_in[4] = 1'b0;
                $display("[%0t] 通道4信号生成完成", $time);
            end
        join
        
        $display("[%0t] 所有通道测试信号生成完成", $time);
        
        // 等待测量完成 - 多通道需要更长时间
        $display("[%0t] 等待多通道测量完成...", $time);
        #(CLK_PERIOD_NS * 5000);
        
        // 解析和验证多通道结果
        parse_dsm_results;
        verify_dsm_results;

        $display("\n===============================================");
        $display("       多通道测试完成");
        $display("===============================================");

        $finish;
    end

    //-----------------------------------------------------------------------------
    // 调试监控
    //-----------------------------------------------------------------------------
   `ifdef DSM_DEBUG
    //ifdef
    
    // 边沿检测寄存器
    reg [3:0] prev_upload_byte_index;
    reg [3:0] prev_upload_channel;
    reg [1:0] prev_upload_state;
    
    always @(posedge clk) begin
        prev_upload_byte_index <= dut.u_dsm_handler.upload_byte_index;
        prev_upload_channel <= dut.u_dsm_handler.upload_channel;
        prev_upload_state <= dut.u_dsm_handler.upload_state;
    end
    
    // 精简调试 - 专注于上传字节计数问题
    always @(posedge clk) begin
        // 监控DSM handler上传状态转换
        if (dut.u_dsm_handler.upload_state != 0) begin
            $display("[%0t] 📊 DSM上传状态: state=%0d, channel=%0d, byte_idx=%0d, req=%0d, valid=%0d, ready=%0d", 
                     $time, dut.u_dsm_handler.upload_state, dut.u_dsm_handler.upload_channel, 
                     dut.u_dsm_handler.upload_byte_index, dut.dsm_upload_req, 
                     dut.dsm_upload_valid, dut.dsm_upload_ready);
        end
        
        // 监控字节索引变化
        if (dut.u_dsm_handler.upload_byte_index != prev_upload_byte_index) begin
            $display("[%0t] 🔢 字节索引变化: %0d -> %0d", $time, prev_upload_byte_index, dut.u_dsm_handler.upload_byte_index);
        end
        
        // 监控实际上传的数据字节
        if (dut.dsm_upload_valid && dut.dsm_upload_ready) begin
            $display("[%0t] 📤 DSM数据上传: channel=%0d, byte_idx=%0d, data=0x%02X", 
                     $time, dut.u_dsm_handler.upload_channel, dut.u_dsm_handler.upload_byte_index, dut.dsm_upload_data);
        end
        
        // 监控通道切换
        if (dut.u_dsm_handler.upload_channel != prev_upload_channel) begin
            $display("[%0t] 🔄 通道切换: %0d -> %0d (byte_idx重置为:%0d)", 
                     $time, prev_upload_channel, dut.u_dsm_handler.upload_channel, dut.u_dsm_handler.upload_byte_index);
        end
        
        // 监控状态切换
        if (dut.u_dsm_handler.upload_state != prev_upload_state) begin
            $display("[%0t] 🔄 上传状态切换: %0d -> %0d", $time, prev_upload_state, dut.u_dsm_handler.upload_state);
        end
        
        // 监控最终USB输出
        if (usb_upload_valid) begin
            $display("[%0t] 🔗 最终USB输出: data=0x%02X (总计:%0d字节)", $time, usb_upload_data, usb_received_count + 1);
        end
    end
`endif
    //-----------------------------------------------------------------------------
    // 波形转储
    //-----------------------------------------------------------------------------
    initial begin
        $dumpfile("cdc_dsm_tb.vcd");
        $dumpvars(0, cdc_dsm_tb);
    end

endmodule