## SPI从机工具 - 完整命令列表

### 命令码说明
- **0x14** - 预装数据到发送缓冲区（外部SPI主机读取）
- **0x15** - 控制上传使能（外部SPI主机写入的数据是否上传）

---

## 📤 预装数据命令 (0x14)

### 基本数据格式
```bash
# 文本
python spi_slave_tool.py --text "Hello SPI" --port COM3

# 十六进制
python spi_slave_tool.py --hex "01 02 03 04 05" --port COM3

# 二进制
python spi_slave_tool.py --bin "11110000 10101010" --port COM3

# 从文件
python spi_slave_tool.py --file data.bin --port COM3
```

### 预设模板
```bash
# 传感器ID (设备类型 序列号 版本)
python spi_slave_tool.py --sensor-id 0x1234 0xABCD5678 0x0102 --port COM3

# 配置参数 (采样率 增益 模式 使能)
python spi_slave_tool.py --config 1000000 128 3 1 --port COM3

# 状态寄存器 (温度×100 电压mV 标志位)
python spi_slave_tool.py --status 2530 3300 0xA1 --port COM3

# 查找表
python spi_slave_tool.py --lut sine 128 --port COM3      # 正弦波
python spi_slave_tool.py --lut square 16 --port COM3     # 平方表
python spi_slave_tool.py --lut triangle 64 --port COM3   # 三角波
```

---

## 📥 上传控制命令 (0x15)

```bash
# 启用上传（外部主机写入的数据会通过USB-CDC上传到PC）
python spi_slave_tool.py --upload-enable --port COM3
# 命令包: AA 55 15 00 01 01 17

# 禁用上传（外部主机写入的数据不会上传）
python spi_slave_tool.py --upload-disable --port COM3
# 命令包: AA 55 15 00 01 00 16
```

---

## 🔄 完整工作流程

### 场景1: 外部主机读取FPGA数据
```bash
# 步骤1: PC预装数据到FPGA
python spi_slave_tool.py --text "FPGA2025" --port COM3

# 步骤2: 外部SPI主机读取（Arduino代码）
# digitalWrite(SS, LOW);
# for(int i=0; i<8; i++) {
#     char c = SPI.transfer(0x00);
#     Serial.print(c);
# }
# digitalWrite(SS, HIGH);
# 输出: FPGA2025
```

### 场景2: 外部主机写入数据到PC
```bash
# 步骤1: PC启用上传
python spi_slave_tool.py --upload-enable --port COM3

# 步骤2: 外部SPI主机写入（Arduino代码）
# digitalWrite(SS, LOW);
# SPI.transfer(0x01);
# SPI.transfer(0x02);
# SPI.transfer(0x03);
# digitalWrite(SS, HIGH);

# 步骤3: PC从USB-CDC读取上传的数据
# 数据源标识: 0x14
# 数据内容: 01 02 03

# 步骤4: 不需要时禁用上传
python spi_slave_tool.py --upload-disable --port COM3
```

### 场景3: 双向通信
```bash
# 1. 预装数据供外部主机读取
python spi_slave_tool.py --text "Status:OK" --port COM3

# 2. 启用上传接收外部主机写入的数据
python spi_slave_tool.py --upload-enable --port COM3

# 3. 外部主机同时读写
# - MISO线: 读取 "Status:OK"
# - MOSI线: 写入命令，数据自动上传到PC
```

---

## 📊 命令包格式

### 0x14 命令 (预装数据)
```
AA 55 14 00 09 48 65 6C 6C 6F 20 53 50 49 1D
[帧头][CM][--长度--][-------数据--------][CK]
      14   9字节     "Hello SPI"         校验和
```

### 0x15 命令 (上传控制)
```
# 启用
AA 55 15 00 01 01 17
[帧头][CM][长度1][EN][CK]
      15          01  校验和

# 禁用
AA 55 15 00 01 00 16
[帧头][CM][长度1][DI][CK]
      15          00  校验和
```

---

## 🛠 常用选项

```bash
# 只生成命令，不发送
python spi_slave_tool.py --text "Test"

# 保存到文件
python spi_slave_tool.py --text "Test" -o cmd.bin

# 发送到串口
python spi_slave_tool.py --text "Test" --port COM3

# 安静模式（脚本友好）
python spi_slave_tool.py --text "Test" --port COM3 -q

# 自定义波特率
python spi_slave_tool.py --text "Test" --port COM3 --baud 9600

# 同时保存和发送
python spi_slave_tool.py --text "Test" -o test.bin --port COM3
```

---

## 🎯 快速参考

| 功能 | 命令 |
|------|------|
| **预装文本** | `--text "Hello"` |
| **预装字节** | `--hex "01 02 03"` |
| **传感器ID** | `--sensor-id TYPE SERIAL VER` |
| **配置参数** | `--config RATE GAIN MODE EN` |
| **状态寄存器** | `--status TEMP VOLT FLAGS` |
| **查找表** | `--lut sine 128` |
| **启用上传** | `--upload-enable` |
| **禁用上传** | `--upload-disable` |
| **发送串口** | `--port COM3` |
| **保存文件** | `-o file.bin` |
| **安静模式** | `-q` |

---

## ✅ 完成！

所有功能已实现：
- ✅ 0x14 命令 - 预装数据（8种方式）
- ✅ 0x15 命令 - 上传控制（启用/禁用）
- ✅ 串口发送
- ✅ 文件保存
- ✅ 详细/安静模式

**位置**: `F:\FPGA2025\software\spi_slave_tool.py`
