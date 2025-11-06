# I2C 命令工具使用指南

## 快速开始 🚀

### 1️⃣ 命令行使用

#### 配置 I2C 设备
```bash
# 配置 EEPROM: 地址 0x50, 频率 100kHz
python i2c_command_tool.py config --addr 0x50 --freq 100000

# 配置 OLED: 地址 0x3C, 频率 400kHz
python i2c_command_tool.py config --addr 0x3C --freq 400000
```

#### 写入数据
```bash
# 向寄存器 0x003C 写入 4 字节
python i2c_command_tool.py write --reg 0x003C --data "DEADBEEF"

# 写入字符串 "Hello" (转换为十六进制)
python i2c_command_tool.py write --reg 0x0000 --data "48656C6C6F"
```

#### 读取数据
```bash
# 从寄存器 0x003C 读取 4 字节
python i2c_command_tool.py read --reg 0x003C --len 4

# 读取 EEPROM 前 16 字节
python i2c_command_tool.py read --reg 0x0000 --len 16
```

---

### 2️⃣ Python 脚本使用

```python
from i2c_command_tool import *
import serial
import time

# 打开串口
ser = serial.Serial('COM3', 115200, timeout=1)

# 1. 配置 I2C (地址 0x50, 100kHz)
config = i2c_config(0x50, 100000)
ser.write(config)
time.sleep(0.01)

# 2. 写入数据到 EEPROM
write_cmd = i2c_write(0x0000, b"Hello FPGA!")
ser.write(write_cmd)
time.sleep(0.01)

# 3. 读取数据
read_cmd = i2c_read(0x0000, 11)
ser.write(read_cmd)
time.sleep(0.1)

# 4. 接收响应
if ser.in_waiting > 0:
    response = ser.read(ser.in_waiting)
    print(f"收到: {response.hex().upper()}")

ser.close()
```

---

## 常用设备示例 📱

### EEPROM (AT24C64)
```python
# 配置
config = i2c_config(0x50, 400000)

# 写入 "Hello World"
write_data = i2c_write(0x0000, b"Hello World")

# 读取 11 字节
read_data = i2c_read(0x0000, 11)
```

### OLED 显示屏 (SSD1306)
```python
# 配置
config = i2c_config(0x3C, 400000)

# 初始化命令
init = i2c_write(0x0000, bytes([
    0x00,        # 控制字节
    0xAE,        # 关闭显示
    0x8D, 0x14,  # 使能电荷泵
    0xAF,        # 开启显示
]))
```

### 温度传感器 (LM75)
```python
# 配置
config = i2c_config(0x48, 100000)

# 读取温度 (2字节)
read_temp = i2c_read(0x0000, 2)

# 温度计算: temp = (MSB << 8 | LSB) / 256.0
```

---

## 协议格式说明 📋

### 命令帧格式
```
[帧头] [功能码] [长度] [数据体] [校验和]
AA 55   04-06   2字节   N字节    1字节
```

### I2C 命令一览

| 功能码 | 命令 | 数据体 | 说明 |
|--------|------|--------|------|
| 0x04 | 配置 | [地址][频率代码] | 配置从机地址和时钟频率 |
| 0x05 | 写入 | [寄存器地址 16位][数据 1-128字节] | 写入寄存器 |
| 0x06 | 读取 | [寄存器地址 16位][长度 16位] | 读取寄存器 |

### 时钟频率代码

| 代码 | 频率 |
|------|------|
| 0x00 | 50kHz |
| 0x01 | 100kHz |
| 0x02 | 200kHz |
| 0x03 | 400kHz |

---

## 完整示例：EEPROM 读写 💾

```python
from i2c_command_tool import *
import serial
import time

def eeprom_test():
    # 打开串口
    ser = serial.Serial('COM3', 115200, timeout=1)

    print("1. 配置 I2C...")
    ser.write(i2c_config(0x50, 100000))
    time.sleep(0.01)

    print("2. 写入数据...")
    data = b"FPGA2025 Test Data"
    ser.write(i2c_write(0x0000, data))
    time.sleep(0.05)  # EEPROM 写入需要时间

    print("3. 读取数据...")
    ser.write(i2c_read(0x0000, len(data)))
    time.sleep(0.1)

    print("4. 接收响应...")
    if ser.in_waiting > 0:
        response = ser.read(ser.in_waiting)
        # 解析响应 (跳过协议头)
        if len(response) > 6:
            received_data = response[5:-1]  # 去掉头和校验和
            print(f"读取成功: {received_data.decode('ascii')}")

    ser.close()

eeprom_test()
```

**预期输出**:
```
1. 配置 I2C...
2. 写入数据...
3. 读取数据...
4. 接收响应...
读取成功: FPGA2025 Test Data
```

---

## 运行示例脚本 🎯

```bash
# 查看所有示例
python i2c_examples.py

# 示例包括:
# - EEPROM 读写操作
# - 多字节 EEPROM 操作
# - SSD1306 OLED 初始化
# - LM75 温度传感器读取
# - 单字节读写操作
```

---

## 错误排查 🔍

### 问题：串口打不开
```
[ERROR] Could not open serial port COM3
```
**解决方法**:
- 检查串口号是否正确（Windows: COM1-COM9, Linux: /dev/ttyUSB0）
- 确认没有其他程序占用串口
- 验证 USB 线缆连接正常

### 问题：无响应
**可能原因**:
1. I2C 地址错误 → 检查设备数据手册
2. 时钟频率过高 → 尝试降低到 100kHz
3. 硬件连接问题 → 检查 SCL/SDA 引脚和上拉电阻

### 问题：数据错误
**检查清单**:
- ✅ 寄存器地址是否正确（16位大端格式）
- ✅ 数据长度是否超过 128 字节
- ✅ EEPROM 写入后需要等待 5-10ms
- ✅ 校验和是否匹配

---

## 对比旧版本 ⚠️

### 旧版 `i2c_oled_command.py` 的问题

**错误的配置命令** (第 45 行):
```python
# ❌ 错误: 发送 5 字节 (4字节频率 + 1字节地址)
data_body = struct.pack('>IB', clock_frequency, slave_address)
```

**新版正确实现**:
```python
# ✅ 正确: 发送 2 字节 (1字节地址 + 1字节频率代码)
freq_code = I2C_FREQ_MAP[freq_hz]
payload = struct.pack('BB', slave_addr, freq_code)
```

### 新工具优势
- ✅ 与 RTL 代码完全一致 (`rtl/i2c/i2c_handler.v:166-180`)
- ✅ 与协议文档完全匹配 (`doc/USB-CDC通信协议.md`)
- ✅ 完整的错误检查和参数验证
- ✅ 支持命令行和 Python 库两种模式
- ✅ 丰富的使用示例和文档

---

## 参考资料 📚

- **详细说明**: `I2C_TOOL_README.md`
- **协议文档**: `doc/USB-CDC通信协议.md`
- **RTL 代码**: `rtl/i2c/i2c_handler.v`
- **仿真测试**: `sim/cdc_i2c_tb/`

---

**最后更新**: 2025-10-21
**作者**: FPGA2025 Project
