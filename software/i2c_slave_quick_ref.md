# I2C从机CDC测试 - 快速参考卡

## 🚀 快速开始

```bash
# 1. 进入工具目录
cd F:\FPGA2025_ee_fix_up\FPGA2025-main\software

# 2. 确认串口(设备管理器查看)
# 例如: COM3

# 3. 运行完整测试
python test_i2c_slave.py COM3
```

## 📋 测试命令速查

### 命令1: 写所有寄存器 (0x35)

```bash
# 写入: Reg[0]=0xAA, Reg[1]=0xBB, Reg[2]=0xCC, Reg[3]=0xDD
python i2c_slave_cdc_test.py write --start 0 --data "AA BB CC DD" --port COM3
```

**原始命令帧:**
```
AA 55 35 00 06 00 04 AA BB CC DD 08
└─┘└─┘└─┘└───┘└─┘└─┘└───────┘└─┘
头   命  长度  起  长  数据    校验
```

### 命令2: 读所有寄存器 (0x36)

```bash
# 读取所有4个寄存器
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3
```

**原始命令帧:**
```
AA 55 36 00 02 00 04 70
└─┘└─┘└─┘└───┘└─┘└─┘└─┘
头   命  长度  起  长  校验
```

**预期响应:**
```
AA 44 36 00 04 AA BB CC DD [CS]
└─┘└─┘└─┘└───┘└───────┘ └─┘
头   源  长度  数据       校验
```

### 命令3: 部分寄存器测试

```bash
# 写入Reg[2:3]
python i2c_slave_cdc_test.py write --start 2 --data "11 22" --port COM3

# 读取Reg[2:3]
python i2c_slave_cdc_test.py read --start 2 --len 2 --port COM3
```

### 命令4: 单寄存器测试

```bash
# 写入Reg[1]=0x55
python i2c_slave_cdc_test.py write --start 1 --data "55" --port COM3

# 读取Reg[1]
python i2c_slave_cdc_test.py read --start 1 --len 1 --port COM3
```

## 🔧 原始命令对照表

| 操作 | 原始命令 | 说明 |
|------|---------|------|
| 写Reg[0:3] | `AA 55 35 00 06 00 04 AA BB CC DD 08` | 写4个寄存器 |
| 读Reg[0:3] | `AA 55 36 00 02 00 04 70` | 读4个寄存器 |
| 写Reg[2:3] | `AA 55 35 00 04 02 02 11 22 A0` | 写2个寄存器 |
| 读Reg[2:3] | `AA 55 36 00 02 02 02 6E` | 读2个寄存器 |
| 写Reg[1] | `AA 55 35 00 03 01 01 55 CA` | 写1个寄存器 |
| 读Reg[1] | `AA 55 36 00 02 01 01 6E` | 读1个寄存器 |

## 📊 数据格式说明

### CDC写命令 (0x35)

```
字段          字节数  说明
-----------  ------  --------------------------
帧头          2      AA 55 (固定)
命令码        1      35 (固定)
数据长度      2      N+2 (起始地址+长度字节+数据)
起始地址      1      0-3 (寄存器地址)
数据长度字节  1      1-4 (要写入的字节数)
数据          N      实际数据
校验和        1      累加和 & 0xFF
```

### CDC读命令 (0x36)

```
【请求】
字段          字节数  说明
-----------  ------  --------------------------
帧头          2      AA 55 (固定)
命令码        1      36 (固定)
数据长度      2      00 02 (固定2字节)
起始地址      1      0-3 (寄存器地址)
读取长度      1      1-4 (要读取的字节数)
校验和        1      累加和 & 0xFF

【响应】
字段          字节数  说明
-----------  ------  --------------------------
帧头          2      AA 44 (上传数据标识)
数据源        1      36 (I2C_SLAVE)
数据长度      2      N (读取的字节数)
数据          N      寄存器值
校验和        1      累加和 & 0xFF
```

## ✅ 测试检查清单

上板测试前检查:

- [ ] USB线连接正常
- [ ] FPGA已烧录最新固件
- [ ] 设备管理器中识别到CDC设备
- [ ] 记录正确的串口号 (如COM3)
- [ ] 已安装pyserial: `pip install pyserial`

