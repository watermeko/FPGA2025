# DSM (数字信号测量) 仿真说明

## 📁 文件位置

- **Testbench**: `F:\FPGA2025\tb\cdc_dsm_simple_tb.sv`
- **仿真脚本**: `F:\FPGA2025\sim\cdc_dsm_simple_tb\cmd.do`

## 🚀 运行仿真

### 方法1: 使用 ModelSim GUI

```bash
cd F:\FPGA2025\sim\cdc_dsm_simple_tb
modelsim
# 在 ModelSim 控制台输入:
do cmd.do
```

### 方法2: 命令行直接运行

```bash
cd F:\FPGA2025\sim\cdc_dsm_simple_tb
vsim -do cmd.do
```

## 🧪 测试内容

仿真包含4个自动化测试场景：

### Test 1: 1kHz @ 50% 占空比
- **通道**: 0
- **频率**: 1kHz (周期 = 60,000 时钟周期 @ 60MHz)
- **高电平**: 30,000 周期
- **低电平**: 30,000 周期
- **周期数**: 3

### Test 2: 10kHz @ 50% 占空比
- **通道**: 0
- **频率**: 10kHz (周期 = 6,000 时钟周期)
- **高电平**: 3,000 周期
- **低电平**: 3,000 周期
- **周期数**: 5

### Test 3: 1kHz @ 25% 占空比
- **通道**: 0
- **高电平**: 15,000 周期 (25%)
- **低电平**: 45,000 周期 (75%)
- **周期数**: 3

### Test 4: 1kHz @ 75% 占空比
- **通道**: 0
- **高电平**: 45,000 周期 (75%)
- **低电平**: 15,000 周期 (25%)
- **周期数**: 3

## 📊 验证标准

每个测试会自动验证：
- ✅ 高电平时间 (±3 时钟周期容差)
- ✅ 低电平时间 (±3 时钟周期容差)
- ✅ 上传数据格式正确性
- ✅ 协议帧头和校验和

## 🔍 观察信号

仿真脚本自动添加了以下信号组：

### 1. Top Level
- 时钟和复位
- USB接口信号
- DSM输入信号 (8通道)

### 2. Protocol Parser
- 状态机
- 命令解析输出 (cmd_out, len_out)
- 解析完成/错误信号

### 3. Command Processor
- 状态机
- 命令总线信号
- Payload 读取

### 4. DSM Handler
- **主状态机**: IDLE → RX_CMD → MEASURING → UPLOAD_DATA
- **上传状态机**: UP_IDLE → UP_SEND → UP_WAIT
- 通道掩码和测量控制
- 上传接口信号

### 5. DSM Core (Multi-channel)
- 8通道测量启动/完成信号
- 打包的测量结果 (128位向量)

### 6. DSM Channel 0 Detail
- **状态机**: IDLE → WAIT_RISING → MEASURE_HIGH → MEASURE_LOW → CALCULATE → DONE
- 同步器链 (3级)
- 边沿检测信号
- 计数器 (high_counter, low_counter)
- 测量结果输出

### 7. Upload Pipeline
- Adapter → Packer → Arbiter 各级信号
- 数据打包过程
- 仲裁和合并

### 8. USB Upload
- 最终上传到USB的数据
- 接收字节计数

## 📝 预期输出

### 控制台输出示例

```
========================================
=== Test 1: 1kHz @ 50% Duty ===
========================================

[XXX] ======= Sending DSM Command: Channel Mask=0x01 =======
[XXX] DSM Command sent (checksum=0x0C)
[XXX] DSM Channel 0: Generating 3 periods (H=30000, L=30000 cycles)
[XXX] DSM_HANDLER: RX_CMD, channel_mask=0x01
[XXX] DSM_HANDLER: MEASURING
[XXX] DSM measure_done changed: 0x01
[XXX] DSM_HANDLER: UPLOAD_DATA

=== Parsing DSM Upload Data ===
Total bytes received: 11
Header: 0xAA44 (expect AA44)
Source: 0x0A (expect 0A=DSM)
Payload Length: 5 bytes

Channel 0:
  High Time: 30000 cycles
  Low Time:  30000 cycles
  Period:    60000 cycles
  Frequency: 1000 Hz
  Duty:      50%

--- Verification: Channel 0 ---
Expected: High=30000, Low=30000
Actual:   High=30000, Low=30000
Tolerance: ±3 cycles
✅ High time: PASS
✅ Low time: PASS
✅ FINAL: PASS

=== Test Complete ===
```

## 🐛 调试技巧

### 1. 检查信号生成
观察波形中的 `dsm_signal_in[0]`，确认方波正确生成

### 2. 检查边沿检测
查看 DSM Ch0 组中的：
- `measure_pin_sync2` (同步后的输入)
- `rising_edge` / `falling_edge` (边沿检测)

### 3. 检查状态机转换
- DSM Ch0 的 `state` 应该按序转换
- 如果卡在 `WAIT_RISING`(1)，说明没检测到上升沿

### 4. 检查计数器
- `high_counter` 应该在 MEASURE_HIGH 状态递增
- `low_counter` 应该在 MEASURE_LOW 状态递增

### 5. 检查上传流程
依次观察：
- DSM Handler 的 upload_valid
- DSM Adapter 的 packer_upload_valid
- Packer 输出的 packed_valid[2]
- Merged upload 的 merged_upload_valid
- 最终的 usb_upload_valid

## ⚙️ 修改测试参数

在 `cdc_dsm_simple_tb.sv` 的主测试序列中修改：

```systemverilog
// 添加新的测试
run_dsm_test(
    "Test 5: 自定义测试",
    8'h01,      // 通道掩码 (bit0=通道0)
    0,          // 测试哪个通道
    12000,      // 高电平周期数
    48000,      // 低电平周期数
    4           // 生成几个完整周期
);
```

## 📌 常见问题

### Q1: 测量结果为0
**原因**: 信号未正确生成或状态机未启动
**检查**:
- `dsm_signal_in` 波形
- DSM Handler 的 `channel_mask` 是否正确
- `measure_start_reg` 是否被置位

### Q2: High_time=0, Low_time=全周期
**原因**: 信号可能反相，或占空比极低
**检查**:
- 信号源配置
- 边沿检测逻辑

### Q3: 上传数据不完整
**原因**: Upload pipeline 有阻塞
**检查**:
- Arbiter FIFO 是否满
- Ready/Valid 握手信号

## 🎯 成功标准

所有测试显示：
```
✅ High time: PASS
✅ Low time: PASS
✅ FINAL: PASS
```

误差应在 ±3 个时钟周期内（由同步器和状态机延迟造成）。

---

**作者**: Claude Code
**日期**: 2025-01-XX
**版本**: 1.0
