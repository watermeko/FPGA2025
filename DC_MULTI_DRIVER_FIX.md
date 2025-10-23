# 多驱动错误修复

## ❌ 错误信息
```
ERROR (EX2000) : Net 'divider_changed' is constantly driven from multiple places
```

## 🔍 问题原因

`divider_changed` 信号在两个不同的 `always` 块中被赋值：

1. **采样时钟分频器 always 块** (第 78-101 行)
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       ...
       divider_changed <= 1'b0;  // ❌ 第一次驱动
   ```

2. **主状态机 always 块** (第 147-210 行)
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       ...
       divider_changed <= 1'b1;  // ❌ 第二次驱动
   ```

在 Verilog 中，一个 `reg` 信号只能在一个 `always` 块中被赋值，否则会造成多驱动冲突。

## ✅ 修复方案

将信号改名为 `reset_sample_counter`，并**只在状态机 always 块中赋值**：

### 修改 1: 信号声明和采样逻辑 (第 76 行)
```verilog
reg reset_sample_counter;  // 改名，避免混淆

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_counter <= 16'd0;
        sample_tick <= 1'b0;
        // ✅ 不再在这里驱动 reset_sample_counter
    end else begin
        sample_tick <= 1'b0;

        // ✅ 只读取 reset_sample_counter，不写入
        if (reset_sample_counter) begin
            sample_counter <= 16'd0;
        end else if (capture_enable) begin
            ...
        end
    end
end
```

### 修改 2: 状态机中驱动信号 (第 153, 162, 191 行)
```verilog
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reset_sample_counter <= 1'b0;  // ✅ 初始化
    end else begin
        reset_sample_counter <= 1'b0;  // ✅ 默认清除 (第 162 行)

        case (handler_state)
            H_RX_CMD: begin
                if (cmd_done) begin
                    sample_divider <= {cmd_data_buf[0], cmd_data_buf[1]};
                    reset_sample_counter <= 1'b1;  // ✅ 设置标志 (第 191 行)
                    capture_enable <= 1'b1;
                    handler_state <= H_CAPTURING;
                end
            end
        endcase
    end
end
```

## 🎯 修复效果

现在 `reset_sample_counter` 只在一个 `always` 块中被驱动，符合 Verilog 语法规则：

- ✅ **状态机 always 块**: 写入 `reset_sample_counter`
- ✅ **采样时钟 always 块**: 只读取 `reset_sample_counter`

## 📋 验证

重新综合应该不再出现 EX2000 错误：

```bash
# 在 GOWIN EDA 中:
# 1. Synthesize → 应该成功，无 EX2000 错误
# 2. Place & Route
# 3. Program Device
```

---

**功能完全相同，只是修复了多驱动问题！**
