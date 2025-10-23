# USB 速度问题真正原因分析

## 实验结果总结

### ✅ 确认的事实

1. **960 MHz 时钟是正确的**
   - 修改为 480 MHz 后，设备描述符请求失败
   - GOWIN USB PHY 内部会进行分频处理
   - 960 MHz → 内部 ÷2 → 实际 480 MHz 用于 High-Speed

2. **当前配置是正确的**
   - PLL Clkout0: 960 MHz ✅
   - PLL Clkout1: 60 MHz ✅
   - USB 描述符 HSSUPPORT: 1 ✅
   - USB Controller Speed_Mode: High Speed ✅

3. **EP3 MaxPacketSize 已优化**
   - 从 64 bytes 改为 512 bytes ✅
   - 速率从 6 KB/s 提升到 47.5 KB/s ✅

## 真正的瓶颈

### 为什么仍然是 Full-Speed (47.5 KB/s)？

当前速率分析：
- **47.5 KB/s** ≈ 380 kbps
- Full-Speed 理论最大: 12 Mbps (1.5 MB/s)
- **实际只达到理论值的 3%**

### 根本原因：USB 枚举为 Full-Speed

查看 `rtl/usb/usb_device_controller/usb_device_controller.ipc:44`：
```
Speed_Mode=High Speed
```

配置是正确的，但为什么设备没有枚举为 High-Speed？

## 可能的原因

### 1. **硬件连接问题** (最可能)

High-Speed USB 需要额外的硬件支持：

**检查项**:
- ✅ USB D+ 和 D- 数据线
- ❓ **High-Speed Chirp 检测电路**
- ❓ **终端电阻 (usb_term_dp_io, usb_term_dn_io)**
- ❓ **Pull-up 电阻配置**

**High-Speed 握手过程**:
1. 设备上电，D+ 拉高 (Full-Speed 模式)
2. 主机检测到设备，发送 Reset 信号
3. **Chirp K/J 握手** (High-Speed 特有)
   - 如果成功 → High-Speed (480 Mbps)
   - 如果失败 → 降级到 Full-Speed (12 Mbps)

### 2. **USB PHY 配置问题**

查看 `rtl/usb/usb2_0_softphy/usb2_0_softphy.ipc:10`：
```
DisableIO=true
```

**DisableIO=true** 意味着 USB PHY 的 IO 由外部控制。

**需要检查**:
- `usb_term_dp_io` 和 `usb_term_dn_io` 的连接
- 这些信号在 High-Speed 模式下用于 chirp 检测
- 如果没有正确配置，设备只能运行在 Full-Speed

### 3. **时序约束问题**

High-Speed USB 对时序要求极高：
- 960 MHz 时钟的建立/保持时间
- USB PHY 输出到 pads 的延迟

**检查**: `constraints/*.sdc` 或 `.cst` 文件中的时序约束

## 解决方案

### 方案 1: 检查硬件连接 (推荐首先尝试)

**检查 USB 引脚连接**:

打开 `constraints/pin_cons.cst`，查找：
```
usb_dxp_io
usb_dxn_io
usb_term_dp_io  ← 重要！
usb_term_dn_io  ← 重要！
usb_pullup_en_o
```

**High-Speed 需要的引脚**:
- `usb_dxp_io` / `usb_dxn_io`: 主数据线
- `usb_term_dp_io` / `usb_term_dn_io`: **High-Speed 终端电阻控制**
- `usb_pullup_en_o`: Pull-up 使能

如果 `term` 引脚没有连接或配置错误，设备无法进行 High-Speed chirp 握手。

### 方案 2: 检查 USB PHY IP 配置

重新生成 USB PHY IP 核，确认：
1. 打开 GOWIN IDE
2. 找到 `rtl/usb/usb2_0_softphy/usb2_0_softphy.ipc`
3. 双击打开配置向导
4. 确认 **DisableIO 选项** 的含义
5. 检查是否有 "High-Speed Enable" 选项

### 方案 3: 检查 USB 线缆和端口

**物理检查**:
- 使用 **USB 2.0 高质量线缆**（不要用便宜的充电线）
- 连接到 **USB 2.0 或 3.0 端口**（不是 USB Hub）
- 尝试不同的 USB 端口

### 方案 4: 添加调试信号

修改 `rtl/usb/usb_cdc.v`，输出 High-Speed 检测信号：

```verilog
// 在 usb_cdc 模块中
output usb_highspeed_o  // 新增输出

// 连接内部信号
assign usb_highspeed_o = usb_highspeed;  // 来自 USB Controller (第 259 行)
```

然后在 `rtl/top.v` 中连接到 LED：
```verilog
output usb_hs_led,  // 新增引脚

// 实例化 USB_CDC
USB_CDC u_usb_cdc(
    // ...
    .usb_highspeed_o(usb_hs_led)  // 连接到 LED
);
```

**观察 LED**:
- LED 亮 → High-Speed 枚举成功
- LED 灭 → 仍然是 Full-Speed

## 47.5 KB/s 性能分析

### 当前状态

| 项目 | 值 |
|------|-----|
| USB 模式 | Full-Speed (12 Mbps) |
| EP3 MaxPacketSize | 512 bytes (RTL 中设置) |
| **实际 MaxPacketSize** | **64 bytes** (受限于 Full-Speed) |
| 包频率 | 47500 ÷ 64 ≈ 742 包/秒 |
| 包间隔 | 1.35 ms |
| 理论最大 | 1.5 MB/s (Full-Speed 极限) |
| **实际吞吐** | **47.5 KB/s (3% 利用率)** |

### 为什么只有 47.5 KB/s？

即使在 Full-Speed 模式下，47.5 KB/s 也太低了。

**可能的限制**:
1. **FIFO 发送逻辑**:
   - 每 1.35 ms 才发送一个包
   - 可能是轮询间隔设置
   - 或者 FIFO 阈值过高

2. **采样率不够高**:
   - 数据源本身速度限制

3. **USB 驱动问题**:
   - Windows USB CDC 驱动有缓冲策略
   - 可能批量传输导致延迟

## 下一步操作

### 立即检查

1. **查看引脚约束文件**:
```bash
cat constraints/pin_cons.cst | grep -i usb
```

2. **检查 usb_term 引脚是否连接**

3. **运行 USB 速度检测**:
```bash
python software/check_usb_speed.py
```
查看是否显示 "High Speed"

### 如果确认是 Full-Speed

那么需要修复 High-Speed 握手问题：
- 检查硬件连接
- 重新配置 USB PHY IP 核
- 添加调试信号确认 chirp 过程

### 如果已经是 High-Speed

那么 47.5 KB/s 的限制来自 FIFO 逻辑，需要：
- 优化 `rtl/usb/sync_fifo/usb_fifo.v` 中的 EP3 发送状态机
- 降低发送触发阈值
- 添加超时机制

## 总结

1. ✅ **960 MHz 时钟是正确的**，不要改为 480 MHz
2. ✅ **EP3 MaxPacketSize = 512** 已优化
3. ❌ **设备可能仍运行在 Full-Speed**，需要检查硬件配置
4. ❌ **即使是 Full-Speed，47.5 KB/s 也偏低**，需要优化 FIFO 逻辑

**首要任务**: 确认设备是否成功枚举为 High-Speed！
