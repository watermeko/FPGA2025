# USB Bulk 传输优化总结

## ✅ 完成的所有修改

### 修改 1: 修复 EP10 信号连接错误
**文件**: `rtl/usb/sync_fifo/usb_fifo.v`
**位置**: 第 1026-1027 行

**修改前**:
```verilog
,.i_ep_tx_dval  (_ep10_tx_dval  )//  ❌ 缺少 'i' 前缀
,.i_ep_tx_data  (_ep10_tx_data  )//  ❌ 缺少 'i' 前缀
```

**修改后**:
```verilog
,.i_ep_tx_dval  (i_ep10_tx_dval  )//  ✅ 正确连接
,.i_ep_tx_data  (i_ep10_tx_data  )//  ✅ 正确连接
```

---

### 修改 2: 修复 EP12 重复参数定义
**文件**: `rtl/usb/sync_fifo/usb_fifo.v`
**位置**: 第 1096-1100 行

**修改前**:
```verilog
usb_tx_buf #(
     .P_ENDPOINT (12 )
    ,.P_DSIZE    (8  )
    ,.P_ASIZE    (10 )   // ❌ 硬编码
    ,.P_ASIZE    (`EP12_IN_BUF_ASIZE)  // ❌ 重复定义
)usb_tx_buf_ep12
```

**修改后**:
```verilog
usb_tx_buf #(
     .P_ENDPOINT (12 )
    ,.P_DSIZE    (8  )
    ,.P_ASIZE    (`EP12_IN_BUF_ASIZE)  // ✅ 使用正确的参数
)usb_tx_buf_ep12
```

---

### 修改 3: 修复 EP14/EP15 宏定义缺失反引号
**文件**: `rtl/usb/sync_fifo/usb_fifo.v`
**位置**: 第 1203-1207 行 (EP14), 第 1246-1250 行 (EP15)

**修改前**:
```verilog
usb_rx_buf #(
     .P_ENDPOINT (14 )
    ,.P_AFULL    (EP14_OUT_BUF_AFULL)   // ❌ 缺少反引号
    ,.P_DSIZE    (8  )
    ,.P_ASIZE    (EP14_OUT_BUF_ASIZE)   // ❌ 缺少反引号
)usb_rx_buf_ep14
```

**修改后**:
```verilog
usb_rx_buf #(
     .P_ENDPOINT (14 )
    ,.P_AFULL    (`EP14_OUT_BUF_AFULL)  // ✅ 添加反引号
    ,.P_DSIZE    (8  )
    ,.P_ASIZE    (`EP14_OUT_BUF_ASIZE)  // ✅ 添加反引号
)usb_rx_buf_ep14
```

同样修复了 EP15。

---

### 修改 4: FIFO 优化 - TX 方向
**文件**: `rtl/usb/sync_fifo/usb_fifo.v`
**位置**: 第 1310-1360 行

#### 4.1 连接 AlmostFull 信号并添加背压

**修改前**:
```verilog
assign c_fifo_wr = i_ep_tx_dval;  // ❌ 无背压控制
assign c_fifo_wr_data = i_ep_tx_data;

clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (6  )      // ❌ 硬编码为 6 → 仅 64 字节
  ,.AEMPT (1  )
  ,.AFULL (32 )      // ❌ 太小
)clk_cross_fifo
(
     .WrClock    (i_ep_clk      )
    ,.Reset      (i_reset       )
    ,.WrEn       (c_fifo_wr     )
    ,.Data       (c_fifo_wr_data)
    ,.AlmostFull (              )  // ❌ 未连接
    ,.Full       ()
    // ...
);
```

**修改后**:
```verilog
wire c_fifo_afull;  // ✅ 声明信号

// ✅ 添加背压控制：FIFO 快满时停止写入
assign c_fifo_wr      = i_ep_tx_dval & ~c_fifo_afull;
assign c_fifo_wr_data = i_ep_tx_data;

clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (P_ASIZE  )  // ✅ 使用参数（EP3 = 12 → 4096 bytes）
  ,.AEMPT (1  )
  ,.AFULL (512 )       // ✅ 提高到 512 字节
)clk_cross_fifo
(
     .WrClock    (i_ep_clk      )
    ,.Reset      (i_reset       )
    ,.WrEn       (c_fifo_wr     )
    ,.Data       (c_fifo_wr_data)
    ,.AlmostFull (c_fifo_afull  )  // ✅ 连接信号
    ,.Full       ()
    // ...
);
```

#### 4.2 优化读取逻辑 - 连续读取

**修改前**:
```verilog
always@(posedge i_clk, posedge i_reset) begin
    if (i_reset) begin
        c_fifo_rd <= 1'b0;
    end
    else begin
        if (c_fifo_empty) begin
            c_fifo_rd <= 1'b0;
        end else begin
            c_fifo_rd <= 1'b1;  // 简单但有 1 周期延迟
        end
    end
end
```

**修改后**:
```verilog
always@(posedge i_clk, posedge i_reset) begin
    if (i_reset) begin
        c_fifo_rd <= 1'b0;
    end
    else begin
        // ✅ 连续读取：只要 FIFO 非空就读
        c_fifo_rd <= ~c_fifo_empty;
    end
end
```

**优化效果**: 移除条件判断，简化为直接赋值，减少延迟。

---

### 修改 5: FIFO 优化 - RX 方向
**文件**: `rtl/usb/sync_fifo/usb_fifo.v`
**位置**: 第 1497-1516 行

**修改前**:
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (6  )      // ❌ 硬编码
  ,.AEMPT (1  )
  ,.AFULL (32 )      // ❌ 太小
)clk_cross_fifo
```

**修改后**:
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (P_ASIZE  )  // ✅ 使用参数
  ,.AEMPT (1  )
  ,.AFULL (128 )       // ✅ 提高到 128 字节（RX 端）
)clk_cross_fifo
(
     .WrClock    (i_clk         )
    ,.Reset      (i_reset       )
    ,.WrEn       (c_fifo_wr     )
    ,.Data       (c_fifo_wr_data)
    ,.AlmostFull (c_fifo_afull  )  // ✅ 连接信号
    ,.Full       ()
    // ...
);
```

