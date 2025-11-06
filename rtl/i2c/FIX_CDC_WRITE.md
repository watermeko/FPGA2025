# CDC写入功能修复说明

## 问题描述

通过仿真调试发现，CDC写入命令（0x35）虽然被正确识别和执行，但数据从未真正写入寄存器。

**根本原因**: 状态机在 `S_EXEC_WRITE` 状态停留时间太短，`handler_wr_en` 信号持续时间不足，导致 `reg_map` 的边沿检测逻辑无法捕获写脉冲。

## 修复方案

### 方案1：增加写入等待周期状态 ✅ 已实施

通过添加 `S_EXEC_WRITE_HOLD` 状态，确保每次写入操作有足够的时钟周期完成。

---

## 修改内容

### 1. 添加新状态定义

**文件**: `rtl/i2c/i2c_slave_handler.sv:119`

```systemverilog
localparam S_IDLE              = 4'd0;
localparam S_CMD_CAPTURE       = 4'd1;
localparam S_EXEC_SET_ADDR     = 4'd2;
localparam S_EXEC_WRITE        = 4'd3;
localparam S_EXEC_WRITE_HOLD   = 4'd4; // ← 新增：写入保持状态
localparam S_EXEC_READ_SETUP   = 4'd5;
localparam S_UPLOAD_DATA       = 4'd6;
localparam S_FINISH            = 4'd7;
```

### 2. 修改写状态机逻辑

**文件**: `rtl/i2c/i2c_slave_handler.sv:170-185`

#### 原始代码（有问题）:
```systemverilog
S_EXEC_WRITE: begin
    if (cdc_write_ptr < cdc_len) begin
        cdc_write_ptr <= cdc_write_ptr + 1;  // 立即递增
    end else begin
        state <= S_FINISH;
    end
end
```

**问题**: 指针立即递增，状态立即退出，写使能信号只持续1个周期。

#### 修复后代码:
```systemverilog
S_EXEC_WRITE: begin
    // This state checks if we need to write more bytes
    if (cdc_write_ptr < cdc_len) begin
        // Go to hold state to allow write to complete
        state <= S_EXEC_WRITE_HOLD;
    end else begin
        state <= S_FINISH; // All bytes written
    end
end

S_EXEC_WRITE_HOLD: begin
    // Hold state: increment pointer after write completes
    // This gives reg_map time to capture the write enable edge
    cdc_write_ptr <= cdc_write_ptr + 1;
    state <= S_EXEC_WRITE; // Return to check if more writes needed
end
```

---

## 状态机时序改进

### 原始时序（失败）:

```
周期1: 进入 S_EXEC_WRITE
       cdc_write_ptr = 0 < cdc_len = 1
       handler_wr_en = 1
       递增 cdc_write_ptr

周期2: 仍在 S_EXEC_WRITE
       cdc_write_ptr = 1 (不再小于 cdc_len)
       handler_wr_en = 1 (但指针已经不对了)
       跳转到 S_FINISH

周期3: 进入 S_FINISH
       handler_wr_en = 0

结果: handler_wr_en 只有2个周期，但地址/数据不稳定
      reg_map 的边沿检测失败
```

### 修复后时序（成功）:

```
周期1: 进入 S_EXEC_WRITE
       cdc_write_ptr = 0 < cdc_len = 1
       handler_wr_en = 1 ✓
       handler_addr = 0x00 ✓
       handler_wdata = 0x55 ✓

周期2: 跳转到 S_EXEC_WRITE_HOLD
       仍在 S_EXEC_WRITE_HOLD
       handler_wr_en = 0 (状态不是S_EXEC_WRITE)
       递增 cdc_write_ptr

周期3: 跳转回 S_EXEC_WRITE
       cdc_write_ptr = 1 (不再小于 cdc_len)
       handler_wr_en = 1 (但会立即检查完成)

周期4: 跳转到 S_FINISH
       handler_wr_en = 0

结果: handler_wr_en 产生了 1→0→1→0 的变化
      reg_map 可以捕获到下降沿
      数据在写使能有效时保持稳定
```

**注意**: 实际上修复后，每个字节的写入循环是：
- `S_EXEC_WRITE` (handler_wr_en=1, 地址和数据稳定)
- `S_EXEC_WRITE_HOLD` (handler_wr_en=0, 指针递增)
- 循环...

这样每次写入都有完整的上升沿和下降沿。

