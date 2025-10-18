# I2C Handler 集成总结

## ✅ 集成完成

I2C handler已成功集成到FPGA2025项目的CDC模块中。

---

## 📋 集成内容

### 1. **修改的文件**

#### `rtl/cdc.v` (主要修改)
1. **添加I2C端口** (第31-33行)
   ```verilog
   // I2C Interface
   output       i2c_scl,
   inout        i2c_sda,
   ```

2. **添加I2C ready信号** (第60行)
   ```verilog
   wire pwm_ready, ext_uart_ready, dac_ready, spi_ready, dsm_ready, i2c_ready;
   ```

3. **添加I2C上传信号** (第85-90行)
   ```verilog
   wire        i2c_upload_active;
   wire        i2c_upload_req;
   wire [7:0]  i2c_upload_data;
   wire [7:0]  i2c_upload_source;
   wire        i2c_upload_valid;
   wire        i2c_upload_ready;
   ```

4. **更新cmd_ready逻辑** (第103行)
   ```verilog
   wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready & spi_ready & dsm_ready & i2c_ready;
   ```

5. **更新上传通道数量** (第110行)
   ```verilog
   parameter NUM_UPLOAD_CHANNELS = 4;  // UART + SPI + DSM + I2C
   ```

6. **添加I2C adapter信号** (第131-135行)
   ```verilog
   wire       i2c_packer_req;
   wire [7:0] i2c_packer_data;
   wire [7:0] i2c_packer_source;
   wire       i2c_packer_valid;
   wire       i2c_packer_ready;
   ```

7. **实例化I2C adapter** (第218-232行)
   ```verilog
   upload_adapter u_i2c_adapter (
       .clk(clk),
       .rst_n(rst_n),
       .handler_upload_active(i2c_upload_active),
       .handler_upload_data(i2c_upload_data),
       .handler_upload_source(i2c_upload_source),
       .handler_upload_valid(i2c_upload_valid),
       .handler_upload_ready(i2c_upload_ready),
       .packer_upload_req(i2c_packer_req),
       .packer_upload_data(i2c_packer_data),
       .packer_upload_source(i2c_packer_source),
       .packer_upload_valid(i2c_packer_valid),
       .packer_upload_ready(i2c_packer_ready)
   );
   ```

8. **更新packer连接** (第242-246行)
   ```verilog
   .raw_upload_req({i2c_packer_req, dsm_packer_req, spi_packer_req, uart_packer_req}),
   .raw_upload_data({i2c_packer_data, dsm_packer_data, spi_packer_data, uart_packer_data}),
   .raw_upload_source({i2c_packer_source, dsm_packer_source, spi_packer_source, uart_packer_source}),
   .raw_upload_valid({i2c_packer_valid, dsm_packer_valid, spi_packer_valid, uart_packer_valid}),
   .raw_upload_ready({i2c_packer_ready, dsm_packer_ready, spi_packer_ready, uart_packer_ready}),
   ```

9. **实例化I2C handler** (第419-441行)
   ```verilog
   i2c_handler #(
       .WRITE_BUFFER_SIZE(128),
       .READ_BUFFER_SIZE(128)
   ) u_i2c_handler (
       .clk(clk),
       .rst_n(rst_n),
       .cmd_type(cmd_type),
       .cmd_length(cmd_length),
       .cmd_data(cmd_data),
       .cmd_data_index(cmd_data_index),
       .cmd_start(cmd_start),
       .cmd_data_valid(cmd_data_valid),
       .cmd_done(cmd_done),
       .cmd_ready(i2c_ready),
       .i2c_scl(i2c_scl),
       .i2c_sda(i2c_sda),
       .upload_active(i2c_upload_active),
       .upload_req(i2c_upload_req),
       .upload_data(i2c_upload_data),
       .upload_source(i2c_upload_source),
       .upload_valid(i2c_upload_valid),
       .upload_ready(i2c_upload_ready)
   );
   ```

