# I2C从机CDC命令测试指南

## 概述

本指南介绍如何使用CDC命令总线测试I2C从机模块的寄存器读写功能。

## 测试环境

- **FPGA板**: GW5A-25A
- **USB-CDC接口**: 通过USB连接PC
- **测试工具**: `i2c_slave_cdc_test.py`
- **默认串口波特率**: 115200

## CDC命令说明

### 命令0x34: 设置I2C从机地址

动态配置I2C从机地址(7位)。

**数据格式:**
```
AA 55 34 00 01 [ADDR] [CS]
```

**字段说明:**
- `AA 55`: 帧头
- `34`: 命令码
- `00 01`: 数据长度(1字节)
- `[ADDR]`: 新的7位从机地址
- `[CS]`: 校验和

**示例: 设置地址为0x25**
```
AA 55 34 00 01 25 5A
```

### 命令0x35: CDC写寄存器

通过CDC总线写入I2C从机内部寄存器(共4个寄存器: 0-3)。

**数据格式:**
```
AA 55 35 00 [LEN] [START_ADDR] [DATA_LEN] [DATA...] [CS]
```

**字段说明:**
- `AA 55`: 帧头
- `35`: 命令码
- `00 [LEN]`: 数据长度(起始地址 + 数据长度字节 + 数据)
- `[START_ADDR]`: 起始寄存器地址(0-3)
- `[DATA_LEN]`: 要写入的字节数(1-4)
- `[DATA...]`: 要写入的数据
- `[CS]`: 校验和

**示例1: 写入寄存器2和3**
```
写入数据: Reg[2]=0x11, Reg[3]=0x22
命令: AA 55 35 00 04 02 02 11 22 A0
      ^^^^帧头 ^^命令 ^^^^长度4 ^^起始地址2 ^^写2字节 ^^数据 ^^校验和
```

**示例2: 写入所有4个寄存器**
```
写入数据: Reg[0]=0xAA, Reg[1]=0xBB, Reg[2]=0xCC, Reg[3]=0xDD
命令: AA 55 35 00 06 00 04 AA BB CC DD 08
      ^^^^帧头 ^^命令 ^^^^长度6 ^^起始地址0 ^^写4字节 ^^^数据^^^ ^^校验和
```

**示例3: 写入单个寄存器**
```
写入数据: Reg[1]=0x55
命令: AA 55 35 00 03 01 01 55 CA
      ^^^^帧头 ^^命令 ^^^^长度3 ^^起始地址1 ^^写1字节 ^^数据 ^^校验和
```

### 命令0x36: CDC读寄存器

通过CDC总线读取I2C从机内部寄存器。

**请求格式:**
```
AA 55 36 00 02 [START_ADDR] [READ_LEN] [CS]
```

**响应格式:**
```
AA 44 36 00 [LEN] [DATA...] [CS]
```

**字段说明:**
- 请求:
  - `AA 55`: 帧头
  - `36`: 命令码
  - `00 02`: 数据长度(固定2字节)
  - `[START_ADDR]`: 起始寄存器地址(0-3)
  - `[READ_LEN]`: 要读取的字节数(1-4)
  - `[CS]`: 校验和

- 响应:
  - `AA 44`: 上传数据帧头
  - `36`: 数据来源(I2C_SLAVE)
  - `00 [LEN]`: 数据长度
  - `[DATA...]`: 寄存器值
  - `[CS]`: 校验和

**示例1: 读取所有4个寄存器**
```
请求: AA 55 36 00 02 00 04 70
      ^^^^帧头 ^^命令 ^^^^长度2 ^^起始地址0 ^^读4字节 ^^校验和

响应: AA 44 36 00 04 AA BB CC DD [CS]
      ^^^^上传帧头 ^^来源 ^^^^长度4 ^^^读取的数据^^^ ^^校验和
```

**示例2: 读取寄存器2和3**
```
请求: AA 55 36 00 02 02 02 6E
      ^^^^帧头 ^^命令 ^^^^长度2 ^^起始地址2 ^^读2字节 ^^校验和

响应: AA 44 36 00 02 CC DD [CS]
      ^^^^上传帧头 ^^来源 ^^^^长度2 ^^数据 ^^校验和
```

**示例3: 读取单个寄存器0**
```
请求: AA 55 36 00 02 00 01 6D
      ^^^^帧头 ^^命令 ^^^^长度2 ^^起始地址0 ^^读1字节 ^^校验和

响应: AA 44 36 00 01 AA [CS]
      ^^^^上传帧头 ^^来源 ^^^^长度1 ^^数据 ^^校验和
```

## Python工具使用方法

### 1. 安装依赖

```bash
pip install pyserial
```

### 2. 命令行使用

#### 查看帮助
```bash
python i2c_slave_cdc_test.py --help
python i2c_slave_cdc_test.py write --help
python i2c_slave_cdc_test.py read --help
```

