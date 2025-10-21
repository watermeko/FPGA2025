# DC模块仿真验证指南

## 快速开始

### 方法1：ModelSim GUI（推荐）

1. **打开ModelSim**
   ```
   启动 ModelSim (Questa Sim)
   ```

2. **切换到仿真目录**
   ```tcl
   cd F:/FPGA2025/sim/cdc_dc_tb
   ```

3. **运行仿真脚本**
   ```tcl
   do cmd.do
   ```

4. **等待编译和仿真完成** (~30秒)

5. **查看波形窗口**
   - 自动打开，包含7个信号组
   - 重点关注：DC Handler, MUX Arbitration, USB Upload

---

### 方法2：命令行模式

```bash
cd F:\FPGA2025\sim\cdc_dc_tb
vsim -do cmd.do
```

---

## 仿真测试内容

仿真会自动运行**5个测试用例**：

### Test 1: 1MHz 采样 - 静态模式 0xAA
```
命令: AA 55 0B 00 02 00 3C 49
输入: 10101010 (0xAA)
持续: 100μs
预期: ~100个采样，全部为 0xAA
```

### Test 2: 2MHz 采样 - 静态模式 0x55
```
命令: AA 55 0B 00 02 00 1E 2B
输入: 01010101 (0x55)
持续: 50μs
预期: ~100个采样，全部为 0x55
```

### Test 3: 500kHz 采样 - 静态模式 0xFF
```
命令: AA 55 0B 00 02 00 78 85
输入: 11111111 (0xFF)
持续: 200μs
预期: ~100个采样，全部为 0xFF
```

### Test 4: 1MHz 采样 - 动态模式
```
命令: AA 55 0B 00 02 00 3C 49
输入: 0x11 → 0x22 → 0x44 → 0x88 (每30μs变化)
预期: 每个模式约30个采样
```

### Test 5: 1.2MHz 最大采样率
```
命令: AA 55 0B 00 02 00 32 3F
输入: 10101010 (0xAA)
持续: 83μs
预期: ~100个采样，验证最大带宽
```

---

## 关键验证点

### ✅ 必须通过的检查项

1. **命令解析正确**
   - `u_parser/parse_done` 应在收到完整帧后脉冲
   - `u_parser/cmd_out` 应为 `0x0B` (启动) 或 `0x0C` (停止)
   - `u_parser/parse_error` 应始终为 0

2. **DC Handler 状态转换**
   ```
   H_IDLE (0) → H_RX_CMD (1) → H_CAPTURING (2)
   ```
   - 查看信号：`dut/u_dc_handler/handler_state`

3. **MUX 仲裁正确**
   - `dc_upload_active` 在捕获期间为高
   - `final_upload_source` 在捕获期间 = `0x0B`
   - `final_upload_data` 应匹配 `dc_signal_in`

4. **采样率正确**
   - `sample_tick` 周期 = 分频系数 × 16.67ns
   - 例如：divider=60 → 周期 = 1μs (1MHz)

5. **数据正确性**
   - `usb_upload_data` 应等于 `dc_signal_in`
   - **无协议头**（直通模式）
   - 连续字节流

---

## 波形窗口信号组

### 1. Top Level - 基本信号
- `clk` - 系统时钟 (60MHz)
- `rst_n` - 复位信号
- `usb_data_in` - USB输入命令字节
- `usb_data_valid_in` - 命令有效信号
- `dc_signal_in[7:0]` - 8通道输入 (二进制显示)

### 2. Protocol Parser - 帧解析
- `state` - 解析器状态机
- `parse_done` - 解析完成脉冲
- `parse_error` - ⚠️ 解析错误（应为0）
- `cmd_out` - 提取的命令码
- `len_out` - 数据长度

### 3. Command Processor - 命令分发
- `state` - 命令处理器状态
- `cmd_type` - 当前命令类型
- `cmd_start` - 命令启动信号
- `cmd_done` - 命令完成信号
- `cmd_ready` - 所有handler就绪

