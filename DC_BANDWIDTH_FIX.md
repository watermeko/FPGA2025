# Digital Capture 速率瓶颈修复方案

## 问题诊断

**症状**: 采样率设置 >50 kHz 时，实际速率固定在 ~47-48 KB/s

**根本原因**: 上传状态机设计缺陷

## 详细分析

### 当前状态机流程

```
采样 → new_sample_flag=1 → UP_IDLE → UP_SEND → UP_WAIT → UP_IDLE
                                ↓         ↓         ↓
                            set valid  keep valid  clear valid
                                         clear flag!
```

### 问题所在

1. **第 114 行**: `new_sample_flag` 在 `upload_valid && upload_ready` 时立即清除
2. **upload_ready 永远为 1** (cdc.v:170)
3. 所以 `new_sample_flag` 在 UP_SEND 状态就被清除
4. 状态机进入 UP_WAIT 时，`new_sample_flag` 已经是 0
5. 回到 UP_IDLE 后，必须等待下一个 `sample_tick` 才能再次上传

### 延迟计算

假设采样率 = 1 MHz (sample_divider = 60):
- `sample_tick` 每 60 个时钟周期产生一次
- 状态机循环: IDLE(1) → SEND(1) → WAIT(1) = 3 个时钟
- 但由于 `new_sample_flag` 被提前清除，实际需要等到下一个 `sample_tick`

**实际发送间隔** ≈ 60 + 3 = 63 时钟周期/样本
**理论间隔** = 60 时钟周期/样本
**额外开销** = 5%

但这不足以解释 1 MHz → 48 kHz 的巨大差距！

### 真正的问题

让我重新检查... `new_sample_flag` 的清除逻辑有问题！

```verilog
if (sample_tick) begin
    captured_data <= dc_signal_in;
    captured_data_sync <= captured_data;
    new_sample_flag <= 1'b1;  // 每次采样时设置
end else if (upload_valid && upload_ready) begin
    new_sample_flag <= 1'b0;  // 上传时清除
end
```

**关键**: 如果采样速度 > 上传速度，`new_sample_flag` 会一直保持为 1！

但状态机在 UP_WAIT 时不检查 `new_sample_flag`，所以：

```
采样@1MHz    : tick---tick---tick---tick---tick---tick
状态机       : IDLE-SEND-WAIT-IDLE-SEND-WAIT-IDLE...
发送         : ^send      ^send      ^send
丢失的采样   :      X  X       X  X       X  X
```

**每 3 个时钟周期只能发送 1 个样本**！

60 MHz ÷ 3 = **20 MHz 理论最大速率**

但为什么实际只有 48 kHz？

## 深入分析：关键发现

重新看状态机第 207 行：

```verilog
if ((handler_state == H_CAPTURING) && new_sample_flag) begin
```

只有在 `UP_IDLE` 状态 **且** `new_sample_flag=1` 时才会进入 UP_SEND。

如果采样非常快：
1. sample_tick 产生 → new_sample_flag=1
2. 状态机在 UP_IDLE → 立即进入 UP_SEND
3. UP_SEND 时 upload_valid=1, upload_ready=1 → **new_sample_flag 立即清除**
4. 进入 UP_WAIT
5. 回到 UP_IDLE，但 new_sample_flag=0，**需要等待下一个 sample_tick**

### 如果采样率 = 1 MHz (divider=60)

- sample_tick 间隔 = 60 时钟
- 状态机循环 IDLE→SEND→WAIT = 3 时钟
- 但回到 IDLE 后，new_sample_flag=0，需要再等 60 时钟

**实际发送间隔** = 3 + 60 = 63 时钟 ≈ 1 MHz / 63 * 60 = 952 kHz

这还不够低...

### 等等！还有一个问题！

看第 223-226 行：

```verilog
UP_SEND: begin
    // Wait for ready signal to complete transfer
    if (upload_ready) begin  // upload_ready 永远为 1
        upload_state <= UP_WAIT;  // 立即进入 WAIT
    end
end
```

所以：
- IDLE (1 clk) - 检查 new_sample_flag
- SEND (1 clk) - 立即转到 WAIT
- WAIT (1 clk) - 清除信号
- 回到 IDLE，等待下一个 sample_tick

如果 divider = 1263 (对应 47.5 kHz):
- 60 MHz / 1263 = 47.5 kHz ✅

**所以你肯定设置的采样率就是 47.5 kHz！**

---

## 修复方案

### 方案 1: 优化状态机（推荐）

修改状态机，移除 UP_WAIT 状态，直接在 UP_SEND 后回到 UP_IDLE：

```verilog
// 修改后的状态机
localparam UP_IDLE = 1'b0;
localparam UP_SEND = 1'b1;

case (upload_state)
    UP_IDLE: begin
        if ((handler_state == H_CAPTURING) && new_sample_flag) begin
            upload_req <= 1'b1;
            upload_source <= UPLOAD_SOURCE_DC;
            upload_data <= captured_data_sync;
            upload_valid <= 1'b1;
            upload_state <= UP_SEND;
        end else begin
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
        end
    end

    UP_SEND: begin
        // 立即回到 IDLE，不需要 WAIT 状态
        upload_req <= 1'b0;
        upload_valid <= 1'b0;
        upload_state <= UP_IDLE;
    end
endcase
```

**预期性能**: 每样本 2 个时钟周期，最大速率 = 30 MHz

### 方案 2: 流水线发送（最优）

完全重新设计，使用单周期发送：

```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        upload_data <= 8'h00;
        upload_valid <= 1'b0;
    end else begin
        if (capture_enable && sample_tick) begin
            upload_data <= dc_signal_in;  // 直接发送，无延迟
            upload_valid <= 1'b1;
        end else begin
            upload_valid <= 1'b0;
        end
    end
end

assign upload_req = capture_enable;
assign upload_source = UPLOAD_SOURCE_DC;
```

**预期性能**: 每样本 1 个时钟周期，最大速率 = 60 MHz！

### 方案 3: 检查实际配置（立即测试）

先确认你设置的采样率到底是多少！

运行这个测试：

```python
# 在 diagnose_dc.py 中添加调试输出
divider = SYSTEM_CLK // sample_rate_hz
print(f"设置采样率: {sample_rate_hz} Hz")
print(f"分频器: {divider}")
print(f"实际采样率: {SYSTEM_CLK / divider} Hz")
```

我怀疑你实际设置的就是 47.5 kHz！

---

## 立即测试

运行这个来确认：

```bash
python -c "
SYSTEM_CLK = 60_000_000
sample_rate = 47500
divider = SYSTEM_CLK // sample_rate
print(f'采样率: {sample_rate} Hz')
print(f'分频器: {divider}')
print(f'实际: {SYSTEM_CLK / divider:.1f} Hz')
"
```

如果输出是 47.5 kHz，说明问题不在状态机，而是**你的设置**！

请告诉我你在 `diagnose_dc.py` 中选择的采样率编号是多少？
