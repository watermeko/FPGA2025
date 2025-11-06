# Upload Full Integration Test

## 概述

完整的三模块集成测试，验证数据上传链路的完整功能：

```
[UART Handler] ──> [Adapter] ──> [Packer] ──┐
                                              ├──> [Arbiter] ──> [Processor]
[SPI Handler]  ──> [Adapter] ──> [Packer] ──┘
```

## 测试模块

1. **upload_adapter_0.v** - 协议适配器（2个实例：UART + SPI）
2. **upload_packer.v** - 数据打包器（多通道，2通道配置）
3. **upload_arbiter.v** - 数据仲裁器（FIFO缓存 + 优先级调度）

## 测试场景

### Test 1: UART单独发送
- 发送3字节原始数据
- 预期输出：9字节协议帧（帧头2 + 源1 + 长度2 + 数据3 + 校验1）

### Test 2: SPI单独发送
- 发送4字节原始数据
- 预期输出：10字节协议帧

### Test 3: 并发发送测试（关键）
- UART和SPI同时开始发送
- 验证优先级：UART优先
- 验证数据包完整性：正在传输的包不会被打断
- 预期输出：20字节（UART 9字节 + SPI 11字节）

### Test 4: 背压测试
- Processor中途变busy
- 验证背压机制是否正常工作
- 数据不应丢失

### Test 5: 交替发送
- UART -> SPI -> UART 连续发送
- 验证仲裁器的公平性

## 运行仿真

### 方法1：使用脚本（推荐）

```bash
cd sim/upload_full_integration_tb
./run_sim.sh          # 命令行模式
```

### 方法2：使用ModelSim GUI

```bash
cd sim/upload_full_integration_tb
vsim -do cmd.do       # GUI模式
```

### 方法3：手动执行

```bash
cd sim/upload_full_integration_tb
vsim
# 在ModelSim中执行：
ModelSim> do cmd.do
```

## 仿真输出

### 终端输出
仿真过程会显示详细的日志：
- 每个字节的发送记录
- 每个字节的接收记录
- 测试通过/失败状态
- 最终统计信息

### 波形文件
- `upload_full_integration_tb.vcd` - 波形数据

查看波形：
```bash
gtkwave upload_full_integration_tb.vcd
```

或在ModelSim GUI中直接查看。

## 预期结果

所有5个测试应该通过：

```
================================================================
  FINAL SUMMARY
================================================================
  UART packets sent:     5
  SPI packets sent:      4
  Total packets:         9
  UART bytes sent:       11
  SPI bytes sent:        15
  Total bytes sent:      26
  Total bytes received:  70 (包括协议帧头和校验)
================================================================
```

## 关键观察点

### 1. Adapter功能
- `upload_active` 信号正确控制 `req` 信号
- 数据透传无误

### 2. Packer功能
- 正确添加帧头（0xAA44）
- 正确计算长度和校验和
- 多通道并行工作

### 3. Arbiter功能
- FIFO正常缓存数据
- 优先级正确（UART > SPI）
- 数据包完整性保证（req信号识别包边界）
- 无数据丢失

## 故障排查

### 编译错误
检查文件路径是否正确：
```
../../rtl/upload_adapter_0.v
../../rtl/upload_packer.v
../../rtl/upload_arbiter.v
../../tb/upload_full_integration_tb.v
```

### 仿真超时
检查状态机是否卡死，查看波形中的state信号。

### 字节数不匹配
- 检查packer是否正确打包
- 检查arbiter的FIFO是否满/空

## 文件结构

```
sim/upload_full_integration_tb/
├── cmd.do              # ModelSim仿真脚本
├── run_sim.sh          # 快速启动脚本
├── README.md           # 本文档
├── work/               # 编译库（自动生成）
├── transcript          # 仿真日志（自动生成）
└── *.vcd               # 波形文件（自动生成）
```

## 修改建议

### 调整测试参数
编辑 `tb/upload_full_integration_tb.v`，修改发送的字节数：

```verilog
send_uart_packet(3, 8'hC1);  // 改为其他数值
```

### 调整FIFO深度
编辑 `cmd.do` 或 testbench，修改arbiter参数：

```verilog
upload_arbiter #(
    .NUM_SOURCES(2),
    .FIFO_DEPTH(128)  // 改为其他值
)
```

### 添加更多波形
编辑 `cmd.do`，添加更多 `add wave` 命令。

## 版本说明

- **Testbench**: upload_full_integration_tb.v
- **使用模块版本**:
  - upload_adapter_0.v (唯一版本)
  - upload_packer.v (最新版)
  - upload_arbiter.v (最新版，UART优先级更高)

## 联系信息

如有问题，请检查：
1. ModelSim版本兼容性
2. 文件路径是否正确
3. 波形中的状态机状态
