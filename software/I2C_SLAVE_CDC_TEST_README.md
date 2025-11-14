# I2C从机CDC测试工具包

完整的I2C从机模块测试工具,用于通过CDC命令总线验证寄存器读写功能。

## 📦 文件清单

| 文件 | 说明 |
|------|------|
| `i2c_slave_cdc_test.py` | 核心测试工具,生成CDC命令并通过串口通信 |
| `test_i2c_slave.py` | 自动化测试脚本,包含完整测试套件 |
| `i2c_slave_test_guide.md` | 详细测试指南,包含协议说明和故障排查 |
| `i2c_slave_quick_ref.md` | 快速参考卡片,上板测试速查表 |

## 🚀 快速开始

### 1. 安装依赖

```bash
pip install pyserial
```

### 2. 运行自动测试

```bash
# Windows
python test_i2c_slave.py COM3

# Linux
python test_i2c_slave.py /dev/ttyUSB0
```

### 3. 手动测试命令

```bash
# 写入寄存器
python i2c_slave_cdc_test.py write --start 0 --data "AA BB CC DD" --port COM3

# 读取寄存器
python i2c_slave_cdc_test.py read --start 0 --len 4 --port COM3
```

## 📖 功能说明

### 支持的CDC命令

- **0x34**: 动态设置I2C从机地址
- **0x35**: 通过CDC总线写I2C从机寄存器
- **0x36**: 通过CDC总线读I2C从机寄存器

### 寄存器说明

I2C从机模块包含4个8位寄存器(地址0-3):
- 可通过CDC命令总线访问
- 可通过物理I2C接口访问
- 支持FPGA内部预加载

## 💻 使用示例

### 命令行使用

```bash
# 查看帮助
python i2c_slave_cdc_test.py --help
python i2c_slave_cdc_test.py write --help

# 设置从机地址
python i2c_slave_cdc_test.py set-addr --addr 0x25 --port COM3

# 写入所有寄存器
python i2c_slave_cdc_test.py write --start 0 --data "AA BB CC DD" --port COM3

# 读取部分寄存器
python i2c_slave_cdc_test.py read --start 2 --len 2 --port COM3

# 保存命令到文件
python i2c_slave_cdc_test.py write --start 0 --data "12 34" -o write_cmd.bin
```

### Python模块使用

```python
from i2c_slave_cdc_test import *
import serial

# 打开串口
ser = serial.Serial('COM3', 115200, timeout=1)

# 写入寄存器
write_frame = i2c_slave_write_registers(0, [0xAA, 0xBB, 0xCC, 0xDD])
ser.write(write_frame)

# 读取寄存器
read_frame = i2c_slave_read_registers(0, 4)
ser.write(read_frame)
response = ser.read(100)

# 解析响应
parsed = parse_upload_response(response)
if parsed['valid']:
    print(f"Register values: {parsed['data'].hex().upper()}")
    for i, byte in enumerate(parsed['data']):
        print(f"  Reg[{i}] = 0x{byte:02X}")
```

## 🧪 测试套件

`test_i2c_slave.py` 包含5个测试用例:

1. **完整寄存器读写**: 写入并读取所有4个寄存器
2. **部分寄存器读写**: 测试部分寄存器访问
3. **单寄存器操作**: 逐个测试每个寄存器
4. **边界条件测试**: 测试最大值/最小值/边界地址
5. **顺序模式测试**: 验证数据完整性

**预期输出:**
```
TEST SUMMARY
======================================================================
  ✓ PASS  Test 1: Full Register Write-Read
  ✓ PASS  Test 2: Partial Register Write-Read
  ✓ PASS  Test 3: Single Register Operations
  ✓ PASS  Test 4: Boundary Conditions
  ✓ PASS  Test 5: Sequential Pattern

  Results: 5/5 tests passed

  🎉 ALL TESTS PASSED! 🎉
```

## 📋 命令格式速查

### CDC写寄存器 (0x35)

```
AA 55 35 00 [LEN] [START] [NUM] [DATA...] [CS]

示例: AA 55 35 00 06 00 04 AA BB CC DD 08
      写入Reg[0:3] = [AA, BB, CC, DD]
```

### CDC读寄存器 (0x36)

```
请求: AA 55 36 00 02 [START] [NUM] [CS]
响应: AA 44 36 00 [LEN] [DATA...] [CS]

示例: AA 55 36 00 02 00 04 70
      读取Reg[0:3]

响应: AA 44 36 00 04 AA BB CC DD [CS]
```

## 🔧 故障排查

### 问题: 找不到串口

**解决方法:**
```bash
# 列出所有可用串口
python -m serial.tools.list_ports

# 检查设备管理器(Windows)或dmesg(Linux)
```

### 问题: 无响应

**可能原因:**
1. 串口号错误
2. FPGA未运行
3. CDC模块未启用

**调试步骤:**
```bash
# 1. 验证串口通信
python uart_command.py tx "test" --port COM3

# 2. 测试简单命令
python i2c_slave_cdc_test.py write --start 0 --data "FF" --port COM3

# 3. 查看原始输出
python i2c_slave_cdc_test.py read --start 0 --len 1 --port COM3
```

### 问题: 数据不匹配

**调试方法:**
```bash
# 逐个寄存器测试
for i in 0 1 2 3; do
    python i2c_slave_cdc_test.py write --start $i --data "FF" --port COM3
    python i2c_slave_cdc_test.py read --start $i --len 1 --port COM3
done
```

## 📚 文档索引

- **快速参考**: 查看 `i2c_slave_quick_ref.md` - 上板测试速查表
- **详细指南**: 查看 `i2c_slave_test_guide.md` - 完整协议和测试说明
- **源码分析**: 查看 `../rtl/i2c/i2c_slave_handler.sv` - 模块实现
- **CDC协议**: 查看 `../doc/USB-CDC通信协议.md` - 通信协议规范

## 🎯 测试前检查清单

- [ ] FPGA已连接USB
- [ ] 设备管理器识别到CDC设备
- [ ] 已安装pyserial: `pip install pyserial`
- [ ] 确认串口号(如COM3)
- [ ] FPGA已烧录最新固件

## 📞 技术支持

如遇问题,请检查:
1. 串口连接和波特率(默认115200)
2. FPGA固件是否包含I2C从机模块
3. CDC命令总线是否正确连接到i2c_slave_handler

## 📄 许可证

MIT License - FPGA2025 Project