### 4. DC Handler - 数字捕获核心 ⭐
- **状态机**
  - `handler_state` - 主状态：0=IDLE, 1=RX_CMD, 2=CAPTURING
  - `upload_state` - 上传状态：0=IDLE, 1=SEND, 2=WAIT

- **采样控制**
  - `sample_divider` - 分频系数配置
  - `sample_counter` - 当前计数值
  - `sample_tick` - 采样触发脉冲 ⭐
  - `capture_enable` - 捕获使能

- **数据通路**
  - `captured_data` - 捕获的原始数据
  - `captured_data_sync` - 同步后的数据
  - `new_sample_flag` - 新采样标志

- **上传接口**
  - `upload_active` - 上传激活（MUX选择信号）
  - `upload_req` - 上传请求
  - `upload_data` - 上传数据
  - `upload_valid` - 数据有效
  - `upload_ready` - 处理器就绪

### 5. MUX Arbitration - 数据路径选择 ⭐
- **DC直通路径**
  - `dc_upload_active` - DC激活标志
  - `dc_upload_data` - DC数据
  - `dc_upload_valid` - DC有效信号

- **合并路径（其他模块）**
  - `merged_upload_data` - 协议封装数据
  - `merged_upload_source` - 数据源标识

- **最终输出**
  - `final_upload_data` - MUX后的数据 ⭐
  - `final_upload_source` - 最终数据源 (应为0x0B)
  - `final_upload_valid` - 最终有效信号

### 6. USB Upload - USB输出
- `usb_upload_data` - 最终USB输出 ⭐
- `usb_upload_valid` - 输出有效信号
- `usb_received_count` - 接收字节计数
- `sample_count` - 采样计数
- `error_count` - 错误计数（应为0）

### 7. TB Status - 测试台状态
- `expected_pattern` - 预期模式
- `error_count` - 检测到的错误数

---

## 成功标准

仿真成功的标志：

```
Console 输出:
========================================
All Tests Passed!
========================================
Total Errors: 0
```

**波形验证：**
1. ✅ `parse_error` = 0 (全程无错误)
2. ✅ `handler_state` 转换到 CAPTURING (2)
3. ✅ `dc_upload_active` = 1 (捕获期间)
4. ✅ `final_upload_source` = 0x0B (DC数据源)
5. ✅ `usb_upload_data` = `dc_signal_in` (数据匹配)
6. ✅ `error_count` = 0 (TB检测无错误)

---

## 故障排查

### 问题1：parse_error 为 1

**原因：** 校验和错误或帧格式错误

**检查：**
```
查看波形：
- u_parser/uart_rx_data - 接收的字节流
- u_parser/checksum - 计算的校验和
```

**解决：** 修改测试台的 `send_dc_start_command` 任务

---

### 问题2：handler_state 停在 H_IDLE

**原因：** 命令未被识别或cmd_ready=0

**检查：**
```
- dut/cmd_type 应为 0x0B
- dut/cmd_start 应有脉冲
- dut/u_dc_handler/cmd_ready 应为1
```

**解决：** 检查 `cdc.v` 中 DC handler 是否正确实例化

---

### 问题3：dc_upload_active 始终为 0

**原因：** Handler未进入CAPTURING状态

**检查：**
```
- handler_state 是否到达 2 (H_CAPTURING)
- capture_enable 是否为 1
- sample_divider 是否正确配置
```

---

### 问题4：usb_upload_data 无数据

**原因：** MUX选择错误或upload_valid未触发

**检查：**
```
- dc_upload_active 应为 1
- dc_upload_valid 应有周期性脉冲
- processor_upload_ready 应为 1
- final_upload_valid 应跟随 dc_upload_valid
```

---

### 问题5：数据不匹配

**原因：** 采样同步或数据通路问题

**检查：**
```
对比信号：
- dc_signal_in (输入)
- captured_data (第一级锁存)
- captured_data_sync (第二级锁存)
- upload_data (上传数据)
- usb_upload_data (最终输出)
```

**注意：** 由于双缓冲，首个采样可能显示旧值（正常现象）

---

## 查看仿真日志

仿真过程中会生成详细日志：

