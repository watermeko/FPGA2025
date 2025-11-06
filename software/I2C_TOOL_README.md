# I2C Command Tool for FPGA2025

完整的 I2C 命令生成工具，用于 FPGA2025 USB-CDC 通信协议。

## 📁 文件说明

- **`i2c_command_tool.py`** - 核心命令生成库和命令行工具
- **`i2c_examples.py`** - 使用示例和测试脚本
- **`I2C_TOOL_README.md`** - 本说明文档

## 🚀 快速开始

### 1. 命令行模式

#### 配置 I2C
```bash
# 配置 I2C 从机地址为 0x50，时钟频率 100kHz
python i2c_command_tool.py config --addr 0x50 --freq 100000

# 输出:
# I2C Config: Addr=0x50, Freq=100000Hz
# Frame (8 bytes): AA 55 04 00 02 50 01 57
```

#### 写入数据
```bash
# 向寄存器 0x003C 写入 4 字节数据
python i2c_command_tool.py write --reg 0x003C --data "DEADBEEF"

# 输出:
# I2C Write: Reg=0x003C, Data=DEADBEEF (4 bytes)
# Frame (12 bytes): AA 55 05 00 06 00 3C DE AD BE EF 7F
```

#### 读取数据
```bash
# 从寄存器 0x003C 读取 4 字节
python i2c_command_tool.py read --reg 0x003C --len 4

# 输出:
# I2C Read: Reg=0x003C, Length=4 bytes
# Frame (10 bytes): AA 55 06 00 04 00 3C 00 04 4A
```

#### 仅输出十六进制（用于脚本）
```bash
# 只输出十六进制字符串，方便用于其他脚本
python i2c_command_tool.py write --reg 0x10 --data FF --hex-only

# 输出:
# AA5505000300100066
```

### 2. Python 模块模式

```python
from i2c_command_tool import *

# 配置 I2C
config_frame = i2c_config(slave_addr=0x50, freq_hz=400000)
print(config_frame.hex())  # AA5504000250035D

# 写入数据
write_frame = i2c_write(reg_addr=0x0000, data=[0x48, 0x65, 0x6C, 0x6C, 0x6F])
print(write_frame.hex())

# 读取数据
read_frame = i2c_read(reg_addr=0x0000, read_len=5)
print(read_frame.hex())

# 通过串口发送
import serial
import time

with serial.Serial('COM3', 115200) as ser:
    ser.write(config_frame)
    time.sleep(0.01)
    ser.write(write_frame)
    time.sleep(0.01)
    ser.write(read_frame)

    # 读取响应
    time.sleep(0.1)
    if ser.in_waiting > 0:
        response = ser.read(ser.in_waiting)
        print(f"Response: {response.hex().upper()}")
```

### 3. 运行示例脚本

```bash
# 运行所有示例，查看各种 I2C 操作
python i2c_examples.py
```

## 📋 I2C 协议说明

### 帧格式
```
[帧头(2)] [功能码(1)] [长度(2)] [数据体(N)] [校验和(1)]
0xAA55    0x04-0x06   大端模式   数据       和 & 0xFF
```

### 支持的命令

#### 0x04 - I2C 配置
**作用**: 配置 I2C 从机地址和时钟频率

**数据体格式**:
| 字节 | 说明 | 值 |
|------|------|-----|
| 0 | 从机地址 (7位) | 0x00-0x7F |
| 1 | 时钟频率代码 | 0x00=50kHz, 0x01=100kHz, 0x02=200kHz, 0x03=400kHz |

**示例**:
```
AA 55 04 00 02 50 01 57
         ^^功能码 ^^^^长度=2 ^^地址0x50 ^^100kHz ^^校验和
```

**参考代码**: `rtl/i2c/i2c_handler.v:166-180`

#### 0x05 - I2C 写入
**作用**: 向 I2C 设备的寄存器写入数据

**数据体格式**:
| 字节 | 说明 | 值 |
|------|------|-----|
| 0-1 | 寄存器地址 (16位大端) | 0x0000-0xFFFF |
| 2-N | 写入数据 (1-128字节) | 数据内容 |

**示例**:
```
AA 55 05 00 06 00 3C DE AD BE EF 7F
         ^^功能码 ^^^^长度=6 ^^^^寄存器0x003C ^^^^^^^^数据4字节 ^^校验和
```

**参考代码**: `rtl/i2c/i2c_handler.v:187-201`

#### 0x06 - I2C 读取
**作用**: 从 I2C 设备的寄存器读取数据

**数据体格式**:
| 字节 | 说明 | 值 |
|------|------|-----|
| 0-1 | 寄存器地址 (16位大端) | 0x0000-0xFFFF |
| 2-3 | 读取长度 (16位大端) | 0x0001-0x0080 (1-128字节) |

**示例**:
```
AA 55 06 00 04 00 3C 00 04 4A
         ^^功能码 ^^^^长度=4 ^^^^寄存器0x003C ^^^^读4字节 ^^校验和
```

**响应格式**:
```
AA 44 06 00 04 [4字节数据] [校验和]
^^^^上传帧头 ^^数据来源 ^^^^长度 ^^^读取的数据^^^ ^^校验和
```

**参考代码**: `rtl/i2c/i2c_handler.v:203-216`

### 校验和计算
```python
# 从功能码开始到数据体结束，所有字节累加后取低8位
checksum = (cmd + length_h + length_l + ... + payload[N-1]) & 0xFF
```