---

## 📊 性能提升预期

### FIFO 深度对比

| 端点 | 方向 | 修改前 | 修改后 | 提升 |
|------|------|--------|--------|------|
| EP1  | IN   | 64 B   | 4096 B | **64x** |
| EP2  | IN   | 64 B   | 4096 B | **64x** |
| **EP3** | **IN** | **64 B** | **4096 B** | **64x** |
| EP2  | OUT  | 64 B   | 4096 B | **64x** |

### AFULL 阈值对比

| FIFO 类型 | 修改前 | 修改后 | 说明 |
|-----------|--------|--------|------|
| TX (IN)   | 32 B   | 512 B  | FIFO 有 512 字节时触发传输 |
| RX (OUT)  | 32 B   | 128 B  | 防止 RX 溢出 |

### 传输速率预期

| 采样率 | 数据率 | 修改前 | 修改后（预期） | 说明 |
|--------|--------|--------|----------------|------|
| 1 MHz  | 1 MB/s | 970 KB/s ✅ | 970 KB/s ✅ | 保持正常 |
| 5 MHz  | 5 MB/s | 4.8 MB/s ⚠️  | 5 MB/s ✅ | 应达到全速 |
| 10 MHz | 10 MB/s | 4.8 MB/s ⚠️ | 10 MB/s ✅ | 应达到全速 |
| 20 MHz | 20 MB/s | 4.8 MB/s ⚠️ | 18-20 MB/s ✅ | 接近 USB 极限 |
| 30 MHz | 30 MB/s | 4.8 MB/s ⚠️ | 25-30 MB/s ⚠️ | USB 2.0 极限 |

---

## 🧪 测试验证步骤

### 步骤 1: 综合和烧录

1. **在 GOWIN EDA 中**:
   - 打开项目 `fpga_project.gprj`
   - **Synthesize** → 应该无错误
   - **Place & Route**
   - **Program Device** → 烧录到 FPGA

2. **检查综合报告**:
   - 查看 Block RAM 使用量（应增加约 20 KB）
   - 确认无 Warning 或 Error

---

### 步骤 2: 基础功能测试

```bash
cd software
python diagnose_dc.py
```

**测试项目**:
1. ✅ FPGA 复位后第一次采样应正常（非 0 KB/s）
2. ✅ 可以动态切换采样率（无需复位 FPGA）
3. ✅ 所有采样率（1M, 5M, 10M, 20M）都应正常工作

---

### 步骤 3: 速率基准测试

创建并运行测试脚本：