#### `rtl/top.v`
1. **添加I2C端口声明** (第32-34行)
   ```verilog
   // I2C Interface
   output       i2c_scl,
   inout        i2c_sda,
   ```

2. **连接I2C到CDC模块** (第134-135行)
   ```verilog
   .i2c_scl(i2c_scl),              // I2C SCL
   .i2c_sda(i2c_sda),              // I2C SDA
   ```

---

## 🏗️ I2C Handler 功能特性

### 支持的命令

| 命令码 | 功能 | Payload格式 | 说明 |
|-------|------|------------|------|
| **0x04** | I2C_CONFIG | [Device_Addr(1B)] | 配置I2C从机地址 (默认0x50) |
| **0x05** | I2C_WRITE | [Reg_Addr_H(1B), Reg_Addr_L(1B), Data...] | 写数据到I2C设备 |
| **0x06** | I2C_READ | [Reg_Addr_H(1B), Reg_Addr_L(1B), Len_H(1B), Len_L(1B)] | 从I2C设备读数据 |

### 参数配置

- **写缓冲区大小**: 128字节
- **读缓冲区大小**: 128字节
- **I2C时钟频率**: 100kHz (可在`i2c_bit_shift.v`中修改`SCL_CLOCK`参数)
- **系统时钟**: 60MHz (假设，与系统时钟一致)
- **地址模式**: 16位寄存器地址 (大端模式)

### 上传数据

- **数据源标识 (Source ID)**: 0x06 (使用I2C_READ命令码)
- **上传帧格式**:
  ```
  ┌──────┬──────┬──────┬────────┬──────────┬──────────┐
  │ 0xAA │ 0x44 │ 0x06 │ Length │   Data   │ Checksum │
  │ (1B) │ (1B) │ (1B) │  (2B)  │  (N字节)  │   (1B)   │
  └──────┴──────┴──────┴────────┴──────────┴──────────┘
  ```

---

## 🎯 上传流水线集成

I2C handler已完整集成到4通道上传流水线中：

```
┌─────────────┐
│ I2C Handler │
└──────┬──────┘
       │ upload_active, upload_data, upload_valid...
       ▼
┌─────────────┐
│ I2C Adapter │ ← 转换per-byte到packet-level
└──────┬──────┘
       │ packer_req, packer_data, packer_valid...
       ▼
┌─────────────┐
│   Packer    │ ← 4通道打包 (UART, SPI, DSM, I2C)
│ (4 channels)│
└──────┬──────┘
       │ packed_req[3:0], packed_data[31:0]...
       ▼
┌─────────────┐
│   Arbiter   │ ← FIFO仲裁
│  (FIFO=32)  │
└──────┬──────┘
       │ merged_upload_req, merged_upload_data...
       ▼
┌─────────────┐
│  Processor  │ ← 发送到USB
└─────────────┘
```

### 优先级顺序

固定优先级 (从高到低):
1. **UART** (通道0, Source=0x01)
2. **SPI** (通道1, Source=0x03)
3. **DSM** (通道2, Source=0x0A)
4. **I2C** (通道3, Source=0x06) ← **新增**

---

## 📝 使用示例

### 1. 配置I2C设备地址

```python
# 配置I2C从机地址为0xA0 (EEPROM常用地址)
cmd = [0xAA, 0x55, 0x04, 0x00, 0x01, 0xA0, 0xFA]
#      ^^^^^^^^^^^  ^^^^  ^^^^^^^^^^  ^^^^  ^^^^
#      帧头         CMD   长度        地址  校验和
ser.write(bytes(cmd))
```

### 2. 写入数据到I2C设备

```python
# 写入3字节数据到寄存器地址0x0010
reg_addr = 0x0010
data = [0x12, 0x34, 0x56]

cmd = [0xAA, 0x55, 0x05, 0x00, 0x05]  # 帧头 + CMD + 长度(2+3=5)
cmd += [(reg_addr >> 8) & 0xFF, reg_addr & 0xFF]  # 寄存器地址
cmd += data  # 数据
checksum = sum(cmd[2:]) & 0xFF  # 校验和
cmd.append(checksum)

ser.write(bytes(cmd))
```

