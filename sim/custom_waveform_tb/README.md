# Custom Waveform Handler 仿真测试

## 概述

本目录包含 `custom_waveform_handler.sv` 的最小化仿真测试。

## 文件结构

```
sim/custom_waveform_tb/
├── cmd.do                          # ModelSim 编译运行脚本
├── generate_test_waveforms.py     # 测试波形生成器
├── test_waveforms/                 # 生成的测试波形数据
│   ├── sine_256_*.txt
│   ├── triangle_256_*.txt
│   └── ...
└── README.md                       # 本文件
```

测试平台位于:
- `tb/custom_waveform_tb.sv` - SystemVerilog testbench

被测模块:
- `rtl/dds/custom_waveform_handler.sv` - 自定义波形处理器

## 测试场景

Testbench 当前验证两个场景:
1. **Loop playback**: 将 CSV 中的波形作为循环单包上传, 检查播放保持有效。
2. **Single-pass playback**: 使用相同波形上传但禁用循环, 断言播放自动停止。

## 运行仿真

### 方法1: 使用 ModelSim GUI

```bash
cd C:\Development\GOWIN\FPGA2025\sim\custom_waveform_tb
modelsim -do cmd.do
```

脚本会自动编译依赖、加载 CSV 波形并运行完整测试序列。

### 方法2: 命令行运行

```bash
cd C:\Development\GOWIN\FPGA2025\sim\custom_waveform_tb

# 编译
vlib work
vlog -sv ../../rtl/dds/custom_waveform_handler.sv
vlog -sv ../../tb/custom_waveform_tb.sv

# 运行
vsim -c -do "run -all; quit" work.custom_waveform_tb
```

### 方法3: 批处理运行

```bash
# 从项目根目录
modelsim -do sim/custom_waveform_tb/cmd.do
```

## 生成测试波形数据

`custom_waveform_tool.py` 在 GUI 或命令行下生成 CSV(每行一个 14bit 整数采样值)。GUI 基于 PySide6, 启动示例: `python software/custom_waveform_tool.py --gui --port COM3`，可直接设置导出文件路径与名称。命令行模式可用 `--freq`、`--sample-rate` 指定输出频率与播放采样率, 例如: `python software/custom_waveform_tool.py --generate sine --samples 256 --freq 1500 --sample-rate 640000 --export sim/custom_waveform_tb/waveform_custom.csv`。仿真默认读取 `sim/custom_waveform_tb/waveform_1760523841.csv`; 也可以在仿真命令行追加 `+WAVEFORM=relative/path.csv` 指定其它文件。

## 查看仿真结果

### 控制台输出

仿真过程会打印关键日志:
```
========================================
Test 1: Upload 256-sample sine wave
========================================
[16766] Command 0xFC sent, length=519
[16766] Waveform uploaded: control=0x04, length=256, samples=256

[123456] *** Playback STARTED ***
[133456] DAC output: 0x2000 (8192)
[143456] DAC output: 0x2324 (8996)
...
```

### 波形文件

仿真会生成 `dac_output.txt`,包含所有DAC输出值:
`dac_output.txt` 记录正在播放时的每个采样点, 便于后处理或绘图分析。

### VCD 波形文件

自动生成 `custom_waveform_tb.vcd`,可用GTKWave查看:
```bash
gtkwave custom_waveform_tb.vcd
```

## 关键信号说明

### 命令接口信号
- `cmd_type`: 0xFC(自定义波形命令)
- `cmd_start`: 命令开始脉冲
- `cmd_data_valid`: 数据字节有效
- `cmd_done`: 命令完成脉冲
- `cmd_ready`: Handler就绪信号

### 内部状态信号
- `handler_state`: 状态机状态
  - `000`: H_IDLE
  - `001`: H_RECEIVING
  - `010`: H_PARSE_HEADER
  - `011`: H_PROCESS

### 播放控制信号
- `play_enable`: 播放使能(clk域)
- `play_enable_sync2`: 同步后的播放使能(dac_clk域)
- `phase_acc`: DDS相位累加器
- `ram_rd_addr`: RAM读地址
- `playing`: 播放状态输出

