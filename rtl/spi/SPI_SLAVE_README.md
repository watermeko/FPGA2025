# SPI从机Handler使用说明

## 📋 概述

SPI从机Handler模块允许FPGA作为SPI从机，与外部SPI主机通信。

### 文件清单
- `simple_spi_slave.v` - SPI从机物理层实现
- `spi_slave_handler.v` - SPI从机命令处理层
- 本文档 - 使用说明

---

## 🔌 硬件接口

### SPI物理接口（从机侧）
| 信号 | 方向 | 说明 |
|------|------|------|
| `spi_clk` | 输入 | SPI时钟（来自主机） |
| `spi_cs_n` | 输入 | 片选信号，低有效 |
| `spi_mosi` | 输入 | 主机输出从机输入 |
| `spi_miso` | 输出 | 主机输入从机输出 |

### 特性
- **SPI模式**: Mode 0 (CPOL=0, CPHA=0)
- **数据位宽**: 8位
- **缓冲区大小**: 256字节（发送和接收各256字节）
- **数据上传源标识**: 0x14

---

## 📡 通信协议

### 功能码定义

| 功能码 | 名称 | 说明 |
|--------|------|------|
| 0x14 | 配置从机发送缓冲区 | 设置主机将要读取的数据 |
| 0x15 | 控制数据上传 | 启用/禁用接收数据自动上传 |

---

## 🎯 使用场景

### 场景1：配置从机发送数据（主机读取模式）

**步骤**:
1. 通过USB CDC发送配置命令，将数据写入从机的发送缓冲区
2. 外部SPI主机发起读取操作
3. FPGA从机自动从缓冲区输出数据

**命令格式** (功能码 0x14):
```
帧头: AA 55
功能码: 14
数据长度: [高字节] [低字节] (最大256)
数据体: [N个字节的数据]
校验和: [累加和]
```

**示例1**: 配置从机发送 "Hello"
```
发送: AA 55 14 00 05 48 65 6C 6C 6F XX
      ^^^^帧头 ^^功能码 ^^^^长度=5 ^^^^^^^^^^"Hello" ^^校验和
```

**示例2**: 配置从机发送10个递增数字
```
发送: AA 55 14 00 0A 00 01 02 03 04 05 06 07 08 09 XX
      ^^^^帧头 ^^功能码 ^^^^长度=10 ^^^^^^^^^^数据^^^^^^^^^^ ^^校验和
```

### 场景2：接收主机数据并上传

**步骤**:
1. 发送控制命令启用数据上传
2. 外部SPI主机发起写入操作
3. FPGA从机自动接收并上传数据到USB CDC

**控制命令格式** (功能码 0x15):
```
帧头: AA 55
功能码: 15
数据长度: 00 01
数据体: [控制字节]
  Bit[0]: 0=禁用上传, 1=启用上传
校验和: [累加和]
```

**示例1**: 启用接收数据上传
```
发送: AA 55 15 00 01 01 17
      ^^^^帧头 ^^功能码 ^^^^长度=1 ^^启用 ^^校验和
```

**示例2**: 禁用接收数据上传
```
发送: AA 55 15 00 01 00 16
      ^^^^帧头 ^^功能码 ^^^^长度=1 ^^禁用 ^^校验和
```

**上传数据格式**:
```
响应: AA 44 14 [高字节] [低字节] [数据...] [校验和]
      ^^^^上传帧头 ^^从机源 ^^^^数据长度 ^^接收数据^^ ^^校验和
```

### 场景3：双向通信（读写组合）

主机可以在一次传输中同时写入和读取数据：
1. 配置从机发送缓冲区（步骤1）
2. 启用接收上传（步骤2）
3. 主机发起SPI传输，同时发送和接收数据

---

## 🔧 集成到cdc.v

在 `cdc.v` 中添加SPI从机Handler：

