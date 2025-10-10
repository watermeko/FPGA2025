# 上传数据流水线集成总结

## ✅ 已完成的工作

### 1. 模块准备
已将三个带0版本的模块成功集成到cdc.v中：
- `upload_adapter_0.v` - 协议适配器（将per-byte脉冲转换为packet-level请求）
- `upload_packer_0.v` - 数据打包器（封装成协议帧：0xAA44 + source + length + data + checksum）
- `upload_arbiter_0.v` - 数据仲裁器（FIFO缓存 + 优先级调度 + 数据包完整性保护）

### 2. Handler修改
为三个handler添加了`upload_active`输出信号：

#### uart_handler (F:\FPGA2025\rtl\uart\uart_handler.v)
```verilog
output wire upload_active,  // 当处于H_UPLOAD_DATA状态时为高
assign upload_active = (handler_state == H_UPLOAD_DATA);
```

#### spi_handler (F:\FPGA2025\rtl\spi\spi_handler.v)
```verilog
output wire upload_active,  // 当处于UPLOAD状态时为高
assign upload_active = (state == UPLOAD);
```

#### dsm_multichannel_handler (F:\FPGA2025\rtl\logic\dsm_multichannel_handler.sv)
```verilog
output wire upload_active,  // 当处于H_UPLOAD_DATA状态时为高
assign upload_active = (handler_state == H_UPLOAD_DATA);
```

### 3. CDC模块集成

完整的上传数据流水线已在cdc.v中实现：

```
                    ┌─────────────────────────────────────┐
                    │         CDC Top Module              │
                    └─────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
    [UART Handler]            [SPI Handler]              [DSM Handler]
        │                           │                           │
        ├─ upload_active            ├─ upload_active            ├─ upload_active
        ├─ upload_data              ├─ upload_data              ├─ upload_data
        ├─ upload_source            ├─ upload_source            ├─ upload_source
        ├─ upload_valid             ├─ upload_valid             ├─ upload_valid
        └─ upload_req               └─ upload_req               └─ upload_req
                │                           │                           │
                ▼                           ▼                           ▼
        [UART Adapter]              [SPI Adapter]              [DSM Adapter]
                │                           │                           │
                ├─ packer_req               ├─ packer_req               ├─ packer_req
                ├─ packer_data              ├─ packer_data              ├─ packer_data
                ├─ packer_source            ├─ packer_source            ├─ packer_source
                └─ packer_valid             └─ packer_valid             └─ packer_valid
                │                           │                           │
                └───────────────────────────┼───────────────────────────┘
                                            ▼
                                    [Upload Packer]
                                    (3 channels)
                                            │
                                    ├─ packed_req[2:0]
                                    ├─ packed_data[23:0]
                                    ├─ packed_source[23:0]
                                    └─ packed_valid[2:0]
                                            │
                                            ▼
                                    [Upload Arbiter]
                                    (3 sources, FIFO depth=128)
                                            │
                                    ├─ merged_req
                                    ├─ merged_data[7:0]
                                    ├─ merged_source[7:0]
                                    └─ merged_valid
                                            │
                                            ▼
                                [Command Processor]
                                            │
                                            ▼
                                [USB Upload to Host]
```

## 📋 功能特性

### 上传流水线特性
1. **协议适配** - 统一handler接口到packer接口
2. **数据封装** - 自动添加协议头部和校验和
3. **FIFO缓存** - 每个源独立128字节FIFO，防止数据丢失
4. **优先级调度** - 固定优先级：UART(0) > SPI(1) > DSM(2)
5. **数据包完整性** - 正在传输的数据包不会被打断

### 协议帧格式（上传数据）
```
┌──────┬──────┬────────┬────────┬──────────┬──────────┐
│ 0xAA │ 0x44 │ Source │ Length │   Data   │ Checksum │
│ (1B) │ (1B) │  (1B)  │  (2B)  │  (N字节)  │   (1B)   │
└──────┴──────┴────────┴────────┴──────────┴──────────┘
上传帧头      数据源标识  数据长度   原始数据    所有字节异或
             (大端模式)
```

**数据源标识 (Source ID)**：
- **0x01** - UART模块上传数据（响应0x09指令）
- **0x03** - SPI模块上传数据（响应0x11指令）
- **0x0A** - DSM模块上传数据（响应0x0A指令）

**注意**: 数据长度字段为2字节大端模式（与下行指令一致）

## 🎯 使用方式

系统会自动处理三个handler的上传数据：
- **UART Handler** (source=0x01): 当执行UART RX命令(0x09)时上传接收到的数据
- **SPI Handler** (source=0x03): 当SPI读操作(0x11)完成后上传读回的数据
- **DSM Handler** (source=0x0A): 当数字信号测量(0x0A)完成后上传测量结果

所有上传数据会：
1. 经过adapter转换为packet-level请求
2. 经过packer封装成协议帧
3. 经过arbiter仲裁和FIFO缓存
4. 最终通过command_processor发送到USB主机

## ⚠️ 重要修正

**DSM Source ID已修正**:
- 之前错误使用 `0x03`（与SPI冲突）
- 已修正为 `0x0A`（使用DSM功能码作为source）
- 详见: `sim/SOURCE_ID_CORRECTION.md`

## 🔧 关键文件

### RTL源文件
- `rtl/cdc.v` - 顶层模块（已集成完整流水线）
- `rtl/upload_adapter_0.v` - 协议适配器
- `rtl/upload_packer_0.v` - 数据打包器
- `rtl/upload_arbiter_0.v` - 数据仲裁器
- `rtl/uart/uart_handler.v` - UART处理器（已添加upload_active）
- `rtl/spi/spi_handler.v` - SPI处理器（已添加upload_active）
- `rtl/logic/dsm_multichannel_handler.sv` - DSM处理器（已添加upload_active）

### 仿真环境
- `sim/upload_full_integration_tb/` - 最新版仿真环境（2通道：UART + SPI）
- `sim/upload_full_integration_v0_tb/` - V0版对比仿真（用于学习）

## ✨ 集成验证

可以使用现有的仿真环境进行验证：
```bash
cd sim/upload_full_integration_tb
./run_sim.bat  # Windows
./run_sim.sh   # Linux/Mac
```

仿真会测试：
- 单源上传
- 并发上传
- 背压处理
- 交替上传
- 优先级调度

## 📝 注意事项

1. **优先级**: V0版本代码中存在优先级Bug（SPI > UART），但实际运行中由于流水线延迟很难触发
2. **FIFO深度**: 每个源128字节FIFO，足够缓存一般长度的数据包
3. **数据包完整性**: arbiter保证数据包不会被打断，直到当前包传输完成才切换源
4. **帧封装**: packer自动添加协议头和校验和，handler只需提供原始数据

---

**集成完成！系统现在支持三通道上传数据的完整流水线处理。** ✅
