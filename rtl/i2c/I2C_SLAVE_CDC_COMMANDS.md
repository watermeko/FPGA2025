# I2C从机CDC命令文档

## 概述

本文档描述通过USB-CDC接口控制FPGA内部I2C从机模块的命令协议。I2C从机模块包含4个8位寄存器，可通过CDC命令进行读写配置，外部I2C主机可通过物理I2C总线访问这些寄存器。

## 硬件架构

```
┌─────────────────────────────────────────────────────────────┐
│                         FPGA芯片                             │
│                                                               │
│  ┌──────────┐  CDC命令  ┌─────────────────┐                │
│  │   USB    │─────────>│ I2C Slave       │                 │
│  │   CDC    │           │ Handler         │                 │
│  │ Interface│<─────────│ (4个寄存器)     │                 │
│  └──────────┘  响应数据 └────────┬────────┘                │
│                                   │                          │
│                                   │ I2C物理接口              │
│                                   ↓                          │
│                          ┌────────────────┐                 │
│                          │  I2C Slave     │                 │
│                          │  Core          │                 │
│                          └───────┬────────┘                 │
│                                  │                          │
└──────────────────────────────────┼──────────────────────────┘
                                   │
                                   ↓ SDA/SCL
                          ┌────────────────┐
                          │  外部I2C主机   │
                          └────────────────┘
```

## 寄存器映射

I2C从机包含4个8位寄存器：

| 寄存器地址 | 名称   | 访问方式 | 复位值 | 说明                    |
|-----------|--------|---------|--------|-------------------------|
| 0x00      | REG0   | R/W     | 0x00   | 通用数据寄存器0         |
| 0x01      | REG1   | R/W     | 0x00   | 通用数据寄存器1         |
| 0x02      | REG2   | R/W     | 0x00   | 通用数据寄存器2         |
| 0x03      | REG3   | R/W     | 0x00   | 通用数据寄存器3         |

**访问方式：**
- **CDC访问**：通过USB-CDC命令（0x34/0x35/0x36）读写
- **I2C访问**：外部I2C主机通过物理I2C总线访问

## CDC命令协议

### 帧格式

所有CDC命令遵循统一的帧格式：

```
+--------+--------+--------+--------+--------+----------+----------+
| Header | Header |  CMD   | LEN_H  | LEN_L  | PAYLOAD  | CHECKSUM |
|  0xAA  |  0x55  | (1B)   | (1B)   | (1B)   | (0-N B)  |  (1B)    |
+--------+--------+--------+--------+--------+----------+----------+
```

- **Header**: 固定为 `0xAA 0x55`，标识帧起始
- **CMD**: 命令字节（0x34/0x35/0x36）
- **LEN_H/LEN_L**: Payload长度（大端序，16位）
- **PAYLOAD**: 命令数据（长度由LEN指定）
- **CHECKSUM**: 校验和 = (CMD + LEN_H + LEN_L + sum(PAYLOAD)) & 0xFF

### 响应帧格式

命令响应（读寄存器时）使用以下格式：

```
+--------+--------+--------+--------+--------+----------+----------+
| Header | Header | SOURCE | LEN_H  | LEN_L  |   DATA   | CHECKSUM |
|  0xAA  |  0x44  | (1B)   | (1B)   | (1B)   | (0-N B)  |  (1B)    |
+--------+--------+--------+--------+--------+----------+----------+
```

- **Header**: 固定为 `0xAA 0x44`，标识响应帧
- **SOURCE**: 数据源标识（I2C从机固定为0x36）
- **LEN_H/LEN_L**: 数据长度（大端序，16位）
- **DATA**: 读取的寄存器数据
- **CHECKSUM**: 校验和 = (SOURCE + LEN_H + LEN_L + sum(DATA)) & 0xFF

## 命令详解

### 0x34 - 设置I2C从机地址

**功能**: 配置I2C从机的7位地址

**Payload格式**:
```
Byte 0: I2C从机地址（7位，低7位有效）
```

**示例 - 设置地址为0x50**:
```
发送: AA 55 34 00 01 50 85
```

**说明**:
- 地址范围：0x08 - 0x77（避免保留地址）
- 默认地址：0x50
- 地址设置后立即生效
- 外部I2C主机需使用新地址访问

---

### 0x35 - 写寄存器

**功能**: 通过CDC接口写入I2C从机的寄存器

**Payload格式**:
```
Byte 0:       起始地址 (0-3)
Byte 1:       写入长度 (1-4)
Byte 2..N:    数据字节
```

**约束**:
- 起始地址必须在 0-3 范围内
- 写入长度必须在 1-4 范围内
- `起始地址 + 写入长度` 不能超过4

#### 示例1 - 写单个寄存器

**写入 Reg[0] = 0x55**:
```
发送: AA 55 35 00 03 00 01 55 8E

解析:
  Header:    AA 55
  Command:   0x35 (写寄存器)
  Length:    0x0003 (3字节payload)
  Payload[0]: 0x00 (起始地址 = 0)
  Payload[1]: 0x01 (写入1字节)
  Payload[2]: 0x55 (数据)
  Checksum:  0x8E
```

