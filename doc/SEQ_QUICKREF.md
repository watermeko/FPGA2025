## 自定义序列发生器 - 快速参考

### 已创建的文件

#### RTL模块
```
F:\FPGA2025\rtl\pwm\
├── seq_generator.v       - 单通道核心（90行）
├── seq_multichannel.sv   - 8通道管理器（75行）
└── seq_handler.v         - 命令处理器（130行）
```

#### 测试台
```
F:\FPGA2025\tb\
├── seq_generator_tb.v    - 核心模块测试
└── seq_handler_tb.v      - 完整系统测试
```

#### 工具和文档
```
F:\FPGA2025\software\
└── seq_command_tool.py   - Python配置工具

F:\FPGA2025\doc\
└── 自定义序列发生器说明.md  - 完整文档
```

---

### 快速使用指南

#### 1. 生成配置命令（Python）

**示例：通道0，1MHz基准，10位序列 "0101010101"**
```bash
python software/seq_command_tool.py -c 0 -f 1000000 -p "0101010101"
```

输出命令包：
```
AA 55 F0 00 0D 00 01 00 3C 0A 55 01 00 00 00 00 00 00 XX
```

#### 2. 命令格式快查

**命令码**: `0xF0`
**Payload**: 13字节

| 字节 | 内容 | 说明 |
|-----|------|------|
| 0 | 通道 | 0-7 |
| 1 | 使能 | 0/1 |
| 2-3 | 分频器 | 大端序 |
| 4 | 长度 | 1-64位 |
| 5-12 | 序列 | 小端序 |

#### 3. 频率计算

```
分频器 = 系统时钟(60MHz) / 基准频率
输出频率 = 基准频率 / 序列长度
```

**示例**:
- 基准频率 1MHz → 分频器 = 60
- 序列长度 10位 → 输出 = 100kHz

#### 4. 常用配置示例

| 需求 | 通道 | 基准频率 | 分频器 | 序列 | 长度 | 输出频率 |
|-----|------|---------|--------|------|------|---------|
| 100kHz方波 | 0 | 1MHz | 60 | 0101010101 | 10 | 100kHz |
| 250kHz | 1 | 2MHz | 30 | 11001100 | 8 | 250kHz |
| 125kHz | 2 | 500kHz | 120 | 1010 | 4 | 125kHz |

#### 5. Python工具参数

```bash
python seq_command_tool.py \
  -c <通道0-7> \
  -f <基准频率Hz> \
  -p "<位模式>" \
  [--disable] \
  [-o 输出文件]
```

---

### 集成到项目

#### 在 cdc.v 中添加:

```verilog
wire [7:0] seq_pins;
wire       seq_cmd_ready;

seq_handler u_seq_handler (
    .clk(clk),
    .rst_n(rst_n),
    .cmd_type(cmd_type),
    .cmd_length(cmd_length),
    .cmd_data(cmd_data),
    .cmd_data_index(cmd_data_index),
    .cmd_start(cmd_start),
    .cmd_data_valid(cmd_data_valid),
    .cmd_done(cmd_done),
    .cmd_ready(seq_cmd_ready),
    .seq_pins(seq_pins)
);
```

#### 在 top.v 中添加:

```verilog
output [7:0] seq_out,
// ...
assign seq_out = seq_pins;
```

---

### 仿真测试

```bash
cd F:\FPGA2025\sim

# 测试核心模块
vlog ../rtl/pwm/seq_generator.v
vlog ../tb/seq_generator_tb.v
vsim seq_generator_tb
run -all

# 测试完整系统
vlog ../rtl/pwm/*.v ../rtl/pwm/*.sv
vlog ../tb/seq_handler_tb.v
vsim seq_handler_tb
run -all
```

---

### 技术规格

- **通道数**: 8独立通道
- **序列长度**: 1-64位
- **基准频率**: 915Hz - 60MHz
- **输出频率**: 14Hz - 60MHz
- **命令码**: 0xF0
- **系统时钟**: 60MHz

---

### 应用示例

1. **串行协议模拟**: 生成SPI/I2C时钟模式
2. **测试向量**: 循环测试序列
3. **分数分频**: 非整数倍频率输出
4. **自定义PWM**: 复杂占空比波形

---

**完整文档**: `F:\FPGA2025\doc\自定义序列发生器说明.md`
