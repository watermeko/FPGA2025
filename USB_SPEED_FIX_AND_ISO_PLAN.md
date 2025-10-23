# USB 速率瓶颈深度分析与 ISO 传输方案

## 🔍 问题确认

你说得对！**USB 2.0 High-Speed Bulk 传输的实际极限应该是 30-40 MB/s**，而不是 4.8 MB/s。

当前系统只达到 4.8 MB/s 明显有设计问题。

---

## 📊 USB 2.0 真实性能数据

### 理论与实际对比

| 传输类型 | 理论带宽 | 实际可达 | 典型应用 |
|---------|---------|---------|---------|
| **Bulk** | 60 MB/s | **30-40 MB/s** | 存储设备、打印机 |
| **Isochronous** | 24 MB/s | **20-24 MB/s** | 音视频流 |
| **Interrupt** | 8 MB/s | 6-8 MB/s | HID 设备 |

### 为什么 Bulk 能达到 30-40 MB/s？

1. **高效打包**: 512 字节/包 × 每微帧多包
2. **连续传输**: 减少协议间隙
3. **硬件优化**: DMA、零拷贝

---

## 🐛 当前系统瓶颈分析

### 瓶颈 1: FIFO 读取逻辑效率低

**文件**: `rtl/usb/sync_fifo/usb_fifo.v`

```verilog
// 第 1341-1361 行
always@(posedge i_clk, posedge i_reset) begin
    if (c_fifo_empty) begin
        c_fifo_rd <= 1'b0;
    end
    else begin
        c_fifo_rd <= 1'b1;  // 持续读取
    end
end

always@(posedge i_clk, posedge i_reset) begin
    c_fifo_rd_dval <= c_fifo_rd & (!c_fifo_empty);  // 延迟1拍
end

assign pkt_fifo_wr = c_fifo_rd_dval;  // 写入包FIFO
```

**问题**: 虽然时钟是 60 MHz，但：
- 读取有 1 个时钟周期延迟
- **有效数据率 < 60 MB/s**

### 瓶颈 2: USB 控制器传输调度

**i_usb_txpop 频率不够高！**

60 MHz 时钟下，如果 `i_usb_txpop` 不是每个时钟都有效，实际传输速率会大幅下降。

**计算**:
```
如果 txpop 每 12 个时钟才有效一次：
60 MHz ÷ 12 = 5 MHz → 5 MB/s ✅ 接近观测值 4.8 MB/s
```

### 瓶颈 3: 包 FIFO 的传输机制

**文件**: `rtl/usb/sync_fifo/sync_tx_pkt_fifo.v`

```verilog
// 第 75-86 行
else if ( txact_fall ) begin  // 包传输结束时
    if ( read & (~empty)  ) begin
        rp <= pkt_rp + 1'b1;  // 只移动1字节！
    end
end
```

这是**包级别的提交机制**，可能限制了连续传输效率。

---

## 🎯 Bulk 传输优化方案（优先尝试）

在切换到 ISO 之前，先尝试优化 Bulk 传输：

### 优化 1: 增大突发传输长度

修改 `usb_fifo.v` 中的 txlen 上报逻辑，让每次传输更多数据：

```verilog
// 当前: 每次最多 512 字节
assign o_usb_txlen = pkt_fifo_wr_num_d0;

// 优化: 累积更多数据再传输
reg [11:0] burst_threshold;
assign o_usb_txlen = (pkt_fifo_wr_num_d0 >= burst_threshold) ?
                      pkt_fifo_wr_num_d0 : 12'd0;
```

### 优化 2: 启用 USB 设备控制器的高速模式

检查 USB Device Controller 是否正确配置为 High-Speed 模式。

---

## 🚀 Isochronous (ISO) 传输方案

如果 Bulk 优化后仍无法突破 10 MB/s，则采用 ISO 传输。

### ISO 传输特点

| 特性 | Bulk | ISO |
|------|------|-----|
| **带宽保证** | ❌ 无保证 | ✅ 保证带宽 |
| **错误检测** | ✅ 有 CRC | ❌ 无（或简化） |
| **延迟** | 较高 | ⚡ 超低 |
| **实际速率** | 4-40 MB/s | **20-24 MB/s 稳定** |
| **适用场景** | 数据完整性优先 | 实时性优先 |

### ISO 传输配置

