# 1-Wire Master 仿真指南

## 📁 文件说明

| 文件 | 描述 |
|------|------|
| `cmd.do` | ModelSim 仿真脚本 |
| `README.md` | 本文档 |

---

## 🚀 运行仿真

### 方法1: ModelSim GUI
1. 打开 ModelSim
2. 切换到当前目录：
   ```tcl
   cd F:/FPGA2025/sim/one_wire_master_tb
   ```
3. 执行脚本：
   ```tcl
   do cmd.do
   ```

### 方法2: 命令行
```bash
cd F:\FPGA2025\sim\one_wire_master_tb
vsim -do cmd.do
```

---

## 📊 波形组说明

### 1. Clock & Reset
- `clk` - 系统时钟 (60MHz)
- `rst_n` - 复位信号

### 2. Control
- `start_reset` - 启动复位序列
- `start_write_bit` - 启动写位操作
- `start_read_bit` - 启动读位操作
- `write_bit_data` - 要写入的位值 (0/1)

### 3. Status
- `busy` - 操作进行中
- `done` - 操作完成脉冲
- `read_bit_data` - 读取到的位值
- `presence_detected` - 检测到从机应答

### 4. 1-Wire Bus
- `onewire_io` - 双向1-Wire总线
- `onewire_drive` - 从机驱动信号 (testbench)
- `onewire_value` - 从机驱动值 (testbench)

### 5. State Machine
- `state` - 状态机当前状态
  - 0: ST_IDLE
  - 1: ST_RESET_LOW
  - 2: ST_RESET_WAIT
  - 3: ST_RESET_SAMPLE
  - 4: ST_RESET_RECOVERY
  - 5: ST_WRITE_LOW
  - 6: ST_WRITE_RECOVERY
  - 7: ST_READ_LOW
  - 8: ST_READ_SAMPLE
  - 9: ST_READ_RECOVERY
- `timer` - 时序计数器

### 6. DUT Internal
- `oe` - 输出使能 (1=驱动低电平, 0=释放)
- `output_val` - 输出值

---

## 🧪 测试场景

### Test 1: 复位与应答检测
- **操作**: 主机发起复位脉冲
- **预期**: 从机在合适时间窗口内拉低总线
- **验证**: `presence_detected` 信号为高

### Test 2: 写位 0
- **操作**: 主机写 0
- **预期**: 总线拉低 60μs
- **时序**: 3600 个时钟周期 @ 60MHz

### Test 3: 写位 1
- **操作**: 主机写 1
- **预期**: 总线拉低 6μs 后释放
- **时序**: 360 个时钟周期 @ 60MHz

### Test 4: 读位 0
- **操作**: 主机读位，从机发送 0
- **预期**: 从机在采样窗口拉低总线
- **验证**: `read_bit_data` = 0

### Test 5: 读位 1
- **操作**: 主机读位，从机发送 1
- **预期**: 从机保持总线为高
- **验证**: `read_bit_data` = 1

---

## ⏱️ 关键时序参数

| 参数 | 时间 | 时钟周期 (@60MHz) |
|------|------|------------------|
| 复位脉冲 | 480μs | 28800 |
| 应答检测窗口 | 70μs | 4200 |
| 写0低电平 | 60μs | 3600 |
| 写1低电平 | 6μs | 360 |
| 读低电平 | 6μs | 360 |
| 读采样延迟 | 9μs | 540 |

---

## 📝 仿真结果检查

### 检查点
1. ✓ 复位脉冲宽度是否正确 (~480μs)
2. ✓ 从机应答是否被正确检测
3. ✓ 写0时序是否符合规范 (~60μs)
4. ✓ 写1时序是否符合规范 (~6μs)
5. ✓ 读位采样时间是否正确 (~9μs)
6. ✓ 状态转换是否正常

### 成功标志
- Console 输出：
  ```
  [Test 1] PASS: Presence detected
  [Test 4] PASS: Read bit = 0
  [Test 5] PASS: Read bit = 1
  All Tests Complete
  ```

---

## 🔧 调试技巧

### 如果应答检测失败
1. 检查 `RESET_LOW_TIME` 是否为 28800
2. 检查 `RESET_WAIT_TIME` 是否为 4200
3. 检查从机模拟器的应答时序

### 如果读写时序不正确
1. 验证系统时钟频率为 60MHz
2. 检查时序常量定义
3. 使用波形缩放查看精确时序

### 如果状态机卡死
1. 检查 `done` 信号是否正常产生
2. 检查 `busy` 信号是否正确清除
3. 查看 `timer` 计数器是否溢出

---

## 📚 相关文档

- `../../rtl/one_wire/one_wire_master.v` - 源代码
- `../../rtl/one_wire/PROTOCOL.md` - 协议说明
- `../../tb/one_wire_master_tb.v` - 测试台源码

---

## 🎯 下一步

仿真通过后，可以进行：
1. 集成到 `one_wire_handler.v` 测试
2. 完整的 CDC 系统仿真
3. 硬件测试

---

**创建日期**: 2025-10-12
**工具**: ModelSim 10.6c 或更高版本