```verilog
module cdc(
    // ... 现有端口 ...

    // 添加SPI从机接口
    input        spi_slave_clk,
    input        spi_slave_cs_n,
    input        spi_slave_mosi,
    output       spi_slave_miso
);

    // ... 现有代码 ...

    // 添加SPI从机ready和上传信号
    wire spi_slave_ready;
    wire spi_slave_upload_active;
    wire spi_slave_upload_req;
    wire [7:0] spi_slave_upload_data;
    wire [7:0] spi_slave_upload_source;
    wire spi_slave_upload_valid;
    wire spi_slave_upload_ready;

    // 修改cmd_ready（添加spi_slave_ready）
    wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready &
                     spi_ready & dsm_ready & i2c_ready & dc_ready &
                     spi_slave_ready;  // 新增

    // 实例化SPI从机Handler
    spi_slave_handler u_spi_slave_handler (
        .clk              (clk),
        .rst_n            (rst_n),
        .cmd_type         (cmd_type),
        .cmd_length       (cmd_length),
        .cmd_data         (cmd_data),
        .cmd_data_index   (cmd_data_index),
        .cmd_start        (cmd_start),
        .cmd_data_valid   (cmd_data_valid),
        .cmd_done         (cmd_done),
        .cmd_ready        (spi_slave_ready),
        .spi_clk          (spi_slave_clk),
        .spi_cs_n         (spi_slave_cs_n),
        .spi_mosi         (spi_slave_mosi),
        .spi_miso         (spi_slave_miso),
        .upload_active    (spi_slave_upload_active),
        .upload_req       (spi_slave_upload_req),
        .upload_data      (spi_slave_upload_data),
        .upload_source    (spi_slave_upload_source),
        .upload_valid     (spi_slave_upload_valid),
        .upload_ready     (spi_slave_upload_ready)
    );

    // 添加SPI从机到上传流水线
    // 方法1: 添加一个新的upload_adapter
    upload_adapter u_spi_slave_adapter (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .handler_upload_active    (spi_slave_upload_active),
        .handler_upload_data      (spi_slave_upload_data),
        .handler_upload_source    (spi_slave_upload_source),
        .handler_upload_valid     (spi_slave_upload_valid),
        .handler_upload_ready     (spi_slave_upload_ready),
        .packer_upload_req        (spi_slave_packer_req),
        .packer_upload_data       (spi_slave_packer_data),
        .packer_upload_source     (spi_slave_packer_source),
        .packer_upload_valid      (spi_slave_packer_valid),
        .packer_upload_ready      (spi_slave_packer_ready)
    );

    // 修改upload_packer参数：NUM_CHANNELS增加到5
    // 修改packed_req等信号的位宽

endmodule
```

---

## 📌 引脚约束

在 `constraints/pin_cons.cst` 中添加：

```tcl
// SPI Slave Interface
IO_LOC "spi_slave_clk"   XX;
IO_PORT "spi_slave_clk"  IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "spi_slave_cs_n"  XX;
IO_PORT "spi_slave_cs_n" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "spi_slave_mosi"  XX;
IO_PORT "spi_slave_mosi" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "spi_slave_miso"  XX;
IO_PORT "spi_slave_miso" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
```

---

## 🧪 测试示例

### Python测试脚本

```python
#!/usr/bin/env python3
import serial
import struct

def calculate_checksum(data):
    """计算校验和（从功能码开始累加）"""
    return sum(data) & 0xFF

def send_command(ser, cmd, length, data):
    """发送命令到FPGA"""
    frame = bytearray([0xAA, 0x55, cmd])
    frame += struct.pack('>H', length)  # 大端模式
    frame += data
    checksum = calculate_checksum(frame[2:])
    frame.append(checksum)
    ser.write(frame)
    print(f"发送: {frame.hex(' ')}")

# 打开串口
ser = serial.Serial('COM3', 115200, timeout=1)

# 测试1: 配置从机发送 "FPGA2025"
print("\n=== 测试1: 配置从机发送数据 ===")
test_data = b"FPGA2025"
send_command(ser, 0x14, len(test_data), test_data)

# 测试2: 启用接收数据上传
print("\n=== 测试2: 启用数据上传 ===")
send_command(ser, 0x15, 1, b'\x01')

# 测试3: 读取上传数据（等待外部主机写入）
print("\n=== 测试3: 等待接收数据 ===")
while True:
    if ser.in_waiting > 0:
        data = ser.read(ser.in_waiting)
        print(f"接收: {data.hex(' ')}")
        # 解析AA 44帧
        if len(data) >= 6 and data[0:2] == b'\xAA\x44':
            source = data[2]
            length = struct.unpack('>H', data[3:5])[0]
            payload = data[5:5+length]
            print(f"  数据源: 0x{source:02X}")
            print(f"  长度: {length}")
            print(f"  数据: {payload.hex(' ')} ({payload})")

ser.close()
```

