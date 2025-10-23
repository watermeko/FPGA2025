# DC模块Bug分析报告

## 测试日期
2025-10-22

## 测试环境
- FPGA: GOWIN GW5A-25A
- USB: High-Speed CDC (COM23)
- 系统时钟: 60 MHz
- 测试工具: diagnose_dc.py

---

## 完整测试结果

| 采样率 | Divider | 理论速率 | 实际速率 | 效率 | 测试时长 | 状态 |
|--------|---------|----------|----------|------|----------|------|
| 1 kHz | 60,000 | 1 KB/s | 1.1 KB/s | 110% | - | ✅ 正常 |
| 2 kHz | 30,000 | 2 KB/s | 2.0 KB/s | 100% | 162秒 | ✅ 正常 |
| 5 kHz | 12,000 | 5 KB/s | 5.2 KB/s | 104% | - | ✅ 正常 |
| 10 kHz | 6,000 | 10 KB/s | 10 KB/s | 100% | ~3秒 | ❌ **卡住** |
| 20 kHz | 3,000 | 20 KB/s | 0.8 KB/s | 4% | - | ❌ **几乎不工作** |
| 50 kHz | 1,200 | 50 KB/s | 48.7 KB/s | 97% | - | ✅ 正常 |
| 100 kHz | 600 | 100 KB/s | 100 KB/s | 100% | - | ✅ 正常 |
| 200 kHz | 300 | 200 KB/s | 142 KB/s | 71% | - | ❌ **丢失29%** |
| 500 kHz | 120 | 500 KB/s | 506 KB/s | 101% | - | ✅ 正常 |
| 1 MHz | 60 | 1 MB/s | 500 KB/s | 50% | - | ✅ 达到系统极限 |
| 2 MHz | 30 | 2 MB/s | - | - | ~1秒 | ❌ **卡住** |
| 30 MHz | 2 | 30 MB/s | 507 KB/s | 1.7% | 258秒 | ✅ 达到系统极限 |

---

## 发现的问题

### Bug #1：特定Divider值触发严重故障

**有问题的Divider值（仅4个）**：

```
Divider = 30      (30 × 1)    → 2 MHz   ❌ 完全卡住，需要复位FPGA
Divider = 300     (30 × 10)   → 200 kHz ❌ 丢失29%数据
Divider = 3,000   (30 × 100)  → 20 kHz  ❌ 几乎不工作（只有4%效率）
Divider = 6,000   (30 × 200)  → 10 kHz  ❌ 3秒后完全卡住，需要复位FPGA
```

**规律**：
- 所有问题都出现在 `divider = 30 × k` 且 `k ∈ {1, 10, 100, 200}`
- 其他所有divider值（包括30×2, 30×4, 30×20, 30×40, 30×400, 30×1000, 30×2000）都正常

**影响**：
- `divider = 30, 6000`：系统完全死锁，需要复位FPGA才能恢复
- `divider = 3000`：数据传输几乎停止
- `divider = 300`：29%的数据丢失

**根本原因推测**：
1. 跨时钟域FIFO在特定频率比值下的同步问题
2. 分频器与USB时钟产生特定的"拍频"或"共振"
3. 状态机在特定时序窗口下进入死锁状态

---

### Bug #2：系统上传速率瓶颈（~500 KB/s）

**现象**：
- 所有采样率 > 500 KB/s 时，实际上传速率都被限制在 ~500 KB/s
- 不会导致系统卡住，但会大量丢失样本

**测试证据**：
```
1 MHz   理论1000 KB/s → 实际500 KB/s (50%效率)
30 MHz  理论30000 KB/s → 实际507 KB/s (1.7%效率，丢失98.3%数据)
```

**瓶颈位置分析**：

1. **跨时钟域FIFO太小（64字节）**
   - 位置：`usb_fifo.v:1319` - `ASIZE=6` → 2^6 = 64字节
   - 问题：64字节 ÷ 500 KB/s = 每128微秒就填满
   - FIFO的Full信号未连接（无反压）

2. **USB CDC实际吞吐率限制**
   - 理论：USB High-Speed可达15-30 MB/s
   - 实际：系统只能达到 ~500 KB/s
   - 可能原因：CDC协议开销、轮询延迟、PC端读取速度

