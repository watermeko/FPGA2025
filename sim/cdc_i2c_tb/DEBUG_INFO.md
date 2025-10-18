# I2C仿真调试信息说明

## 增强的调试功能

测试bench现在包含以下实时监控器：

### 1. 📤 USB上传数据监控
```
[时间] 📤 USB UPLOAD: Data=0xXX (Count=N)
```
**作用**: 实时显示每个通过USB上传通道输出的字节
- `Data`: 上传的数据值
- `Count`: 累计上传的字节数

### 2. 🔵 I2C Handler状态机监控
```
[时间] 🔵 I2C_HANDLER: <STATE_NAME>
```
**状态列表**:
- `IDLE` - 空闲状态，等待命令
- `PARSE_CONFIG` - 解析配置命令（设置设备地址）
- `PARSE_WRITE` - 解析写命令
- `PARSE_READ` - 解析读命令
- `EXEC_WRITE` - 执行I2C写操作
- `EXEC_READ` - 执行I2C读操作
- `UPLOAD_DATA` - 上传读取的数据

**作用**: 追踪I2C Handler的状态转换，帮助定位卡死或跳过的状态

### 3. 📖✏️ I2C物理读写操作监控
```
[时间] 📖 I2C READ Done: Data=0xXX, Addr=0xXXXX
[时间] ✏️  I2C WRITE Done: Data=0xXX, Addr=0xXXXX
```
**作用**: 显示每次I2C总线级别的读写完成事件
- `Data`: 读取或写入的数据
- `Addr`: 当前EEPROM地址

### 4. 🔄 上传管道数据流监控
```
[时间] 🔄 UPLOAD PIPELINE: Data=0xXX, Ptr=N/M
```
**作用**: 追踪从I2C Handler到上传管道的数据传输
- `Data`: 正在传输的数据
- `Ptr`: 当前指针/总长度

### 5. 📥📤 I2C Upload Adapter监控
```
[时间] 📥 I2C_ADAPTER IN: Data=0xXX, Source=0xXX, Active=X
[时间] 📤 I2C_ADAPTER OUT: Data=0xXX, Source=0xXX, Req=X
```
**作用**: 监控Adapter的输入输出
- `IN`: 从I2C Handler接收的数据
- `OUT`: 发送到Packer的数据
- `Active`: Handler的active信号
- `Req`: Adapter的请求信号

### 6. 📦 Upload Packer监控 (I2C通道)
```
[时间] 📦 PACKER[I2C] RAW IN: Data=0xXX, Source=0xXX, Req=X
[时间] 📦 PACKER[I2C] PACKED OUT: Data=0xXX, Source=0xXX
```
**作用**: 监控Packer的帧封装过程
- `RAW IN`: 原始数据输入（来自Adapter）
- `PACKED OUT`: 封装后的数据输出（带0xAA44帧头）
- I2C是4个通道中的通道1（索引1）

### 7. 🎯 Upload Arbiter监控
```
[时间] 🎯 ARBITER IN: Valid=XXXX, Ready=XXXX, Data=0xXX...
[时间] 🎯 ARBITER OUT: Data=0xXX, Source=0xXX, Req=X
```
**作用**: 监控多通道仲裁器
- `Valid/Ready`: 4个通道的握手信号（二进制）
- `Data`: 4个通道的数据（每个8位）
- `OUT`: 仲裁后输出的单一数据流

### 8. 🖥️ Command Processor最终输出监控
```
[时间] 🖥️  CMD_PROCESSOR IN: Data=0xXX, Source=0xXX
```
**作用**: 监控进入Command Processor的最终数据流
- 这是数据到达USB输出前的最后一站

### 5. 🔍 EEPROM内存内容验证
```
[时间] 🔍 Verifying EEPROM Memory Content:
           EEPROM[0xXXXX] = 0xXX
```
**作用**: 在读取前直接检查EEPROM模型的内存，验证写入是否成功

## 完整的数据流追踪

### 读取操作的完整数据路径

