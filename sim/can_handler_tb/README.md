# CAN Handler 仿真测试

## 📁 文件说明

- `cmd.do` - ModelSim仿真脚本
- `run_sim.bat` - Windows启动脚本
- `../../tb/can_handler_tb.v` - 测试台源文件

## 🎯 测试内容

### 测试架构

```
can_handler (DUT)                    can_top (对端设备)
    ├─ 命令接口 ← [测试激励]         ├─ ID=0x002
    ├─ can_tx ──────────┐             ├─ 接收ID=0x001
    └─ can_rx ←─────────┼─ CAN总线 ──┤
                        │             │
                        └─────────────┴─ can_rx/tx
```

### 测试场景

1. **配置测试**：配置CAN handler的ID和过滤器
   - Local ID = 0x001
   - RX Filter = 0x002
   - 波特率 = 1MHz @ 60MHz时钟

2. **发送测试**：Handler发送数据给Peer
   - Handler发送：`0xDEADBEEF`
   - Peer接收验证

3. **接收测试**：Peer发送数据给Handler
   - Peer发送：`0xCAFEBABE`
   - Handler接收并上传（源标识0x05）

4. **读取测试**：通过命令0x13读取接收到的数据

5. **双向通信**：同时进行收发测试
   - Handler发送：`0x12345678`
   - Peer发送：`0x87654321`

## 🚀 运行方法

### 方法1：使用批处理脚本（推荐）
```bash
run_sim.bat
```

### 方法2：直接使用ModelSim
```bash
cd F:\FPGA2025\sim\can_handler_tb
vsim -do cmd.do
```

### 方法3：命令行模式
```bash
cd F:\FPGA2025\sim\can_handler_tb
vlib work
vlog -work work ../../rtl/can/*.v
vlog -work work ../../tb/can_handler_tb.v
vsim -c -do "run -all" work.can_handler_tb
```

## 📊 预期结果

### 控制台输出示例

```
[333ns] Reset released
[2000ns] === Sending CAN CONFIG Command ===
[2500ns] CAN CONFIG sent
[18000ns] === Sending CAN TX Command ===
[18500ns] CAN TX command sent
[28000ns] PEER RX: id=0x001, data=0xDE, last=0
[28100ns] PEER RX: id=0x001, data=0xAD, last=0
...
[45000ns] === Peer Sending CAN Frame ===
[55000ns] UPLOAD: source=0x05, data=0xCA
[55100ns] UPLOAD: source=0x05, data=0xFE
...
```

### 波形验证要点

1. ✅ CAN总线波形符合CAN协议标准
2. ✅ Handler状态机正确转换（IDLE → RX_CMD → TX/RX）
3. ✅ 接收数据进入RX FIFO
4. ✅ Upload信号正确输出（source=0x05）
5. ✅ Peer设备正确接收到Handler发送的帧

## ⚠️ 注意事项

1. **ModelSim版本**：需要10.5或更高版本
2. **路径问题**：确保相对路径正确指向rtl和tb目录
3. **CAN总线仲裁**：使用wired-AND模拟真实CAN总线
4. **超时设置**：仿真超时时间为500k时钟周期（约8.3ms）

## 🔧 调试提示

如果仿真失败，检查：

1. **编译错误**：
   - 检查所有CAN模块文件是否存在
   - 确认Verilog语法正确

2. **功能错误**：
   - 查看`handler_state`状态机是否正常转换
   - 检查`rx_count`是否正确累加
   - 验证CAN总线上是否有正确的波形

3. **时序问题**：
   - CAN位时序是否正确（PTS=34, PBS1=5, PBS2=10）
   - 总线仲裁是否工作正常

## 📈 性能指标

- **CAN波特率**：1 Mbps（理论值，实际约1.2 Mbps）
- **系统时钟**：60 MHz
- **仿真时间**：约100 us实际时间
- **预计仿真耗时**：约10-30秒（取决于电脑性能）

## 📝 修改建议

如果需要测试其他场景：

1. **修改波特率**：调整`c_PTS/c_PBS1/c_PBS2`参数
2. **测试长ID**：修改为29位扩展ID
3. **压力测试**：增加连续发送/接收的数据量
4. **错误注入**：人为制造CRC错误或总线冲突

---

创建时间：2025-10-29
作者：Claude Code
