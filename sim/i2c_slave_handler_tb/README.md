# I2C Slave Handler Testbench - Core CDC Commands Test

## 概述

这个testbench专注测试 `i2c_slave_handler` 模块的核心CDC命令功能：**CDC写入（0x35）**和**CDC读取（0x36）**。

## 测试覆盖

### CDC命令测试

| 命令码 | 功能 | 测试内容 |
|--------|------|---------|
| **0x35** | CDC写入寄存器 | 单字节写入、多字节写入 |
| **0x36** | CDC读取寄存器 | 单字节读取、多字节读取 |

## 测试用例列表（共4个）

### Test 1: CDC写单个寄存器
- **命令**: 0x35
- **操作**: 写入寄存器0 = 0x55
- **验证**: 通过CDC读取验证

### Test 2: CDC读单个寄存器
- **命令**: 0x36
- **操作**: 读取寄存器0
- **验证**: 确认读取值为0x55

### Test 3: CDC写所有寄存器
- **命令**: 0x35
- **操作**: 写入寄存器0-3 = 0xAA, 0xBB, 0xCC, 0xDD
- **验证**: 通过CDC读取验证

### Test 4: CDC读所有寄存器
- **命令**: 0x36
- **操作**: 读取寄存器0-3
- **验证**: 确认所有值正确

## 运行仿真

### 方法1: 使用ModelSim GUI

```bash
cd F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb
vsim -do cmd.do
```

### 方法2: 命令行模式

```bash
cd F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb
vsim -c -do cmd.do
```

### 方法3: 手动编译和运行

```tcl
# 创建库
vlib work
vmap work work

# 编译设计文件
vlog -sv ../../rtl/i2c/synchronizer.sv
vlog -sv ../../rtl/i2c/edge_detector.v
vlog -sv ../../rtl/i2c/i2c_slave.sv
vlog -sv ../../rtl/i2c/reg_map.sv
vlog -sv ../../rtl/i2c/bidir.sv
vlog -sv ../../rtl/i2c/i2c_slave_handler.sv

# 编译testbench
vlog -sv ../../tb/i2c_slave_handler_tb.sv

# 启动仿真
vsim work.i2c_slave_handler_tb

# 添加波形
do cmd.do

# 运行
run -all
```

## 预期输出

仿真成功时会看到如下输出：

```
============================================================
  I2C Slave Handler Testbench - Core CDC Commands Test
  Testing CDC Commands 0x35/0x36 (Write/Read Registers)
============================================================

############################################################
# TEST 1: CDC Write Single Register (0x35)
############################################################
[...测试过程...]
TEST 1: PASS - CDC write command executed

############################################################
# TEST 2: CDC Read Single Register (0x36)
############################################################
[...测试过程...]
TEST 2: PASS - Read data matches (0x55)

############################################################
# TEST 3: CDC Write All 4 Registers (0x35)
############################################################
[...测试过程...]
TEST 3: PASS - CDC write all registers

############################################################
# TEST 4: CDC Read All 4 Registers (0x36)
############################################################
[...测试过程...]
TEST 4: PASS - All registers read correctly

============================================================
  TEST SUMMARY
============================================================
  Total Tests: 4
  Passed:      4
  Failed:      0
============================================================
  *** ALL TESTS PASSED ***
============================================================
```

## 波形查看

仿真完成后，可以在ModelSim波形窗口查看以下信号组：

### 关键信号组

1. **Top Level**: 顶层时钟、复位和I2C物理总线
2. **CDC Command**: CDC命令总线接口
3. **CDC Upload**: CDC上传数据接口
4. **FPGA Preload**: FPGA内部预装接口
5. **DUT State**: 处理器状态机和缓冲区
6. **I2C Slave**: I2C从机核心操作
7. **Register Map**: 寄存器存储和控制
8. **Test Control**: 测试台控制信号

### 重要时序点

查看波形时关注以下关键时序：

- **CDC命令**: `cmd_start` → `cmd_data_valid` → `cmd_done`
- **CDC上传**: `upload_req` ↔ `upload_ready` 握手
- **I2C通信**: `i2c_scl` 和 `i2c_sda` 的START/STOP/ACK时序
- **寄存器更新**: `registers[]` 数组的变化

## 故障排查

### 问题1: 编译错误
**原因**: 缺少依赖文件
**解决**: 确保以下文件存在：
- rtl/i2c/synchronizer.sv
- rtl/i2c/edge_detector.v
- rtl/i2c/i2c_slave.sv
- rtl/i2c/reg_map.sv
- rtl/i2c/bidir.sv
- rtl/i2c/i2c_slave_handler.sv

### 问题2: 仿真超时
**原因**: 测试卡死或时序问题
**解决**:
1. 检查 `cmd_ready` 信号是否正常
2. 检查 `upload_ready` 握手是否正常
3. 检查I2C时钟是否正常生成

### 问题3: 测试失败
**原因**: 数据不匹配
**解决**:
1. 查看"DUT State"信号组的captured_data和upload_buffer
2. 查看"Register Map"的registers数组内容
3. 确认CDC命令时序是否正确

## 文件结构

```
F:\FPGA2025-main_mux\
├── rtl\i2c\
│   ├── synchronizer.sv           # 同步器
│   ├── edge_detector.v            # 边沿检测
│   ├── i2c_slave.sv               # I2C从机核心
│   ├── reg_map.sv                 # 寄存器映射
│   ├── bidir.sv                   # 双向IO
│   └── i2c_slave_handler.sv       # I2C从机处理器(DUT)
├── tb\
│   └── i2c_slave_handler_tb.sv    # 测试平台
└── sim\i2c_slave_handler_tb\
    ├── cmd.do                     # ModelSim仿真脚本
    └── README.md                  # 本文档
```

## 时序参数

- **系统时钟**: 50MHz (CLK_PERIOD = 20ns)
- **I2C时钟**: ~100kHz (手动生成，周期约10us)
- **仿真时长**: 约50ms (可根据需要调整)

## CDC命令格式参考

### 0x34 - 设置I2C地址
```
cmd_type = 0x34
captured_data[0] = 新地址(7位)
```

### 0x35 - 写寄存器
```
cmd_type = 0x35
captured_data[0] = 起始地址
captured_data[1] = 长度
captured_data[2~N] = 数据
```

### 0x36 - 读寄存器
```
cmd_type = 0x36
captured_data[0] = 起始地址
captured_data[1] = 长度

返回:
upload_data = 寄存器值
upload_source = 0x36
```

## 性能指标

- **CDC写入延迟**: ~10个时钟周期
- **CDC读取延迟**: ~15个时钟周期(含上传握手)
- **I2C写入速度**: 标准I2C速度(100kHz)
- **I2C读取速度**: 标准I2C速度(100kHz)

## 参考文档

- `CDC_COMMANDS_QUICK_REFERENCE.md` - CDC命令详细说明
- `i2c_slave_usage_example.sv` - 使用示例
- `CDC_COMMAND_SPEC.md` - CDC命令规范

## 版本信息

- **版本**: v1.0
- **创建日期**: 2025-11-03
- **作者**: Claude Code
- **测试模块**: i2c_slave_handler.sv

---
