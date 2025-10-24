# CDC Sequence Generator Testbench - Simulation Guide

## 概述

本仿真测试CDC模块中的序列发生器功能。测试通过USB-CDC命令配置8个独立序列通道，并验证输出波形。

## 测试环境

- **仿真器**: ModelSim (Questa)
- **时钟频率**: 60MHz
- **测试模块**: `cdc_seq_tb`
- **被测模块**: CDC + seq_handler + seq_multichannel + seq_generator

## 文件结构

```
F:/FPGA2025/sim/cdc_seq_tb/
├── cmd.do              - ModelSim仿真脚本（主脚本）
├── README.md           - 本文档
└── (自动生成)
    ├── work/           - 编译库
    ├── gw5a/           - Gowin原语库
    ├── cdc_seq_tb.vcd  - 波形文件
    └── transcript      - 仿真日志
```

## 快速开始

### 方法1: 使用ModelSim GUI

```bash
cd F:\FPGA2025\sim\cdc_seq_tb
vsim
# 在ModelSim控制台执行:
do cmd.do
```

### 方法2: 命令行运行

```bash
cd F:\FPGA2025\sim\cdc_seq_tb
vsim -do cmd.do
```

### 方法3: 使用GTKWave查看波形

```bash
cd F:\FPGA2025\sim\cdc_seq_tb
# 先运行仿真生成VCD文件
vsim -c -do "do cmd.do; quit"
# 然后用GTKWave查看
gtkwave cdc_seq_tb.vcd
```

## 测试用例说明

本测试台包含6个测试用例：

### TEST 1: 通道0 - 1MHz基准，10位序列
```
配置:
  - 通道: 0
  - 基准频率: 1MHz (freq_div = 60)
  - 序列: 0101010101 (10位)
  - 序列数据: 0x0155

预期:
  - 输出频率: 100kHz (1MHz / 10)
  - 每位持续: 1us
  - 完整序列周期: 10us
```

### TEST 2: 通道1 - 2MHz基准，8位序列
```
配置:
  - 通道: 1
  - 基准频率: 2MHz (freq_div = 30)
  - 序列: 11001100 (8位)
  - 序列数据: 0xCC

预期:
  - 输出频率: 250kHz (2MHz / 8)
  - 每位持续: 500ns
  - 完整序列周期: 4us
```

### TEST 3: 通道2 - 4MHz基准，4位序列
```
配置:
  - 通道: 2
  - 基准频率: 4MHz (freq_div = 15)
  - 序列: 1010 (4位)
  - 序列数据: 0x0A

预期:
  - 输出频率: 1MHz (4MHz / 4)
  - 每位持续: 250ns
  - 完整序列周期: 1us
```

### TEST 4: 通道3 - 500kHz基准，2位序列
```
配置:
  - 通道: 3
  - 基准频率: 500kHz (freq_div = 120)
  - 序列: 11 (2位)
  - 序列数据: 0x03

预期:
  - 输出频率: 250kHz (500kHz / 2)
  - 每位持续: 2us
  - 完整序列周期: 4us
```

### TEST 5: 禁用通道0
```
操作: 发送disable命令到通道0
预期: 通道0输出变为0且保持
```

### TEST 6: 多通道同时运行
```
配置所有8个通道:
  - CH0: 100kHz  (10位序列)
  - CH1: 250kHz  (8位序列)
  - CH2: 1MHz    (4位序列)
  - CH3: 250kHz  (2位序列)
  - CH4: 200kHz  (5位序列)
  - CH5: 166kHz  (6位序列)
  - CH6: 83kHz   (12位序列)
  - CH7: 62.5kHz (16位序列)

预期: 所有通道独立运行，互不干扰
```

## 命令格式

序列配置命令 (0xF0):

```
AA 55 F0 00 0D [CH] [EN] [DIV_H] [DIV_L] [LEN] [D0-D7] [CS]
│  │  │  │  │   │    │    └──┬──┘ └──┬──┘ │    └──┬──┘  │
│  │  │  │  │   │    │       │       │     │       │     └─ 校验和
│  │  │  │  │   │    │       │       │     │       └─ 序列数据8字节
│  │  │  │  │   │    │       │       │     └─ 序列长度(1-64位)
│  │  │  │  │   │    │       │       └─ 频率分频器(大端)
│  │  │  │  │   │    └─ 使能标志
│  │  │  │  │   └─ 通道索引(0-7)
│  │  │  │  └─ Payload长度(13)
│  │  │  └─ 命令码
│  │  └─ 帧头
```

示例 (通道0, 1MHz基准, 10位 "0101010101"):
```
AA 55 F0 00 0D 00 01 00 3C 0A 55 01 00 00 00 00 00 00 [CS]
```

## 波形查看指南

### 关键信号组

1. **Top Level**
   - `clk`, `rst_n`: 时钟和复位
   - `usb_data_in`, `usb_data_valid_in`: USB输入数据
   - `seq_pins[7:0]`: 8路序列输出

2. **Protocol Parser**
   - `state`: 协议解析状态机
   - `cmd_out`: 解析出的命令码
   - `parse_done`: 解析完成标志

3. **Command Processor**
   - `state`: 命令处理器状态
   - `cmd_type`: 当前命令类型
   - `cmd_data`: 命令数据字节
   - `cmd_start`, `cmd_done`: 命令开始/结束

