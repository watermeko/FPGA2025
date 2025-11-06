# CDC I2C Testbench Simulation

## 概述
此仿真测试CDC模块中的I2C功能，使用M24LC64 EEPROM模型验证I2C读写操作和数据上传流水线。

## 运行仿真

### 方法1：使用do脚本（推荐）
```bash
cd F:\FPGA2025\sim\cdc_i2c_tb
vsim -do cmd.do
```

### 方法2：从项目根目录运行
```bash
cd F:\FPGA2025
vsim -c -do sim/cdc_i2c_tb/cmd.do
```

## 仿真内容

### 测试场景
1. **I2C配置**: 发送I2C Config命令（0x04），配置EEPROM设备地址
2. **I2C写入**: 写入4字节数据到EEPROM地址 0x003C
   - 数据: `0xDE, 0xAD, 0xBE, 0xEF`
3. **I2C读取**: 从EEPROM读取4字节并验证
4. **数据上传**: 验证读取的数据通过上传流水线返回到USB

### 验证内容
- ✅ I2C命令解析（命令码 0x04/0x05/0x06）
- ✅ I2C写操作时序（START + ADDR + DATA + STOP）
- ✅ I2C读操作时序（START + ADDR + READ + STOP）
- ✅ EEPROM页写入和随机读取
- ✅ I2C Handler状态机正确性
- ✅ 数据上传流水线：I2C Handler → Adapter → Packer → Arbiter → Processor
- ✅ 上传帧格式：`0xAA44 | SOURCE(0x02) | LEN | DATA | CHECKSUM`

## I2C命令协议

### 命令格式
```
[Header] [CMD] [Length] [Payload] [Checksum]
 0xAA55   1B     2B       N bytes    1B
```

### 支持的命令

#### 1. I2C Config (0x04)
配置I2C设备地址（7位）

**Payload**:
```
Byte 0: Device Address (7-bit, 不含R/W位)
```

**示例**: 配置EEPROM地址为0xA0（7位地址=0x50）
```
AA 55 04 00 01 50 55
```

#### 2. I2C Write (0x05)
向I2C设备写入数据

**Payload**:
```
Byte 0-1: Memory Address (大端，16位)
Byte 2-N: Data bytes to write
```

**示例**: 写入4字节到地址0x003C
```
AA 55 05 00 06 00 3C DE AD BE EF [CHECKSUM]
```

#### 3. I2C Read (0x06)
从I2C设备读取数据

**Payload**:
```
Byte 0-1: Memory Address (大端，16位)
Byte 2-3: Number of bytes to read (大端，16位)
```

**示例**: 从地址0x003C读取4字节
```
AA 55 06 00 04 00 3C 00 04 [CHECKSUM]
```

### 数据上传格式
I2C读取的数据通过上传流水线返回：

```
帧头: 0xAA 0x44
源ID: 0x02 (I2C Handler)
长度: 读取的字节数 (2字节，大端)
数据: 读取的字节流
校验: 累加和 (从源ID到数据的所有字节)
```

## 波形查看

仿真自动添加以下波形组：
- **Top Level**: 顶层信号（时钟、复位、USB数据）
- **I2C Bus**: I2C物理总线信号（SCL, SDA, EEPROM状态）
- **Protocol Parser**: 协议解析器状态
- **Command Processor**: 命令处理器
- **I2C Handler**: I2C Handler状态机、缓冲区、控制信号
- **I2C Control**: I2C低层控制器（位级操作）
- **Upload Pipeline**: 上传数据流水线（Adapter → Packer → Arbiter）
- **Testbench**: 测试台变量（payload, expected_data）

## 关键信号说明

### I2C Handler内部信号
```verilog
state              // 主状态机: IDLE, CONFIG, WRITE, READ等
device_addr_7bit   // 配置的7位I2C设备地址
num_wr_bytes       // 写入字节数
num_rd_bytes       // 读取字节数
tx_buffer[0:127]   // 发送缓冲区
rx_buffer[0:127]   // 接收缓冲区
buf_index          // 缓冲区索引
```

