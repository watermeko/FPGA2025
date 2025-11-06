# Testbench 简化说明

## 修改内容

已将testbench从8个测试用例简化为**4个核心CDC测试用例**，专注于验证CDC命令0x35和0x36的功能。

## 删除的测试

以下测试已被移除：

- ❌ Test 5: FPGA Internal Preload
- ❌ Test 6: I2C Master Write to Slave
- ❌ Test 7: I2C Master Read from Slave
- ❌ Test 8: CDC Set I2C Address (0x34)

## 保留的测试

✅ Test 1: CDC写单个寄存器 (0x35)
✅ Test 2: CDC读单个寄存器 (0x36)
✅ Test 3: CDC写所有4个寄存器 (0x35)
✅ Test 4: CDC读所有4个寄存器 (0x36)

## 修改的文件

1. **F:\FPGA2025-main_mux\tb\i2c_slave_handler_tb.sv**
   - 删除了Test 5-8的代码
   - 更新了测试标题

2. **F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb\cmd.do**
   - 更新了测试列表说明

3. **F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb\README.md**
   - 更新了文档说明
   - 修改了预期输出

## 当前测试状态（上次仿真结果）

根据之前的仿真结果：

| 测试 | 状态 | 问题 |
|------|------|------|
| Test 1 | ✅ PASS | CDC写命令正常执行 |
| Test 2 | ❌ FAIL | 读取到0x00，期望0x55 |
| Test 3 | ✅ PASS | CDC写命令正常执行 |
| Test 4 | ❌ FAIL | 读取全为0x00 |

## 下一步

需要调试CDC写入逻辑，确保数据能够正确写入寄存器。主要检查点：

1. `handler_wr_en` 信号时序
2. `handler_addr` 和 `handler_wdata` 的稳定性
3. `reg_map` 的写使能边沿检测逻辑
4. 状态机 `S_EXEC_WRITE` 的执行时序

建议查看波形文件，重点观察时间戳 **430000ps** 附近（Test 1执行时）的信号变化。
