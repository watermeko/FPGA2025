# Digital Capture Handler 高速优化方案

## 当前瓶颈

**1 MHz 可达 970 KB/s，但 >1 MHz 时速率为 0**

### 根本原因

上传状态机需要 **3 个时钟周期/样本**：
- UP_IDLE: 检查 new_sample_flag
- UP_SEND: 发送数据
- UP_WAIT: 清除标志

当采样率 > 20 MHz (60MHz ÷ 3) 时，状态机跟不上采样速度。

但实际瓶颈更低，因为：
1. `new_sample_flag` 清除逻辑导致延迟
2. 多状态切换开销
3. 可能的竞争条件

## 修复方案 1: 简化状态机（推荐）

### 修改文件
`rtl/logic/digital_capture_handler.v`

### 修改位置 1: 状态定义（第 56-59 行）

**原代码**:
```verilog
// Upload state machine
localparam UP_IDLE = 2'b00;
localparam UP_SEND = 2'b01;
localparam UP_WAIT = 2'b10;

reg [1:0] upload_state;
```

**修改为**:
```verilog
// Upload state machine - 简化为单状态
localparam UP_IDLE = 1'b0;
localparam UP_ACTIVE = 1'b1;

reg upload_state;
```

### 修改位置 2: 信号捕获逻辑（第 103-119 行）

**原代码**:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        captured_data <= 8'h00;
        captured_data_sync <= 8'h00;
        new_sample_flag <= 1'b0;
    end else begin
        if (sample_tick) begin
            // Capture all 8 channels on sampling tick
            captured_data <= dc_signal_in;
            captured_data_sync <= captured_data;
            new_sample_flag <= 1'b1;
        end else if (upload_valid && upload_ready) begin
            // Clear flag after successful upload
            new_sample_flag <= 1'b0;
        end
    end
end
```

**修改为（直接发送模式）**:
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        captured_data <= 8'h00;
    end else begin
        if (sample_tick && capture_enable) begin
            // 直接捕获，无需同步
            captured_data <= dc_signal_in;
        end
    end
end
```

### 修改位置 3: 上传状态机（第 205-239 行）

**原代码**:
```verilog
case (upload_state)
    UP_IDLE: begin
        if ((handler_state == H_CAPTURING) && new_sample_flag) begin
            upload_req <= 1'b1;
            upload_source <= UPLOAD_SOURCE_DC;
            upload_data <= captured_data_sync;

            if (upload_ready) begin
                upload_valid <= 1'b1;
                upload_state <= UP_SEND;
            end
        end else begin
            upload_req <= 1'b0;
        end
    end

    UP_SEND: begin
        if (upload_ready) begin
            upload_state <= UP_WAIT;
        end
    end

    UP_WAIT: begin
        upload_req <= 1'b0;
        upload_valid <= 1'b0;
        upload_state <= UP_IDLE;
    end

    default: begin
        upload_state <= UP_IDLE;
    end
endcase
```

**修改为（单周期发送）**:
```verilog
// 简化的上传逻辑 - 直接跟随 sample_tick
if (handler_state == H_CAPTURING) begin
    if (sample_tick) begin
        upload_data <= captured_data;
        upload_valid <= 1'b1;
        upload_req <= 1'b1;
    end else begin
        upload_valid <= 1'b0;
        upload_req <= 1'b0;
    end
end else begin
    upload_valid <= 1'b0;
    upload_req <= 1'b0;
end

// upload_source 保持不变
// （在初始化部分已设置为 UPLOAD_SOURCE_DC）
```

### 预期改进

| 采样率 | 修改前 | 修改后 |
|--------|--------|--------|
| 1 MHz | 970 KB/s ✅ | 970 KB/s ✅ |
| 5 MHz | 0 KB/s ❌ | 4.8 MB/s ✅ |
| 10 MHz | 0 KB/s ❌ | 9.5 MB/s ✅ |
| 20 MHz | 0 KB/s ❌ | 19 MB/s ✅ |
| 30 MHz | 0 KB/s ❌ | 28 MB/s ✅ |

**最大理论速率**: 60 MHz = 60 MB/s（受限于系统时钟）
**实际最大速率**: ~30 MB/s（受限于 USB High-Speed 和 FIFO）

---

## 修复方案 2: 保守优化（如果方案 1 有问题）

只修改状态机，保留 new_sample_flag 逻辑：

### 修改位置: 上传状态机（第 205-239 行）

**修改为（2 状态版本）**:
```verilog
case (upload_state)
    UP_IDLE: begin
        if ((handler_state == H_CAPTURING) && new_sample_flag) begin
            upload_data <= captured_data_sync;
            upload_valid <= 1'b1;
            upload_req <= 1'b1;
            upload_state <= UP_ACTIVE;  // 直接进入 ACTIVE
        end else begin
            upload_req <= 1'b0;
            upload_valid <= 1'b0;
        end
    end

    UP_ACTIVE: begin
        // 立即回到 IDLE，允许下一次采样
        upload_req <= 1'b0;
        upload_valid <= 1'b0;
        upload_state <= UP_IDLE;
    end

    default: begin
        upload_state <= UP_IDLE;
    end
endcase
```

### 预期改进

| 采样率 | 修改前 | 修改后 |
|--------|--------|--------|
| 1 MHz | 970 KB/s ✅ | 970 KB/s ✅ |
| 5 MHz | 0 KB/s ❌ | 2-3 MB/s ⚠️ |
| 10 MHz | 0 KB/s ❌ | 4-5 MB/s ⚠️ |

**最大理论速率**: 30 MHz（60 MHz ÷ 2 状态）

---

## 实施步骤

### 选项 A: 使用方案 1（激进优化）

1. 备份原文件：
   ```bash
   cp rtl/logic/digital_capture_handler.v rtl/logic/digital_capture_handler.v.bak
   ```

2. 手动编辑文件，应用上述修改

3. 综合、烧录

4. 测试：
   ```bash
   python software/test_usb_bandwidth.py
   ```

### 选项 B: 使用方案 2（保守优化）

只修改状态机部分，风险更低。

### 选项 C: 让我创建修改后的文件

我可以读取原文件，生成修改后的完整版本，你复制替换即可。

---

## 当前状态总结

✅ **成功**: 1 MHz @ 970 KB/s
❌ **失败**: >1 MHz → 0 KB/s
🎯 **目标**: 支持 5-30 MHz，达到 5-30 MB/s

请告诉我想使用哪个方案，我会帮你生成修改后的文件！