**USB 2.0 High-Speed ISO 规格**:
- 每微帧 (125μs): 最多 **3 × 1024 bytes = 3072 bytes**
- 理论最大: 3072 × 8000 = **24.576 MB/s**

---

## 📝 ISO 传输实施方案

### 步骤 1: 修改 USB 描述符

**文件**: `rtl/usb/usb_descriptor.v`

**修改 EP3 配置** (High-Speed, 约第 238-244 行):

```verilog
// 当前 Bulk 配置
descrom[DESC_HSCFG_ADDR + 34] <= 8'h83;  // bEndpointAddress = INPUT 3
descrom[DESC_HSCFG_ADDR + 35] <= 8'h02;  // bmAttributes = Bulk (0x02)
descrom[DESC_HSCFG_ADDR + 36] <= 8'h00;
descrom[DESC_HSCFG_ADDR + 37] <= 8'h02;  // wMaxPacketSize = 512 bytes
descrom[DESC_HSCFG_ADDR + 38] <= 8'h00;  // bInterval = 0 (ignored for Bulk)

// 修改为 ISO 配置
descrom[DESC_HSCFG_ADDR + 34] <= 8'h83;  // bEndpointAddress = INPUT 3
descrom[DESC_HSCFG_ADDR + 35] <= 8'h05;  // bmAttributes = Isochronous (0x05)
                                          // Bit 2-3: Sync Type = 01 (Asynchronous)
                                          // Bit 4-5: Usage Type = 00 (Data endpoint)
descrom[DESC_HSCFG_ADDR + 36] <= 8'h00;  // wMaxPacketSize Low = 0x0400 (1024 bytes)
descrom[DESC_HSCFG_ADDR + 37] <= 8'h04;  // wMaxPacketSize High = 0x04
                                          // Bit 11-12: Additional transactions per microframe = 10 (3 total)
                                          // 实际 = (10b + 1) × 1024 = 3 × 1024 = 3072 bytes/microframe
descrom[DESC_HSCFG_ADDR + 38] <= 8'h01;  // bInterval = 1 (每微帧传输)
```

**Full-Speed 也需要修改** (约第 180-186 行):

```verilog
// Full-Speed ISO (备用，速度较低)
descrom[DESC_FSCFG_ADDR + 34] <= 8'h83;  // bEndpointAddress = INPUT 3
descrom[DESC_FSCFG_ADDR + 35] <= 8'h05;  // bmAttributes = Isochronous
descrom[DESC_FSCFG_ADDR + 36] <= 8'hFF;  // wMaxPacketSize = 0x03FF (1023 bytes)
descrom[DESC_FSCFG_ADDR + 37] <= 8'h03;
descrom[DESC_FSCFG_ADDR + 38] <= 8'h01;  // bInterval = 1 (每帧)
```

### 步骤 2: 修改 FIFO 配置

**文件**: `rtl/usb/sync_fifo/usb_fifo.v`

ISO 传输需要**更大的缓冲**和**定时传输**：