#### 设置从机地址
```bash
# 生成命令(不发送)
python i2c_slave_cdc_test.py set-addr --addr 0x25

# 通过串口发送
python i2c_slave_cdc_test.py set-addr --addr 0x25 --port COM3
```

#### 写寄存器测试
```bash
# 写入寄存器2和3
python i2c_slave_cdc_test.py write --start 2 --data "11 22" --port COM3

# 写入所有4个寄存器
python i2c_slave_cdc_test.py write --start 0 --data "AA BB CC DD" --port COM3

# 写入单个寄存器
python i2c_slave_cdc_test.py write --start 1 --data "55" --port COM3
```

#### 读寄存器测试
```bash
# 读取所有4个寄存器
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3

# 读取寄存器2和3
python i2c_slave_cdc_test.py read --start 2 --len 2 --port COM3

# 读取单个寄存器0
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3
```

#### 保存命令到文件
```bash
# 生成命令并保存
python i2c_slave_cdc_test.py write --start 0 --data "AA BB" -o write_cmd.bin
python i2c_slave_cdc_test.py read --start 0 --len 2 -o read_cmd.bin
```

### 3. Python脚本使用

创建测试脚本 `test_i2c_slave.py`:

```python
#!/usr/bin/env python3
import serial
import time
from i2c_slave_cdc_test import *

# 配置串口
PORT = 'COM3'  # Windows
# PORT = '/dev/ttyUSB0'  # Linux
BAUDRATE = 115200

def test_write_read_cycle():
    """测试完整的写-读循环"""
    with serial.Serial(PORT, BAUDRATE, timeout=2) as ser:
        print("="*70)
        print("I2C Slave Register Write-Read Test")
        print("="*70)

        # 清空缓冲区
        ser.reset_input_buffer()
        ser.reset_output_buffer()

        # 测试1: 写入所有寄存器
        print("\n[Test 1] Write all registers...")
        test_data = [0xAA, 0xBB, 0xCC, 0xDD]
        write_frame = i2c_slave_write_registers(0, test_data)
        print(f"Sending: {write_frame.hex().upper()}")
        ser.write(write_frame)
        time.sleep(0.1)
        print("✓ Write complete")

        # 测试2: 读取所有寄存器
        print("\n[Test 2] Read all registers...")
        read_frame = i2c_slave_read_registers(0, 4)
        print(f"Sending: {read_frame.hex().upper()}")
        ser.write(read_frame)
        time.sleep(0.1)

        # 接收响应
        response = ser.read(100)
        if response:
            print(f"Received: {response.hex().upper()}")
            parsed = parse_upload_response(response)

            if parsed['valid']:
                print("✓ Valid response received")
                print("\nRegister Values:")
                for i, byte in enumerate(parsed['data']):
                    expected = test_data[i]
                    status = "✓" if byte == expected else "✗"
                    print(f"  {status} Reg[{i}] = 0x{byte:02X} (expected 0x{expected:02X})")

                # 验证数据
                if list(parsed['data']) == test_data:
                    print("\n✓ ALL TESTS PASSED!")
                    return True
                else:
                    print("\n✗ Data mismatch!")
                    return False
            else:
                print(f"✗ Invalid response: {parsed['error']}")
                return False
        else:
            print("✗ No response received")
            return False

def test_partial_write_read():
    """测试部分寄存器读写"""
    with serial.Serial(PORT, BAUDRATE, timeout=2) as ser:
        print("\n" + "="*70)
        print("Partial Register Write-Read Test")
        print("="*70)

        ser.reset_input_buffer()
        ser.reset_output_buffer()

        # 写入寄存器2和3
        print("\n[Test 3] Write Reg[2:3]...")
        test_data = [0x11, 0x22]
        write_frame = i2c_slave_write_registers(2, test_data)
        ser.write(write_frame)
        time.sleep(0.1)
        print("✓ Write complete")

        # 读取寄存器2和3
        print("\n[Test 4] Read Reg[2:3]...")
        read_frame = i2c_slave_read_registers(2, 2)
        ser.write(read_frame)
        time.sleep(0.1)

        response = ser.read(100)
        if response:
            parsed = parse_upload_response(response)
            if parsed['valid']:
                print("✓ Valid response received")
                print("\nRegister Values:")
                for i, byte in enumerate(parsed['data']):
                    reg_addr = 2 + i
                    expected = test_data[i]
                    status = "✓" if byte == expected else "✗"
                    print(f"  {status} Reg[{reg_addr}] = 0x{byte:02X} (expected 0x{expected:02X})")

                return list(parsed['data']) == test_data
            else:
                print(f"✗ Invalid response: {parsed['error']}")
                return False
        else:
            print("✗ No response received")
            return False

if __name__ == '__main__':
    try:
        result1 = test_write_read_cycle()
        result2 = test_partial_write_read()

        print("\n" + "="*70)
        print("TEST SUMMARY")
        print("="*70)
        print(f"Full Register Test:    {'PASS ✓' if result1 else 'FAIL ✗'}")
        print(f"Partial Register Test: {'PASS ✓' if result2 else 'FAIL ✗'}")

        if result1 and result2:
            print("\n🎉 All tests passed!")
        else:
            print("\n⚠️  Some tests failed")

    except Exception as e:
        print(f"\n✗ Test error: {e}")
```

