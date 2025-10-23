# 启用 USB High-Speed 模式修改指南

## 问题分析

你的设备目前运行在 **Full-Speed (12 Mbps)** 模式，最大速率只有 47.5 KB/s。
原因：PLL 时钟配置错误，输出 960 MHz 而不是 480 MHz。

## 已完成的修改

### 1. ✅ EP3 MaxPacketSize
**文件**: `rtl/usb/usb_cdc.v:229`
```verilog
.i_ep3_tx_max(12'd512)  // 已改为 512 字节
```

### 2. ✅ USB 描述符 HSSUPPORT
**文件**: `rtl/usb/usb_cdc.v:330`
```verilog
.HSSUPPORT(1)  // 已启用 High-Speed 支持
```

### 3. ✅ PLL 配置文件
**文件**: `rtl/clk/gowin_pll/gowin_pll.ipc`
- 已将 Clkout0 从 960 MHz 改为 **480 MHz**
- VCO 分频系数从 1 改为 **2**

## 需要手动操作的步骤

### 步骤 1: 重新生成 PLL IP 核 ⚠️ 重要！

由于我只能修改 `.ipc` 配置文件，但 GOWIN EDA 需要重新生成 Verilog 代码。

**操作方法**:

1. 打开 GOWIN EDA IDE
2. 打开项目 `fpga_project.gprj`
3. 在 IP Core 列表中找到 `Gowin_PLL` (位于 `rtl/clk/gowin_pll/`)
4. 双击打开 PLL 配置向导
5. 检查配置：
   - **输入时钟**: 24 MHz
   - **Clkout0 (fclk_480M)**: **480 MHz** ← 确认这个值！
   - **Clkout1 (PHY_CLK)**: 60 MHz
6. 点击 "OK" 保存
7. 右键选择 "Generate" 重新生成 IP 核

**或者使用命令行（如果可用）**:
```bash
cd rtl/clk/gowin_pll
gw_sh gowin_pll.ipc
```

### 步骤 2: 综合和烧录

1. 在 GOWIN EDA 中点击 "Synthesize"
2. 点击 "Place & Route"
3. 点击 "Generate Bitstream"
4. 烧录到 FPGA

### 步骤 3: 验证 High-Speed 枚举

烧录后，运行验证脚本：

```bash
python software/check_usb_speed.py
```

**期望输出**:
```
USB Speed:     High Speed (480 Mbps)
EP 0x83 (IN ): Bulk         MaxPacket= 512 bytes ⭐ EP3 - Digital Capture
       ✅ MaxPacketSize = 512 (High-Speed)
       → 理论最大吞吐: ~30 MB/s
```

### 步骤 4: 测试实际速率

```bash
python software/diagnose_dc.py
```

**期望速率**:
- **Full-Speed 时**: ~47.5 KB/s (当前状态)
- **High-Speed 时**: **5-20 MB/s** (预期提升 100-400 倍！)

## 如果 PLL 重新生成有问题

### 方案 A: 手动修改 PLL 参数

1. 打开 GOWIN EDA PLL 配置向导
2. 设置参数：
   - **CLKIN**: 24 MHz (输入时钟)
   - **VCO 频率**: 960 MHz (内部)
   - **Clkout0**: 480 MHz (VCO ÷ 2)
   - **Clkout1**: 60 MHz (VCO ÷ 16)

### 方案 B: 检查现有的 PLL 输出

如果 PLL 已经生成，检查 `rtl/clk/gowin_pll/gowin_pll.v` 文件：

```verilog
// 应该看到类似这样的参数:
.CLKOUT0_DIV(2)  // 960 MHz / 2 = 480 MHz
.CLKOUT1_DIV(16) // 960 MHz / 16 = 60 MHz
```

## 问题排查

### 如果重新综合后仍然是 Full-Speed:

1. **检查 USB 线缆**: 使用支持 High-Speed 的 USB 2.0 线缆
2. **检查 USB 端口**: 使用 USB 2.0 或 3.0 端口（不是 USB 1.1）
3. **检查时钟**: 使用示波器测量 fclk_480M 引脚，应该是 480 MHz
4. **检查 USB 描述符**: 运行 `python software/test_usb_backend.py` 查看详细信息

### 如果设备无法枚举:

1. **可能是时钟过快**: 检查 PLL 是否正确生成 480 MHz（不是 960 MHz）
2. **恢复到 Full-Speed**: 临时将 `.ipc` 文件中的频率改回 960 MHz，重新生成
3. **检查错误日志**: 在 Windows 设备管理器中查看 USB 设备错误

## 预期性能提升

### 当前 (Full-Speed):
- USB 速度: 12 Mbps
- EP3 MaxPacketSize: 512 bytes (但受限于 FS 协议)
- 实际吞吐: **47.5 KB/s**

### 修改后 (High-Speed):
- USB 速度: **480 Mbps**
- EP3 MaxPacketSize: **512 bytes**
- 理论吞吐: **30-40 MB/s**
- 预期实际吞吐: **5-20 MB/s** (取决于 FIFO 和采样率)

**性能提升**: **100-400 倍** 🚀

## 修改总结

| 项目 | 原值 | 修改后 | 状态 |
|------|------|--------|------|
| PLL Clkout0 | 960 MHz | **480 MHz** | ⚠️ 需重新生成 |
| EP3 MaxPacketSize | 64 bytes | **512 bytes** | ✅ 已修改 |
| HSSUPPORT | 1 | **1** | ✅ 已启用 |
| USB 描述符 HS | 512 bytes | **512 bytes** | ✅ 已配置 |

## 下一步

1. ✅ 打开 GOWIN EDA
2. ✅ 重新生成 `Gowin_PLL` IP 核（确认 480 MHz）
3. ✅ 综合 + 烧录
4. ✅ 运行 `check_usb_speed.py` 验证
5. ✅ 运行 `diagnose_dc.py` 测试速率

完成后，你的 USB 速率应该从 **47.5 KB/s** 提升到 **5-20 MB/s**！