4. **SEQ Handler**
   - `handler_state`: 处理器状态 (IDLE/RECEIVING/UPDATE_CONFIG/STROBE)
   - `seq_ch_index`: 目标通道
   - `seq_freq_div`: 频率分频器
   - `seq_length`: 序列长度
   - `seq_data`: 序列数据

5. **SEQ Multi-Channel**
   - `seq_out_vector[0..7]`: 8路独立输出

6. **SEQ CH0 Detail** (通道0详细信息)
   - `clk_div_counter`: 分频计数器 (0到freq_div-1)
   - `bit_clk_tick`: 位时钟脉冲 (每freq_div个周期产生1次)
   - `bit_index`: 当前位索引 (0到seq_len-1循环)
   - `seq_out`: 输出波形

### 验证要点

#### 1. 命令接收验证
- 检查 `Protocol Parser` 状态转换
- 确认 `cmd_type = 0xF0`
- 验证 `parse_done` 在接收完成后变高

#### 2. 配置更新验证
- 观察 `SEQ Handler` 状态: IDLE → RECEIVING → UPDATE_CONFIG → STROBE
- 检查 `seq_update_strobe` 在STROBE状态产生单周期脉冲
- 确认配置值正确写入寄存器

#### 3. 频率验证
以TEST 1为例 (1MHz基准, 10位序列):
```
clk_div_counter: 0→1→2→...→59→0 (循环)
bit_clk_tick:    每60个周期产生1个脉冲
bit_index:       每1us变化一次: 0→1→2→...→9→0
seq_out:         每1us切换: seq_data[0]→seq_data[1]→...→seq_data[9]
```

测量方法:
- 放置光标在两个 `bit_clk_tick` 脉冲之间
- 应该间隔 60 × 16.67ns = 1us
- 完整序列周期 = 10us

#### 4. 序列模式验证
查看 `seq_out` 波形:
```
序列: 0101010101
时间: 0   1   2   3   4   5   6   7   8   9   10us
输出: 0   1   0   1   0   1   0   1   0   1   0 (循环)
```

#### 5. 多通道独立性验证
- 同时查看所有8路 `seq_out_vector`
- 确认各通道频率和模式互不干扰

## 预期输出

### 控制台输出示例

```
[334] Reset released
========================================
[834] ========================================
[834] Sending SEQ CONFIG Command (0xF0)
[834] Channel: 0
[834] Enable: 1
[834] Freq Div: 60 (Base freq: 1000000 Hz)
[834] Seq Len: 10 bits
[834] Seq Data: 0x155
[834] Output Freq: 100000 Hz
[834] ========================================
[5184] SEQ CONFIG command sent
[5184] SEQ Handler State: H_IDLE -> H_RECEIVING
[5434] SEQ Handler State: H_RECEIVING -> H_UPDATE_CONFIG
[5451] SEQ Handler State: H_UPDATE_CONFIG -> H_STROBE
[5468] SEQ Handler State: H_STROBE -> H_IDLE
[5468] CH0: 0 -> 1 (transition #0)
[6501] CH0: 1 -> 0 (transition #1)
[7534] CH0: 0 -> 1 (transition #2)
...

================================================================================
  TEST SUMMARY
================================================================================
Transition counts per channel:
  CH0: 2400 transitions
  CH1: 4000 transitions
  CH2: 8000 transitions
  ...
  ✅ All sequence configuration commands sent successfully
================================================================================
```

## 常见问题排查

### 1. 编译错误

**问题**: `vlog: command not found`
**解决**: 确保ModelSim已添加到PATH，或使用完整路径

**问题**: GOWIN路径错误
**解决**: 修改 `cmd.do` 中的 `GOWIN_PATH` 变量

### 2. 仿真错误

**问题**: 序列输出始终为0
**检查**:
- `enable_regs[channel]` 是否为1
- `freq_div_regs[channel]` 是否非0
- `seq_len_regs[channel]` 是否非0

**问题**: 输出频率不正确
**检查**:
- 测量 `bit_clk_tick` 间隔是否 = `freq_div × 16.67ns`
- 测量完整序列周期是否 = `freq_div × seq_len × 16.67ns`

**问题**: 序列模式错误
**检查**:
- `seq_data` 是否正确（注意小端序）
- `bit_index` 是否正确循环 (0到seq_len-1)

### 3. 波形查看问题

**问题**: 波形太密集
**解决**: 使用 `zoom range` 放大特定时间段
```tcl
wave zoom range 0us 50us
```

**问题**: 找不到信号
**解决**: 检查层次路径是否正确
```tcl
add wave /cdc_seq_tb/dut/u_seq_handler/seq_pins
```

## 性能统计

预期仿真时间: ~5分钟 (取决于CPU性能)
仿真时长: ~700us
VCD文件大小: ~50MB

## 下一步

1. **集成到CDC**: 将seq_handler添加到 `rtl/cdc.v`
2. **引脚约束**: 添加seq_pins到约束文件
3. **硬件测试**: 在实际FPGA上验证
4. **Python工具**: 使用 `seq_command_tool.py` 生成命令

## 参考文档

- [自定义序列发生器说明](../../doc/自定义序列发生器说明.md)
- [USB-CDC通信协议](../../doc/USB-CDC通信协议.md)
- [快速参考](../../doc/SEQ_QUICKREF.md)

---

**作者**: Claude
**日期**: 2025-10-24
**版本**: 1.0
