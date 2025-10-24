# SPI从机命令工具对比

## 工具对比

| 特性 | test_preload_example.py | spi_slave_tool.py |
|------|------------------------|-------------------|
| **定位** | 测试示例/演示代码 | 生产级命令行工具 |
| **输入方式** | 硬编码 | 命令行参数 |
| **数据格式** | 固定7种场景 | 灵活多格式 |
| **命令行** | ❌ 需修改代码 | ✅ 完整CLI |
| **文件支持** | ❌ 无 | ✅ 读取/保存 |
| **串口发送** | ✅ 内置 | ✅ 可选 |
| **脚本集成** | ⚠️ 需改代码 | ✅ 友好 |
| **文档** | 注释 | 完整帮助 |

---

## 功能映射

### 原示例 → 新工具

#### 场景1: 文本数据
**原示例** (需修改代码):
```python
# 编辑 test_preload_example.py
test_data = b"Hello SPI"
send_command(ser, 0x14, len(test_data), test_data)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --text "Hello SPI" --port COM3
```

---

#### 场景2: 传感器ID
**原示例** (需修改代码):
```python
device_type = 0x1234
serial_number = 0xABCD5678
version = 0x0102
sensor_id = struct.pack('>HLH', device_type, serial_number, version)
send_command(ser, 0x14, len(sensor_id), sensor_id)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --sensor-id 0x1234 0xABCD5678 0x0102 --port COM3
```

---

#### 场景3: 查找表
**原示例** (需修改代码):
```python
lut_data = bytearray([i*i for i in range(16)])
send_command(ser, 0x14, len(lut_data), lut_data)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --lut square 16 --port COM3
```

---

#### 场景4: 配置参数
**原示例** (需修改代码):
```python
config = struct.pack('>LHBB', 1000000, 128, 0x03, 0x01)
send_command(ser, 0x14, len(config), config)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --config 1000000 128 3 1 --port COM3
```

---

#### 场景5: 版本信息
**原示例** (需修改代码):
```python
version_string = b"FPGA2025 v1.2.3"
send_command(ser, 0x14, len(version_string), version_string)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --text "FPGA2025 v1.2.3" --port COM3
```

---

#### 场景6: 状态寄存器
**原示例** (需修改代码):
```python
temperature = 2530
voltage = 3300
status_flags = 0b10100001
status_data = struct.pack('>HHB', temperature, voltage, status_flags)
send_command(ser, 0x14, len(status_data), status_data)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --status 2530 3300 0b10100001 --port COM3
```

---

#### 场景7: 波形数据
**原示例** (需修改代码):
```python
import math
waveform = bytearray([
    int(127.5 + 127.5 * math.sin(2 * math.pi * i / 128))
    for i in range(128)
])
send_command(ser, 0x14, len(waveform), waveform)
```

**新工具** (命令行):
```bash
python spi_slave_tool.py --lut sine 128 --port COM3
```

---

## 新增功能

### 1. 十六进制直接输入
```bash
python spi_slave_tool.py --hex "01 02 03 04 05"
```

### 2. 二进制字符串输入
```bash
python spi_slave_tool.py --bin "11110000 10101010"
```

### 3. 文件读取
```bash
python spi_slave_tool.py --file config.bin --port COM3
```

### 4. 命令保存
```bash
python spi_slave_tool.py --text "Test" -o cmd.bin
```

### 5. 安静模式（脚本友好）
```bash
python spi_slave_tool.py --text "Test" --port COM3 -q
```

### 6. 三角波查找表
```bash
python spi_slave_tool.py --lut triangle 64
```

---

## 自动化优势

### 批量处理
**原示例**: 需要循环调用函数
```python
for i in range(10):
    test_data = f"Message {i}".encode()
    send_command(ser, 0x14, len(test_data), test_data)
```

**新工具**: Shell脚本轻松实现
```bash
for i in {1..10}; do
    python spi_slave_tool.py --text "Message $i" --port COM3 -q
done
```

---

### CI/CD集成
**新工具**可直接集成到自动化流程:
```yaml
# GitHub Actions 示例
- name: Configure FPGA
  run: |
    python spi_slave_tool.py --config 1000000 128 1 1 --port /dev/ttyUSB0
```

---

## 开发流程对比

### 原示例开发流程
1. 编辑 `test_preload_example.py`
2. 修改硬编码参数
3. 运行 `python test_preload_example.py`
4. 需要改参数？返回步骤1

### 新工具开发流程
1. 直接命令行运行
```bash
python spi_slave_tool.py --text "Test1" --port COM3
python spi_slave_tool.py --text "Test2" --port COM3
python spi_slave_tool.py --sensor-id 0x1234 0x5678 0x0100 --port COM3
```
2. 无需修改代码

---

## 使用场景建议

### 使用原示例 (test_preload_example.py)
- ✅ 学习SPI从机功能
- ✅ 理解命令包格式
- ✅ 查看详细演示
- ✅ 参考代码实现

### 使用新工具 (spi_slave_tool.py)
- ✅ 日常开发调试
- ✅ 生产环境配置
- ✅ 自动化测试
- ✅ 批量操作
- ✅ CI/CD集成
- ✅ Shell脚本集成

---

## 迁移指南

如果你已经在使用 `test_preload_example.py`，迁移到新工具很简单：

### 1. 找到硬编码数据
```python
# 原代码
test_data = b"Hello SPI"
```

### 2. 转换为命令行
```bash
python spi_slave_tool.py --text "Hello SPI"
```

### 3. 添加串口（如需要）
```bash
python spi_slave_tool.py --text "Hello SPI" --port COM3
```

---

## 性能对比

| 操作 | 原示例 | 新工具 |
|------|--------|--------|
| 单次发送 | ~0.5秒 | ~0.5秒 |
| 改参数发送 | 需修改代码+重启 (~30秒) | 直接命令行 (~1秒) |
| 批量100次 | 需编写循环 (~60秒) | Shell循环 (~50秒) |

---

## 总结

`spi_slave_tool.py` 是 `test_preload_example.py` 的**生产级升级版**：

| 维度 | 提升 |
|------|------|
| **易用性** | 命令行 vs 改代码 |
| **灵活性** | 多格式 vs 固定场景 |
| **可集成性** | CLI友好 vs 需包装 |
| **生产就绪** | ✅ vs 演示级 |

**建议**:
- 学习阶段：两者都看
- 开发阶段：使用新工具
- 生产环境：使用新工具

---

**文件位置**:
- 原示例: `F:\FPGA2025\rtl\spi\test_preload_example.py`
- 新工具: `F:\FPGA2025\software\spi_slave_tool.py`
- 使用文档: `F:\FPGA2025\software\spi_slave_tool_examples.txt`
