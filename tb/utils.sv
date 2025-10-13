`ifndef __COMMON_SV__
`define __COMMON_SV__

        package SimSrcGen;
            task automatic GenClk(
                    ref logic clk, input realtime delay, realtime period
                );
                clk = 1'b0;
                #delay;
                forever
                    #(period/2) clk = ~clk;
            endtask
            task automatic GenRst(
                    ref logic clk,
                    ref logic rst,
                    input int start,
                    input int duration
                );
                rst = 1'b0;
                repeat(start) @(posedge clk);
                rst = 1'b1;
                repeat(duration) @(posedge clk);
                rst = 1'b0;
            endtask
            task automatic GenRstN(
                    ref logic clk,
                    ref logic rst,
                    input int start,
                    input int duration
                );
                rst = 1'b1;
                repeat(start) @(posedge clk);
                rst = 1'b0;
                repeat(duration) @(posedge clk);
                rst = 1'b1;
            endtask
            task automatic KeyPress(ref logic key, input realtime t);
                for(int i = 0; i < 30; i++) begin
                    #0.11ms key = '0;
                    #0.14ms key = '1;
                end
                #t;
                key = '0;
            endtask
            task automatic QuadEncGo(ref logic a, b, input logic ccw, realtime qprd);
                a = 0;
                b = 0;
                if(!ccw) begin
                    #qprd a = 1;
                    #qprd b = 1;
                    #qprd a = 0;
                    #qprd b = 0;
                end
                else begin
                    #qprd b = 1;
                    #qprd a = 1;
                    #qprd b = 0;
                    #qprd a = 0;
                end
            endtask
        endpackage

        package USB;
            task automatic SendByte(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] byte_to_send,
                input realtime clk_period_ns
            );
                begin
                    @(posedge clk);
                    #1;  // 在时钟边沿后稍微延迟，避免竞争
                    usb_data_out = byte_to_send;
                    usb_data_valid_out = 1'b1;
                    @(posedge clk);
                    #1;
                    usb_data_valid_out = 1'b0;
                    #(clk_period_ns * 10);
                end
            endtask

            task automatic SendProtocolFrame(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] cmd,
                input [7:0] len_h,
                input [7:0] len_l,
                input [7:0] data_bytes[],
                input realtime clk_period_ns
            );
                automatic reg [7:0] checksum;
                automatic integer i;
                automatic integer data_len;
                begin
                    data_len = data_bytes.size();
                    
                    checksum = cmd + len_h + len_l;
                    for (i = 0; i < data_len; i++) begin
                        checksum = checksum + data_bytes[i];
                    end
                    
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'hAA, clk_period_ns); // SOF1
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'h55, clk_period_ns); // SOF2
                    SendByte(clk, usb_data_out, usb_data_valid_out, cmd, clk_period_ns);    // CMD
                    SendByte(clk, usb_data_out, usb_data_valid_out, len_h, clk_period_ns);  // LEN_H
                    SendByte(clk, usb_data_out, usb_data_valid_out, len_l, clk_period_ns);  // LEN_L
                    
                    for (i = 0; i < data_len; i++) begin
                        SendByte(clk, usb_data_out, usb_data_valid_out, data_bytes[i], clk_period_ns);
                    end
                    
                    SendByte(clk, usb_data_out, usb_data_valid_out, checksum, clk_period_ns);
                    
                    #(clk_period_ns * 100);
                end
            endtask

            task automatic SendDSMCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] channel_mask,
                input realtime clk_period_ns
            );
                automatic reg [7:0] data_array[1];
                begin
                    $display("[%0t] 发送DSM命令: 通道掩码=0x%02X (二进制:%08b)", $time, channel_mask, channel_mask);
                    
                    data_array[0] = channel_mask;
                    SendProtocolFrame(clk, usb_data_out, usb_data_valid_out, 
                                    8'h0A, 8'h00, 8'h01, data_array, clk_period_ns);
                end
            endtask

            task automatic SendPWMCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] channel,
                input [15:0] period,        // 16位周期 
                input [15:0] duty_cycle,    // 16位占空比
                input realtime clk_period_ns
            );
                automatic reg [7:0] data_array[5];
                begin
                    $display("[%0t] 发送PWM命令: 通道=%0d, 周期=%0d, 占空比=%0d", $time, channel, period, duty_cycle);
                    
                    data_array[0] = channel;
                    data_array[1] = period[15:8];     // 周期高字节
                    data_array[2] = period[7:0];      // 周期低字节
                    data_array[3] = duty_cycle[15:8]; // 占空比高字节
                    data_array[4] = duty_cycle[7:0];  // 占空比低字节
                    
                    SendProtocolFrame(clk, usb_data_out, usb_data_valid_out, 
                                    8'hFE, 8'h00, 8'h05, data_array, clk_period_ns);
                end
            endtask

            task automatic SendDACCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] waveform_type,  // 0: 正弦波, 1: 三角波, 2: 锯齿波, 3: 方波
                input [31:0] frequency_word,
                input [31:0] phase_word,
                input realtime clk_period_ns
            );
                automatic reg [7:0] data_array[9];
                begin
                    $display("[%0t] 发送DAC命令: 波形=%0d, 频率字=0x%08X, 相位字=0x%08X", 
                            $time, waveform_type, frequency_word, phase_word);
                    
                    data_array[0] = waveform_type;
                    data_array[1] = frequency_word[31:24];
                    data_array[2] = frequency_word[23:16];
                    data_array[3] = frequency_word[15:8];
                    data_array[4] = frequency_word[7:0];
                    data_array[5] = phase_word[31:24];
                    data_array[6] = phase_word[23:16];
                    data_array[7] = phase_word[15:8];
                    data_array[8] = phase_word[7:0];
                    
                    SendProtocolFrame(clk, usb_data_out, usb_data_valid_out, 
                                    8'hFD, 8'h00, 8'h09, data_array, clk_period_ns);
                end
            endtask

            task automatic SendUARTConfigCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [31:0] baud_rate,
                input [7:0] data_bits,
                input [7:0] stop_bits,
                input [7:0] parity,
                input realtime clk_period_ns
            );
                automatic reg [7:0] data_array[7];
                begin
                    $display("[%0t] 发送UART配置命令: 波特率=%0d, 数据位=%0d, 停止位=%0d, 校验=%0d", 
                            $time, baud_rate, data_bits, stop_bits, parity);
                    
                    data_array[0] = baud_rate[31:24];
                    data_array[1] = baud_rate[23:16];
                    data_array[2] = baud_rate[15:8];
                    data_array[3] = baud_rate[7:0];
                    data_array[4] = data_bits;
                    data_array[5] = stop_bits;
                    data_array[6] = parity;
                    
                    SendProtocolFrame(clk, usb_data_out, usb_data_valid_out, 
                                    8'h07, 8'h00, 8'h07, data_array, clk_period_ns);
                end
            endtask

            task automatic SendUARTDataCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] uart_data[],
                input realtime clk_period_ns
            );
                automatic integer data_len;
                begin
                    data_len = uart_data.size();
                    $display("[%0t] 发送UART数据命令: 数据长度=%0d字节", $time, data_len);
                    
                    SendProtocolFrame(clk, usb_data_out, usb_data_valid_out, 
                                    8'h08, data_len[15:8], data_len[7:0], uart_data, clk_period_ns);
                end
            endtask

            task automatic SendEmptyDataCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input [7:0] cmd,
                input realtime clk_period_ns
            );
                begin
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'hAA, clk_period_ns); // SOF1
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'h55, clk_period_ns); // SOF2
                    SendByte(clk, usb_data_out, usb_data_valid_out, cmd, clk_period_ns);    // CMD
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'h00, clk_period_ns); // LEN_H
                    SendByte(clk, usb_data_out, usb_data_valid_out, 8'h00, clk_period_ns); // LEN_L
                    SendByte(clk, usb_data_out, usb_data_valid_out, cmd, clk_period_ns);    // 校验和 = cmd + 0 + 0
                    
                    #(clk_period_ns * 100);
                end
            endtask

            task automatic SendUARTReceiveCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input realtime clk_period_ns
            );
                begin
                    $display("[%0t] 发送UART接收命令", $time);
                    SendEmptyDataCommand(clk, usb_data_out, usb_data_valid_out, 8'h09, clk_period_ns);
                end
            endtask

            task automatic SendHeartbeatCommand(
                ref logic clk,
                ref logic [7:0] usb_data_out,
                ref logic usb_data_valid_out,
                input realtime clk_period_ns
            );
                begin
                    $display("[%0t] 发送心跳测试命令", $time);
                    SendEmptyDataCommand(clk, usb_data_out, usb_data_valid_out, 8'hFF, clk_period_ns);
                end
            endtask

            function automatic [31:0] CalcFrequencyWord(
                input real target_freq_hz,
                input real dac_clock_freq_hz
            );
                automatic real freq_word_real;
                automatic integer freq_word_int;
                begin
                    freq_word_real = (target_freq_hz * (2.0**32)) / dac_clock_freq_hz;
                    freq_word_int = integer'(freq_word_real);
                    CalcFrequencyWord = freq_word_int;
                    $display("计算频率字: 目标频率=%.0fHz, DAC时钟=%.0fHz, 频率字=0x%08X", 
                            target_freq_hz, dac_clock_freq_hz, CalcFrequencyWord);
                end
            endfunction

            function automatic [31:0] CalcPhaseWord(
                input real phase_deg
            );
                automatic real phase_word_real;
                automatic integer phase_word_int;
                begin
                    phase_word_real = (phase_deg * (2.0**32)) / 360.0;
                    phase_word_int = integer'(phase_word_real);
                    CalcPhaseWord = phase_word_int;
                    $display("计算相位字: 目标相位=%.1f度, 相位字=0x%08X", phase_deg, CalcPhaseWord);
                end
            endfunction

        endpackage

        package CombFunctions;
`define DEF_PRIO_ENC(fname, ow) \
	function automatic logic [ow - 1 : 0] fname( \
		input logic [2**ow - 1 : 0] in \
	); \
		fname = '0; \
		for(integer i = 2**ow - 1; i >= 0; i--) begin \
			if(in[i]) fname = ow'(i); \
		end \
	endfunction

        endpackage

        package Fixedpoint;
            let max(x, y) = x > y? x : y;
`define DEF_REAL_TO_Q(name, i, f) \
    let name(x) = ((i)+(f))'(integer(x * (2**(f))));
`define DEF_Q_TO_REAL(name, i, f) \
    let name(x) = real'($signed(x)) / 2.0 ** (f);
`define DEF_FP_ADD(name, i0, f0, i1, f1, fr) \
    let name(x, y) = \
    ((f0) >= (f1)) ? \
        (   (  max((i0),(i1))+(f0))'(x) + \
            ( (max((i0),(i1))+(f0))'(y) <<< ((f0)-(f1)) ) \
        ) >>> ((f0)-(fr)) : \
        (   ( (max((i0),(i1))+(f1))'(x) <<< ((f1)-(f0)) ) + \
              (max((i0),(i1))+(f1))'(y) \
        ) >>> ((f1)-(fr));
`define DEF_FP_MUL(name, i0, f0, i1, f1, fr) \
    let name(x, y) = \
    (   ((i0)+(i1)+(f0)+(f1))'(x) * ((i0)+(i1)+(f0)+(f1))'(y) \
    ) >>> ((f0)+(f1)-(fr));
            // // if you need DEF_FP_MUL and your compiler doesn't support "let":
            // `define DEF_FP_MUL(name, i0, f0, i1, f1, fr) \
            //     function automatic signed [(i0)+(i1)+(fr)-1:0] name(input signed [(i0)+(f0)-1:0] x, input signed [(i1)+(f1)-1:0] y); \
            //         name = (((i0)+(i1)+(f0)+(f1))'(x) * ((i0)+(i1)+(f0)+(f1))'(y)) >>> ((f0)+(f1)-(fr)); \
            //     endfunction

`define DEF_CPLX_CALC(typename, addname, subname, mulname, i, f) \
    typedef struct { \
        logic signed [(i)+(f)-1:0] re; \
        logic signed [(i)+(f)-1:0] im; \
    } typename; \
    function automatic typename mulname(typename a, typename b, logic sc); \
        mulname.re = ( (2*(i)+2*(f))'(a.re) * b.re - (2*(i)+2*(f))'(a.im) * b.im ) >>> ((f)+sc); \
        mulname.im = ( (2*(i)+2*(f))'(a.re) * b.im + (2*(i)+2*(f))'(a.im) * b.re ) >>> ((f)+sc); \
    endfunction \
    function automatic typename addname(typename a, typename b, logic sc); \
        addname.re = ( ((i)+(f)+1)'(a.re) + b.re ) >>> sc; \
        addname.im = ( ((i)+(f)+1)'(a.im) + b.im ) >>> sc; \
    endfunction \
    function automatic typename subname(typename a, typename b, logic sc); \
        subname.re = ( ((i)+(f)+1)'(a.re) - b.re ) >>> sc; \
        subname.im = ( ((i)+(f)+1)'(a.im) - b.im ) >>> sc; \
    endfunction

        endpackage

`endif
