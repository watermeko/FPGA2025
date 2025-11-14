# Testbench 调试增强说明

## 修改内容

为了验证CDC写入是否真正写入寄存器，已在testbench中添加了**实时寄存器监控功能**。

## 新增的调试任务

### 1. `display_registers()` - 显示寄存器值
直接访问DUT内部寄存器数组，输出当前4个寄存器的实际值。

**访问路径**: `u_dut.u_reg_map.registers[0-3]`

**输出示例**:
```
========================================
[630000] Current Register Values (from DUT):
  Reg[0] = 0x55
  Reg[1] = 0x00
  Reg[2] = 0x00
  Reg[3] = 0x00
========================================
```

### 2. `display_dut_state()` - 显示DUT内部状态
显示状态机和控制信号的当前状态，用于调试写入逻辑。

**监控信号**:
- `state` - 状态机当前状态
- `handler_wr_en` - CDC写使能信号
- `handler_addr` - CDC写地址
- `handler_wdata` - CDC写数据
- `cdc_write_ptr` - 写指针
- `cdc_len` - 写长度
- `reg_map wr_en` - reg_map写使能输入
- `reg_map fedge` - reg_map边沿检测信号

**输出示例**:
```
----------------------------------------
[630000] DUT Internal State:
  State:          0
  handler_wr_en:  0
  handler_addr:   0x00
  handler_wdata:  0x00
  cdc_write_ptr:  0
  cdc_len:        1
  reg_map wr_en:  0
  reg_map fedge:  0
----------------------------------------
```

## 监控点分布

### 初始化后
- 显示寄存器初始值（应该全为0x00）

### TEST 1 - CDC写单个寄存器后
- 显示寄存器值（检查Reg[0]是否为0x55）
- 显示DUT状态（检查写使能等信号）

### TEST 2 - CDC读单个寄存器后
- 再次显示寄存器值（确认读操作不影响寄存器）

### TEST 3 - CDC写所有寄存器后
- 显示寄存器值（检查是否为0xAA, 0xBB, 0xCC, 0xDD）

### TEST 4 - CDC读所有寄存器后
- 最后显示寄存器值（确认最终状态）

## 预期行为

如果CDC写入功能正常，应该看到：

```
*** Initial Register State ***
========================================
[290000] Current Register Values (from DUT):
  Reg[0] = 0x00
  Reg[1] = 0x00
  Reg[2] = 0x00
  Reg[3] = 0x00
========================================

... CDC Write Command 0x35 执行 ...

*** After CDC Write (0x35) - Check Registers ***
========================================
[630000] Current Register Values (from DUT):
  Reg[0] = 0x55  ✅ (成功写入!)
  Reg[1] = 0x00
  Reg[2] = 0x00
  Reg[3] = 0x00
========================================
```

## 如果写入失败

如果看到寄存器值仍然是0x00，说明CDC写入没有生效：

```
*** After CDC Write (0x35) - Check Registers ***
========================================
[630000] Current Register Values (from DUT):
  Reg[0] = 0x00  ❌ (写入失败!)
  Reg[1] = 0x00
  Reg[2] = 0x00
  Reg[3] = 0x00
========================================

----------------------------------------
[630000] DUT Internal State:
  State:          0    (已经回到IDLE)
  handler_wr_en:  0    (写使能已关闭)
  handler_addr:   0x00
  handler_wdata:  0xaa (数据还在，但没写入)
  cdc_write_ptr:  4    (指针已递增完成)
  cdc_len:        4
  reg_map wr_en:  0    (没有写使能传递到reg_map)
  reg_map fedge:  0    (没有检测到下降沿)
----------------------------------------
```

这表明问题在于：
1. `handler_wr_en` 没有正确触发
2. 或者 `reg_map` 的边沿检测逻辑没有捕获到写脉冲

## 运行方法

```bash
cd F:\FPGA2025-main_mux\sim\i2c_slave_handler_tb
vsim -do cmd.do
```

仿真输出会清晰显示每一步的寄存器实际值，让问题无处可藏！

## 调试建议

1. **重点查看**: TEST 1之后的寄存器值
2. **如果Reg[0]仍为0x00**: 说明CDC写入逻辑有问题
3. **如果Reg[0]变为0x55**: 说明TEST 1成功，继续检查TEST 3

通过这些实时监控，我们可以准确定位问题发生在哪一步！
