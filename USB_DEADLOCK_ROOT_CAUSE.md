# USB 传输死锁问题 - 根本原因分析与修复

## 问题症状

- **初始表现**：19.5 MB/s 稳定传输
- **运行约 19 秒后**：速率突然下降到 6 MB/s，然后完全卡死（0 KB/s）
- **可复现性**：每次运行约 18-20 秒后必然发生

## 根本原因

### 问题代码位置

`rtl/usb/sync_fifo/sync_tx_pkt_fifo.v` 第 67-87 行（修复前）：

```verilog
always @ ( posedge CLK or negedge RSTn )
begin                  // read from RAM
    if (!RSTn)
    begin
        rp <= 'd0;
        rp_next <= 'd1;
    end
    //else if ( txact_rise ) begin
    else if ( txact_fall ) begin  // ❌ 这是问题所在！
        if ( read & (~empty)  ) begin
            rp <= pkt_rp + 1'b1;
        end
        else begin
            rp <= pkt_rp;  // ❌ rp 被回退！
        end
    end
    else if ( read & (~empty)  ) begin
        rp <= rp + 1'b1;
        rp_next <= rp + 2'd2;
    end
end
```

### 问题机制

#### USB Packet 传输机制

USB 批量传输使用 **packet-based** 机制：

1. **写入阶段**：数据连续写入 FIFO（`wp` 递增）
2. **packet 准备**：当有足够数据时，USB 控制器开始传输一个 packet（通常 512 字节）
3. **传输阶段**：`txact = 1`，`read` 信号每周期递增 `rp`
4. **传输结束**：`txact_fall`（txact 从 1 → 0）
5. **确认阶段**：如果传输成功，`pktfin` 信号到来，`pkt_rp <= rp`

#### 致命的指针回退

**问题**：第 75-82 行在 `txact_fall` 时，**无条件地将 `rp` 回退到 `pkt_rp`**！

**场景重现**：

```
时刻 T1: 正常传输中
  wp = 2000 (写入指针)
  rp = 1500 (读取指针，正在传输第 1000-1500 字节)
  pkt_rp = 1000 (上一个成功 packet 的位置)

时刻 T2: txact_fall 发生（传输结束）
  ❌ rp 被强制回退：rp = pkt_rp = 1000
  ❌ 500 字节的读取进度被"撤销"

时刻 T3: pktfin 到来（延迟 1-2 个周期）
  pkt_rp <= rp = 1000
  ❌ 但此时 rp 应该是 1500！

时刻 T4: 下一个 packet 开始传输
  从 rp = 1000 开始读取
  ❌ 1000-1500 的数据被重新读取（重复传输）

时刻 T5: wp 持续增长，rp 因回退而落后
  FIFO 逐渐填满

时刻 T6: FIFO 满（wp 追上 rp + FIFO_SIZE）
  ✋ 写入被阻止
  🔒 死锁发生
```

### 为什么运行 ~19 秒才发生？

- **FIFO 大小**：4096 字节（EP3_IN_BUF_ASIZE = 12，即 2^12）
- **写入速率**：20 MB/s
- **每次回退丢失**：约 200-500 字节（取决于 packet 传输时长）
- **累积效应**：
  ```
  每次回退损失：~300 字节
  FIFO 容量：4096 字节
  达到满的次数：4096 / 300 ≈ 14 次
  每秒约 1-2 次回退
  → 约 7-14 秒后 FIFO 满
  ```

加上 USB 传输的缓冲机制，实际表现为 18-20 秒后卡死。

## 修复方案

### 核心修复

**移除 `txact_fall` 时的指针回退逻辑**：

```verilog
always @ ( posedge CLK or negedge RSTn )
begin                  // read from RAM
    if (!RSTn)
    begin
        rp <= 'd0;
        rp_next <= 'd1;
    end
    // ✅ CRITICAL FIX: Do NOT reset rp on txact_fall
    // ✅ rp should only advance forward when reading
    // ✅ pkt_rp is updated separately on pktfin
    else if ( read & (~empty)  ) begin
        rp <= rp + 1'b1;
        rp_next <= rp + 2'd2;
    end
end
```

### 修复原理

1. **`rp` 只向前移动**：每次 `read` 时递增，永不回退
2. **`pkt_rp` 独立更新**：由 `pktfin` 信号控制（第 132-138 行）
3. **指针一致性**：
   ```
   pkt_rp ≤ rp ≤ wp
   ```
   - `pkt_rp`：最后一个成功传输的 packet 结束位置
   - `rp`：当前读取位置
   - `wp`：当前写入位置

### 为什么原代码有这个逻辑？

**推测**：原设计可能想处理 USB 传输失败的情况（例如 NACK），通过回退 `rp` 重新发送数据。

**问题**：
1. **没有检查 `pktfin`**：无论成功失败都回退
2. **与 USB 控制器冲突**：USB Device Controller 已经处理重传逻辑
3. **破坏指针一致性**：导致 FIFO 状态错误

## 测试验证

### 预期结果

修复后应该能够：
1. ✅ **稳定传输**：持续 19.5 MB/s，不会衰减
2. ✅ **长时间运行**：运行数分钟甚至数小时不卡死
3. ✅ **多次运行**：连续 5-10 次运行均正常

### 测试步骤

```bash
# 1. 综合并烧录新固件（GOWIN EDA）

# 2. 长时间测试（至少 60 秒）
python diagnose_dc.py
# 选择 20 MHz，运行 60 秒观察

# 3. 连续测试（5 次）
for i in {1..5}; do
    echo "=== 测试 $i ==="
    timeout 30 python diagnose_dc.py
done
```

### 验证指标

| 指标 | 修复前 | 修复后（预期） |
|------|--------|----------------|
| 稳定传输时间 | ~19 秒 | ∞（无限期） |
| 平均速率 | 19.5 MB/s → 0 | 19.5 MB/s 稳定 |
| 多次运行 | 第3次失败 | 所有次数成功 |
| FIFO 状态 | 逐渐满 | 动态平衡 |

## 相关文件

- **修复文件**：`rtl/usb/sync_fifo/sync_tx_pkt_fifo.v`（第 67-82 行）
- **相关模块**：
  - `rtl/usb/sync_fifo/usb_fifo.v`（EP3 FIFO 管理）
  - `rtl/logic/digital_capture_handler.v`（数据源）
  - `rtl/usb/usb_cdc.v`（USB CDC 接口）

## 总结

这是一个经典的 **FIFO 指针管理错误**：

- ❌ **错误设计**：在不该回退的时候回退指针
- ✅ **正确设计**：指针只向前移动，由确认信号控制
- 🎯 **关键教训**：FIFO 读写指针的更新逻辑必须严格与控制信号同步，不能有"猜测性"的回退

修复后，USB 传输应该能够以 19.5 MB/s 稳定运行，不再出现死锁。