## 🎯 推荐测试顺序

### 1. 基础连通性测试
```bash
# 测试心跳(可选)
python uart_command.py tx "hello" --port COM3
```

### 2. 简单读写测试
```bash
# 写1个寄存器
python i2c_slave_cdc_test.py write --start 0 --data "12" --port COM3

# 读1个寄存器
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3
```

### 3. 完整功能测试
```bash
# 运行完整测试套件
python test_i2c_slave.py COM3
```

## 🐛 常见问题

### 问题: 无响应
```bash
# 检查串口列表
python -m serial.tools.list_ports

# 尝试不同波特率
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3 --baudrate 9600
```

### 问题: 数据不匹配
```bash
# 分步测试
python i2c_slave_cdc_test.py write --start 0 --data "FF" --port COM3
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3

# 查看详细输出
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3
```

### 问题: 校验和错误
```python
# 手动测试原始命令
import serial
ser = serial.Serial('COM3', 115200, timeout=2)

# 发送读命令
cmd = bytes.fromhex('AA5536000200047')
ser.write(cmd)

# 查看原始响应
response = ser.read(100)
print(response.hex().upper())
```

## 📁 相关文件

- **测试工具**: `i2c_slave_cdc_test.py`
- **自动测试脚本**: `test_i2c_slave.py`
- **详细文档**: `i2c_slave_test_guide.md`
- **I2C从机源码**: `../rtl/i2c/i2c_slave_handler.sv`
- **CDC协议文档**: `../doc/USB-CDC通信协议.md`

## 💡 使用技巧

### 只生成命令不发送
```bash
python i2c_slave_cdc_test.py write --start 0 --data "AA BB"
# 输出命令但不发送到串口
```

### 保存命令到文件
```bash
python i2c_slave_cdc_test.py write --start 0 --data "AA BB" -o write.bin
python i2c_slave_cdc_test.py read --start 0 --len 2 -o read.bin
```

### 查看十六进制命令
```bash
python i2c_slave_cdc_test.py write --start 0 --data "AA BB" --hex-only
# 输出: AA553500040002AABB...
```

### Python脚本使用
```python
from i2c_slave_cdc_test import *
import serial

ser = serial.Serial('COM3', 115200, timeout=1)

# 写入寄存器
frame = i2c_slave_write_registers(0, [0x12, 0x34])
ser.write(frame)

# 读取寄存器
frame = i2c_slave_read_registers(0, 2)
ser.write(frame)
response = ser.read(100)

# 解析响应
parsed = parse_upload_response(response)
if parsed['valid']:
    print(f"Data: {parsed['data'].hex()}")
```

## 🎓 示例输出

**成功的测试输出:**
```
I2C SLAVE CDC COMMAND TEST SUITE
======================================================================

Configuration:
  Serial Port: COM3
  Baud Rate:   115200
  Timeout:     2 seconds

✓ Serial port opened successfully

======================================================================
TEST CASE 1: Full Register Write-Read Cycle
======================================================================

Step 1: Writing test data to Reg[0:3]
  Data: 0xAA 0xBB 0xCC 0xDD
  Command: AA5535000600AABBCCDD08
  ✓ Write command sent

Step 2: Reading back Reg[0:3]
  Command: AA5536000200047
  Received: AA443600AABBCCDD[CS]
  ✓ Valid response received

Step 3: Verifying data
  ✓ Reg[0] = 0xAA (OK)
  ✓ Reg[1] = 0xBB (OK)
  ✓ Reg[2] = 0xCC (OK)
  ✓ Reg[3] = 0xDD (OK)

  ✓ TEST 1 PASSED: All registers match!

...

======================================================================
TEST SUMMARY
======================================================================
  ✓ PASS  Test 1: Full Register Write-Read
  ✓ PASS  Test 2: Partial Register Write-Read
  ✓ PASS  Test 3: Single Register Operations
  ✓ PASS  Test 4: Boundary Conditions
  ✓ PASS  Test 5: Sequential Pattern

  Results: 5/5 tests passed

  🎉 ALL TESTS PASSED! 🎉

  I2C Slave CDC commands are working correctly!
```