## 完整测试流程

### 步骤1: 准备硬件
1. 将FPGA板通过USB连接到PC
2. 确认USB-CDC设备已识别(查看设备管理器/`ls /dev/ttyUSB*`)
3. 记录串口号(如COM3)

### 步骤2: 快速测试(命令行)

```bash
# Windows示例
cd F:\FPGA2025_ee_fix_up\FPGA2025-main\software

# 测试写入
python i2c_slave_cdc_test.py write --start 0 --data "AA BB CC DD" --port COM3

# 测试读取
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3
```

### 步骤3: 完整测试(脚本)

```bash
# 运行完整测试脚本
python test_i2c_slave.py
```

### 步骤4: 预期结果

**写入命令成功:**
```
Sending 11 bytes to COM3...
✓ Sent successfully
```

**读取命令成功:**
```
✓ Received 10 bytes

✓ Valid response:
  Source:   0x36 (I2C_SLAVE)
  Length:   4 bytes
  Data:     AABBCCDD

  Register Values:
    Reg[0] = 0xAA (170)
    Reg[1] = 0xBB (187)
    Reg[2] = 0xCC (204)
    Reg[3] = 0xDD (221)
```

## 常见问题排查

### 问题1: 无响应

**症状:** 发送读命令后无任何响应

**可能原因:**
1. 串口未正确打开
2. FPGA固件未运行
3. CDC命令处理器未启用

**解决方法:**
```bash
# 1. 检查串口
python -m serial.tools.list_ports

# 2. 测试心跳命令(0xFF)
# 创建心跳测试
echo -ne '\xAA\x55\xFF\x00\x00\xF5' > heartbeat.bin

# 3. 检查波特率是否正确
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3 --baudrate 115200
```

### 问题2: 校验和错误

**症状:** 返回"Checksum mismatch"

**可能原因:**
1. 数据传输错误
2. FPGA响应格式不正确

**解决方法:**
```python
# 查看原始响应数据
response = ser.read(100)
print("Raw response:", response.hex().upper())
```

### 问题3: 读取的数据不正确

**症状:** 读取的值与写入的值不匹配

**可能原因:**
1. 寄存器地址错误
2. 写入未生效
3. 寄存器被其他模块修改

**调试方法:**
```bash
# 1. 分步测试
python i2c_slave_cdc_test.py write --start 0 --data "12" --port COM3
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3

# 2. 测试单个寄存器
for i in 0 1 2 3; do
    python i2c_slave_cdc_test.py write --start $i --data "FF" --port COM3
    python i2c_slave_cdc_test.py read --start $i --len 1 --port COM3
done
```

## 高级测试

### 测试1: 压力测试(连续读写)

```python
import time
for i in range(100):
    write_frame = i2c_slave_write_registers(0, [i & 0xFF, (i+1) & 0xFF])
    ser.write(write_frame)
    time.sleep(0.01)

    read_frame = i2c_slave_read_registers(0, 2)
    ser.write(read_frame)
    response = ser.read(100)
    # 验证响应
```

### 测试2: 边界条件测试

```bash
# 测试最大地址
python i2c_slave_cdc_test.py write --start 3 --data "FF" --port COM3
python i2c_slave_cdc_test.py read --start 3 --len 1 --port COM3

# 测试最大长度
python i2c_slave_cdc_test.py write --start 0 --data "00 11 22 33" --port COM3
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3
```

## 附录: 原始命令速查表

| 操作 | 命令示例 | 说明 |
|------|---------|------|
| 设置地址0x25 | `AA 55 34 00 01 25 5A` | 设置I2C从机地址 |
| 写Reg[0-3] | `AA 55 35 00 06 00 04 AA BB CC DD 08` | 写入4个寄存器 |
| 写Reg[2-3] | `AA 55 35 00 04 02 02 11 22 A0` | 写入2个寄存器 |
| 写Reg[1] | `AA 55 35 00 03 01 01 55 CA` | 写入单个寄存器 |
| 读Reg[0-3] | `AA 55 36 00 02 00 04 70` | 读取4个寄存器 |
| 读Reg[2-3] | `AA 55 36 00 02 02 02 6E` | 读取2个寄存器 |
| 读Reg[0] | `AA 55 36 00 02 00 01 6D` | 读取单个寄存器 |

## 参考资料

- I2C从机模块源码: `rtl/i2c/i2c_slave_handler.sv`
- CDC协议文档: `doc/USB-CDC通信协议.md`
- 测试工具源码: `software/i2c_slave_cdc_test.py`