### 3. 从I2C设备读取数据

```python
# 从寄存器地址0x0020读取8字节数据
reg_addr = 0x0020
read_len = 8

cmd = [0xAA, 0x55, 0x06, 0x00, 0x04]  # 帧头 + CMD + 长度(固定4字节)
cmd += [(reg_addr >> 8) & 0xFF, reg_addr & 0xFF]  # 寄存器地址
cmd += [(read_len >> 8) & 0xFF, read_len & 0xFF]  # 读取长度
checksum = sum(cmd[2:]) & 0xFF
cmd.append(checksum)

ser.write(bytes(cmd))

# 等待响应
time.sleep(0.1)
response = ser.read(100)  # 读取响应帧

# 解析响应: 0xAA 0x44 0x06 LEN_H LEN_L [DATA...] CHECKSUM
if len(response) >= 6:
    if response[0] == 0xAA and response[1] == 0x44:
        source = response[2]  # 应为0x06
        length = (response[3] << 8) | response[4]
        data = response[5:5+length]
        print(f"Read {length} bytes: {data.hex()}")
```

---

## 🔌 硬件连接

### I2C总线连接

```
FPGA (GW5A-25A)              I2C从机设备
┌────────────────┐           ┌──────────────┐
│                │           │              │
│  i2c_scl  ────────────────────── SCL      │
│           │   │  ↑        │              │
│  i2c_sda  ─────┼──┼────────────── SDA      │
│           │   │  │  ↑     │              │
└────────────────┘ │  │     └──────────────┘
                   │  │
                  R1 R2
               (4.7kΩ 上拉电阻到VDD)
```

### 约束文件示例

需要在`constraints/pin_cons.cst`中添加I2C管脚约束：

```tcl
# I2C Interface
IO_LOC "i2c_scl" <PIN_NUMBER>;
IO_PORT "i2c_scl" PULL_MODE=UP IO_TYPE=LVCMOS33 DRIVE=8;

IO_LOC "i2c_sda" <PIN_NUMBER>;
IO_PORT "i2c_sda" PULL_MODE=UP IO_TYPE=LVCMOS33 DRIVE=8;
```

**注意**:
- 将`<PIN_NUMBER>`替换为实际的FPGA管脚号
- LVCMOS33表示3.3V电平，根据实际硬件调整
- `PULL_MODE=UP`提供内部上拉，但外部上拉电阻仍然推荐

---

## ⚡ 性能参数

### 时序参数

| 参数 | 值 | 说明 |
|-----|---|------|
| SCL频率 | 100 kHz | 可在`i2c_bit_shift.v`修改 |
| 系统时钟 | 60 MHz | 与CDC模块一致 |
| SCL分频 | 150 | 60MHz / 4 / 150 = 100kHz |
| 最大写长度 | 128 字节 | 受WRITE_BUFFER限制 |
| 最大读长度 | 128 字节 | 受READ_BUFFER限制 |

### 资源使用估算

| 资源类型 | i2c_handler | i2c_control | i2c_bit_shift | 总计 |
|---------|-------------|-------------|---------------|------|
| LUTs | ~200 | ~150 | ~100 | ~450 |
| Registers | ~180 | ~120 | ~80 | ~380 |
| Block RAM | 0 | 0 | 0 | 0 |

**说明**: 使用分布式RAM实现缓冲区，无需Block RAM

---

## ⚠️ 注意事项

### 1. 仿真模式
在`i2c_handler.v`第1行有仿真开关：
```verilog
//`define DO_SIM 1 // 取消注释以用于仿真 板级验证请注释掉
```
- **仿真时**: 取消注释，时钟分频降低到250 (加快仿真)
- **硬件验证时**: 必须注释掉，使用正常分频250000

### 2. 时序延迟
I2C控制器在每次读写操作后有延迟 (`WAIT_DLY`状态):
- **仿真**: `dly_cnt_max = 250-1`
- **硬件**: `dly_cnt_max = 250000-1` (约4.17ms @ 60MHz)

### 3. 地址模式
当前固定为16位地址模式 (`addr_mode = 1'b1`)，适用于大容量EEPROM。
如需8位地址模式，需修改`i2c_control.v`中的连接。

