`timescale 1ns / 1ps
`include "./utils.sv"
//`define DSM_DEBUG  
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
    cdc_us dut(
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
    // DSM Handler 状态监控（新增）
    //-----------------------------------------------------------------------------
    initial begin
        $display("=== DSM Debug Monitors Initialized ===");
        #8000;  // 8us - after command should be fully received
        $display("\n[%0t] ===== DEBUG SNAPSHOT 1 (After command sent) =====", $time);
        $display("Parser: done=%0d, error=%0d, cmd=0x%02X, len=%0d",
                 dut.parser_done, dut.parser_error, dut.cmd_out, dut.len_out);
        $display("Command Bus: start=%0d, type=0x%02X, length=%0d, data_valid=%0d, done=%0d",
                 dut.cmd_start, dut.cmd_type, dut.cmd_length, dut.cmd_data_valid, dut.cmd_done);
        $display("Command Processor State: %0d", dut.u_command_processor.state);
        $display("DSM Handler: state=%0d, channel_mask=0x%02X, measure_start=0x%02X",
                 dut.u_dsm_handler.handler_state, dut.u_dsm_handler.channel_mask,
                 dut.u_dsm_handler.measure_start_reg);
        $display("Ready signals: cmd_ready=%0d, dsm_ready=%0d", dut.cmd_ready, dut.dsm_ready);
        $display("=====================================================\n");

        #20000; // Check again at 26us (after all measurements should be done)
        $display("\n[%0t] ===== DEBUG SNAPSHOT 2 (After measurements) =====", $time);
        $display("DSM Handler: state=%0d, upload_state=%0d",
                 dut.u_dsm_handler.handler_state, dut.u_dsm_handler.upload_state);
        $display("DSM Measurement: all_done=%0d, measure_done=0x%02X",
                 dut.u_dsm_handler.all_done, dut.u_dsm_handler.measure_done);
        $display("Upload: req=%0d, valid=%0d, ready=%0d, data=0x%02X",
                 dut.dsm_upload_req, dut.dsm_upload_valid, dut.dsm_upload_ready, dut.dsm_upload_data);
        $display("=====================================================\n");
    end

    reg [1:0] dsm_handler_state_prev;
    reg [1:0] dsm_upload_state_prev;
    reg [7:0] dsm_measure_start_prev;
    reg [7:0] dsm_measure_done_prev;
    reg       dsm_all_done_prev;

    initial begin
        dsm_handler_state_prev = 0;
        dsm_upload_state_prev = 0;
        dsm_measure_start_prev = 0;
        dsm_measure_done_prev = 0;
        dsm_all_done_prev = 0;
    end

    always @(posedge clk) begin
        // 监控 handler 状态变化
        if (dut.u_dsm_handler.handler_state != dsm_handler_state_prev) begin
            case(dut.u_dsm_handler.handler_state)
                2'b00: $display("[%0t] DSM Handler: IDLE", $time);
                2'b01: $display("[%0t] DSM Handler: RX_CMD (channel_mask=0x%02X)", $time, dut.u_dsm_handler.channel_mask);
                2'b10: $display("[%0t] DSM Handler: MEASURING", $time);
                2'b11: $display("[%0t] DSM Handler: UPLOAD_DATA", $time);
            endcase
            dsm_handler_state_prev = dut.u_dsm_handler.handler_state;
        end

        // 监控上传状态变化
        if (dut.u_dsm_handler.upload_state != dsm_upload_state_prev) begin
            case(dut.u_dsm_handler.upload_state)
                2'b00: $display("[%0t] DSM Upload: IDLE", $time);
                2'b01: $display("[%0t] DSM Upload: SEND (ch=%0d, byte=%0d)", $time,
                        dut.u_dsm_handler.upload_channel, dut.u_dsm_handler.upload_byte_index);
                2'b10: $display("[%0t] DSM Upload: WAIT", $time);
            endcase
            dsm_upload_state_prev = dut.u_dsm_handler.upload_state;
        end

        // 监控测量启动信号
        if (dut.u_dsm_handler.measure_start_reg != dsm_measure_start_prev) begin
            $display("[%0t] DSM measure_start: 0x%02X", $time, dut.u_dsm_handler.measure_start_reg);
            dsm_measure_start_prev = dut.u_dsm_handler.measure_start_reg;
        end

        // 监控测量完成信号
        if (dut.u_dsm_handler.measure_done_sync != dsm_measure_done_prev) begin
            $display("[%0t] DSM measure_done: 0x%02X", $time, dut.u_dsm_handler.measure_done_sync);
            dsm_measure_done_prev = dut.u_dsm_handler.measure_done_sync;
        end

        // 监控所有通道完成信号
        if (dut.u_dsm_handler.all_done != dsm_all_done_prev) begin
            $display("[%0t] DSM all_done: %0d", $time, dut.u_dsm_handler.all_done);
            dsm_all_done_prev = dut.u_dsm_handler.all_done;
        end
    end

    // 监控 DSM 上传握手信号
    always @(posedge clk) begin
        if (dut.dsm_upload_req || dut.dsm_upload_valid) begin
            $display("[%0t] DSM Upload: req=%0d, valid=%0d, ready=%0d, data=0x%02X",
                     $time, dut.dsm_upload_req, dut.dsm_upload_valid,
                     dut.dsm_upload_ready, dut.dsm_upload_data);
        end
    end

    // 监控命令总线信号（检查 DSM 是否接收到命令）
    reg cmd_start_prev = 0;
    always @(posedge clk) begin
        if (dut.cmd_start && !cmd_start_prev) begin
            $display("[%0t] CMD_START pulse detected: cmd_type=0x%02X, cmd_length=%0d",
                     $time, dut.cmd_type, dut.cmd_length);
        end
        cmd_start_prev = dut.cmd_start;

        if (dut.cmd_data_valid) begin
            $display("[%0t] CMD_DATA_VALID: index=%0d, data=0x%02X",
                     $time, dut.cmd_data_index, dut.cmd_data);
        end

        if (dut.cmd_done) begin
            $display("[%0t] CMD_DONE pulse", $time);
        end
    end

    // 监控 parser 和 processor 关键信号
    reg parse_done_prev = 0;
    integer usb_in_count = 0;
    integer usb_pulse_count = 0;
    reg [2:0] parser_state_prev = 0;

    always @(posedge clk) begin
        // Count USB input bytes
        if (usb_data_valid_in) begin
            usb_in_count = usb_in_count + 1;
            $display("[%0t] USB_IN[%0d]: 0x%02X (valid_in=%0d, valid_d1=%0d, pulse=%0d)",
                     $time, usb_in_count-1, usb_data_in, usb_data_valid_in,
                     dut.usb_data_valid_in_d1, dut.usb_data_valid_pulse);
        end

        // Count USB valid pulses that reach parser
        if (dut.usb_data_valid_pulse) begin
            usb_pulse_count = usb_pulse_count + 1;
            $display("[%0t] USB_PULSE[%0d]: 0x%02X -> Parser",
                     $time, usb_pulse_count-1, dut.usb_data_in);
        end

        // Monitor parser state changes
        if (dut.u_parser.state != parser_state_prev) begin
            $display("[%0t] PARSER_STATE: %0d -> %0d", $time, parser_state_prev, dut.u_parser.state);
            parser_state_prev = dut.u_parser.state;
        end

        if (dut.parser_done && !parse_done_prev) begin
            $display("[%0t] PARSER_DONE: cmd=0x%02X, len=%0d", $time, dut.cmd_out, dut.len_out);
        end
        parse_done_prev = dut.parser_done;

        if (dut.parser_error) begin
            $display("[%0t] PARSER_ERROR!", $time);
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
    // 单次DSM测量任务
    //-----------------------------------------------------------------------------
    task automatic run_dsm_test(
        input [7:0] channel_mask,
        input integer ch0_high, input integer ch0_low,
        input integer ch1_high, input integer ch1_low,
        input integer ch2_high, input integer ch2_low,
        input integer ch3_high, input integer ch3_low,
        input integer ch4_high, input integer ch4_low,
        input integer ch5_high, input integer ch5_low,
        input integer ch6_high, input integer ch6_low,
        input integer ch7_high, input integer ch7_low,
        input string test_name
    );
        integer expected_bytes;
        integer i, active_channels;
        begin
            $display("\n=================================================");
            $display("  测试: %s", test_name);
            $display("  通道掩码: 0x%02X", channel_mask);
            $display("=================================================");

            // 计算预期字节数
            active_channels = 0;
            for (i = 0; i < 8; i = i + 1) begin
                if (channel_mask[i]) active_channels = active_channels + 1;
            end
            expected_bytes = active_channels * 9;

            // 重置计数器
            usb_received_count = 0;
            usb_valid_pulse_count = 0;
            dsm_result_count = 0;

            // 确保所有DSM信号初始为0
            dsm_signal_in = 8'h00;
            usb_data_valid_in = 1'b0;
            #(CLK_PERIOD_NS * 200);

            // 发送DSM命令
            $display("[%0t] 发送DSM命令: 通道掩码=0x%02X", $time, channel_mask);
            USB::SendDSMCommand(clk, usb_data_in, usb_data_valid_in, channel_mask, CLK_PERIOD_NS);

            // 等待命令处理
            #(CLK_PERIOD_NS * 500);
            $display("[%0t] 开始生成测试信号", $time);

            // 并行生成所有启用通道的信号
            fork
                // 通道0
                if (channel_mask[0]) begin
                    repeat(10) @(posedge clk);
                    repeat(6) begin
                        dsm_signal_in[0] = 1'b1;
                        repeat(ch0_high) @(posedge clk);
                        dsm_signal_in[0] = 1'b0;
                        repeat(ch0_low) @(posedge clk);
                    end
                end

                // 通道1
                if (channel_mask[1]) begin
                    repeat(10) @(posedge clk);
                    repeat(5) begin
                        dsm_signal_in[1] = 1'b1;
                        repeat(ch1_high) @(posedge clk);
                        dsm_signal_in[1] = 1'b0;
                        repeat(ch1_low) @(posedge clk);
                    end
                end

                // 通道2
                if (channel_mask[2]) begin
                    repeat(10) @(posedge clk);
                    repeat(4) begin
                        dsm_signal_in[2] = 1'b1;
                        repeat(ch2_high) @(posedge clk);
                        dsm_signal_in[2] = 1'b0;
                        repeat(ch2_low) @(posedge clk);
                    end
                end

                // 通道3
                if (channel_mask[3]) begin
                    repeat(10) @(posedge clk);
                    repeat(5) begin
                        dsm_signal_in[3] = 1'b1;
                        repeat(ch3_high) @(posedge clk);
                        dsm_signal_in[3] = 1'b0;
                        repeat(ch3_low) @(posedge clk);
                    end
                end

                // 通道4
                if (channel_mask[4]) begin
                    repeat(10) @(posedge clk);
                    repeat(4) begin
                        dsm_signal_in[4] = 1'b1;
                        repeat(ch4_high) @(posedge clk);
                        dsm_signal_in[4] = 1'b0;
                        repeat(ch4_low) @(posedge clk);
                    end
                end

                // 通道5
                if (channel_mask[5]) begin
                    repeat(10) @(posedge clk);
                    repeat(5) begin
                        dsm_signal_in[5] = 1'b1;
                        repeat(ch5_high) @(posedge clk);
                        dsm_signal_in[5] = 1'b0;
                        repeat(ch5_low) @(posedge clk);
                    end
                end

                // 通道6
                if (channel_mask[6]) begin
                    repeat(10) @(posedge clk);
                    repeat(5) begin
                        dsm_signal_in[6] = 1'b1;
                        repeat(ch6_high) @(posedge clk);
                        dsm_signal_in[6] = 1'b0;
                        repeat(ch6_low) @(posedge clk);
                    end
                end

                // 通道7
                if (channel_mask[7]) begin
                    repeat(10) @(posedge clk);
                    repeat(5) begin
                        dsm_signal_in[7] = 1'b1;
                        repeat(ch7_high) @(posedge clk);
                        dsm_signal_in[7] = 1'b0;
                        repeat(ch7_low) @(posedge clk);
                    end
                end
            join

            $display("[%0t] 信号生成完成，等待测量和上传", $time);
            #(CLK_PERIOD_NS * 5000);

            // 验证接收到的字节数
            $display("\n=== 测试结果 ===");
            $display("预期字节数: %0d", expected_bytes);
            $display("实际接收: %0d", usb_received_count);

            if (usb_received_count == expected_bytes) begin
                $display("✅ 字节数正确！");
            end else begin
                $display("❌ 字节数错误！");
            end

            // 解析和验证结果
            parse_dsm_results;

            $display("=================================================\n");
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
        $display("       包含多轮重复测试验证稳定性");
        $display("===============================================");

        // 测试1: 5通道测试 - 不同占空比
        run_dsm_test(
            .channel_mask(8'b00011111),
            .ch0_high(50), .ch0_low(50),  // 50%
            .ch1_high(25), .ch1_low(75),  // 25%
            .ch2_high(75), .ch2_low(25),  // 75%
            .ch3_high(30), .ch3_low(70),  // 30%
            .ch4_high(80), .ch4_low(20),  // 80%
            .ch5_high(0),  .ch5_low(0),
            .ch6_high(0),  .ch6_low(0),
            .ch7_high(0),  .ch7_low(0),
            .test_name("测试1: 5通道混合占空比")
        );

        // 测试2: 单通道测试 - 验证最简单场景
        run_dsm_test(
            .channel_mask(8'b00000001),
            .ch0_high(40), .ch0_low(60),  // 40%
            .ch1_high(0),  .ch1_low(0),
            .ch2_high(0),  .ch2_low(0),
            .ch3_high(0),  .ch3_low(0),
            .ch4_high(0),  .ch4_low(0),
            .ch5_high(0),  .ch5_low(0),
            .ch6_high(0),  .ch6_low(0),
            .ch7_high(0),  .ch7_low(0),
            .test_name("测试2: 单通道(CH0) 40%占空比")
        );

        // 测试3: 3通道测试 - 验证非连续通道
        run_dsm_test(
            .channel_mask(8'b00010101),  // 通道0,2,4
            .ch0_high(60), .ch0_low(40),  // 60%
            .ch1_high(0),  .ch1_low(0),
            .ch2_high(33), .ch2_low(67),  // 33%
            .ch3_high(0),  .ch3_low(0),
            .ch4_high(90), .ch4_low(10),  // 90%
            .ch5_high(0),  .ch5_low(0),
            .ch6_high(0),  .ch6_low(0),
            .ch7_high(0),  .ch7_low(0),
            .test_name("测试3: 非连续3通道(CH0,2,4)")
        );

        // 测试4: 全8通道测试 - 验证最大负载
        run_dsm_test(
            .channel_mask(8'b11111111),
            .ch0_high(50), .ch0_low(50),  // 50%
            .ch1_high(20), .ch1_low(80),  // 20%
            .ch2_high(40), .ch2_low(60),  // 40%
            .ch3_high(60), .ch3_low(40),  // 60%
            .ch4_high(70), .ch4_low(30),  // 70%
            .ch5_high(30), .ch5_low(70),  // 30%
            .ch6_high(80), .ch6_low(20),  // 80%
            .ch7_high(90), .ch7_low(10),  // 90%
            .test_name("测试4: 全8通道最大负载")
        );

        // 测试5: 重复测试1验证稳定性
        run_dsm_test(
            .channel_mask(8'b00011111),
            .ch0_high(50), .ch0_low(50),
            .ch1_high(25), .ch1_low(75),
            .ch2_high(75), .ch2_low(25),
            .ch3_high(30), .ch3_low(70),
            .ch4_high(80), .ch4_low(20),
            .ch5_high(0),  .ch5_low(0),
            .ch6_high(0),  .ch6_low(0),
            .ch7_high(0),  .ch7_low(0),
            .test_name("测试5: 重复测试1(稳定性验证)")
        );

        // 测试6: 高通道测试 - 验证高位通道
        run_dsm_test(
            .channel_mask(8'b11100000),  // 通道5,6,7
            .ch0_high(0),  .ch0_low(0),
            .ch1_high(0),  .ch1_low(0),
            .ch2_high(0),  .ch2_low(0),
            .ch3_high(0),  .ch3_low(0),
            .ch4_high(0),  .ch4_low(0),
            .ch5_high(45), .ch5_low(55),  // 45%
            .ch6_high(65), .ch6_low(35),  // 65%
            .ch7_high(85), .ch7_low(15),  // 85%
            .test_name("测试6: 高位通道(CH5,6,7)")
        );

        $display("\n===============================================");
        $display("       所有测试完成！");
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