```
┌─────────────────────────────────────────────────────────────────┐
│ I2C读取数据流 (每个字节的完整路径)                                │
└─────────────────────────────────────────────────────────────────┘

1️⃣  EEPROM Memory
    └─> 📖 I2C READ Done: Data=0xXX
         ↓

2️⃣  I2C Handler (read_buffer)
    └─> 🔄 UPLOAD PIPELINE: Data=0xXX, Ptr=N/M
         ↓

3️⃣  Upload Adapter
    ├─> 📥 I2C_ADAPTER IN: Data=0xXX
    └─> 📤 I2C_ADAPTER OUT: Data=0xXX
         ↓

4️⃣  Upload Packer (添加帧头和校验和)
    ├─> 📦 PACKER[I2C] RAW IN: Data=0xXX
    └─> 📦 PACKER[I2C] PACKED OUT: Data=0xXX
         ↓

5️⃣  Upload Arbiter (多通道仲裁)
    ├─> 🎯 ARBITER IN: Valid=XXXX
    └─> 🎯 ARBITER OUT: Data=0xXX
         ↓

6️⃣  Command Processor
    └─> 🖥️  CMD_PROCESSOR IN: Data=0xXX
         ↓

7️⃣  USB Upload Output
    └─> 📤 USB UPLOAD: Data=0xXX (Count=N)
         ↓

8️⃣  Testbench验证
    └─> ✓ SUCCESS: Expected 0xXX, Got 0xXX
```

### 通道映射

上传管道有4个通道（NUM_UPLOAD_CHANNELS = 4）：

```
Packer输入连接 (从LSB到MSB):
.raw_upload_req   ({dsm, i2c, spi, uart})
.raw_upload_data  ({dsm_data, i2c_data, spi_data, uart_data})

通道索引:
- Channel 0: UART
- Channel 1: I2C   ← 我们关注的通道
- Channel 2: SPI
- Channel 3: DSM
```

### 帧格式

Packer会将原始数据封装成帧：

```
┌──────────┬──────────┬──────────┬──────────┬──────┬──────────┐
│ Header H │ Header L │  Source  │  Len(H)  │Len(L)│   Data   │
│  0xAA    │  0x44    │  0x06    │   0x00   │ 0x04 │ 4 bytes  │
└──────────┴──────────┴──────────┴──────────┴──────┴──────────┘
     ↓          ↓          ↓          ↓        ↓         ↓
   Packer    Packer    I2C Read   Packer   Packer   Handler
  (固定)     (固定)    Command    (计算)   (计算)   (数据)
```

## 测试流程

```
==========================================================
=== Starting I2C EEPROM Verification ===
==========================================================

Step 1: I2C Config (设置设备地址 0x50)
   └─> I2C_HANDLER: IDLE → PARSE_CONFIG → IDLE

Step 2: I2C Write (写入4字节到0x003C)
   ├─> I2C_HANDLER: IDLE → PARSE_WRITE → EXEC_WRITE
   ├─> I2C WRITE Done (4次，地址递增)
   └─> I2C_HANDLER: EXEC_WRITE → IDLE

Step 3: 等待5ms (EEPROM写周期)

Step 4: 验证EEPROM内存 (直接读取模型)
   └─> 显示EEPROM[0x003C~0x003F]的内容

Step 5: I2C Read (读取4字节)
   ├─> I2C_HANDLER: IDLE → PARSE_READ → EXEC_READ
   ├─> I2C READ Done (4次，地址递增)
   ├─> I2C_HANDLER: EXEC_READ → UPLOAD_DATA
   ├─> UPLOAD PIPELINE (4次传输)
   ├─> USB UPLOAD (4个字节输出)
   └─> 验证接收数据

==========================================================
=== I2C Test Complete ===
==========================================================
```

## 如何使用调试信息

### 场景1: 测试超时
**查看**:
- I2C_HANDLER卡在哪个状态？
- 是否有 `I2C READ/WRITE Done` 消息？
- `UPLOAD PIPELINE` 有数据吗？

**常见原因**:
- 卡在 `EXEC_READ`: I2C控制器未响应
- 卡在 `UPLOAD_DATA`: 上传管道阻塞

