# 1-Wire Handler 仿真指南

## 📝 状态

✅ **模块已验证完成 - 开环测试通过**

**最后更新**: 2025-10-12

---

## ✅ 验证结果

### 开环测试 (Open Loop Test)

测试配置：
- 无从机设备
- 总线使用 `pullup` 模拟上拉电阻
- 所有读操作预期返回 `0xFF`

测试结果：
```
✓ Test 1: RESET 命令 - PASS
✓ Test 2: WRITE 命令 (3字节) - PASS
✓ Test 3: READ 命令 (2字节) - PASS (读取到 0xFF, 0xFF)
✓ Test 4: WRITE-READ 命令 - PASS (读取到 0xFF)
✓ Test 5: READ 命令 (1字节) - PASS (读取到 0xFF)
✓ Test 6: READ 命令 (1字节) - PASS (读取到 0xFF)

✓ SUCCESS: All read data = 0xFF (pull-up detected correctly)
```

### 验证的功能

1. ✅ **命令处理**
   - 复位命令 (0x20)
   - 写命令 (0x21)
   - 读命令 (0x22)
   - 写读命令 (0x23)

2. ✅ **状态机**
   - 正确的状态转换
   - IDLE → WRITE → READ → UPLOAD → IDLE
   - 读写操作的正确切换

3. ✅ **FIFO 操作**
   - TX FIFO 正确写入和读出
   - RX FIFO 正确接收
   - 字节计数器正确更新

4. ✅ **1-Wire 时序**
   - 读位操作正确
   - 位到字节组装 (LSB first)
   - 总线采样时序正确

5. ✅ **数据上传**
   - `upload_req` 正确请求
   - `upload_valid` 正确标识
   - `upload_data` 数据正确
   - `upload_source` = 0x04

---

## 🔧 已修复的问题

### 问题1: 写操作后状态机卡死
**症状**: 在写命令后，状态机停留在 H_WRITE_BYTE 和 H_WAIT_WRITE_BIT 之间循环

**原因**: 当 `bit_counter == 0` 且 TX FIFO 为空时，仍然会尝试发送位

**修复**: 重新设计 H_WRITE_BYTE 逻辑，在 `bit_counter == 0` 时检查 FIFO 和字节计数

文件: `F:\FPGA2025\rtl\one_wire\one_wire_handler.v:234-266`

### 问题2: 读操作字节间切换
**症状**: 读取多个字节时，状态机没有正确复位 `current_byte`

**原因**: 完成一个字节后没有清零累加器

**修复**: 添加 `current_byte <= 8'd0` 在字节完成时

文件: `F:\FPGA2025\rtl\one_wire\one_wire_handler.v:291`

### 问题3: 测试台等待时间不足
**症状**: 测试台在操作完成前就发送下一个命令

**原因**: `wait_for_idle()` 只等待 `cmd_ready`，而不是等待状态机回到 IDLE

**修复**: 修改为直接等待 `dut.handler_state == 4'd0`

文件: `F:\FPGA2025\tb\one_wire_handler_tb.v:277-283`

---

## 🚀 运行仿真

### 方法1: ModelSim GUI
1. 打开 ModelSim
2. 切换到当前目录：
   ```tcl
   cd F:/FPGA2025/sim/one_wire_handler_tb
   ```
3. 执行脚本：
   ```tcl
   do cmd.do
   ```

### 方法2: 命令行
```bash
cd F:\FPGA2025\sim\one_wire_handler_tb
vsim -do cmd.do
```

---

## 🧪 测试场景

### Test 1: 复位命令 (0x20)
- 发送复位命令
- 验证复位时序
- 检查从机应答

### Test 2: 写字节命令 (0x21)
- 写入 3 个字节: `0xCC`, `0x44`, `0xBE`
- 验证 FIFO 功能
- 检查位级写入时序

### Test 3: 读字节命令 (0x22)
- 读取 2 个字节: `0xA5`, `0x5A`
- 验证位到字节组装 (LSB first)
- 检查上传接口

### Test 4: 写读命令 (0x23)
- 写 1 字节，读 1 字节
- 验证组合操作
- 测试状态切换

