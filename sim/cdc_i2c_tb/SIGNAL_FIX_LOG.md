# I2C仿真脚本修复记录

## 修复日期
2025-10-18

## 修复问题

### 问题1: EEPROM模型信号名称错误
**错误信息**:
```
** Error: (vish-4014) No objects found matching '/cdc_tb/u_eeprom/MemAddr'.
```

**原因**:
脚本中使用了不存在的信号名 `MemAddr` 和 `RdCycle`

**修复**:
使用M24LC64模型中的实际信号：
- `StartAddress` - 起始地址（13位）
- `RdPointer` - 读取指针（13位）
- `WrCycle` - 写周期标志
- `RdCycle` - 读周期标志
- `WriteActive` - 写激活标志

### 问题2: I2C Handler信号名称错误
**错误信息**:
```
** Error: (vish-4014) No objects found matching '/cdc_tb/dut/u_i2c_handler/device_addr_7bit'.
```

**原因**:
I2C Handler重构后信号名称改变

**修复后的信号映射**:

| 旧信号名 | 新信号名 | 说明 |
|---------|---------|------|
| device_addr_7bit | device_addr_reg | 设备地址寄存器（8位） |
| num_wr_bytes | data_len_reg | 数据长度（16位） |
| num_rd_bytes | data_len_reg | 数据长度（16位） |
| buf_index | data_ptr_reg | 数据指针（16位） |
| tx_buffer | write_buffer | 写缓冲区（128字节） |
| rx_buffer | read_buffer | 读缓冲区（128字节） |
| - | reg_addr_reg | 寄存器地址（16位，新增） |
| - | i2c_busy | I2C忙标志（新增） |

### 问题3: I2C Control信号层次错误
**错误信息**:
```
** Error: (vish-4014) No objects found matching '/cdc_tb/dut/u_i2c_handler/u_i2c_control/...'.
```

**原因**:
I2C Control实例名称是 `i2c_control` 而不是 `u_i2c_control`

**修复后的信号映射**:

| 旧信号名 | 新信号名 | 说明 |
|---------|---------|------|
| i2c_start | wrreg_req / rdreg_req | 写/读请求 |
| i2c_busy | (状态机判断) | 通过state判断 |
| i2c_done | RW_Done | 读写完成 |
| i2c_tx_data | wrdata | 写数据 |
| i2c_rx_data | rddata | 读数据 |
| i2c_rw | (命令编码) | 通过Cmd判断 |
| i2c_ack_error | ack | ACK信号（反向逻辑） |

**新增信号**:
- `addr_reg` - 地址寄存器（16位）
- `device_id` - 设备ID（8位）

---

## 修复后的波形组

### I2C Bus (EEPROM)
```tcl
/cdc_tb/u_eeprom/StartAddress   # 起始地址
/cdc_tb/u_eeprom/RdPointer      # 读指针
/cdc_tb/u_eeprom/WrCycle        # 写周期标志
/cdc_tb/u_eeprom/RdCycle        # 读周期标志
/cdc_tb/u_eeprom/WriteActive    # 写激活标志
```

### I2C Handler
```tcl
/cdc_tb/dut/u_i2c_handler/state           # 状态机
/cdc_tb/dut/u_i2c_handler/device_addr_reg # 设备地址
/cdc_tb/dut/u_i2c_handler/reg_addr_reg    # 寄存器地址
/cdc_tb/dut/u_i2c_handler/data_len_reg    # 数据长度
/cdc_tb/dut/u_i2c_handler/data_ptr_reg    # 数据指针
/cdc_tb/dut/u_i2c_handler/write_buffer    # 写缓冲区
/cdc_tb/dut/u_i2c_handler/read_buffer     # 读缓冲区
/cdc_tb/dut/u_i2c_handler/i2c_busy        # 忙标志
```

### I2C Control
```tcl
/cdc_tb/dut/u_i2c_handler/i2c_control/state      # 状态机
/cdc_tb/dut/u_i2c_handler/i2c_control/wrreg_req  # 写请求
/cdc_tb/dut/u_i2c_handler/i2c_control/rdreg_req  # 读请求
/cdc_tb/dut/u_i2c_handler/i2c_control/RW_Done    # 完成标志
/cdc_tb/dut/u_i2c_handler/i2c_control/wrdata     # 写数据
/cdc_tb/dut/u_i2c_handler/i2c_control/rddata     # 读数据
/cdc_tb/dut/u_i2c_handler/i2c_control/ack        # ACK信号
/cdc_tb/dut/u_i2c_handler/i2c_control/addr_reg   # 地址寄存器
/cdc_tb/dut/u_i2c_handler/i2c_control/device_id  # 设备ID
```

---

## 验证状态

✅ EEPROM模型信号 - 已修复
✅ I2C Handler信号 - 已修复
✅ I2C Control信号 - 已修复
✅ 波形脚本语法 - 已验证

---

## 运行测试

```bash
cd F:\FPGA2025\sim\cdc_i2c_tb
vsim -do cmd.do
```

应该不再有波形添加错误。

---

## 注意事项

1. **信号层次**: I2C Control实例名是 `i2c_control` 不是 `u_i2c_control`
2. **EEPROM信号**: 使用 `StartAddress` 和 `RdPointer` 而不是 `MemAddr`
3. **I2C Handler**: 新的设计使用统一的 `data_len_reg` 和 `data_ptr_reg`
4. **状态值**: I2C Handler状态值是3位，I2C Control状态值是8位
