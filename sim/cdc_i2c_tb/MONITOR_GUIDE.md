# I2C仿真调试信号快速参考

## 监控器符号说明

| 符号 | 模块 | 说明 |
|------|------|------|
| 🔵 | I2C Handler | 状态机转换 |
| 📖 | I2C Control | I2C读完成 |
| ✏️ | I2C Control | I2C写完成 |
| 🔄 | Handler→Adapter | Handler输出数据 |
| 📥 | Adapter输入 | 从Handler接收 |
| 📤 | Adapter输出 | 发送到Packer |
| 📦 | Packer | 帧封装处理 |
| 🎯 | Arbiter | 多通道仲裁 |
| 🖥️ | Cmd Processor | 最终数据处理 |
| 📤 | USB Upload | 输出到USB |
| 🔍 | EEPROM验证 | 内存内容检查 |

## 数据流8个阶段

```
EEPROM → I2C Bus → Handler → Adapter → Packer → Arbiter → CmdProc → USB
  🔍      📖📖       🔄        📥📤      📦       🎯       🖥️       📤
```

## 关键检查点

### ✅ 写操作成功的标志
```
✏️  I2C WRITE Done: Data=0xXX (出现4次)
🔍 EEPROM[0x003c] = 0xde (数据正确)
```

### ✅ 读操作成功的标志
```
📖 I2C READ Done: Data=0xXX (出现4次)
🔵 I2C_HANDLER: UPLOAD_DATA (进入上传状态)
```

### ✅ 上传管道成功的标志
```
🔄 UPLOAD PIPELINE: Ptr=0/4, 1/4, 2/4, 3/4 (指针递增)
📥📤 I2C_ADAPTER (每个字节都有IN/OUT)
📦 PACKER (输出9个字节: 帧头+4数据+校验)
```

### ✅ 最终验证成功
```
📤 USB UPLOAD: Count=5,6,7,8 (4个数据字节)
SUCCESS: Expected 0xXX, Got 0xXX (4次成功)
```

## 快速诊断

| 症状 | 检查 | 可能原因 |
|------|------|----------|
| 超时 | 最后的🔵状态 | 状态机卡住 |
| 无数据 | 📖是否出现 | I2C读取失败 |
| 数据错误 | 🔍EEPROM内容 | 写入未成功 |
| 管道阻塞 | 📥有但📤无 | Packer未ready |

## 预期输出数量

| 模块 | 每个字节的输出 |
|------|----------------|
| 📖 I2C READ | 4次 (0xDE, 0xAD, 0xBE, 0xEF) |
| 🔄 UPLOAD PIPELINE | 4次 (Ptr=0,1,2,3) |
| 📥 ADAPTER IN | 4次 |
| 📤 ADAPTER OUT | 4次 |
| 📦 PACKER RAW IN | 4次 |
| 📦 PACKER PACKED OUT | 9次 (帧头2+源1+长度2+数据4) |
| 🎯 ARBITER OUT | 9次 |
| 📤 USB UPLOAD | 9次 (Count=0~8) |

## Packer输出顺序

1. `0xAA` - Header H
2. `0x44` - Header L
3. `0x06` - Source (I2C Read命令)
4. `0x00` - Length High
5. `0x04` - Length Low (4字节)
6. `0xDE` - Data[0]
7. `0xAD` - Data[1]
8. `0xBE` - Data[2]
9. `0xEF` - Data[3]
10. `0xXX` - Checksum (可能会继续输出)

## 调试命令

查看特定模块:
```tcl
# I2C Handler状态
examine /cdc_tb/dut/u_i2c_handler/state

# 读缓冲区
examine /cdc_tb/dut/u_i2c_handler/read_buffer

# Upload信号
examine /cdc_tb/dut/u_i2c_handler/upload_valid
examine /cdc_tb/dut/u_i2c_handler/upload_ready
```

---
快速参考 | 创建: 2025-10-18
