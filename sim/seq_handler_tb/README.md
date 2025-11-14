# Standalone Sequence Handler Simulation

## 简介

独立测试 `seq_handler` 模块，不依赖 CDC 或其他复杂模块。

## 文件

- **cmd.do** - ModelSim 仿真脚本
- **被测模块**:
  - `../../rtl/pwm/seq_generator.v`
  - `../../rtl/pwm/seq_multichannel.sv`
  - `../../rtl/pwm/seq_handler.v`
- **测试台**: `../../tb/seq_handler_tb.v`

## 快速运行

```bash
cd F:\FPGA2025\sim\seq_handler_tb
vsim -do cmd.do
```

或在 ModelSim GUI 中：
```tcl
do cmd.do
```

## 测试内容

测试台会自动运行 6 个测试：

### Test 1: 通道0 - 1MHz基准, 10位序列
- 基准频率: 1MHz (freq_div=60)
- 序列: 0101010101 (0x0155)
- 预期输出: 100kHz

### Test 2: 通道1 - 2MHz基准, 8位序列
- 基准频率: 2MHz (freq_div=30)
- 序列: 11001100 (0xCC)
- 预期输出: 250kHz

### Test 3: 通道2 - 16位序列
- 基准频率: 4MHz (freq_div=15)
- 序列: 1010101011110000 (0xAAF0)
- 预期输出: 250kHz

### Test 4: 禁用测试
- 发送 disable 命令到通道0
- 预期: 输出变为0

### Test 5: 重新使能
- 重新配置通道0
- 验证可以重新启动

### Test 6: 多通道同时运行
- 配置所有8个通道
- 验证各通道独立工作

## 波形查看要点

### 1. 命令处理流程

观察 **SEQ Handler** 组：
```
handler_state:
  H_IDLE (0)
    ↓ (收到cmd_start)
  H_RECEIVING (1)
    ↓ (收到cmd_done)
  H_UPDATE_CONFIG (2)
    ↓ (配置寄存器)
  H_STROBE (3)
    ↓ (发出update脉冲)
  H_IDLE (0) - 完成
```

### 2. 频率验证 (以CH0为例)

在 **CH0 Detail** 组：

**分频计数器**:
```
clk_div_counter: 0→1→2→...→59→0 (循环)
                 └─60个周期─┘
```

**位时钟脉冲**:
```
bit_clk_tick: 每60个系统时钟产生1个脉冲
              间隔 = 60 × 16.67ns = 1us
```

测量方法：
1. 在波形窗口放置两个光标
2. 对准两个相邻的 `bit_clk_tick` 上升沿
3. 查看时间差应为 1us (1000ns)

### 3. 序列模式验证

**位索引循环**:
```
bit_index: 0→1→2→...→9→0 (对于10位序列)
           每个值持续1us
```

**序列输出**:
```
seq_data = 0x0155 = 0b0101010101

bit_index:  0  1  2  3  4  5  6  7  8  9  0  1
seq_data[]: 0  1  0  1  0  1  0  1  0  1  0  1
seq_out:    ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
            0  1  0  1  0  1  0  1  0  1  0  1
```

### 4. 多通道独立性

观察 **All 8 Channels** 组：
- 各通道应该以不同频率运行
- 各通道模式应该独立
- 禁用的通道输出为0

## 预期控制台输出

```
=== Test 1: Configure CH0 with 0101010101 @ 1MHz ===
Command sent: CH=0, EN=1, DIV=60, LEN=10, DATA=0x155

=== Test 2: Configure CH1 with 11001100 @ 2MHz ===
Command sent: CH=1, EN=1, DIV=30, LEN=8, DATA=0xcc

=== Test 3: Configure CH2 with 16-bit pattern @ 4MHz ===
Command sent: CH=2, EN=1, DIV=15, LEN=16, DATA=0xaaf0

=== Test 4: Disable CH0 ===
Command sent: CH=0, EN=0, DIV=60, LEN=10, DATA=0x155

=== Test 5: Re-enable CH0 with new pattern ===
Command sent: CH=0, EN=1, DIV=120, LEN=4, DATA=0xa

=== Test 6: Configure all 8 channels ===
Command sent: CH=3, EN=1, DIV=60, LEN=2, DATA=0x3
Command sent: CH=4, EN=1, DIV=60, LEN=3, DATA=0x5
Command sent: CH=5, EN=1, DIV=60, LEN=4, DATA=0x9
Command sent: CH=6, EN=1, DIV=60, LEN=5, DATA=0x15
Command sent: CH=7, EN=1, DIV=60, LEN=6, DATA=0x2a

=== Simulation completed ===
```

## 故障排查

### 问题：seq_out 始终为0

**检查**:
1. `enable_regs[channel]` 是否为1
2. `freq_div_regs[channel]` 是否非0
3. `seq_len_regs[channel]` 是否非0

### 问题：频率不对

**检查**:
1. 测量 `bit_clk_tick` 间隔
2. 应该 = `freq_div × 16.67ns`
3. 例如 freq_div=60 → 间隔=1us

### 问题：序列模式错误

**检查**:
1. `seq_data_regs[channel]` 值是否正确
2. `bit_index` 是否正确循环 (0到len-1)
3. 注意数据是**小端序**存储

## 仿真时间

- 编译时间: ~10秒
- 仿真时长: ~350us (硬件时间)
- 实际耗时: ~30秒

## 成功标志

✅ 所有命令成功发送
✅ handler_state 正确转换
✅ 各通道配置正确写入
✅ 输出频率符合预期
✅ 序列模式正确循环
✅ 多通道互不干扰

---

**下一步**: 验证通过后，可以运行 CDC 集成测试