#### 示例2 - 写多个寄存器

**写入 Reg[0]=0xAA, Reg[1]=0xBB, Reg[2]=0xCC, Reg[3]=0xDD**:
```
发送: AA 55 35 00 06 00 04 AA BB CC DD 4D

解析:
  Header:     AA 55
  Command:    0x35 (写寄存器)
  Length:     0x0006 (6字节payload)
  Payload[0]: 0x00 (起始地址 = 0)
  Payload[1]: 0x04 (写入4字节)
  Payload[2]: 0xAA (Reg[0])
  Payload[3]: 0xBB (Reg[1])
  Payload[4]: 0xCC (Reg[2])
  Payload[5]: 0xDD (Reg[3])
  Checksum:   0x4D
```

#### 示例3 - 写部分寄存器

**写入 Reg[1]=0x12, Reg[2]=0x34**:
```
发送: AA 55 35 00 04 01 02 12 34 81

解析:
  Header:     AA 55
  Command:    0x35 (写寄存器)
  Length:     0x0004 (4字节payload)
  Payload[0]: 0x01 (起始地址 = 1)
  Payload[1]: 0x02 (写入2字节)
  Payload[2]: 0x12 (Reg[1])
  Payload[3]: 0x34 (Reg[2])
  Checksum:   0x81
```

**注意事项**:
- 写入操作无响应帧（fire-and-forget）
- 可通过外部I2C主机或CDC读命令验证写入结果
- 超出范围的地址或长度会被忽略

---

### 0x36 - 读寄存器

**功能**: 通过CDC接口读取I2C从机的寄存器

**Payload格式**:
```
Byte 0:  起始地址 (0-3)
Byte 1:  读取长度 (1-4)
```

**响应格式**:
```
Header:  AA 44
Source:  0x36 (I2C从机标识)
Length:  读取的字节数
Data:    寄存器数据
Checksum: 校验和
```

**约束**:
- 起始地址必须在 0-3 范围内
- 读取长度必须在 1-4 范围内
- `起始地址 + 读取长度` 不能超过4

#### 示例1 - 读单个寄存器

**读取 Reg[0]（假设值为0x55）**:
```
发送: AA 55 36 00 02 00 01 39

响应: AA 44 36 00 01 55 7A

响应解析:
  Header:    AA 44
  Source:    0x36 (I2C从机)
  Length:    0x0001 (1字节数据)
  Data[0]:   0x55 (Reg[0]的值)
  Checksum:  0x7A
```

#### 示例2 - 读多个寄存器

**读取 Reg[0]=0xAA, Reg[1]=0xBB, Reg[2]=0xCC, Reg[3]=0xDD**:
```
发送: AA 55 36 00 02 00 04 3C

响应: AA 44 36 00 04 AA BB CC DD 36

响应解析:
  Header:    AA 44
  Source:    0x36 (I2C从机)
  Length:    0x0004 (4字节数据)
  Data[0]:   0xAA (Reg[0])
  Data[1]:   0xBB (Reg[1])
  Data[2]:   0xCC (Reg[2])
  Data[3]:   0xDD (Reg[3])
  Checksum:  0x36
```

#### 示例3 - 读部分寄存器

**读取 Reg[2], Reg[3]（假设值为0x12, 0x34）**:
```
发送: AA 55 36 00 02 02 02 3A

响应: AA 44 36 00 02 12 34 7E

响应解析:
  Header:    AA 44
  Source:    0x36 (I2C从机)
  Length:    0x0002 (2字节数据)
  Data[0]:   0x12 (Reg[2])
  Data[1]:   0x34 (Reg[3])
  Checksum:  0x7E
```

---

## 校验和计算

### 发送命令校验和
```python
checksum = (CMD + LEN_H + LEN_L + sum(PAYLOAD)) & 0xFF
```

### 接收响应校验和
```python
checksum = (SOURCE + LEN_H + LEN_L + sum(DATA)) & 0xFF
```

### Python示例代码
```python
def calculate_checksum(cmd_or_source, length, data):
    """计算CDC帧校验和"""
    checksum = cmd_or_source
    checksum += (length >> 8) & 0xFF  # LEN_H
    checksum += length & 0xFF         # LEN_L
    for byte in data:
        checksum += byte
    return checksum & 0xFF

# 示例：写Reg[0]=0x55
cmd = 0x35
payload = [0x00, 0x01, 0x55]
length = len(payload)
checksum = calculate_checksum(cmd, length, payload)
# checksum = 0x8E
```

---

## 使用场景

### 场景1：配置I2C从机寄存器供外部主机读取

