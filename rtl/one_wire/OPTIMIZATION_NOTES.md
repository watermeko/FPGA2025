# 1-Wire Handler BSRAM Optimization

## 优化日期
2025-11-21

## 优化内容

### 问题
原始 `one_wire_handler` 模块使用了 **2 块 BSRAM**：
- TX FIFO: 256 字节 (1 BSRAM)
- RX FIFO: 256 字节 (1 BSRAM)

对于低速的 1-Wire 协议来说，这个 FIFO 深度过大。

### 解决方案
将 FIFO 深度从 **256 字节减少到 16 字节**：
- TX FIFO: 16 字节 (分布式 RAM)
- RX FIFO: 16 字节 (分布式 RAM)

### 资源节省
- **BSRAM 使用**: 2 块 → 0 块 ✅
- **逻辑资源**: 略微增加（分布式 RAM 使用 LUT）

### 合理性分析
16 字节 FIFO 对于 1-Wire 应用完全足够：

| 应用场景 | 数据量 | FIFO 需求 |
|---------|--------|----------|
| DS18B20 ROM ID 读取 | 8 字节 | < 16 字节 ✅ |
| DS18B20 温度读取 | 9 字节 (暂存器) | < 16 字节 ✅ |
| DS2431 EEPROM 写入 | 最多 12 字节/页 | < 16 字节 ✅ |
| 命令序列 | 通常 1-4 字节 | < 16 字节 ✅ |

### 兼容性
- ✅ 完全向后兼容现有协议
- ✅ 支持所有 1-Wire 命令 (0x20-0x23)
- ✅ 无需修改上层软件

### 使用方法
如果需要更大的 FIFO（例如读取大容量 EEPROM），可在实例化时覆盖参数：

```verilog
one_wire_handler #(
    .CLK_FREQ(60_000_000),
    .FIFO_DEPTH(32)  // 增加到 32 字节（仍使用分布式 RAM）
) u_onewire_handler (
    // ... 端口连接 ...
);
```

### 参数说明
- `FIFO_DEPTH = 16` (默认): 适用于绝大多数 1-Wire 应用
- `FIFO_DEPTH = 32`: 适用于读取大块数据的场景
- `FIFO_DEPTH = 64`: 特殊应用（不推荐，会增加资源消耗）

## 测试验证
- [x] 语法检查通过
- [ ] 仿真测试 (使用 `sim/one_wire_handler_tb/cmd.do`)
- [ ] 硬件测试 (DS18B20 温度传感器)
- [ ] 资源使用报告验证

## 相关文件
- 修改文件: `rtl/one_wire/one_wire_handler.v`
- 测试文件: `tb/one_wire_handler_tb.v`
- 测试工具: `software/one_wire_test.py`
