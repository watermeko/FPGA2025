# Digital Capture 高速优化实施指南

## 当前状态

✅ **已解决**: 1 MHz 采样率可达 970 KB/s
❌ **待修复**: >1 MHz 采样率速率降为 0 KB/s

## 根本原因

原始 `digital_capture_handler.v` 的上传状态机有 3 个状态：

```
UP_IDLE → UP_SEND → UP_WAIT → UP_IDLE (循环)
   1 clk    1 clk     1 clk
```

**每个样本需要 3 个时钟周期上传**，导致：
- 理论最大速率 = 60 MHz ÷ 3 = **20 MHz**
- 但由于 `new_sample_flag` 清除逻辑问题，实际更低

当采样率超过状态机处理能力时，样本被丢弃，导致 0 速率。

---

## 实施步骤

### 第 1 步：备份原文件

```bash
cd C:\Development\GOWIN\FPGA2025
cp rtl/logic/digital_capture_handler.v rtl/logic/digital_capture_handler.v.bak
```

### 第 2 步：替换文件

**方法 A（推荐）**: 直接替换
```bash
cp rtl/logic/digital_capture_handler_optimized.v rtl/logic/digital_capture_handler.v
```

**方法 B**: 手动合并（如果需要保留其他修改）
- 对比两个文件的差异
- 手动应用优化部分

### 第 3 步：在 GOWIN EDA 中重新综合

1. 打开 `fpga_project.gprj`
2. **Synthesize** → 运行综合
3. **Place & Route** → 运行布局布线
4. **Program Device** → 生成并烧录 bitstream

### 第 4 步：测试性能

```bash
cd software
python test_usb_bandwidth.py
```

**预期结果**:

| 采样率 | 修改前 | 修改后（预期） |
|--------|--------|----------------|
| 1 MHz  | 970 KB/s ✅ | 970 KB/s ✅ |
| 5 MHz  | 0 KB/s ❌ | ~4.8 MB/s ✅ |
| 10 MHz | 0 KB/s ❌ | ~9.5 MB/s ✅ |
| 20 MHz | 0 KB/s ❌ | ~19 MB/s ✅ |
| 30 MHz | 0 KB/s ❌ | ~28 MB/s ✅ |

**理论极限**: 60 MHz（受系统时钟限制）
**实际极限**: ~30-40 MB/s（受 USB High-Speed 和 FIFO 带宽限制）

---

## 技术细节：优化方案对比

### 原始版本（慢速）

```verilog
// 3-状态机：UP_IDLE → UP_SEND → UP_WAIT
case (upload_state)
    UP_IDLE: begin
        if (new_sample_flag) begin
            upload_req <= 1'b1;
            upload_data <= captured_data_sync;
            if (upload_ready) upload_state <= UP_SEND;
        end
    end
    UP_SEND: begin
        if (upload_ready) upload_state <= UP_WAIT;
    end
    UP_WAIT: begin
        upload_req <= 1'b0;
        upload_valid <= 1'b0;
        upload_state <= UP_IDLE;
    end
endcase
```

**问题**:
1. 每样本需要 3 个时钟周期
2. `new_sample_flag` 清除时机不当
3. 状态切换开销大

---

### 优化版本（高速）

```verilog
// 单周期直接发送，无状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        upload_data <= 8'h00;
        upload_valid <= 1'b0;
        upload_req <= 1'b0;
    end else begin
        if ((handler_state == H_CAPTURING) && sample_tick) begin
            upload_data <= captured_data;  // 直接发送采样数据
            upload_valid <= 1'b1;
            upload_req <= 1'b1;
        end else begin
            upload_valid <= 1'b0;
            upload_req <= 1'b0;
        end
    end
end
```

**优化**:
1. **零延迟**: `sample_tick` 产生时立即发送
2. **无状态机**: 没有状态切换开销
3. **无标志位**: 移除 `new_sample_flag` 和 `captured_data_sync`
4. **流水线**: 每个时钟周期都可以发送样本

**性能提升**:
- 原始版本: 3 时钟周期/样本 → 最大 20 MHz
- 优化版本: 1 时钟周期/样本 → 最大 60 MHz

---