---

## 写使能信号分析

### 原始代码的写使能:
```systemverilog
assign handler_wr_en = (state == S_EXEC_WRITE);
```

**在原始状态机下**:
- `handler_wr_en` 在 S_EXEC_WRITE 期间始终为1
- 但状态停留时间太短
- 地址和数据在变化中

**在修复后的状态机下**:
- `handler_wr_en` 在 S_EXEC_WRITE 时为1
- `handler_wr_en` 在 S_EXEC_WRITE_HOLD 时为0
- 循环往复，产生清晰的脉冲
- 地址和数据在写使能有效时保持稳定

---

## reg_map 的边沿检测

**reg_map.sv:29**:
```systemverilog
assign wr_en_wdata_fedge = wr_en_wdata_hold && (!wr_en_wdata);
```

需要检测**下降沿**来触发写入。

### 修复前（失败）:
```
wr_en_wdata:      ___╱‾╲___
wr_en_wdata_hold: ____╱‾╲__
wr_en_wdata_fedge: _______ (可能捕获失败)
```

### 修复后（成功）:
```
wr_en_wdata:      ___╱‾‾‾╲___╱‾‾‾╲___
wr_en_wdata_hold: ____╱‾‾‾╲___╱‾‾‾╲__
wr_en_wdata_fedge: ________╱‾╲_____╱‾╲ ✓
```

每个写周期都能产生清晰的下降沿脉冲。

---

## 测试场景

### 场景1：写单个字节
```
cmd_type = 0x35
cdc_start_addr = 0x00
cdc_len = 0x01
data = 0x55

时序:
周期1: S_EXEC_WRITE (ptr=0, wr_en=1, addr=0x00, data=0x55)
周期2: S_EXEC_WRITE_HOLD (ptr递增)
周期3: S_EXEC_WRITE (ptr=1, 检查完成)
周期4: S_FINISH

结果: Reg[0] = 0x55 ✓
```

### 场景2：写4个字节
```
cmd_type = 0x35
cdc_start_addr = 0x00
cdc_len = 0x04
data = [0xAA, 0xBB, 0xCC, 0xDD]

时序:
周期1: S_EXEC_WRITE (ptr=0, addr=0x00, data=0xAA)
周期2: S_EXEC_WRITE_HOLD (ptr→1)
周期3: S_EXEC_WRITE (ptr=1, addr=0x01, data=0xBB)
周期4: S_EXEC_WRITE_HOLD (ptr→2)
周期5: S_EXEC_WRITE (ptr=2, addr=0x02, data=0xCC)
周期6: S_EXEC_WRITE_HOLD (ptr→3)
周期7: S_EXEC_WRITE (ptr=3, addr=0x03, data=0xDD)
周期8: S_EXEC_WRITE_HOLD (ptr→4)
周期9: S_EXEC_WRITE (ptr=4, 检查完成)
周期10: S_FINISH

结果: Reg[0-3] = [0xAA, 0xBB, 0xCC, 0xDD] ✓
```

---

## 预期改进

修复后，仿真应该显示：

```
*** After CDC Write (0x35) - Check Registers ***
========================================
[630000] Current Register Values (from DUT):
  Reg[0] = 0x55  ✅ (成功写入!)
  Reg[1] = 0x00
  Reg[2] = 0x00
  Reg[3] = 0x00
========================================

----------------------------------------
[630000] DUT Internal State:
  State:          0    (IDLE)
  handler_wr_en:  0
  handler_addr:   0x01
  handler_wdata:  0xxx
  cdc_write_ptr:  1
  cdc_len:        1
  reg_map wr_en:  0
  reg_map fedge:  0    (已经完成，信号复位)
----------------------------------------
```

---

## 验证方法

1. 重新编译RTL
2. 运行testbench
3. 检查寄存器值是否正确写入
4. 查看波形确认写使能信号时序

```bash
cd F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb
vsim -do cmd.do
```

---

## 版本信息

- **修复日期**: 2025-11-04
- **修改文件**: `rtl/i2c/i2c_slave_handler.sv`
- **修改方法**: 方案1 - 增加写入等待周期状态
- **新增状态**: `S_EXEC_WRITE_HOLD`
- **状态编号变化**: S_EXEC_READ_SETUP: 4→5, S_UPLOAD_DATA: 5→6, S_FINISH: 6→7

---