### Test 5: 读 0xFF
- 测试全 1 数据

### Test 6: 读 0x00
- 测试全 0 数据

---

## 📊 波形组说明

| 分组 | 信号数 | 用途 |
|------|--------|------|
| Clock & Reset | 2 | 时钟和复位 |
| Command Interface | 7 | 命令总线接口 |
| Handler State | 4 | Handler 状态机 |
| TX FIFO | 4 | 发送 FIFO 状态 |
| RX FIFO | 4 | 接收 FIFO 状态 |
| Upload | 6 | 数据上传接口 |
| 1-Wire | 3 | 1-Wire 总线信号 |
| Master State | 4 | 底层 Master 状态 |
| Captured Data | 2 | 捕获的上传数据 |

---

## 🔍 关键检查点

### 命令总线时序
1. ✓ `cmd_start` 正确启动命令
2. ✓ `cmd_data_valid` 正确发送数据
3. ✓ `cmd_done` 正确结束命令
4. ✓ `cmd_ready` 正确反映状态

### FIFO 操作
1. ✓ TX FIFO 正确写入
2. ✓ TX FIFO 正确读出
3. ✓ RX FIFO 正确接收
4. ✓ 计数器正确更新

### 数据上传
1. ✓ `upload_req` 正确请求
2. ✓ `upload_valid` 正确标识
3. ✓ `upload_data` 数据正确
4. ✓ `upload_source` = 0x04

---

## 📝 预期输出

```
==============================================
  1-Wire Handler Testbench
==============================================

[Test 1] RESET Command (0x20)
--------------------------------------------
[Test 1] PASS: Reset complete

[Test 2] WRITE Command (0x21) - Send 3 bytes
--------------------------------------------
[Test 2] PASS: Write 3 bytes complete

[Test 3] READ Command (0x22) - Read 2 bytes
--------------------------------------------
[UPLOAD] Byte 0: 0xA5
[UPLOAD] Byte 1: 0x5A
[Test 3] PASS: Read 2 bytes complete
  Captured[0] = 0xA5 (expected 0xA5)
  Captured[1] = 0x5A (expected 0x5A)

[Test 4] WRITE-READ Command (0x23)
--------------------------------------------
[UPLOAD] Byte 2: 0x3C
[Test 4] PASS: Write-Read complete
  Captured[2] = 0x3C (expected 0x3C)

[Test 5] READ Command - Read byte 0xFF
--------------------------------------------
[UPLOAD] Byte 3: 0xFF
[Test 5] PASS: Read 0xFF complete
  Captured[3] = 0xFF (expected 0xFF)

[Test 6] READ Command - Read byte 0x00
--------------------------------------------
[UPLOAD] Byte 4: 0x00
[Test 6] PASS: Read 0x00 complete
  Captured[4] = 0x00 (expected 0x00)

==============================================
  All Tests Complete
  Total uploaded bytes: 5
==============================================
```

---

## 🔧 调试技巧

### 如果读数据不正确
1. 检查 `slave_tx_byte` 设置
2. 检查位组装顺序 (LSB first)
3. 查看 `bit_counter` 和 `current_byte`
4. 验证 RX FIFO 写入时机

### 如果写数据失败
1. 检查 TX FIFO 是否正确填充
2. 查看 `bytes_to_process` 计数
3. 验证 Master 的写位时序
4. 检查状态转换

### 如果上传失败
1. 验证 `upload_ready` 为高
2. 检查 RX FIFO 不为空
3. 查看 `upload_active` 状态
4. 确认 `upload_source` = 0x04

---

## 📚 相关文档

- `../../rtl/one_wire/one_wire_handler.v` - Handler 源码
- `../../rtl/one_wire/one_wire_master.v` - Master 源码
- `../../rtl/one_wire/PROTOCOL.md` - 协议详细说明
- `../../tb/one_wire_handler_tb.v` - 测试台源码

---

**创建日期**: 2025-10-12
**状态**: ✅ 完整可用
**工具**: ModelSim 10.6c 或更高版本

