# USB 传输死锁问题修复

## 🐛 问题症状

**测试结果**:
- 前 4 秒: 19.5 MB/s ✅（接近理论 20 MB/s）
- 第 5 秒: 降到 8.8 MB/s ⚠️
- 第 6-7 秒: 完全停止 0 KB/s ❌

**结论**: FIFO 优化成功（速率从 4.8 MB/s 提升到 19.5 MB/s），但存在**死锁问题**。

---

## 🔍 根本原因

### 问题分析

在 `rtl/usb/sync_fifo/sync_tx_pkt_fifo.v` 中：

```verilog
// 第 136-138 行: pkt_rp 只在 pktfin 信号时更新
always @ ( posedge CLK or negedge RSTn ) begin
    if (!RSTn) begin
        pkt_rp <= 'd0;
    end
    else if (pktfin) begin
        pkt_rp <= rp;  // 只有这时才更新！
    end
end

// 第 157 行: empty 依赖于 pkt_rp
assign empty = ( wp == pkt_rp );

// 第 156 行: full 也依赖于 pkt_rp
assign full = ( (wp[ASIZE] ^ pkt_rp[ASIZE]) & (wp[ASIZE - 1:0] == pkt_rp[ASIZE - 1:0]) );
```

### 死锁机制

1. **数据持续写入**: `wp` 不断增加
2. **pkt_rp 不更新**: 因为 `pktfin` 信号未触发
3. **FIFO 被认为满**: `full = 1` (wp 追上 pkt_rp)
4. **写入停止**: `write & (~full)` 条件为假
5. **无法读取**: `empty = 0` 但实际 USB 无法读取未提交的数据
6. **死锁**: 既无法写（满），也无法读（等待 pktfin）

---

## 🎯 解决方案

有三种可能的解决方案：

### 方案 A: 使用实际的 rp 而不是 pkt_rp（推荐）

**原理**: 让 `empty` 和 `full` 基于实际的读写指针，而不是等待包完成信号。

**优点**:
- ✅ 消除死锁
- ✅ 提高吞吐量
- ✅ 更简单的逻辑

**缺点**:
- ⚠️ 可能在包传输中途就开始下一个包（但 USB 协议应该能处理）

**修改 `sync_tx_pkt_fifo.v`**:

```verilog
// 第 157 行: 修改 empty 定义
// 修改前
assign empty = ( wp == pkt_rp );

// 修改后
assign empty = ( wp == rp );  // 使用实际读指针
```

```verilog
// 第 156 行: 修改 full 定义
// 修改前
assign full = ( (wp[ASIZE] ^ pkt_rp[ASIZE]) & (wp[ASIZE - 1:0] == pkt_rp[ASIZE - 1:0]) );

// 修改后
assign full = ( (wp[ASIZE] ^ rp[ASIZE]) & (wp[ASIZE - 1:0] == rp[ASIZE - 1:0]) );
```

---

### 方案 B: 定期强制触发 pktfin

**原理**: 在 FIFO 接近满时或定时触发 `pktfin` 信号。

**优点**:
- ✅ 保留包级别的管理
- ✅ 可配置触发条件

**缺点**:
- ⚠️ 更复杂的逻辑
- ⚠️ 需要添加定时器或阈值检测

**修改 `usb_fifo.v`**:

在 `usb_tx_buf` 模块中添加：

```verilog
// 添加自动 pktfin 生成
reg auto_pktfin;
reg [15:0] pktfin_timer;

always @(posedge i_clk or posedge i_reset) begin
    if (i_reset) begin
        auto_pktfin <= 1'b0;
        pktfin_timer <= 16'd0;
    end else begin
        auto_pktfin <= 1'b0;

        // 条件1: FIFO 接近满（>75%）
        if (pkt_fifo_wr_num > (1 << (P_ASIZE - 2)) * 3) begin
            auto_pktfin <= 1'b1;
            pktfin_timer <= 16'd0;
        end
        // 条件2: 超过 1000 个时钟周期未传输
        else if (pktfin_timer > 1000) begin
            if (pkt_fifo_wr_num > 0) begin
                auto_pktfin <= 1'b1;
            end
            pktfin_timer <= 16'd0;
        end else begin
            pktfin_timer <= pktfin_timer + 1;
        end
    end
end

// 修改 pktfin 信号
assign pkt_fifo_rd_pktfin = (i_usb_txpktfin | auto_pktfin) & (i_usb_endpt==P_ENDPOINT);
```

---

### 方案 C: 增加 FIFO 深度（临时缓解）

**原理**: 增大 FIFO 避免填满，延迟死锁发生时间。

**修改 `usb_fifo.v`**:

```verilog
// 第 46 行
// 修改前
`define EP3_IN_BUF_ASIZE 4'd12  // 4096 bytes

// 修改后
`define EP3_IN_BUF_ASIZE 4'd13  // 8192 bytes
```

**缺点**: 治标不治本，只是延迟问题发生。

---

## 🚀 推荐实施

**推荐方案 A** - 最简单有效：

### 修改 `rtl/usb/sync_fifo/sync_tx_pkt_fifo.v`

```verilog
// 第 156-157 行
// 修改前
assign full = ( (wp[ASIZE] ^ pkt_rp[ASIZE]) & (wp[ASIZE - 1:0] == pkt_rp[ASIZE - 1:0]) );
assign empty = ( wp == pkt_rp );

// 修改后
assign full = ( (wp[ASIZE] ^ rp[ASIZE]) & (wp[ASIZE - 1:0] == rp[ASIZE - 1:0]) );
assign empty = ( wp == rp );
```

### 修改 `wrnum` 计算（第 148-154 行）

```verilog
// 修改前
if (wp[ASIZE : 0] >= pkt_rp[ASIZE : 0]) begin
    wrnum <= wp[ASIZE : 0] - pkt_rp[ASIZE : 0];
end
else begin
    wrnum <= {1'b1,wp[ASIZE - 1 : 0]} - {1'b0,pkt_rp[ASIZE - 1 : 0]};
end

// 修改后 - 使用 pkt_rp（这个保持不变，因为 wrnum 是报告给 USB 的可用数据量）
// 保持原样
```

**注意**: `wrnum` 仍然使用 `pkt_rp`，因为它表示"已提交的可读数据量"，这是正确的。只有 `empty` 和 `full` 需要改为使用 `rp`。

---

## 🧪 测试验证

### 步骤 1: 修改代码

按照上述方案 A 修改 `sync_tx_pkt_fifo.v`。

### 步骤 2: 重新综合

1. GOWIN EDA: Synthesize → Place & Route → Program Device

### 步骤 3: 测试

```bash
cd software
python diagnose_dc.py
# 选择 20 MHz (选项 16)
# 观察至少 30 秒，确认不会卡死
```

**预期结果**:
```
时间       总字节          本秒速率            平均速率            USB利用率       状态
-------------------------------------------------------------------------------------
    1.0s 19,999,303 B   19511.4 KB/s   19511.4 KB/s       47.6%  ✅ 正常
    2.0s 39,946,168 B   19472.8 KB/s   19492.1 KB/s       47.5%  ✅ 正常
    3.0s 59,952,995 B   19528.5 KB/s   19504.2 KB/s       47.7%  ✅ 正常
    ...
   30.0s 599,xxx,xxx B  19500.0 KB/s   19500.0 KB/s       47.6%  ✅ 正常
```

### 步骤 4: 全速率测试

```bash
python test_all_rates.py
```

**预期所有速率都应稳定**。

---

## 📊 预期性能

| 采样率 | 理论速率 | 预期实际速率 | 说明 |
|--------|----------|--------------|------|
| 5 MHz  | 5 MB/s   | 4.8-5.0 MB/s ✅ | 接近 100% |
| 10 MHz | 10 MB/s  | 9.5-10 MB/s ✅ | 接近 100% |
| 20 MHz | 20 MB/s  | 19-20 MB/s ✅ | 接近 100%，持续稳定 |
| 30 MHz | 30 MB/s  | 28-30 MB/s ✅ | USB 2.0 Bulk 极限 |

---

## 🔬 技术解释

### 为什么原设计使用 pkt_rp？

原设计的 `pkt_rp` 机制是为了：
1. **包完整性**: 确保只有完整的 USB 包被传输
2. **CRC 校验**: 等待包完成后再计算 CRC
3. **协议兼容**: 符合某些严格的 USB 设备实现

### 为什么我们可以改为 rp？

1. **USB 控制器处理**: 现代 USB 控制器会自动处理包边界
2. **高速传输**: 连续传输比包级别管理更重要
3. **FIFO 流式**: 数据流模式不需要严格的包边界

### 如果方案 A 有问题怎么办？

如果使用 `rp` 后出现 USB 传输错误，则：
1. 回退到方案 B（定期触发 pktfin）
2. 或者实施 ISO 传输（`USB_SPEED_FIX_AND_ISO_PLAN.md`）

---

## 💡 下一步

1. **立即修改**: `sync_tx_pkt_fifo.v` 第 156-157 行
2. **综合烧录**: GOWIN EDA
3. **测试验证**: 运行 `diagnose_dc.py` 和 `test_all_rates.py`
4. **报告结果**: 告诉我是否解决了死锁问题

**期待看到稳定的 19.5 MB/s 传输！** 🎉