### I2C Control核心信号
```verilog
state              // 位级状态机: IDLE, START, ADDR, DATA, STOP等
i2c_start          // 启动I2C传输
i2c_busy           // I2C忙标志
i2c_done           // 传输完成
i2c_tx_data        // 发送数据
i2c_rx_data        // 接收数据
i2c_rw             // 读(1)/写(0)
i2c_ack_error      // ACK错误标志
```

## EEPROM模型

### M24LC64特性
- **容量**: 64Kbit (8KB)
- **页大小**: 32字节
- **地址**: 7位地址 + R/W位
- **写周期时间**: 5ms (仿真中)
- **接口**: I2C (100kHz - 1MHz)

### 模型文件
- `rtl/i2c/M24LC64.v` - 64Kbit EEPROM模型
- `rtl/i2c/M24LC04B.v` - 4Kbit EEPROM模型（未使用）

## 前置条件

### 高云仿真库路径
脚本中默认路径：`E:/GOWIN/Gowin_V1.9.9_x64/IDE`

如果您的安装路径不同，请修改 `cmd.do` 第25行：
```tcl
set GOWIN_PATH "您的路径/IDE"
```

## 预期结果

测试成功后会输出：
```
=== Starting I2C EEPROM Verification (Sequential Single-Byte Read) ===
[xxxxx] Step 1: Sending I2C Config command...
[xxxxx] Step 2: Sending I2C Write command to EEPROM address 0x003C...
[xxxxx] Waiting for physical I2C write to complete...
[xxxxx] Step 3: Sending ONE multi-byte I2C Read command...
[xxxxx] Now waiting to verify 4 consecutive bytes from DUT...
  Verifying byte 0...
    -> SUCCESS: Expected 0xDE, Got 0xDE
  Verifying byte 1...
    -> SUCCESS: Expected 0xAD, Got 0xAD
  Verifying byte 2...
    -> SUCCESS: Expected 0xBE, Got 0xBE
  Verifying byte 3...
    -> SUCCESS: Expected 0xEF, Got 0xEF
=== I2C Test Complete ===
```

## 故障排查

### 错误：找不到gw5a库
**解决**: 修改cmd.do第25行的`GOWIN_PATH`

### 错误：M24LC64.v找不到
**解决**: 确认文件在 `F:\FPGA2025\rtl\i2c/M24LC64.v`

### 错误：I2C ACK错误
**可能原因**:
1. EEPROM未正确复位
2. I2C时序问题
3. 设备地址错误

**调试方法**:
查看波形中的 `i2c_ack_error` 信号和 `i2c_control/state`

### 读取超时
**可能原因**:
1. EEPROM写周期未完成（需等待5ms）
2. I2C Handler状态机卡死
3. 上传流水线阻塞

**调试方法**:
1. 检查 `i2c_handler/state` 是否停留在某个状态
2. 检查 `upload_valid` 和 `upload_ready` 信号握手
3. 增加写入后的等待时间

## 仿真时长

约 **8-15分钟**（取决于CPU性能）

主要耗时：
- EEPROM写周期等待: 5ms
- I2C时序仿真: ~1ms
- 数据验证: ~100us

## 扩展测试

可修改测试台参数进行更多测试：

```systemverilog
// 修改 cdc_i2c_tb.sv 中的参数
localparam WRITE_ADDR = 16'h003C;         // 改变写入地址
localparam NUM_BYTES_TO_TEST = 4;         // 改变测试字节数
localparam EEPROM_DEVICE_ADDR_8BIT = 8'hA0; // 改变设备地址
```

## 相关文件
- `tb/cdc_i2c_tb.sv` - I2C测试台
- `rtl/cdc.v` - CDC顶层模块
- `rtl/i2c/i2c_handler.v` - I2C Handler
- `rtl/i2c/i2c_control.v` - I2C控制器
- `rtl/i2c/i2c_bit_shift.v` - I2C位移位器
- `rtl/i2c/M24LC64.v` - EEPROM模型

## 注意事项

1. ⚠️ I2C总线有上拉电阻模拟（testbench中 `pullup PUP(i2c_sda)`）
2. ⚠️ EEPROM写周期需要5ms，测试中已包含等待
3. ⚠️ I2C地址是7位，不含R/W位
4. ⚠️ 仿真时钟为50MHz，I2C时钟由分频器生成
