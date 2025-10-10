# DSM上传集成仿真环境

## 概述

这个仿真环境专门用于测试DSM（数字信号测量）模块的上传数据流水线：
- **DSM Handler** - 数字信号测量数据上传 (Source ID: 0x0A)
- **Upload Adapter** - 协议适配（per-byte → packet-level）
- **Upload Packer** - 数据封装（添加协议头和校验和）
- **Upload Arbiter** - FIFO缓存和仲裁

## 系统架构

```
┌─────────────┐
│ DSM Handler │
│ (src=0x0A)  │
└──────┬──────┘
       │ upload_active, upload_req, upload_data, upload_source, upload_valid
       ▼
┌─────────────┐
│ DSM Adapter │
│ (per-byte → │
│  packet)    │
└──────┬──────┘
       │ packer_req, packer_data, packer_source, packer_valid
       ▼
┌─────────────┐
│Upload Packer│
│  (Channel 2)│
│   添加协议头  │
└──────┬──────┘
       │ packed_req[2], packed_data[23:16], packed_source[23:16], packed_valid[2]
       ▼
┌─────────────┐
│   Arbiter   │
│ FIFO + 仲裁 │
└──────┬──────┘
       │ merged_upload_req, merged_upload_data, merged_upload_source, merged_upload_valid
       ▼
[USB Upload to Host]
```

## 测试用例

### DSM通道0测量
- 发送DSM测量指令 (0x0A)，启用通道0
- 模拟1kHz方波输入信号（仿真加速版本：30us高+30us低）
- 验证测量数据上传格式：
  - 帧头: 0xAA 0x44
  - Source: 0x0A
  - Length: 0x00 0x09 (9字节)
  - Data: 通道号(1B) + 高电平时间(2B) + 低电平时间(2B) + 周期(2B) + 占空比(2B)
  - Checksum: 所有字节异或

**预期输出**: 15字节 (6字节头部 + 9字节数据)

## 运行仿真

### Windows
```bash
cd sim/upload_full_integration_3ch_tb
run_sim.bat
```

### Linux/Mac
```bash
cd sim/upload_full_integration_3ch_tb
chmod +x run_sim.sh
./run_sim.sh
```

或者直接使用ModelSim：
```bash
vsim -do cmd.do
```

## 仿真时长

默认仿真时长: **2ms**

这个时长足够完成：
- DSM测量（捕获多个完整周期）
- 数据上传传输

## 关键信号

### 命令接口
- `cmd_type` - 功能码 (0x0A=DSM)
- `cmd_start` - 命令开始
- `cmd_data_valid` - 命令数据有效
- `cmd_done` - 命令完成

### DSM Handler输出
- `dsm_upload_active` - 上传活跃信号
- `dsm_upload_req` - 上传请求
- `dsm_upload_data` - 上传数据
- `dsm_upload_source` - 数据源标识 (0x0A)
- `dsm_upload_valid` - 数据有效
- `dsm_upload_ready` - 准备就绪

### DSM测量结果
- `high_time[15:0]` - 高电平时间
- `low_time[15:0]` - 低电平时间
- `period_time[15:0]` - 周期
- `duty_cycle[15:0]` - 占空比

### Adapter输出 (到Packer)
- `dsm_packer_req` - 包请求
- `dsm_packer_data` - 包数据
- `dsm_packer_source` - 源标识
- `dsm_packer_valid` - 数据有效

### Packer输出 (通道2)
- `packed_req[2]` - DSM通道包请求
- `packed_data[23:16]` - DSM通道数据
- `packed_source[23:16]` - DSM通道源标识
- `packed_valid[2]` - DSM通道数据有效

### Arbiter输出 (合并)
- `merged_upload_req` - 合并后上传请求
- `merged_upload_data` - 合并后数据
- `merged_upload_source` - 合并后源标识
- `merged_upload_valid` - 合并后数据有效

### Arbiter内部状态
- `arb_state` - 仲裁器状态机
- `current_source` - 当前选中源
- `in_packet` - 正在传输数据包标志

## 验证要点

### 1. 协议格式正确性
- [ ] 帧头固定为 0xAA44
- [ ] Source ID正确 (DSM=0x0A)
- [ ] Length字段正确（大端模式2字节，值为0x0009）
- [ ] Checksum计算正确（所有字节异或）

### 2. 数据完整性
- [ ] DSM测量数据格式正确（9字节：通道号+高电平+低电平+周期+占空比）
- [ ] 测量值合理（30us高+30us低 = 60us周期，50%占空比）

### 3. 流水线功能
- [ ] Adapter正确转换per-byte到packet-level
- [ ] Packer正确封装协议帧
- [ ] Arbiter正确处理DSM数据流

### 4. 状态机转换
- [ ] DSM Handler: IDLE → RX_CMD → MEASURING → UPLOAD_DATA → IDLE
- [ ] Adapter: IDLE → SEND → WAIT循环
- [ ] Packer: IDLE → COLLECT → SEND_HEADER → ... → SEND_CHECKSUM → IDLE
- [ ] Arbiter: IDLE → READ_FIFO → UPLOAD → IDLE