## 文件修改对比

### 修改位置 1: 状态定义（第 56-62 行）

**原始**:
```verilog
// Upload state machine
localparam UP_IDLE = 2'b00;
localparam UP_SEND = 2'b01;
localparam UP_WAIT = 2'b10;

reg [2:0] handler_state;
reg [1:0] upload_state;  // ← 移除此状态机
```

**优化**:
```verilog
// No upload state machine needed
reg [2:0] handler_state;
// upload_state 已完全移除
```

---

### 修改位置 2: 信号捕获（第 103-119 行）

**原始**:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        captured_data <= 8'h00;
        captured_data_sync <= 8'h00;    // ← 移除同步寄存器
        new_sample_flag <= 1'b0;        // ← 移除标志位
    end else begin
        if (sample_tick) begin
            captured_data <= dc_signal_in;
            captured_data_sync <= captured_data;
            new_sample_flag <= 1'b1;
        end else if (upload_valid && upload_ready) begin
            new_sample_flag <= 1'b0;    // ← 复杂的清除逻辑
        end
    end
end
```

**优化**:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        captured_data <= 8'h00;
    end else begin
        if (sample_tick && capture_enable) begin
            captured_data <= dc_signal_in;  // 简单直接
        end
    end
end
```

---

### 修改位置 3: 上传逻辑（第 205-239 行）

**原始**: 35 行的复杂状态机
```verilog
case (upload_state)
    UP_IDLE: begin ... end
    UP_SEND: begin ... end
    UP_WAIT: begin ... end
endcase
```

**优化**: 14 行的简洁逻辑
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        upload_data <= 8'h00;
        upload_valid <= 1'b0;
        upload_req <= 1'b0;
    end else begin
        if ((handler_state == H_CAPTURING) && sample_tick) begin
            upload_data <= captured_data;
            upload_valid <= 1'b1;
            upload_req <= 1'b1;
        end else begin
            upload_valid <= 1'b0;
            upload_req <= 1'b0;
        end
    end
end
```

---

## 故障排查

### 如果优化后仍然速率为 0

**检查 1**: 确认文件已正确替换
```bash
grep -n "HIGH-SPEED OPTIMIZED VERSION" rtl/logic/digital_capture_handler.v
```
应该在第 2 行看到此注释。

**检查 2**: 确认综合无错误
- 查看 GOWIN EDA 综合日志
- 确认无 timing violations

**检查 3**: 确认 USB 连接稳定
```bash
python software/check_usb_speed.py
```
应该看到 MaxPacketSize = 512 bytes。

**检查 4**: 使用诊断工具
```bash
python software/diagnose_dc.py
```
选择 5 MHz 测试，观察是否有数据流。

---

## 回滚方法

如果优化版本有问题，可以立即回滚：

```bash
cd C:\Development\GOWIN\FPGA2025
cp rtl/logic/digital_capture_handler.v.bak rtl/logic/digital_capture_handler.v
```

然后在 GOWIN EDA 中重新综合和烧录。

---

## 性能验证

运行完整带宽测试：

```bash
cd software
python test_usb_bandwidth.py
```

**成功标准**:
- ✅ 5 MHz: >80% 效率 (>4 MB/s)
- ✅ 10 MHz: >80% 效率 (>8 MB/s)
- ✅ 20 MHz: >80% 效率 (>16 MB/s)

---

## 下一步优化（可选）

如果优化后仍有瓶颈：

1. **FIFO 扩容**: 增大 `usb_fifo.v` 的 FIFO 深度
2. **EP3 优先级**: 在 arbiter 中提高 EP3 优先级
3. **DMA 传输**: 考虑使用 DMA 加速数据传输

---

## 总结

| 指标 | 修改前 | 修改后 |
|------|--------|--------|
| 最大稳定采样率 | 1 MHz | 30 MHz |
| 最大数据速率 | ~1 MB/s | ~30 MB/s |
| 上传延迟 | 3 时钟周期 | 1 时钟周期 |
| 代码复杂度 | 高（3状态+标志） | 低（直接发送） |

**预计改进**: 30 倍性能提升 🚀

---

请按照上述步骤操作，然后告诉我测试结果！