3. **数据路径**：
   ```
   DC Handler (60 MHz, 理论60 MB/s)
       ↓
   Command Processor (直通，无缓冲)
       ↓
   跨时钟域FIFO (64字节) ← 瓶颈1
       ↓
   USB EP2_IN FIFO (4KB)
       ↓
   USB CDC Controller ← 瓶颈2
       ↓
   Windows驱动 + Python读取 ← 瓶颈3
   ```

**影响**：
- 有效采样率上限：约500 kHz
- 超过此速率会大量丢失样本
- 不会导致系统卡住（与Bug #1不同）

---

## 代码问题位置

### 1. DC Handler状态机缺陷
**文件**：`digital_capture_handler.v`
**位置**：Lines 206-220

**问题**：
```verilog
UP_IDLE: begin
    if ((handler_state == H_CAPTURING) && new_sample_flag) begin
        upload_req <= 1'b1;
        upload_source <= UPLOAD_SOURCE_DC;
        upload_data <= captured_data_sync;

        if (upload_ready) begin
            upload_valid <= 1'b1;
            upload_state <= UP_SEND;
        end
        // ❌ 缺少else分支！
        // 当upload_ready=0时，状态机会卡在这里
        // new_sample_flag永远不会被清除
    end else begin
        upload_req <= 1'b0;
    end
end
```

**说明**：
- 虽然`upload_ready`在Command Processor中永远是1
- 但在特定divider值下，某些时序条件可能导致异常
- 缺少异常处理是潜在的死锁源

---

### 2. 跨时钟域FIFO容量不足
**文件**：`usb_fifo.v`
**位置**：Lines 1317-1336

**问题**：
```verilog
clk_cross_fifo #(
   .DSIZE (8)
  ,.ASIZE (6)      // ❌ 2^6 = 64字节，太小！
  ,.AEMPT (1)
  ,.AFULL (32)     // 半满阈值32字节
)clk_cross_fifo (
    ...
    .Full       ()  // ❌ Full信号未连接，无反压！
    .AlmostFull ()  // ❌ AlmostFull未连接
    ...
);
```

**建议**：
- 增大ASIZE到至少8（256字节）或9（512字节）
- 连接Full信号并反馈给上游
- 实现流控机制

---

### 3. Command Processor无流控
**文件**：`command_processor.v`
**位置**：Lines 86, 98-101

**问题**：
```verilog
// Line 86
upload_ready_out <= 1'b1;  // ❌ 永远是1，不检查下游状态

// Lines 98-101
if (upload_req_in && upload_valid_in && upload_ready_out) begin
    usb_upload_data_out <= upload_data_in;
    usb_upload_valid_out <= 1'b1;  // 直接写入，不检查FIFO是否满
end
```

**说明**：
- Command Processor作为直通通道，不检查下游USB FIFO状态
- 当USB FIFO满时，数据会被丢弃（sync_tx_pkt_fifo.v:60-64）
- 应该增加流控反馈机制

---

## 修复方案

### 快速解决方案：软件规避（立即可用）

**在软件层面屏蔽有问题的divider值**：

```python
# 在生成DC启动命令前添加检查
def validate_divider(divider):
    """检查并修正有问题的divider值"""
    problematic_dividers = [30, 300, 3000, 6000]

    if divider in problematic_dividers:
        # 调整到最接近的安全值
        if divider == 30:
            return 60      # 2 MHz → 1 MHz
        elif divider == 300:
            return 600     # 200 kHz → 100 kHz
        elif divider == 3000:
            return 1200    # 20 kHz → 50 kHz
        elif divider == 6000:
            return 12000   # 10 kHz → 5 kHz

    return divider
```

**优点**：
- 无需修改FPGA代码
- 立即可用
- 避免用户遇到死锁

**缺点**：
- 无法使用某些特定采样率
- 治标不治本

---

### 彻底解决方案：硬件修复（需要重新综合）

#### 修复1：增大跨时钟域FIFO

**文件**：`usb_fifo.v:1319`