### DAC输出
- `dac_data`: 14位DAC输出值
  - 0x0000: 最小值
  - 0x2000: 中间值(8192)
  - 0x3FFF: 最大值(16383)

## 验证要点

### 1. 命令接收验证
- [ ] cmd_ready 在 IDLE/RECEIVING 状态为高
- [ ] 数据按顺序接收到 header_buffer 和 RAM
- [ ] 状态机正确转换: IDLE → RECEIVING → PARSE_HEADER → PROCESS → IDLE

### 2. RAM 写入验证
- [ ] ram_wr_en 在接收波形数据时拉高
- [ ] ram_wr_addr 从0开始递增
- [ ] 采样点正确打包(小端模式,14位有效)

### 3. 跨时钟域同步验证
- [ ] play_enable 经过两级触发器同步到 dac_clk 域
- [ ] waveform_length 和 sample_rate_word 正确同步

### 4. 播放控制验证
- [ ] 启动命令后 playing 信号拉高
- [ ] 相位累加器按 sample_rate_word 递增
- [ ] ram_rd_addr 正确映射相位累加器高位
- [ ] 循环模式: 地址回绕到0
- [ ] 单次模式: 播放完成后自动停止

### 5. DAC 输出验证
- [ ] 输出波形与输入波形一致
- [ ] 频率符合 sample_rate_word 计算值
- [ ] 停止时输出 0x2000(中间值)

## 常见问题

### Q1: 仿真编译错误 "custom_waveform_handler not found"
**A**: 确保 `rtl/dds/custom_waveform_handler.sv` 存在并使用 `-sv` 选项编译。

### Q2: 波形窗口显示空白
**A**: 运行 `wave zoom full` 或手动调整时间轴范围。

### Q3: DAC输出全为0x2000
**A**: 检查:
1. 是否发送了启动命令(0x06/0x02)
2. play_enable_sync2 是否为高
3. waveform_length 是否正确同步

### Q4: 播放频率不正确
**A**: 重新计算 sample_rate_word:
```
sample_rate_word = (输出频率 × 波形点数 × 2^20) / 200MHz
```

### Q5: 分包传输失败
**A**: 检查:
1. 首包控制字为 0x00
2. 续包控制字为 0x01
3. write_addr 在续包时继续递增

## 扩展测试

### 添加新测试场景

在 `tb/custom_waveform_tb.sv` 的 `initial begin` 块末尾添加:

```systemverilog
$display("\n========================================");
$display("Test 7: Your test name");
$display("========================================");

// 你的测试代码
upload_waveform_single_packet(...);
send_control_command(...);

#观察时间;
```

### 使用真实波形文件

将生成的波形加载到testbench:

```systemverilog
reg [13:0] external_waveform [0:1023];
initial begin
    $readmemh("test_waveforms/sine_1024_hex.txt", external_waveform);
end

// 然后在测试中使用
upload_waveform_single_packet(
    8'h04, 16'd1024, 32'd10995116,
    external_waveform, 1024
);
```

## 性能指标

从仿真中可以测量:

- **命令处理延迟**: cmd_start 到 第一个 ram_wr_en 的时间
- **RAM写入带宽**: 60MHz clk下,每2个周期写入1个采样点
- **跨时钟域延迟**: play_enable 到 playing 的同步延迟(~3个 dac_clk 周期)
- **相位累加精度**: phase_acc 的增量与 sample_rate_word 是否一致

## 参考资料

- [USB-CDC通信协议.md](../../doc/USB-CDC通信协议.md) - 0xFC命令规范
- [自定义波形集成指南.md](../../doc/自定义波形集成指南.md) - 系统集成说明
- [custom_waveform_tool.py](../../software/custom_waveform_tool.py) - PC端工具

## 维护记录

- 2025-01-15: 初始版本,包含6个基础测试场景
- 添加测试波形生成器
- 添加VCD和文本输出
