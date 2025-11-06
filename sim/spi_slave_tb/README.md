# SPI Slave Handler 仿真指南

## 📋 概述

本目录包含SPI从机Handler的仿真环境，测试功能码 0x14 (预装发送数据) 和 0x15 (控制上传使能)。

## 📁 文件结构

```
sim/spi_slave_tb/
├── cmd.do              # ModelSim仿真脚本
├── README.md           # 本文档
├── work/               # 编译库（自动生成）
└── *.wlf, *.vcd        # 波形文件（自动生成）
```

## 🚀 运行仿真

### 方法1：使用ModelSim GUI

```bash
cd F:\FPGA2025\sim\spi_slave_tb
modelsim
# 在ModelSim GUI中: Tools -> Execute Macro -> 选择 cmd.do
```

### 方法2：命令行运行

```bash
cd F:\FPGA2025\sim\spi_slave_tb
vsim -do cmd.do
```

### 方法3：一键运行（推荐）

```bash
cd F:\FPGA2025\sim\spi_slave_tb
modelsim -do cmd.do
```

## 🧪 测试内容

### Test 1: 预装发送数据 (功能码 0x14)
- **目的**: 测试通过命令总线预装数据到TX缓冲区
- **测试数据**: "FPGA2025" (8字节)
- **验证**: 外部SPI主机读取，验证数据是否匹配

### Test 2: 启用接收上传 (功能码 0x15)
- **目的**: 测试接收数据自动上传功能
- **步骤**:
  1. 发送0x15命令，data=0x01 (启用上传)
  2. 外部SPI主机写入4字节: 0xDE, 0xAD, 0xBE, 0xEF
  3. 验证数据通过upload接口上传
  4. 检查upload_source = 0x14

### Test 3: 禁用接收上传
- **目的**: 验证上传控制功能
- **步骤**:
  1. 发送0x15命令，data=0x00 (禁用上传)
  2. 外部主机写入数据
  3. 验证没有数据上传

### Test 4: 大数据块预装
- **目的**: 测试缓冲区容量
- **测试数据**: 128字节递增数据 (0x00-0x7F)
- **验证**: 外部主机读取128字节并验证

### Test 5: 双向通信
- **目的**: 测试全双工SPI通信
- **步骤**:
  1. 预装TX数据: 0xA0-0xAF (16字节)
  2. 启用RX上传
  3. 外部主机同时写入0xB0-0xBF，读取0xA0-0xAF
  4. 验证读取和上传数据都正确

## 📊 波形查看

仿真完成后，波形自动分组为：

### Top Level 组
- Clock & Reset
- Command Bus (cmd_type, cmd_length, cmd_data, etc.)
- SPI Physical (spi_clk, spi_cs_n, spi_mosi, spi_miso)
- Upload Interface (upload_data, upload_valid, etc.)

### Handler 组
- State (主状态机和上传状态机)
- TX Buffer Control (指针、长度、ready标志)
- RX Buffer Control (指针、上传使能)
- SPI Interface Signals (内部握手信号)

### Physical 组
- State (物理层状态机)
- Synchronized Signals (同步后的SPI信号)
- Edge Detection (边沿检测)
- Shift Registers (发送/接收移位寄存器)

### Test Status 组
- uploaded_count: 已上传字节数
- test_pass_count: 通过测试数
- test_fail_count: 失败测试数

## ✅ 验证要点

### 1. 命令接收
- 检查Handler状态机：IDLE → WAIT_ALL_DATA → UPDATE_TX_BUFFER → IDLE
- 验证tx_buffer内容正确写入
- 确认tx_buffer_ready拉高

### 2. SPI从机读取
- 观察spi_cs_n下降沿
- 检查Physical层state: IDLE → SHIFT → DONE → SHIFT ...
- 验证spi_miso输出与tx_buffer内容匹配
- 观察bit_count递增 (0→7)

### 3. SPI从机写入
- 观察spi_mosi数据采样
- 检查spi_byte_received脉冲
- 验证rx_buffer内容正确

### 4. 数据上传
- 确认upload_active拉高
- 检查upload_state: UP_IDLE → UP_SEND → UP_WAIT
- 验证upload_data与rx_buffer匹配
- 确认upload_source = 0x14

## 🐛 调试技巧

### 问题：数据读取错误
**检查**:
- tx_buffer_ready是否为1
- tx_read_ptr是否正确递增
- Physical层state是否正确转换
- spi_miso时序是否正确（下降沿更新）

### 问题：数据上传失败
**检查**:
- rx_upload_enable是否为1
- rx_write_ptr与rx_read_ptr差值
- upload_state转换
- upload_ready是否为1

### 问题：时序错误
**检查**:
- SPI时钟频率 (1MHz = 1us周期)
- 系统时钟 (60MHz = 16.67ns周期)
- 同步延迟（3个时钟周期）
- CS拉高/拉低时序

## 📈 性能指标

- **系统时钟**: 60MHz (16.67ns)
- **SPI时钟**: 1MHz (1us)
- **数据传输速率**: 1Mbps (全双工)
- **最大缓冲**: 256字节 (TX和RX各256字节)
- **同步延迟**: 3个系统时钟周期
- **仿真时间**: 约5-10秒（取决于机器性能）

## 🔧 故障排除

### 编译错误
```
Error: Module 'simple_spi_slave' not found
```
**解决**: 确保已编译 `../../rtl/spi/simple_spi_slave.v`

### 仿真卡住
**原因**: 可能是状态机死锁
**检查**: Handler和Physical的state信号

### 数据不匹配
**步骤**:
1. 在波形中添加tx_buffer和rx_buffer数组
2. 对比期望值和实际值
3. 检查$display输出的调试信息

## 📝 修改仿真

### 修改测试数据
编辑 `../../tb/spi_slave_handler_tb.sv`，在Main Test Sequence中修改：

```systemverilog
// 修改预装数据
test_data[0] = 8'hXX;  // 你的数据
test_data[1] = 8'hYY;
...
```

### 修改SPI时钟频率
在testbench顶部修改：
```systemverilog
localparam SPI_CLK_PERIOD_NS = 1000;  // 1MHz
// 改为：
localparam SPI_CLK_PERIOD_NS = 500;   // 2MHz
```

### 添加新测试
在Main Test Sequence的末尾，Test 5之后添加新的测试代码。

## 📞 支持

如果遇到问题：
1. 检查$display输出的调试信息
2. 查看波形中的状态机转换
3. 对比本README的验证要点
4. 参考 `../../rtl/spi/SPI_SLAVE_README.md` 了解模块设计

---

**最后更新**: 2025-01-23
**作者**: AI Assistant
**版本**: 1.0