### 4. 上传数据源ID
I2C使用命令码`0x06`作为上传数据的source ID，确保不与其他模块冲突：
- UART: 0x01
- SPI: 0x03
- DSM: 0x0A
- I2C: 0x06 ✅

---

## 🧪 测试建议

### 1. 仿真测试
```bash
cd F:\FPGA2025\sim
# 创建 i2c_handler_tb 仿真工程
# 测试配置、写入、读取三个命令
```

### 2. 硬件测试

#### 测试1: I2C EEPROM写入
使用24LC64 (64Kbit EEPROM, 地址0xA0):
```python
# 配置地址
send_cmd([0xAA, 0x55, 0x04, 0x00, 0x01, 0xA0, 0xFA])

# 写入"Hello"到地址0x0000
data = b"Hello"
cmd = [0xAA, 0x55, 0x05, 0x00, 2+len(data), 0x00, 0x00] + list(data)
cmd.append(sum(cmd[2:]) & 0xFF)
send_cmd(cmd)
```

#### 测试2: I2C EEPROM读取
```python
# 读取5字节从地址0x0000
cmd = [0xAA, 0x55, 0x06, 0x00, 0x04, 0x00, 0x00, 0x00, 0x05]
cmd.append(sum(cmd[2:]) & 0xFF)
send_cmd(cmd)

# 接收响应
response = ser.read(100)
# 应收到: 0xAA 0x44 0x06 0x00 0x05 H e l l o CHECKSUM
```

---

## 📚 相关文件

### 源码文件
- `rtl/i2c/i2c_handler.v` - I2C handler顶层
- `rtl/i2c/i2c_control.v` - I2C控制逻辑
- `rtl/i2c/i2c_bit_shift.v` - I2C位级操作
- `rtl/cdc.v` - CDC模块 (已集成I2C)
- `rtl/top.v` - 顶层模块 (已添加I2C端口)

### 依赖模块
- `rtl/upload_adapter.v` - 上传适配器
- `rtl/upload_packer.v` - 数据打包器
- `rtl/upload_arbiter.v` - 数据仲裁器

### 文档
- `CLAUDE.md` - 项目开发指南
- `sim/INTEGRATION_SUMMARY.md` - 上传流水线总结

---

## ✅ 集成验证清单

- [x] I2C端口添加到cdc.v
- [x] I2C端口添加到top.v
- [x] I2C ready信号添加到cmd_ready
- [x] I2C上传信号声明
- [x] 上传通道数量更新 (3→4)
- [x] I2C adapter实例化
- [x] Packer连接更新为4通道
- [x] Arbiter配置更新为4源
- [x] I2C handler实例化
- [ ] 管脚约束添加到.cst文件
- [ ] 综合测试
- [ ] 硬件验证

---

## 🎉 总结

I2C handler已成功集成到FPGA2025项目中，具有以下特点：

✅ **完全兼容** CDC架构的命令总线接口
✅ **完整集成** 4通道上传流水线 (UART + SPI + DSM + I2C)
✅ **功能完善** 支持配置、写入、读取操作
✅ **易于使用** 提供Python示例代码
✅ **灵活配置** 128字节读写缓冲，100kHz时钟
✅ **文档完善** 包含使用说明、测试建议

**下一步**:
1. 添加I2C管脚约束到`constraints/pin_cons.cst`
2. 综合项目并检查时序
3. 使用EEPROM或其他I2C设备进行硬件验证

---

**创建日期**: 2025-10-18
**集成版本**: FPGA2025 v1.0 + I2C
**作者**: Claude Code
**状态**: ✅ 集成完成，待硬件验证