## 📚 常用设备示例

### EEPROM (AT24C64)
```python
from i2c_command_tool import *

# 1. 配置 I2C (地址 0x50, 400kHz)
config = i2c_config(0x50, 400000)

# 2. 写入字符串 "Hello" 到地址 0x0000
data = b"Hello"
write_cmd = i2c_write(0x0000, data)

# 3. 读取 5 字节
read_cmd = i2c_read(0x0000, 5)
```

### SSD1306 OLED 显示屏
```python
# 配置 I2C (地址 0x3C, 400kHz)
config = i2c_config(0x3C, 400000)

# 发送初始化命令
init_cmds = bytes([
    0x00,        # 控制字节：命令流
    0xAE,        # 关闭显示
    0xD5, 0x80,  # 设置时钟
    0xA8, 0x3F,  # 设置复用比 (64)
    0x8D, 0x14,  # 使能电荷泵
    0xAF,        # 开启显示
])
init_cmd = i2c_write(0x0000, init_cmds)
```

### LM75 温度传感器
```python
# 配置 I2C (地址 0x48, 100kHz)
config = i2c_config(0x48, 100000)

# 读取温度寄存器 (2字节)
read_temp = i2c_read(0x0000, 2)

# 温度计算: temp_celsius = (MSB << 8 | LSB) / 256.0
```

## 🔍 调试技巧

### 1. 查看完整帧结构
```bash
# 不使用 --hex-only 参数，可以看到详细的帧解析
python i2c_command_tool.py write --reg 0x10 --data FF
```

输出:
```
I2C Write: Reg=0x0010, Data=FF (1 bytes)
Frame (9 bytes): AA 55 05 00 03 00 10 FF 0D
  Header:   AA55 (Command)
  Command:  0x05
  Length:   3 (0x0003)
  Payload:  0010FF
  Checksum: 0x0D
```

### 2. 验证校验和
```python
from i2c_command_tool import calculate_checksum

# 手动计算校验和
data = bytes.fromhex("05000300100FF")  # 功能码到数据体结束
checksum = calculate_checksum(data)
print(f"Checksum: 0x{checksum:02X}")  # 0x0D
```

### 3. 对比协议文档
运行 `i2c_examples.py` 中的 Example 2，输出会自动与协议文档对比：

```
[OK] This matches the protocol documentation example:
  AA 55 05 00 06 00 3C DE AD BE EF 7F
```

## ⚠️ 常见错误

### 1. 地址超出范围
```python
# 错误: 8位地址
i2c_config(0x80, 100000)
# ValueError: Slave address must be 7-bit (0x00-0x7F)

# 正确: 7位地址
i2c_config(0x50, 100000)  # 正确
```

### 2. 不支持的频率
```python
# 错误: 不支持的频率
i2c_config(0x50, 115200)
# ValueError: Frequency must be one of [50000, 100000, 200000, 400000]

# 正确
i2c_config(0x50, 100000)  # 100kHz
i2c_config(0x50, 400000)  # 400kHz
```

### 3. 数据长度超限
```python
# 错误: 超过128字节
data = bytes([0xFF] * 200)
i2c_write(0x0000, data)
# ValueError: Data length exceeds buffer size (128 bytes)

# 正确: 最多128字节
data = bytes([0xFF] * 128)
i2c_write(0x0000, data)
```

## 🔗 相关文档

- **协议规范**: `doc/USB-CDC通信协议.md:107-146`
- **I2C Handler 代码**: `rtl/i2c/i2c_handler.v:1-315`
- **I2C Control 代码**: `rtl/i2c/i2c_control.v:1-231`
- **现有测试平台**: `sim/cdc_i2c_tb/`

## 🐛 与旧版本的差异

### ⚠️ 重要修正
原有的 `i2c_oled_command.py` 在配置命令格式上有错误：

**错误代码** (`i2c_oled_command.py:45`):
```python
# 错误: 发送了5字节 (4字节频率 + 1字节地址)
data_body = struct.pack('>IB', clock_frequency, slave_address)
```

**正确代码** (`i2c_command_tool.py:181-182`):
```python
# 正确: 发送2字节 (1字节地址 + 1字节频率代码)
freq_code = I2C_FREQ_MAP[freq_hz]
payload = struct.pack('BB', slave_addr, freq_code)
```

**对比 RTL 代码** (`rtl/i2c/i2c_handler.v:166-180`):
```verilog
// 数据体第0字节: 从机地址
device_addr_reg <= cmd_data;

// 数据体第1字节: 时钟频率代码
case(cmd_data)
    8'h00: scl_cnt_max_reg <= 20'd249; // 50kHz
    8'h01: scl_cnt_max_reg <= 20'd124; // 100kHz
    8'h02: scl_cnt_max_reg <= 20'd61;  // 200kHz
    8'h03: scl_cnt_max_reg <= 20'd30;  // 400kHz
endcase
```

### ✅ 新工具改进
1. **正确的配置命令格式** - 与 RTL 代码完全匹配
2. **完整的命令支持** - 配置、写入、读取三种命令
3. **详细的错误检查** - 地址范围、数据长度、频率代码
4. **两种使用模式** - 命令行工具 + Python 库
5. **丰富的示例** - EEPROM、OLED、温度传感器等
6. **清晰的文档** - 与协议文档和 RTL 代码对应

## 📝 许可证

MIT License

---

**作者**: FPGA2025 Project
**最后更新**: 2025-10-21