### 场景2: 数据错误
**查看**:
- `EEPROM Memory Content` 是否正确？
- `I2C READ Done` 读取的数据值
- `USB UPLOAD` 输出的数据值

**数据流路径**:
```
EEPROM → I2C Bus → i2c_rddata → read_buffer →
upload_data → packer → arbiter → usb_upload_data
```

### 场景3: 部分成功
**查看**:
- `Count` 计数器显示收到多少字节
- `Ptr` 显示当前处理到第几个字节

## 典型成功输出示例（完整数据流）

```
==========================================================
=== Starting I2C EEPROM Verification ===
==========================================================

[1400000] 📋 Step 1: Sending I2C Config command...
[1420000] 🔵 I2C_HANDLER: IDLE
[1440000] 🔵 I2C_HANDLER: PARSE_CONFIG
[1460000] 🔵 I2C_HANDLER: IDLE

[3670000] 📋 Step 2: Sending I2C Write command...
           Target Address: 0x003c
           Write Data: 0xde 0xad 0xbe 0xef
[3690000] 🔵 I2C_HANDLER: PARSE_WRITE
[3710000] 🔵 I2C_HANDLER: EXEC_WRITE
[3850000] ✏️  I2C WRITE Done: Data=0xde, Addr=0x003c
[4020000] ✏️  I2C WRITE Done: Data=0xad, Addr=0x003d
[4190000] ✏️  I2C WRITE Done: Data=0xbe, Addr=0x003e
[4360000] ✏️  I2C WRITE Done: Data=0xef, Addr=0x003f
[4370000] 🔵 I2C_HANDLER: IDLE

[5004130000] ⏳ Waiting 5ms for EEPROM write cycle...

[5004130000] 🔍 Verifying EEPROM Memory Content:
             EEPROM[0x003c] = 0xde
             EEPROM[0x003d] = 0xad
             EEPROM[0x003e] = 0xbe
             EEPROM[0x003f] = 0xef

==========================================================
[5004130000] 📋 Step 3: Sending I2C Read command...
             Read Address: 0x003c
             Read Length: 4 bytes

[5004150000] 🔵 I2C_HANDLER: PARSE_READ
[5004170000] 🔵 I2C_HANDLER: EXEC_READ
[5004310000] 📖 I2C READ Done: Data=0xde, Addr=0x003c
[5004480000] 📖 I2C READ Done: Data=0xad, Addr=0x003d
[5004650000] 📖 I2C READ Done: Data=0xbe, Addr=0x003e
[5004820000] 📖 I2C READ Done: Data=0xef, Addr=0x003f
[5004830000] 🔵 I2C_HANDLER: UPLOAD_DATA

[5004850000] 🔄 UPLOAD PIPELINE: Data=0xde, Ptr=0/4
[5004850000] 📥 I2C_ADAPTER IN: Data=0xde, Source=0x06, Active=1
[5004850000] 📤 I2C_ADAPTER OUT: Data=0xde, Source=0x06, Req=1
[5004850000] 📦 PACKER[I2C] RAW IN: Data=0xde, Source=0x06, Req=1
[5004860000] 📦 PACKER[I2C] PACKED OUT: Data=0xaa, Source=0x06  ← Header H
[5004870000] 🎯 ARBITER IN: Valid=0010, Ready=1111, Data=...
[5004870000] 🎯 ARBITER OUT: Data=0xaa, Source=0x06, Req=1
[5004870000] 🖥️  CMD_PROCESSOR IN: Data=0xaa, Source=0x06
[5004870000] 📤 USB UPLOAD: Data=0xaa (Count=0)

[5004880000] 📦 PACKER[I2C] PACKED OUT: Data=0x44, Source=0x06  ← Header L
[5004880000] 📤 USB UPLOAD: Data=0x44 (Count=1)

[5004890000] 📦 PACKER[I2C] PACKED OUT: Data=0x06, Source=0x06  ← Source
[5004890000] 📤 USB UPLOAD: Data=0x06 (Count=2)

[5004900000] 📦 PACKER[I2C] PACKED OUT: Data=0x00, Source=0x06  ← Len H
[5004900000] 📤 USB UPLOAD: Data=0x00 (Count=3)

[5004910000] 📦 PACKER[I2C] PACKED OUT: Data=0x04, Source=0x06  ← Len L
[5004910000] 📤 USB UPLOAD: Data=0x04 (Count=4)

[5004920000] 📦 PACKER[I2C] PACKED OUT: Data=0xde, Source=0x06  ← Data[0]
[5004920000] 📤 USB UPLOAD: Data=0xde (Count=5)
  Verifying byte 0...
    -> SUCCESS: Expected 0xde, Got 0xde

[5004930000] 🔄 UPLOAD PIPELINE: Data=0xad, Ptr=1/4
[5004930000] 📥 I2C_ADAPTER IN: Data=0xad, Source=0x06, Active=1
[5004930000] 📤 I2C_ADAPTER OUT: Data=0xad, Source=0x06, Req=1
[5004930000] 📦 PACKER[I2C] RAW IN: Data=0xad, Source=0x06, Req=1
[5004940000] 📦 PACKER[I2C] PACKED OUT: Data=0xad, Source=0x06  ← Data[1]
[5004940000] 📤 USB UPLOAD: Data=0xad (Count=6)
  Verifying byte 1...
    -> SUCCESS: Expected 0xad, Got 0xad

[5004950000] 🔄 UPLOAD PIPELINE: Data=0xbe, Ptr=2/4
[5004950000] 📦 PACKER[I2C] PACKED OUT: Data=0xbe, Source=0x06  ← Data[2]
[5004950000] 📤 USB UPLOAD: Data=0xbe (Count=7)
  Verifying byte 2...
    -> SUCCESS: Expected 0xbe, Got 0xbe

[5004960000] 🔄 UPLOAD PIPELINE: Data=0xef, Ptr=3/4
[5004960000] 📦 PACKER[I2C] PACKED OUT: Data=0xef, Source=0x06  ← Data[3]
[5004960000] 📤 USB UPLOAD: Data=0xef (Count=8)
  Verifying byte 3...
    -> SUCCESS: Expected 0xef, Got 0xef

[5004970000] 📦 PACKER[I2C] PACKED OUT: Data=0x??, Source=0x06  ← Checksum
[5004970000] 📤 USB UPLOAD: Data=0x?? (Count=9)

[5004980000] 🔵 I2C_HANDLER: IDLE

==========================================================
=== I2C Test Complete ===
==========================================================

📊 Test Summary:
   - Config: OK
   - Write: OK (4 bytes written)
   - Read: Check results above

[5005000000] ✅ Simulation finished.
```