```verilog
clk_cross_fifo #(
   .DSIZE (8)
  ,.ASIZE (9)      // ✅ 改为9：2^9 = 512字节
  ,.AEMPT (1)
  ,.AFULL (256)    // ✅ 调整半满阈值
)clk_cross_fifo (
    ...
    .Full       (c_fifo_full)      // ✅ 连接Full信号
    .AlmostFull (c_fifo_almost_full) // ✅ 连接AlmostFull
    ...
);
```

#### 修复2：添加流控机制

**需要修改**：
1. `command_processor.v`：根据下游FIFO状态动态调整`upload_ready_out`
2. `digital_capture_handler.v`：添加upload_ready=0时的处理分支
3. `usb_fifo.v`：连接并使用FIFO的Full/AlmostFull信号

#### 修复3：调试特定divider值问题

**需要深入分析**：
1. 使用Chipscope/Logic Analyzer捕获divider=30,300,3000,6000时的时序
2. 检查跨时钟域同步信号
3. 分析状态机状态转换
4. 查找特定频率比值下的时序冲突

---

## 实用建议

### 当前可用的采样率范围

**完全可靠（100%效率）**：
- 1 kHz, 2 kHz, 5 kHz ✅
- 50 kHz, 100 kHz ✅

**可用但达到极限（会丢样本）**：
- 500 kHz ~ 1 MHz：约500 KB/s有效速率
- > 1 MHz：严重丢样本，效率<50%

**不可用（会卡住或严重故障）**：
- 10 kHz ❌ (卡住)
- 20 kHz ❌ (几乎不工作)
- 200 kHz ❌ (丢失29%)
- 2 MHz ❌ (卡住)

---

## 测试方法

**重现bug的步骤**：

```bash
# 终端运行
python F:\FPGA2025\software\diagnose_dc.py

# 选择COM23
# 选择采样率：
#   - 编号4 (10 kHz)  → 3秒后卡住
#   - 编号5 (20 kHz)  → 几乎无数据
#   - 编号8 (200 kHz) → 丢失29%
#   - 编号11 (2 MHz)  → 1秒后卡住
```

**验证修复的测试用例**：
1. 连续运行10 kHz超过5秒不卡住
2. 20 kHz达到接近20 KB/s的速率
3. 200 kHz达到接近200 KB/s的速率
4. 2 MHz能稳定运行（或被限制到500 KB/s但不卡住）

---

## 总结

### 核心发现

1. **只有4个特定divider值有问题**：30, 300, 3000, 6000
2. **其他所有divider值都正常工作**（包括2, 60, 120, 600, 1200, 12000, 30000, 60000）
3. **系统有一个硬性上传速率限制：~500 KB/s**
4. **问题与采样率的"高低"无关，而是与特定divider值有关**

### Bug优先级

1. **P0 - 严重**：divider=30, 6000导致完全死锁
2. **P1 - 高**：divider=3000几乎不工作（4%效率）
3. **P1 - 高**：divider=300丢失29%数据
4. **P2 - 中**：系统上传速率瓶颈（~500 KB/s）

### 下一步行动

**短期（立即）**：
- 在软件中屏蔽4个有问题的divider值
- 提供用户可用采样率列表

**长期（需要FPGA修改）**：
- 增大跨时钟域FIFO容量
- 实现流控机制
- 调试特定divider值的根本原因

---

## 附录：测试原始数据

### 20 kHz测试（divider=3000）
```
运行时长: 17.7秒
总接收: 14,720 bytes (14.4 KB)
平均速率: 0.8 KB/s
理论速率: 20 KB/s
效率: 4%
```

### 200 kHz测试（divider=300）
```
运行时长: 8.4秒
总接收: 1,226,090 bytes (1197.4 KB)
平均速率: 142 KB/s
理论速率: 200 KB/s
效率: 71%
```

### 2 kHz测试（divider=30000）
```
运行时长: 162.5秒
总接收: 324,559 bytes (317.0 KB)
平均速率: 2.0 KB/s
理论速率: 2 KB/s
效率: 100% ✅
```

### 30 MHz测试（divider=2）
```
运行时长: 258秒
总接收: 134,259,993 bytes (131.1 MB)
平均速率: 507 KB/s
理论速率: 30 MB/s
效率: 1.7%（达到系统极限）
```