## DSM信号模拟

测试中使用模拟的方波信号：
```verilog
// 通道0: 1kHz方波 (50%占空比)
forever begin
    dsm_signal_in[0] = 1;
    #30000;  // 高电平 30us (实际应该是500us，仿真加速)
    dsm_signal_in[0] = 0;
    #30000;  // 低电平 30us
end
```

**注意**: 仿真中的时序被加速以减少仿真时间。实际硬件中1kHz方波为500us高+500us低。

## 协议参考

详细协议定义请参考：
- `doc/USB-CDC通信协议.md`
- `sim/INTEGRATION_SUMMARY.md`
- `sim/SOURCE_ID_CORRECTION.md`

## 相关文件

### RTL源文件
- `rtl/upload_adapter_0.v` - 协议适配器
- `rtl/upload_packer_0.v` - 数据打包器
- `rtl/upload_arbiter_0.v` - 数据仲裁器
- `rtl/uart/uart_handler.v` - UART处理器
- `rtl/spi/spi_handler.v` - SPI处理器
- `rtl/logic/dsm_multichannel_handler.sv` - DSM处理器

### 仿真文件
- `tb/upload_full_integration_3ch_tb.v` - 3通道集成测试平台
- `sim/upload_full_integration_3ch_tb/cmd.do` - ModelSim脚本
- `sim/upload_full_integration_3ch_tb/run_sim.bat` - Windows运行脚本
- `sim/upload_full_integration_3ch_tb/run_sim.sh` - Linux/Mac运行脚本

## 调试技巧

### 查看状态机
在波形中重点关注：
- DSM Handler状态: `u_dsm_handler/handler_state`
- DSM Adapter状态: `u_dsm_adapter/state`
- Packer状态: `u_packer/state_2` (通道2)
- Arbiter状态: `u_arbiter/arb_state`

### 查看字节计数
测试平台包含2个监视计数器：
- `dsm_byte_count` - DSM handler输出字节数
- `merged_byte_count` - Arbiter合并输出字节数

通过比较这些计数器可以验证数据是否完整传输（应该都是15字节）。

### 查看测量结果
在波形中查看DSM测量的原始数据：
- `u_dsm_handler/u_dsm_multichannel/high_time[15:0]` - 高电平时间（应约为30000）
- `u_dsm_handler/u_dsm_multichannel/low_time[15:0]` - 低电平时间（应约为30000）
- `u_dsm_handler/u_dsm_multichannel/period_time[15:0]` - 周期（应约为60000）
- `u_dsm_handler/u_dsm_multichannel/duty_cycle[15:0]` - 占空比（应约为50%）

### 常见问题

**Q: DSM没有输出数据？**
- 检查 `dsm_signal_in[0]` 是否有信号变化
- 检查 `channel_mask` 是否正确设置为0x01（启用通道0）
- 检查测量时间是否足够长（至少60us捕获一个完整周期）

**Q: Checksum错误？**
- 检查Packer的checksum计算逻辑
- 应该是从Source字段(0x0A)开始到最后一个数据字节的异或
- 公式: 0x0A ^ 0x00 ^ 0x09 ^ ch_num ^ high_h ^ high_l ^ low_h ^ low_l ^ period_h ^ period_l ^ duty_h ^ duty_l

**Q: 数据格式不对？**
- 检查upload_packer是否正确添加了帧头0xAA44
- 检查长度字段是否为大端模式（0x00 0x09）
- 检查Source字段是否为0x0A

**Q: 仿真时间不够？**
- 增加cmd.do中的仿真时长：`run 5ms` 或更长

## 修改历史

- 2025-01-XX: 创建DSM上传集成仿真环境（简化版，仅测试DSM）
- 2025-01-XX: 修正DSM Source ID从0x03到0x0A
- 2025-01-XX: 添加upload_active信号到DSM handler

## 编译依赖

仿真需要以下RTL文件：
- `rtl/upload_adapter_0.v` - 协议适配器
- `rtl/upload_packer_0.v` - 数据打包器
- `rtl/upload_arbiter_0.v` - 数据仲裁器（内部实现寄存器FIFO）
- `rtl/logic/digital_signal_measure.sv` - 数字信号测量核心模块
- `rtl/logic/dsm_multichannel.sv` - DSM多通道包装器
- `rtl/logic/dsm_multichannel_handler.sv` - DSM处理器
- `tb/upload_dsm_only_tb.v` - 测试平台

**注意**:
- 不需要UART和SPI相关模块
- 不需要sync_fifo IP核（arbiter使用内部寄存器实现的FIFO）
- 编译顺序很重要：digital_signal_measure → dsm_multichannel → dsm_multichannel_handler

---

**准备就绪，可以运行DSM仿真！** ✅