```verilog
// 第 46 行: 增大 EP3 FIFO
`define EP3_IN_BUF_ASIZE 4'd13  // 8192 bytes (支持 2-3 个微帧缓冲)
```

### 步骤 3: 修改 usb_cdc.v 的 EP3 配置

**文件**: `rtl/usb/usb_cdc.v`

```verilog
// 第 228-231 行
,.i_ep3_tx_clk  (PHY_CLKOUT       )
,.i_ep3_tx_max  (12'd1024)  // 修改为 1024 (ISO 单包大小)
,.i_ep3_tx_dval (usb_dc_upload_valid_in)
,.i_ep3_tx_data (usb_dc_upload_data_in)
```

### 步骤 4: 修改 Python 读取代码

**文件**: `software/diagnose_dc.py`

ISO 端点需要不同的读取方式：

```python
# ISO 传输特点
read_size = 3072  # 每次读取一个微帧的数据
timeout_ms = 10   # ISO 传输超时要短（定时传输）

while True:
    try:
        data = dev.read(EP_DC_IN, read_size, timeout=timeout_ms)
        if data:
            total += len(data)
            # ISO 可能返回部分数据，不算错误
    except usb.core.USBError as e:
        if e.errno == 110:  # Timeout
            # ISO 传输中 timeout 很常见，继续即可
            continue
        elif e.errno == 84:  # Overflow (数据丢失)
            print("⚠️ ISO 数据溢出，部分样本丢失")
            continue
        else:
            print(f"❌ USB 错误: {e}")
            break
```

---

## ⚙️ ISO vs Bulk 对比

### Bulk (当前)

**优点**:
- ✅ 数据完整性保证（CRC 校验）
- ✅ 自动重传机制
- ✅ 兼容性好

**缺点**:
- ❌ 无带宽保证
- ❌ 当前实现只有 4.8 MB/s
- ❌ 延迟不确定

### ISO (推荐用于高速采样)

**优点**:
- ✅ **保证带宽: 20-24 MB/s**
- ✅ 低延迟、实时性好
- ✅ 适合连续数据流

**缺点**:
- ⚠️ 无错误重传（丢包就丢了）
- ⚠️ 需要应用层处理丢失样本
- ⚠️ 主机负载稍高

---

## 🧪 测试验证步骤

### 测试 1: 验证描述符修改

```bash
# Windows: 使用 USBTreeView 查看设备描述符
# Linux: lsusb -v -d 33aa:0000

# 应该看到:
# EP3 IN: Isochronous, MaxPacketSize=1024, Interval=1
```

### 测试 2: 基准速率测试

```bash
python test_usb_bandwidth.py

# 预期结果 (ISO):
# 5 MHz:  5 MB/s (100%)
# 10 MHz: 10 MB/s (100%)
# 20 MHz: 20 MB/s (100%)
# 25 MHz: 24 MB/s (96%) ← ISO 极限
```

### 测试 3: 丢包率测试

在高负载下检测丢包：

```python
# 在采样数据中添加序号
# FPGA 端: 每个样本包含递增序号
# PC 端: 检测序号不连续 = 丢包

lost_samples = 0
last_seq = -1

for data in stream:
    seq = extract_sequence_number(data)
    if seq != last_seq + 1:
        lost_samples += (seq - last_seq - 1)
    last_seq = seq

loss_rate = lost_samples / total_samples
print(f"丢包率: {loss_rate*100:.2f}%")
```

---

## 📋 实施清单

### Phase 1: Bulk 优化（先尝试）

- [ ] 检查 USB Device Controller 配置
- [ ] 优化 FIFO 读取逻辑（移除不必要的延迟）
- [ ] 增大突发传输长度
- [ ] 测试速率改善

**如果 Bulk 能达到 >10 MB/s，则无需切换 ISO**

### Phase 2: ISO 实施（如需要）

- [ ] 修改 `usb_descriptor.v` - EP3 改为 ISO
- [ ] 修改 `usb_fifo.v` - 增大 EP3 FIFO
- [ ] 修改 `usb_cdc.v` - EP3 MaxPacketSize = 1024
- [ ] 重新综合和烧录
- [ ] 修改 Python 代码 - ISO 读取逻辑
- [ ] 测试速率和丢包率

---

## 🎯 预期性能

### Bulk 优化后

| 采样率 | 理论速率 | 预期速率 | 状态 |
|--------|----------|----------|------|
| 5 MHz  | 5 MB/s   | 5 MB/s   | ✅ |
| 10 MHz | 10 MB/s  | 9-10 MB/s | ✅ |
| 20 MHz | 20 MB/s  | 15-18 MB/s | ⚠️ 接近极限 |
| 30 MHz | 30 MB/s  | 20-25 MB/s | ⚠️ 可能丢包 |

### ISO 传输

| 采样率 | 理论速率 | 预期速率 | 丢包率 |
|--------|----------|----------|--------|
| 5 MHz  | 5 MB/s   | 5 MB/s   | 0% |
| 10 MHz | 10 MB/s  | 10 MB/s  | 0% |
| 20 MHz | 20 MB/s  | 20 MB/s  | 0% |
| 24 MHz | 24 MB/s  | 24 MB/s  | 0-1% |
| 30 MHz | 30 MB/s  | 24 MB/s  | ~20% ⚠️ |

---

## 💡 建议

1. **优先尝试 Bulk 优化** - 如果能达到 15+ MB/s 就够用
2. **如需 >20 MB/s** - 必须切换到 ISO
3. **添加丢包检测** - ISO 传输必须有应用层处理
4. **考虑压缩** - 如果数据有规律，压缩可能提升有效速率

---

**我会帮你一步步实施！先告诉我想优先尝试 Bulk 优化，还是直接切换到 ISO？**