### Arduino测试代码（作为主机）

```cpp
#include <SPI.h>

void setup() {
  Serial.begin(115200);
  SPI.begin();
  SPI.setClockDivider(SPI_CLOCK_DIV16); // 1MHz
  pinMode(SS, OUTPUT);
  digitalWrite(SS, HIGH);
  delay(1000);
}

void loop() {
  // 测试1: 读取FPGA从机发送的数据
  Serial.println("=== Reading from FPGA Slave ===");
  digitalWrite(SS, LOW);
  for (int i = 0; i < 8; i++) {
    uint8_t data = SPI.transfer(0x00);  // 发送dummy字节
    Serial.print("Read[");
    Serial.print(i);
    Serial.print("]: 0x");
    Serial.println(data, HEX);
  }
  digitalWrite(SS, HIGH);
  delay(2000);

  // 测试2: 向FPGA从机写入数据
  Serial.println("=== Writing to FPGA Slave ===");
  digitalWrite(SS, LOW);
  uint8_t writeData[] = {0xDE, 0xAD, 0xBE, 0xEF};
  for (int i = 0; i < 4; i++) {
    SPI.transfer(writeData[i]);
    Serial.print("Write[");
    Serial.print(i);
    Serial.print("]: 0x");
    Serial.println(writeData[i], HEX);
  }
  digitalWrite(SS, HIGH);
  delay(2000);
}
```

---

## 🔍 调试技巧

1. **查看仿真波形**:
   - 关注 `spi_cs_n` 边沿
   - 检查 `bit_count` 是否正确递增到7
   - 验证 `o_byte_received` 脉冲时机

2. **调试输出**: 模块内置 `$display` 语句，可以在仿真中查看：
   ```
   [时间] SPI_SLAVE_HANDLER: State 0 -> 1
   [时间] SPI_SLAVE: Config TX buffer, length=8
   [时间] SPI_SLAVE: TX buf[0]=0x48
   [时间] SPI_SLAVE: Prepare TX byte[0]=0x48
   ```

3. **常见问题**:
   - **MISO一直为0**: 检查 `tx_buffer_ready` 是否为1
   - **接收数据丢失**: 检查 `rx_upload_enable` 是否已启用
   - **时序错误**: 确保系统时钟至少是SPI时钟的4倍

---

## 📊 资源占用估算

- **LUTs**: ~300 (包含两个256字节RAM)
- **FFs**: ~150
- **Block RAM**: 不使用（使用分布式RAM）

---

## ⚠️ 注意事项

1. **时钟域**: SPI信号经过三级同步器，引入3个系统时钟周期延迟
2. **缓冲区溢出**: 如果主机连续写入超过256字节且未及时上传，会覆盖旧数据
3. **CS控制**: 主机必须正确控制CS信号，每个字节传输完成后可以选择保持CS低或拉高
4. **SPI模式**: 当前仅支持Mode 0，如需其他模式请修改 `simple_spi_slave.v`

---

## 📖 协议文档更新

建议在 `doc/USB-CDC通信协议.md` 中添加：

```markdown
### SPI从机配置 (功能码 0x14)
| 字段 | 字节数 | 说明 |
|------|--------|------|
| 数据体 | N | 主机将要读取的数据（1-256字节）|

### SPI从机控制 (功能码 0x15)
| 字段 | 字节数 | 说明 |
|------|--------|------|
| 控制字 | 1 | Bit[0]: 0=禁用上传, 1=启用接收数据上传 |

### 数据来源标识
| 数据来源 | 标识 | 说明 |
|---------|------|------|
| SPI从机 | 0x14 | SPI从机接收的数据 |
```

---

## ✅ 完成情况

- ✅ SPI从机物理层实现 (`simple_spi_slave.v`)
- ✅ SPI从机Handler实现 (`spi_slave_handler.v`)
- ✅ 命令协议定义 (功能码 0x14, 0x15)
- ✅ 上传接口对接
- ✅ 使用说明文档

模块已完成，可以集成到您的cdc.v中进行测试！
