# 1-Wire Master Handler 集成指南

## 📚 概述

本文档说明如何将 `one_wire_handler` 模块集成到 FPGA2025 项目的 `cdc.v` 中。

---

## 🔧 集成步骤

### 1️⃣ 修改 `cdc.v` 信号定义

在 `cdc.v` 的端口列表中添加 1-Wire 接口：

```verilog
module cdc(
    input clk,
    input rst_n,
    // ... existing ports ...

    // 1-Wire 接口（新增）
    inout wire onewire_io,

    // ... other ports ...
);
```

### 2️⃣ 添加内部信号

在 `cdc.v` 内部添加以下信号声明（约在第52行附近）：

```verilog
// --- Ready & Upload Wires from Handlers ---
wire        pwm_ready, ext_uart_ready, dac_ready, spi_ready, dsm_ready;
wire        onewire_ready;  // 新增
wire        processor_upload_ready;
```

修改 `cmd_ready` 信号（约在第79行）：

```verilog
// 原始代码：
// wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready & spi_ready & dsm_ready;

// 修改为：
wire cmd_ready = pwm_ready & ext_uart_ready & dac_ready & spi_ready & dsm_ready & onewire_ready;
```

### 3️⃣ 添加上传通道信号

在上传接口信号定义处（约在第56-76行）添加：

```verilog
// 1-Wire 上传信号
wire        onewire_upload_active;
wire        onewire_upload_req;
wire [7:0]  onewire_upload_data;
wire [7:0]  onewire_upload_source;
wire        onewire_upload_valid;
wire        onewire_upload_ready;
```

### 4️⃣ 修改上传通道数量

修改 `NUM_UPLOAD_CHANNELS` 参数（约在第86行）：

```verilog
// 原始代码：
// parameter NUM_UPLOAD_CHANNELS = 3;  // UART + SPI + DSM

// 修改为：
parameter NUM_UPLOAD_CHANNELS = 4;  // UART + SPI + DSM + 1-Wire
```

### 5️⃣ 添加 Adapter 信号

在 Adapter 输出信号定义处（约在第88-105行）添加：

```verilog
// 1-Wire Adapter 输出
wire       onewire_packer_req;
wire [7:0] onewire_packer_data;
wire [7:0] onewire_packer_source;
wire       onewire_packer_valid;
wire       onewire_packer_ready;
```

### 6️⃣ 实例化 1-Wire Adapter

在 DSM Adapter 实例化之后（约在第152-166行）添加：

```verilog
// --- 1-Wire Adapter ---
upload_adapter u_onewire_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .handler_upload_active(onewire_upload_active),
    .handler_upload_data(onewire_upload_data),
    .handler_upload_source(onewire_upload_source),
    .handler_upload_valid(onewire_upload_valid),
    .handler_upload_ready(onewire_upload_ready),
    .packer_upload_req(onewire_packer_req),
    .packer_upload_data(onewire_packer_data),
    .packer_upload_source(onewire_packer_source),
    .packer_upload_valid(onewire_packer_valid),
    .packer_upload_ready(onewire_packer_ready)
);
```

### 7️⃣ 修改 Packer 连接

修改 `upload_packer` 实例化（约在第169-186行）：

```verilog
upload_packer #(
    .NUM_CHANNELS(NUM_UPLOAD_CHANNELS),
    .FRAME_HEADER_H(8'hAA),
    .FRAME_HEADER_L(8'h44)
) u_packer (
    .clk(clk),
    .rst_n(rst_n),
    // 原始连接：
    // .raw_upload_req({dsm_packer_req, spi_packer_req, uart_packer_req}),

    // 修改为（添加 onewire_packer_req）：
    .raw_upload_req({onewire_packer_req, dsm_packer_req, spi_packer_req, uart_packer_req}),
    .raw_upload_data({onewire_packer_data, dsm_packer_data, spi_packer_data, uart_packer_data}),
    .raw_upload_source({onewire_packer_source, dsm_packer_source, spi_packer_source, uart_packer_source}),
    .raw_upload_valid({onewire_packer_valid, dsm_packer_valid, spi_packer_valid, uart_packer_valid}),
    .raw_upload_ready({onewire_packer_ready, dsm_packer_ready, spi_packer_ready, uart_packer_ready}),
    .packed_upload_req(packed_req),
    .packed_upload_data(packed_data),
    .packed_upload_source(packed_source),
    .packed_upload_valid(packed_valid),
    .packed_upload_ready(arbiter_ready)
);
```