```
F:\FPGA2025\sim\cdc_dc_tb\simulation.log
```

**查找关键信息：**
```bash
# 查看状态转换
grep "State" simulation.log

# 查看采样数据
grep "Sample" simulation.log

# 查看错误
grep "ERROR\|FAIL" simulation.log
```

---

## 预期Console输出示例

```
# Compiling all design and testbench files into './work' library...
...
# Starting simulation...
# Loading work.cdc_dc_tb
# Adding waveforms...

[0] ========================================
[0] Starting CDC DC Integration Test
[0] ========================================
[0] Reset sequence initiated...

[1000] ========================================
[1000] TEST 1: Static Pattern 0xAA @ 1MHz
[1000] ========================================

[1000] Sending DC START Command (0x0B)
[1000] Divider: 60 (Sample rate: 1000000 Hz)
[1167] DC START command sent, waiting for capture...

[1500] Handler State: H_IDLE → H_RX_CMD
[1834] Handler State: H_RX_CMD → H_CAPTURING
[1834] Capture Started!

[2000] Sample #1: 0xAA (Expected: 0xAA) ✓
[3000] Sample #2: 0xAA (Expected: 0xAA) ✓
...
[101000] Sample #100: 0xAA (Expected: 0xAA) ✓

[101000] Sending DC STOP Command (0x0C)
[101167] DC STOP command sent
[101334] Handler State: H_CAPTURING → H_IDLE
[101334] Capture Stopped!

[101334] Test 1 Complete: 100 samples, 0 errors ✓

...

========================================
All Tests Passed!
========================================
Total Samples: 500
Total Errors: 0
========================================
Simulation completed successfully!
```

---

## 性能分析

### 从仿真中提取的指标

1. **采样精度**
   - 测量 `sample_tick` 间隔
   - 应 = divider × 16.67ns ± 1个时钟周期

2. **上传延迟**
   - 从 `sample_tick` 到 `usb_upload_valid`
   - 应 < 5个时钟周期

3. **吞吐率**
   - 计数 `usb_upload_valid` 脉冲数 / 时间
   - 应接近配置的采样率

4. **数据完整性**
   - 采样数 = 理论值 ± 5%
   - 数据错误率 = 0%

---

## 下一步：硬件调试

**如果仿真通过，但硬件不工作：**

### 检查项 1：FPGA比特流
```
- 确认已下载最新的比特流
- 检查 impl/pnr/ 中的时间戳
- 重新综合并下载
```

### 检查项 2：引脚连接
```
- 验证 dc_signal_in[0] 连接到 F14
- 确保有实际的数字信号输入
- 测试用信号发生器或按键
```

### 检查项 3：时钟系统
```
- 确认 PHY_CLK (60MHz) 正常
- 检查 PLL 锁定状态
- 测量实际时钟频率
```

### 检查项 4：USB CDC连接
```
- 确认PC识别到虚拟串口
- 波特率设置为 115200
- 尝试心跳命令：AA 55 FF 00 00 FF
```

### 检查项 5：校验和
```
使用工具生成正确命令：
python dc_command_tool.py --generate
```

---

## 高级调试：信号注入

在仿真中修改测试模式：

编辑 `tb/cdc_dc_tb.sv`，找到测试函数，修改：
```systemverilog
// 自定义测试模式
dc_signal_in = 8'b10101010;  // 固定模式
#1us;
dc_signal_in = 8'b01010101;  // 切换模式
#1us;
```

重新运行仿真，观察输出。

---

## 联系与报告

**如果仿真失败：**
1. 保存波形文件 (File → Export → Waveform Database)
2. 复制 `simulation.log`
3. 截图关键波形（DC Handler, MUX, USB Upload）
4. 记录失败的测试编号

**仿真环境：**
- ModelSim版本：建议 10.7c 或更高
- SystemVerilog支持：必需
- GOWIN库路径：`E:/GOWIN/Gowin_V1.9.9_x64/IDE/simlib`

---

**Created:** 2025-10-22
**Purpose:** DC模块功能验证
**Status:** Ready for simulation
