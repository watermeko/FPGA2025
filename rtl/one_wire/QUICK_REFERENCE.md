# 1-Wire 主机快速参考

## 📁 文件清单

### 核心模块
```
rtl/one_wire/
├── one_wire_master.v        (8.0K)  - 底层驱动，时序控制
├── one_wire_handler.v       (14K)   - 上层协议处理
├── README.md                (6.9K)  - 项目总结
├── INTEGRATION_GUIDE.md     (7.0K)  - 集成步骤详解
└── PROTOCOL.md              (7.6K)  - 协议说明

tb/
└── one_wire_master_tb.v     (6.4K)  - 仿真测试台

doc/
└── USB-CDC通信协议.md       (已更新) - 完整通信协议
```

---

## ⚡ 快速集成

### 1. 修改 cdc.v (9步骤)
```verilog
// 步骤1: 添加端口
inout wire onewire_io,

// 步骤2: 添加ready信号
wire onewire_ready;

// 步骤3: 修改cmd_ready
wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready &
                 spi_ready & dsm_ready & onewire_ready;

// 步骤4: 修改通道数
parameter NUM_UPLOAD_CHANNELS = 4;  // +1-Wire

// 步骤5-8: 添加上传信号、adapter、修改packer连接

// 步骤9: 实例化handler
one_wire_handler u_onewire_handler(...);
```

### 2. 修改 top.v
```verilog
// 添加端口
inout wire onewire_io,

// 连接到cdc
cdc u_cdc(
    .onewire_io(onewire_io),
    ...
);
```

### 3. 约束文件
```tcl
set_location_assignment PIN_XX -to onewire_io
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to onewire_io
```

---

## 📡 命令速查

### 功能码
```
0x20 - 复位与应答检测
0x21 - 写字节
0x22 - 读字节
0x23 - 写读操作
```

### 数据来源
```
0x04 - 1-Wire上传数据标识
```

---

## 🔧 DS18B20 温度读取

### 完整流程
```
1. AA 55 20 00 00 1F              # 复位
2. AA 55 21 00 01 CC 31           # Skip ROM
3. AA 55 21 00 01 44 65           # Convert T
4. 等待 750ms
5. AA 55 20 00 00 1F              # 复位
6. AA 55 21 00 01 CC 31           # Skip ROM
7. AA 55 23 00 03 01 09 BE 37     # Read Scratchpad (写1读9)
8. 接收: AA 44 04 00 09 [9字节] YY
9. 温度 = (MSB << 8 | LSB) / 16.0
```

### Python代码片段
```python
import serial
import time

ser = serial.Serial('COM3', 115200)

def calc_checksum(data):
    return sum(data) & 0xFF

def send_cmd(cmd):
    cmd.append(calc_checksum(cmd))
    ser.write(bytes(cmd))

# 读温度
send_cmd([0xAA, 0x55, 0x20, 0x00, 0x00])  # 复位
send_cmd([0xAA, 0x55, 0x21, 0x00, 0x01, 0xCC])  # Skip ROM
send_cmd([0xAA, 0x55, 0x21, 0x00, 0x01, 0x44])  # Convert
time.sleep(0.75)
send_cmd([0xAA, 0x55, 0x20, 0x00, 0x00])  # 复位
send_cmd([0xAA, 0x55, 0x21, 0x00, 0x01, 0xCC])  # Skip ROM
send_cmd([0xAA, 0x55, 0x23, 0x00, 0x03, 0x01, 0x09, 0xBE])  # Read

resp = ser.read(13)
temp_lsb = resp[5]
temp_msb = resp[6]
temp = ((temp_msb << 8) | temp_lsb) / 16.0
print(f"Temperature: {temp}°C")
```

---

## ⏱️ 时序参数 (@60MHz)

| 操作 | 时间 | 周期数 |
|-----|------|--------|
| 复位脉冲 | 480μs | 28800 |
| 应答检测 | 70μs | 4200 |
| 写0低电平 | 60μs | 3600 |
| 写1低电平 | 6μs | 360 |
| 读低电平 | 6μs | 360 |
| 读采样 | 9μs | 540 |

---

## 🔌 硬件连接

```
FPGA Pin          4.7kΩ        1-Wire Device
onewire_io --------/\/\/\----+---- VDD
                              |
                              +---- DQ
                              |
                              +---- GND (if needed)
```

---

## 🐛 常见问题

### 无应答
- 检查上拉电阻（4.7kΩ）
- 验证从机供电
- 用示波器检查复位脉冲

### 数据错误
- 确认时钟是60MHz
- 检查字节序（LSB first）
- 验证CRC校验（DS18B20最后一字节）

### 时序错误
- 测量实际时序
- 调整时序参数常量
- 检查系统时钟稳定性

---

## 📚 详细文档

| 文档 | 内容 |
|------|------|
| README.md | 项目总结、检查清单 |
| INTEGRATION_GUIDE.md | 详细集成步骤 |
| PROTOCOL.md | 协议详解、示例代码 |
| USB-CDC通信协议.md | 完整通信协议规范 |

---

## ✅ 集成检查清单

- [ ] 复制文件到项目
- [ ] 修改 cdc.v (9步)
- [ ] 修改 top.v (2步)
- [ ] 添加约束文件
- [ ] 仿真验证
- [ ] 综合工程
- [ ] 硬件测试
- [ ] 读取DS18B20温度

---

**版本**: v1.0
**日期**: 2025-10-12
