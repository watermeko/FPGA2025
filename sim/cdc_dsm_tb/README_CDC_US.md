# CDC_US 仿真说明

## 概述
此仿真用于测试 `cdc_us.v` 模块，验证 DSM（数字信号测量）功能在隔离模式下的工作情况。

## 运行仿真

### 方法1：命令行
```bash
cd F:/FPGA2025/sim/cdc_dsm_tb
modelsim -do cmd_cdc_us.do
```

### 方法2：ModelSim GUI
1. 打开 ModelSim
2. 切换到目录：`F:/FPGA2025/sim/cdc_dsm_tb`
3. 在命令窗口输入：`do cmd_cdc_us.do`

## 测试内容

### 1. CDC_US 配置验证
- ✅ `cmd_ready = dsm_ready`（只检查 DSM handler ready）
- ✅ `merged_upload_*` 只连接到 DSM（隔离测试）
- ✅ `uart_upload_ready = 0`（UART 上传隔离）
- ✅ `spi_upload_ready = 0`（SPI 上传隔离）

### 2. DSM 多通道测量测试
测试 5 个通道同时测量不同占空比的信号：

| 通道 | 高电平周期 | 低电平周期 | 占空比 | 测试周期数 |
|------|-----------|-----------|--------|-----------|
| 0    | 50        | 50        | 50%    | 6         |
| 1    | 25        | 75        | 25%    | 5         |
| 2    | 75        | 25        | 75%    | 4         |
| 3    | 30        | 70        | 30%    | 5         |
| 4    | 80        | 20        | 80%    | 4         |

### 3. 数据上传验证
- 每个通道应上传 9 字节数据
- 数据格式：`[通道号(1字节)][高电平时间(2字节)][低电平时间(2字节)][周期时间(2字节)][占空比(2字节)]`
- 总共应接收：5 通道 × 9 字节 = 45 字节

### 4. 测量精度验证
- 时钟周期测量允许 ±2 周期误差
- 占空比允许 ±3% 误差

## 关键波形观察

### 必看信号组：
1. **Upload Arbitration**：
   - `merged_upload_req` - 应该等于 `dsm_upload_req`
   - `merged_upload_valid` - 应该等于 `dsm_upload_valid`
   - `merged_upload_data` - 应该等于 `dsm_upload_data`

2. **DSM Upload Isolated**：
   - `dsm_upload_req` - DSM 请求上传
   - `dsm_upload_valid` - DSM 数据有效
   - `dsm_upload_ready` - 应该等于 `processor_upload_ready`

3. **UART/SPI Upload (Isolated)**：
   - `uart_upload_ready` - 应该始终为 0
   - `spi_upload_ready` - 应该始终为 0

4. **DSM Handler**：
   - `handler_state` - DSM handler 状态机
   - `upload_state` - 上传状态机
   - `channel_mask` - 通道使能掩码（应为 0x1F，即通道 0-4）
   - `all_done` - 所有通道测量完成

5. **DSM Ch0 Detail**：
   - `state` - 通道 0 的测量状态机
   - `measure_pin` - 输入信号
   - `rising_edge` / `falling_edge` - 边沿检测
   - `high_counter` / `low_counter` - 计数器
   - `measure_done` - 测量完成标志

6. **Test Monitor**：
   - `usb_received_count` - USB 接收的总字节数（应为 45）
   - `usb_valid_pulse_count` - USB valid 脉冲数（应为 45）

## 预期结果

### 控制台输出示例：
```
[xxx ns] 发送多通道DSM命令
[xxx ns] 通道0开始生成信号
[xxx ns] 通道1开始生成信号
...
[xxx ns] USB接收数据[0]: 0x00  // 通道 0
[xxx ns] USB接收数据[1]: 0x00  // 高电平时间高字节
[xxx ns] USB接收数据[2]: 0x32  // 高电平时间低字节 (50)
...
=== 解析DSM测量结果 ===
通道0结果:
  高电平时间: 50 时钟周期
  低电平时间: 50 时钟周期
  周期时间:   100 时钟周期
  占空比:     50%
...
=== DSM测量结果验证 ===
通道0验证:
  ✅ 高电平时间测量正确: 50 (预期: 50±2)
  ✅ 低电平时间测量正确: 50 (预期: 50±2)
  ✅ 占空比测量正确: 50% (预期: 50%±3%)
```

## 故障排查

### 问题1：没有数据上传
**现象**：`usb_received_count = 0`

**检查点**：
1. `cmd_ready` 是否为 1（DSM handler 准备好）
2. `cmd_start` 是否有脉冲（命令已接收）
3. `measure_start` 是否拉高（测量已启动）
4. `measure_done` 是否拉高（测量已完成）
5. `dsm_signal_in` 是否有信号跳变

**可能原因**：
- DSM handler 卡在 `H_MEASURING` 状态等待测量完成
- `dsm_signal_in` 没有信号跳变，导致 `measure_done` 永远不会拉高

### 问题2：数据字节数不对
**现象**：`usb_received_count ≠ 45`

**检查点**：
1. `upload_byte_index` 是否正确递增（0-8）
2. `upload_channel` 是否正确递增（0-4）
3. `upload_valid` 脉冲数是否等于接收字节数

**可能原因**：
- 上传状态机逻辑错误
- `upload_ready` 握手有问题

### 问题3：测量值不准确
**现象**：测量结果与预期值相差太大

**检查点**：
1. 测试信号生成的周期数是否正确
2. 边沿检测是否正常工作
3. 计数器是否有溢出

## 文件说明

- `cmd_cdc_us.do` - CDC_US 仿真脚本（使用 `USE_CDC_US` 宏）
- `cmd.do` - 原始 CDC 仿真脚本（使用 `cdc.v`）
- `cdc_dsm_tb.sv` - 测试平台（支持条件编译）

## 相关文件

- 被测模块：`F:/FPGA2025/rtl/cdc_us.v`
- DSM Handler：`F:/FPGA2025/rtl/logic/dsm_multichannel_handler.sv`
- DSM Core：`F:/FPGA2025/rtl/logic/dsm_multichannel.sv`
- 协议文档：`F:/FPGA2025/doc/USB-CDC通信协议.md`

## 注意事项

1. **仿真时间**：完整测试需要约 100us 仿真时间
2. **调试宏**：testbench 启用了 `DSM_DEBUG` 宏，会打印详细调试信息
3. **库依赖**：不需要 GOWIN `gw5a` 库即可进行功能仿真