### 8️⃣ 实例化 1-Wire Handler

在 DSM Handler 实例化之后（约在第333-351行）添加：

```verilog
// --- 1-Wire Handler ---
one_wire_handler #(
    .CLK_FREQ(60_000_000)  // 60MHz 系统时钟
) u_onewire_handler (
    .clk(clk),
    .rst_n(rst_n),
    .cmd_type(cmd_type),
    .cmd_length(cmd_length),
    .cmd_data(cmd_data),
    .cmd_data_index(cmd_data_index),
    .cmd_start(cmd_start),
    .cmd_data_valid(cmd_data_valid),
    .cmd_done(cmd_done),
    .cmd_ready(onewire_ready),
    .upload_active(onewire_upload_active),
    .upload_req(onewire_upload_req),
    .upload_data(onewire_upload_data),
    .upload_source(onewire_upload_source),
    .upload_valid(onewire_upload_valid),
    .upload_ready(onewire_upload_ready),
    .onewire_io(onewire_io)
);
```

### 9️⃣ 修改顶层模块 `top.v`

在 `top.v` 中添加 1-Wire 端口并连接到 CDC 模块：

```verilog
module top(
    // ... existing ports ...

    // 1-Wire 接口（新增）
    inout wire onewire_io,

    // ... other ports ...
);

// CDC 实例化（修改）
cdc u_cdc(
    .clk(PHY_CLK),
    .rst_n(system_rst_n),
    // ... existing connections ...

    // 1-Wire 接口（新增）
    .onewire_io(onewire_io),

    // ... other connections ...
);
```

---

## 📋 功能码定义

将以下功能码添加到通信协议文档 `USB-CDC通信协议.md` 中：

| 功能码 | 功能描述 | 完成情况 |
|--------|---------|---------|
| 0x10 | **1-Wire 复位** | ✅ |
| 0x11 | **1-Wire 写字节** | ✅ |
| 0x12 | **1-Wire 读字节** | ✅ |
| 0x13 | **1-Wire 写读操作** | ✅ |

---

## 🧪 测试建议

### 1. 硬件连接测试
```
FPGA (onewire_io) <---[4.7kΩ上拉]---> 从机设备 (DQ)
                           |
                          VDD
```

### 2. 功能测试顺序
1. **复位测试** - 发送 `AA 55 10 00 00 [校验和]`
2. **写单字节** - 发送 `AA 55 11 00 01 AB [校验和]`
3. **读单字节** - 发送 `AA 55 12 00 01 [校验和]`
4. **写读测试** - 发送 `AA 55 13 00 03 01 01 AB [校验和]`

### 3. 时序验证
使用 SignalTap 或逻辑分析仪验证以下时序：
- 复位脉冲：480μs
- 应答检测：60μs 内采样
- 写0：60μs 低电平
- 写1：6μs 低电平
- 读时隙：6μs 低电平 + 9μs 采样

---

## ⚠️ 注意事项

1. **上拉电阻必需** - 1-Wire 总线需要 4.7kΩ 上拉电阻
2. **时钟频率** - 当前时序参数针对 60MHz 系统时钟设计
3. **管脚约束** - 需要在约束文件中添加 `onewire_io` 管脚定义
4. **IO 标准** - 建议使用 3.3V LVCMOS33 标准

---

## 📊 资源使用估算

| 资源类型 | 预估用量 |
|---------|---------|
| LUTs | ~200 |
| Registers | ~150 |
| Block RAM | 0 (使用分布式 RAM) |

---

## 🔍 调试建议

1. **添加调试输出**
   ```verilog
   // 在 cdc.v 中添加调试信号
   assign debug_out = u_onewire_handler.ow_busy;
   ```

2. **SignalTap 监控信号**
   - `onewire_io`
   - `handler_state`
   - `ow_busy` / `ow_done`
   - `presence_detected`

3. **常见问题**
   - 无应答：检查上拉电阻和从机供电
   - 时序错误：验证系统时钟频率是否为 60MHz
   - 数据错误：检查字节序（LSB first）

---

完成以上步骤后，1-Wire 主机功能即可正常工作！
