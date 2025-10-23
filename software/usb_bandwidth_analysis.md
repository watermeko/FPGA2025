# USB 带宽瓶颈分析报告

## 问题描述
上传速率最大只有 6KB/s，无论采样率设置多高（>5kHz）

## 根本原因分析

### 1. **EP3 MaxPacketSize 限制 (主要瓶颈)**
**位置**: `rtl/usb/usb_cdc.v:229`

```verilog
.i_ep3_tx_max  (12'd64)  // 硬编码为 64 字节
```

**问题**:
- Full-Speed USB 的最大包大小: 64 bytes
- High-Speed USB 的最大包大小: 512 bytes
- 当前代码**硬编码为 64 字节**，即使设备运行在 High-Speed 模式也无法利用更大的包

**影响**:
- Full-Speed 理论带宽: 1.2 MB/s (实际约 600-800 KB/s)
- 64 字节包 + USB 开销 ≈ 每包传输时间约 10-15 µs
- 理论最大吞吐: 64 bytes / 10 µs = 6.4 KB/ms = 6.4 MB/s (理想情况)
- **实际受限于 USB Full-Speed 控制器速度: ~6-8 KB/s**

### 2. **USB 描述符配置**
**位置**: `rtl/usb/usb_descriptor.v`

**Full-Speed 配置** (第 180-186 行):
```verilog
descrom[DESC_FSCFG_ADDR + 34] <= 8'h83;  // EP3 IN
descrom[DESC_FSCFG_ADDR + 35] <= 8'h02;  // Bulk Transfer
descrom[DESC_FSCFG_ADDR + 36] <= 8'h40;  // MaxPacketSize = 0x0040 = 64 bytes
descrom[DESC_FSCFG_ADDR + 37] <= 8'h00;
```

**High-Speed 配置** (第 238-244 行):
```verilog
descrom[DESC_HSCFG_ADDR + 34] <= 8'h83;  // EP3 IN
descrom[DESC_HSCFG_ADDR + 35] <= 8'h02;  // Bulk Transfer
descrom[DESC_HSCFG_ADDR + 36] <= 8'h00;  // MaxPacketSize = 0x0200 = 512 bytes
descrom[DESC_HSCFG_ADDR + 37] <= 8'h02;
```

**问题**:
- USB 描述符正确定义了 High-Speed 的 512 字节包
- 但 RTL 代码中的 `i_ep3_tx_max` 没有根据实际 USB 速度动态调整

### 3. **EP3 FIFO 配置**
**位置**: `rtl/usb/sync_fifo/usb_fifo.v:46`

```verilog
`define EP3_IN_BUF_ASIZE 4'd12  // 2^12 = 4096 字节 FIFO
```

**状态**: ✅ FIFO 大小充足 (4KB)，不是瓶颈

### 4. **USB 控制器速度**
**检测方法**: 查看设备枚举时的速度
- Full-Speed: 12 Mbps (1.2 MB/s 理论值)
- High-Speed: 480 Mbps (60 MB/s 理论值)

**当前状态**: 需要确认设备实际运行速度

## 理论带宽计算

### Full-Speed (当前可能状态)
- USB 速率: 12 Mbps
- 理论吞吐: 1.2 MB/s
- **实际吞吐**: ~600-800 KB/s (考虑协议开销)
- **观测吞吐**: 6 KB/s ❌ (远低于理论值)

### High-Speed (期望状态)
- USB 速率: 480 Mbps
- 理论吞吐: 60 MB/s
- **实际吞吐**: ~30-40 MB/s (考虑协议开销)
- MaxPacketSize = 512 bytes 时预期吞吐: 10-20 MB/s

## 6 KB/s 瓶颈分析

**可能原因**:

1. **包频率限制** (最可能)
   - 每秒发送包数: 6000 bytes/s ÷ 64 bytes/packet ≈ 94 packets/s
   - 包间隔: 1000 ms / 94 ≈ 10.6 ms/packet
   - **这意味着每个包之间有 10ms 的延迟！**

2. **FIFO 发送逻辑** (需检查)
   - 位置: `rtl/usb/sync_fifo/usb_fifo.v` 中的 EP3 发送状态机
   - 可能存在: 等待 FIFO 满 64 字节才发送？
   - 可能存在: 固定延迟的轮询机制？

3. **USB 轮询间隔**
   - Bulk endpoint 的 bInterval = 0 (第 186、244 行) ✅ 正确
   - NAK 限制: 如果 FIFO 空，设备会 NAK，主机会重试

4. **Python 读取速度** (不太可能)
   - 读取大小: 512 bytes/次
   - 超时: 100 ms
   - 应该不是瓶颈

## 解决方案

### 方案 1: 动态设置 MaxPacketSize (推荐)
修改 `rtl/usb/usb_cdc.v`，根据 USB 速度动态设置包大小

**步骤**:
1. 添加 USB 速度检测信号（从 USB 控制器获取）
2. 根据速度选择 MaxPacketSize:
   ```verilog
   wire usb_highspeed;  // 从 usb_device_controller 获取
   wire [11:0] ep3_max_packet_size = usb_highspeed ? 12'd512 : 12'd64;

   usb_fifo usb_fifo (
       // ...
       .i_ep3_tx_max(ep3_max_packet_size),  // 动态设置
       // ...
   );
   ```

**预期效果**:
- Full-Speed: 64 bytes/packet → 600-800 KB/s
- High-Speed: 512 bytes/packet → 10-20 MB/s

### 方案 2: 增大 EP3 MaxPacketSize (快速测试)
临时修改，强制使用更大的包

**修改**: `rtl/usb/usb_cdc.v:229`
```verilog
.i_ep3_tx_max(12'd512)  // 改为 512 字节
```

**风险**:
- 如果设备运行在 Full-Speed，会导致错误
- 仅用于测试，不建议生产使用

### 方案 3: 优化 FIFO 发送逻辑 (深度优化)
检查并优化 `usb_fifo.v` 中的 EP3 发送状态机

**可能优化点**:
1. 降低发送触发阈值（不等 FIFO 满再发）
2. 添加超时机制（如果 FIFO 有数据但未满，一定时间后也发送）
3. 连续发送模式（减少包间隔）

### 方案 4: 检查 USB 控制器配置
确认设备是否正确枚举为 High-Speed

**检查方法**:
```bash
# Windows: 使用 USBView 或 Device Manager
# 查看设备属性中的 "Speed" 字段

# 或在 Python 中读取:
print(f"USB 速度: {dev.speed}")
# 1 = Low Speed (1.5 Mbps)
# 2 = Full Speed (12 Mbps)
# 3 = High Speed (480 Mbps)
```

## 推荐实施步骤

1. **立即测试**: 运行下面的 USB 速度检测脚本
2. **确认速度**: 如果是 Full-Speed，6 KB/s 是不正常的，需要调试 FIFO 逻辑
3. **如果是 Full-Speed**:
   - 应该能达到 600+ KB/s，需要检查 EP3 发送状态机
   - 检查是否有固定延迟
4. **如果是 High-Speed**:
   - 修改 `i_ep3_tx_max` 为 512
   - 预期速度提升到 10+ MB/s
5. **长期方案**: 实施方案 1，动态设置 MaxPacketSize

## 测试脚本

见 `software/check_usb_speed.py`
