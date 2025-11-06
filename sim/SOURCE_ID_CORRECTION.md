# Source ID修正说明

## 📋 问题发现

在集成上传数据流水线时，发现DSM handler使用了错误的source ID：
- **错误**: DSM使用 `0x03` 作为upload_source
- **冲突**: SPI也使用 `0x03` 作为upload_source
- **后果**: 会导致主机无法区分SPI和DSM上传的数据

## ✅ 修正方案

根据 `doc/USB-CDC通信协议.md` 的定义，上传数据的source字段应该使用**数据来源标识**：

### 正确的Source ID分配

| 模块 | Source ID | 说明 | 文件位置 |
|------|-----------|------|----------|
| **UART** | `0x01` | UART模块标识 | `rtl/uart/uart_handler.v` |
| **SPI** | `0x03` | SPI模块标识（协议明确指定） | `rtl/spi/spi_handler.v` |
| **DSM** | `0x0A` | DSM功能码（与指令码相同） | `rtl/logic/dsm_multichannel_handler.sv` |

### 修正内容

**文件**: `rtl/logic/dsm_multichannel_handler.sv`

**修改前** (第32行):
```systemverilog
// Upload source identifier for DSM
localparam UPLOAD_SOURCE_DSM = 8'h03;
```

**修改后**:
```systemverilog
// Upload source identifier for DSM - 使用DSM的功能码作为source
localparam UPLOAD_SOURCE_DSM = 8'h0A;  // 修正：使用0x0A而不是0x03
```

## 📖 协议对照

根据 `doc/USB-CDC通信协议.md`:

### 下行指令（主机→FPGA）
```
帧头: 0xAA55
功能码字段:
  - 0x09: UART接收指令
  - 0x11: SPI读写操作指令
  - 0x0A: 数字信号测量指令
```

### 上行数据（FPGA→主机）
```
帧头: 0xAA44
Source字段:
  - 0x01: UART模块上传数据
  - 0x03: SPI模块上传数据（协议明确规定）
  - 0x0A: DSM模块上传数据（使用功能码作为标识）
```

### 协议依据

**SPI上传数据格式** (协议第56-61行):
```
响应数据格式：
- 帧头：0xAA44（上传数据标识）
- 数据来源：0x03（SPI模块）  ← 协议明确规定
- 数据长度：read_len
- 数据体：实际读取到的read_len个字节数据
```

**DSM上传数据格式** (协议第139-147行):
```
数字信号测量 (功能码 0x0A)
响应数据格式 (每个启用的通道返回9字节数据)：
| 字段 | 字节数 | 说明 |
...
```
虽然协议没有明确指定DSM的source ID，但使用功能码0x0A作为source是合理的设计。

## 🎯 验证方法

### 1. 代码验证
```bash
# 检查所有source定义
grep "UPLOAD_SOURCE" rtl/uart/uart_handler.v
grep "upload_source" rtl/spi/spi_handler.v
grep "UPLOAD_SOURCE_DSM" rtl/logic/dsm_multichannel_handler.sv
```

**预期输出**:
```
rtl/uart/uart_handler.v:    localparam UPLOAD_SOURCE_UART = 8'h01;
rtl/spi/spi_handler.v:            upload_source <= 8'h03;
rtl/logic/dsm_multichannel_handler.sv:    localparam UPLOAD_SOURCE_DSM = 8'h0A;
```

### 2. 功能验证

运行完整系统测试时，应该能看到：
- UART RX数据上传: `AA 44 01 00 XX ...` (source=0x01)
- SPI读数据上传: `AA 44 03 00 XX ...` (source=0x03)
- DSM测量数据上传: `AA 44 0A 00 XX ...` (source=0x0A)

## 📝 注意事项

1. **唯一性**: 每个模块的source ID必须唯一，避免混淆
2. **一致性**: source ID应该在协议文档中明确定义
3. **可扩展性**: 保留足够的ID空间用于未来扩展
   - 0x01: UART
   - 0x02: 保留（可能用于I2C）
   - 0x03: SPI
   - 0x04-0x09: 保留
   - 0x0A: DSM
   - 0x0B+: 其他功能

## ✨ 修正完成

- [x] 发现source ID冲突问题
- [x] 修正DSM handler的UPLOAD_SOURCE_DSM定义
- [x] 更新集成总结文档
- [x] 创建修正说明文档

**状态**: ✅ 已完成，现在三个模块的source ID不再冲突！