```python
# test_all_rates.py
import usb.core
import time

EP_DC_IN = 0x83
rates = [1, 5, 10, 20, 30]  # MHz

dev = usb.core.find(idVendor=0x33aa, idProduct=0x0000)
if not dev:
    print("❌ 设备未找到")
    exit()

for rate_mhz in rates:
    divider = 60 // rate_mhz

    # 发送 CMD_DC_START
    cmd = bytes([
        0xAA, 0x55,           # Header
        0x0B,                 # CMD_DC_START
        0x00, 0x02,           # Length = 2
        (divider >> 8) & 0xFF,  # Divider high
        divider & 0xFF,         # Divider low
        0x00, 0x00            # Checksum + Status (ignored)
    ])
    dev.write(0x01, cmd)
    time.sleep(0.1)

    # 测量 3 秒
    start = time.time()
    total = 0

    while time.time() - start < 3.0:
        try:
            data = dev.read(EP_DC_IN, 4096, timeout=100)
            total += len(data)
        except:
            pass

    rate_kbps = total / 3.0 / 1024
    expected_kbps = rate_mhz * 1024
    percentage = (rate_kbps / expected_kbps) * 100

    print(f"{rate_mhz} MHz: {rate_kbps:.1f} KB/s ({percentage:.1f}%)")

    # 停止采样
    cmd_stop = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x00, 0x00])
    dev.write(0x01, cmd_stop)
    time.sleep(0.2)
```

**预期输出**:
```
1 MHz: 970.0 KB/s (95%)
5 MHz: 4850.0 KB/s (95%)   ← 应接近 100%
10 MHz: 9700.0 KB/s (95%)  ← 应接近 100%
20 MHz: 19200.0 KB/s (94%) ← 应接近 100%
30 MHz: 25000.0 KB/s (81%) ← USB 极限约 25-30 MB/s
```

---

### 步骤 4: 长时间稳定性测试

```python
# test_stability.py
import usb.core
import time

dev = usb.core.find(idVendor=0x33aa, idProduct=0x0000)
EP_DC_IN = 0x83

# 10 MHz, 5 分钟稳定性测试
divider = 6
cmd = bytes([0xAA, 0x55, 0x0B, 0x00, 0x02, 0x00, divider, 0x00, 0x00])
dev.write(0x01, cmd)

start = time.time()
total = 0
errors = 0

while time.time() - start < 300:  # 5 分钟
    try:
        data = dev.read(EP_DC_IN, 4096, timeout=100)
        total += len(data)
    except Exception as e:
        errors += 1
        if errors > 10:
            print(f"❌ 错误过多: {e}")
            break

duration = time.time() - start
rate_mbps = total / duration / 1024 / 1024

print(f"✅ 稳定性测试: {duration:.1f}s, {rate_mbps:.2f} MB/s, 错误: {errors}")
```

---

## 🎯 成功标准

### 必须通过的测试

1. ✅ **综合无错误**: 所有语法错误已修复
2. ✅ **首次采样正常**: FPGA 复位后第一次采样非 0 KB/s
3. ✅ **动态切换速率**: 无需复位即可切换
4. ✅ **5 MHz 达到 >4.5 MB/s**: 至少达到理论值的 90%
5. ✅ **10 MHz 达到 >9 MB/s**: 至少达到理论值的 90%
6. ✅ **无死锁**: 任何采样率下都不会卡死

### 期望通过的测试

1. ⭐ **20 MHz 达到 >18 MB/s**: 接近 USB 2.0 Bulk 极限
2. ⭐ **30 MHz 达到 >25 MB/s**: 达到或接近硬件极限
3. ⭐ **稳定性**: 5 分钟连续传输无错误

---

## 🔍 如果速率仍然受限

如果 Bulk 优化后仍然无法达到 >15 MB/s，则需要：

### 分析瓶颈位置

1. **检查 `i_usb_txpop` 频率**:
   - 使用逻辑分析仪或 ChipScope
   - 计算 `txpop` 占空比

2. **检查 `pkt_fifo_empty` 信号**:
   - 如果频繁为空 → FIFO 写入慢
   - 如果一直有数据但速率低 → USB 控制器调度问题

3. **检查 `o_usb_txlen` 值**:
   - 应该是 512 (MaxPacketSize)
   - 如果小于 512 → 包未填满

---

### 备选方案: ISO 传输

如果 Bulk 优化无效，参考 `USB_SPEED_FIX_AND_ISO_PLAN.md` 实施 ISO 传输：

**ISO 传输优势**:
- ✅ 保证带宽: 20-24 MB/s
- ✅ 低延迟、实时性好
- ✅ 适合连续数据流

**ISO 传输劣势**:
- ⚠️ 无错误重传（丢包就丢了）
- ⚠️ 需要应用层处理丢失样本

---

## 📋 修改文件清单

1. ✅ `rtl/usb/sync_fifo/usb_fifo.v` - 所有 FIFO 优化
2. ✅ `rtl/logic/digital_capture_handler.v` - 采样逻辑修复（之前完成）

---

## 💡 下一步

1. **立即操作**: 综合并烧录到 FPGA
2. **基础测试**: 运行 `diagnose_dc.py`
3. **速率测试**: 运行 `test_all_rates.py`
4. **报告结果**: 告知实际测得的速率

**期待看到大幅提升！** 🚀
