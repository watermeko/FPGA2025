# I2C仿真快速参考

## 运行命令
```bash
cd F:\FPGA2025\sim\cdc_i2c_tb
vsim -do cmd.do
```

## I2C命令速查

| 命令 | 码 | Payload | 说明 |
|------|----|---------|----|
| Config | 0x04 | [7bit_Addr] | 配置I2C设备地址 |
| Write | 0x05 | [Addr_H][Addr_L][Data...] | 写入数据 |
| Read | 0x06 | [Addr_H][Addr_L][Len_H][Len_L] | 读取数据 |

## 关键波形组
- **I2C Bus**: SCL/SDA物理信号
- **I2C Handler**: 状态机、缓冲区
- **Upload Pipeline**: 数据上传路径

## 测试流程
1. Config: 设置EEPROM地址(0x50)
2. Write: 写入4字节到0x003C
3. Wait: 等待5ms写周期
4. Read: 读取4字节
5. Verify: 验证上传数据

## 调试技巧
- `i2c_ack_error=1` → 检查设备地址
- 读取超时 → 检查EEPROM写周期等待
- 数据错误 → 查看`rx_buffer`和`upload_data`

## 常见修改
```systemverilog
// 改变Gowin路径 (cmd.do:25)
set GOWIN_PATH "您的路径/IDE"

// 改变测试参数 (cdc_i2c_tb.sv)
localparam WRITE_ADDR = 16'h003C;
localparam NUM_BYTES_TO_TEST = 4;
```