## 典型成功输出示例

```
[时间] 🔵 I2C_HANDLER: IDLE
[时间] 🔵 I2C_HANDLER: PARSE_READ
[时间] 🔵 I2C_HANDLER: EXEC_READ
[时间] 📖 I2C READ Done: Data=0xde, Addr=0x003c
[时间] 📖 I2C READ Done: Data=0xad, Addr=0x003d
[时间] 📖 I2C READ Done: Data=0xbe, Addr=0x003e
[时间] 📖 I2C READ Done: Data=0xef, Addr=0x003f
[时间] 🔵 I2C_HANDLER: UPLOAD_DATA
[时间] 🔄 UPLOAD PIPELINE: Data=0xde, Ptr=0/4
[时间] 📤 USB UPLOAD: Data=0xde (Count=0)
  Verifying byte 0...
    -> SUCCESS: Expected 0xde, Got 0xde
[时间] 🔄 UPLOAD PIPELINE: Data=0xad, Ptr=1/4
[时间] 📤 USB UPLOAD: Data=0xad (Count=1)
  Verifying byte 1...
    -> SUCCESS: Expected 0xad, Got 0xad
...
```

## 注意事项

1. 所有emoji符号仅用于便于识别，不影响仿真功能
2. 时间戳单位为纳秒(ns)
3. 地址为16位十六进制，数据为8位十六进制
4. 实时监控器是独立的 `initial` 块，不会影响主测试流程

---
创建时间: 2025-10-18