```
1. 通过CDC写入寄存器：
   AA 55 35 00 04 00 02 12 34 7E
   (写入 Reg[0]=0x12, Reg[1]=0x34)

2. 外部I2C主机读取：
   Master: START + 0xA0 (写地址0x50) + 0x00 (寄存器地址) + RESTART
   Master: START + 0xA1 (读地址0x50)
   Slave:  0x12 (Reg[0]) + ACK
   Slave:  0x34 (Reg[1]) + ACK
   Master: NACK + STOP
```

### 场景2：读取外部I2C主机写入的数据

```
1. 外部I2C主机写入寄存器：
   Master: START + 0xA0 + 0x00 + 0xAB + STOP
   (写入 Reg[0]=0xAB)

2. 通过CDC读取：
   发送: AA 55 36 00 02 00 01 39
   响应: AA 44 36 00 01 AB 7B
   (读取到 Reg[0]=0xAB)
```

### 场景3：寄存器完整性测试

```python
# 写入测试数据
write_frame = [0xAA, 0x55, 0x35, 0x00, 0x06,
               0x00, 0x04, 0x11, 0x22, 0x33, 0x44, 0x54]
send_to_usb_cdc(write_frame)

# 读取并验证
read_frame = [0xAA, 0x55, 0x36, 0x00, 0x02, 0x00, 0x04, 0x3C]
response = send_and_receive(read_frame)

# 验证响应
assert response == [0xAA, 0x44, 0x36, 0x00, 0x04,
                    0x11, 0x22, 0x33, 0x44, 0xFE]
```

---

## 错误处理

### 常见错误情况

1. **校验和错误**
   - 现象：命令发送后无响应或行为异常
   - 原因：计算错误或传输损坏
   - 解决：重新计算校验和或重发命令

2. **地址超出范围**
   - 现象：写入/读取命令无效
   - 原因：起始地址 > 3 或 起始地址+长度 > 4
   - 解决：检查地址和长度参数

3. **长度为0**
   - 现象：命令无效果
   - 原因：写入/读取长度设为0
   - 解决：长度至少为1

4. **响应超时**
   - 现象：读命令发送后无响应
   - 原因：系统忙或命令队列阻塞
   - 解决：等待并重试，检查系统状态

### 调试建议

1. **使用示波器/逻辑分析仪**
   - 监控I2C总线（SCL/SDA）
   - 验证从机地址和数据传输

2. **启用调试日志**
   - 在仿真中查看handler状态机
   - 检查upload数据流是否正常

3. **逐步测试**
   - 先测试单寄存器写入
   - 再测试单寄存器读取
   - 最后测试多寄存器批量操作

---

## 测试工具

### Python测试脚本

项目提供了完整的Python测试工具：

```bash
# 位置：software/i2c_slave_cdc_test.py

# 设置I2C从机地址
python i2c_slave_cdc_test.py set-addr 0x50

# 写单个寄存器
python i2c_slave_cdc_test.py write 0 0x55

# 写多个寄存器
python i2c_slave_cdc_test.py write 0 0xAA 0xBB 0xCC 0xDD

# 读单个寄存器
python i2c_slave_cdc_test.py read 0 1

# 读所有寄存器
python i2c_slave_cdc_test.py read 0 4

# 运行完整测试
python test_i2c_slave.py
```

### ModelSim仿真

完整的CDC环境测试：

```bash
cd sim/i2c_slave_cdc_env_tb
vsim -do cmd.do
```

仿真覆盖：
- ✅ CDC写单个寄存器
- ✅ CDC读单个寄存器
- ✅ CDC写所有寄存器
- ✅ CDC读所有寄存器
- ✅ Parser → Processor → Handler → Adapter → Packer完整链路

---

## 技术规格

| 参数              | 值                    |
|-------------------|----------------------|
| 寄存器数量        | 4                    |
| 寄存器位宽        | 8 bits               |
| I2C从机地址位宽   | 7 bits               |
| 默认I2C地址       | 0x50 (可配置)        |
| I2C速率支持       | 标准模式(100kHz)     |
|                   | 快速模式(400kHz)     |
| CDC命令响应时间   | < 1ms (典型)         |
| 系统时钟          | 50MHz                |

---

## 版本历史

| 版本   | 日期       | 修改内容                              |
|--------|-----------|--------------------------------------|
| v1.0   | 2025-11-05| 初始版本，支持0x34/0x35/0x36命令     |
| v1.1   | 2025-11-05| 修复cmd_ready死锁问题，优化上传逻辑  |

---

## 相关文档

- **USB-CDC通信协议**: `../../doc/USB-CDC通信协议.md`
- **I2C从机硬件设计**: `i2c_slave_handler.sv`
- **寄存器映射实现**: `reg_map.sv`
- **测试指南**: `../../software/i2c_slave_test_guide.md`

---

## 联系支持

如遇问题或需要技术支持，请查看：
- 仿真测试：`tb/i2c_slave_cdc_env_tb.sv`
- 测试脚本：`software/i2c_slave_cdc_test.py`
- GitHub Issues: [项目仓库]

---

**文档生成时间**: 2025-11-05
**适用固件版本**: v1.1+
**文档维护者**: Claude Code Assistant
