# FIFO容量修改记录

## 修改日期
2025-10-22

## 目的
解决CDC上传速率被限制在~500 KB/s的问题

## 修改内容

### 文件：`F:\FPGA2025\rtl\usb\sync_fifo\usb_fifo.v`

### 修改1：TX方向跨时钟域FIFO（Line 1317-1321）

**修改前**：
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (6  )  // 64 bytes
  ,.AEMPT (1  )
  ,.AFULL (32 )
)clk_cross_fifo
```

**修改后**：
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (9  )  // 512 bytes (8x larger)
  ,.AEMPT (8  )
  ,.AFULL (256)
)clk_cross_fifo
```

### 修改2：RX方向跨时钟域FIFO（Line 1497-1501）

**修改前**：
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (6  )  // 64 bytes
  ,.AEMPT (1  )
  ,.AFULL (32 )
)clk_cross_fifo
```

**修改后**：
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (9  )  // 512 bytes (8x larger)
  ,.AEMPT (8  )
  ,.AFULL (256)
)clk_cross_fifo
```

---

## 预期效果

### 容量变化
- FIFO容量：64字节 → 512字节（8倍提升）
- 填满时间@500KB/s：128μs → 1ms（约8倍延长）

### 速率提升
- 当前极限：~500 KB/s
- 预期极限：1-4 MB/s（取决于USB CDC协议限制）

---

## 测试方法

### 测试1：验证基本功能
```bash
python F:\FPGA2025\software\diagnose_dc.py
# 选择 7 (100 kHz)
# 预期：100 KB/s，稳定
```

### 测试2：验证500 kHz
```bash
python F:\FPGA2025\software\diagnose_dc.py
# 选择 10 (500 kHz)
# 预期：500 KB/s，稳定
```

### 测试3：验证600 kHz（关键测试）
```bash
python F:\FPGA2025\software\diagnose_dc.py
# 选择 11 (600 kHz)
# 修改前：~500 KB/s（被限制）
# 修改后：应该达到 ~600 KB/s
```

### 测试4：验证1 MHz
```bash
python F:\FPGA2025\software\diagnose_dc.py
# 选择 12 (1 MHz)
# 修改前：~300 KB/s（divider=60问题）
# 修改后：应该达到接近 1 MB/s（如果divider=60不是根本问题）
#        或者仍然300 KB/s（说明divider=60是独立问题）
```

---

## 回退方法

如果修改后出现问题（综合失败、功能异常等），按以下步骤回退：

### 方法1：手动回退

编辑文件 `F:\FPGA2025\rtl\usb\sync_fifo\usb_fifo.v`

**第一处（约Line 1317-1321）**：
```verilog
# 将这些行改回原值
.ASIZE (6  )  // 改回 6
.AEMPT (1  )  // 改回 1
.AFULL (32 )  // 改回 32
```

**第二处（约Line 1497-1501）**：
```verilog
# 将这些行改回原值
.ASIZE (6  )  // 改回 6
.AEMPT (1  )  // 改回 1
.AFULL (32 )  // 改回 32
```

### 方法2：使用git回退（如果有版本控制）

```bash
cd F:\FPGA2025
git checkout F:\FPGA2025\rtl\usb\sync_fifo\usb_fifo.v
```

---

## 可能的问题和解决

### 问题1：综合资源不足

**症状**：综合时报告BRAM不足

**原因**：512字节FIFO需要更多BRAM资源

**解决**：
- 降低ASIZE到8（256字节）
- 或降低ASIZE到7（128字节）

### 问题2：时序不满足

**症状**：综合报告时序违规

**原因**：更大的FIFO可能影响时序

**解决**：
- 检查时序报告
- 可能需要添加时序约束
- 考虑降低FIFO大小

### 问题3：功能异常

**症状**：数据传输出错、系统不稳定

**原因**：阈值设置不当

**解决**：
- 尝试调整AEMPT和AFULL的值
- 建议值：
  - ASIZE=8: AEMPT=4, AFULL=128
  - ASIZE=9: AEMPT=8, AFULL=256

---

## 后续优化

如果修改成功但速率仍未达到预期：

### 检查项1：USB包发送频率
查看USB CDC配置，可能需要优化包发送策略

### 检查项2：PC端读取速度
使用C程序替代Python测试，排除PC端瓶颈

### 检查项3：USB CDC协议开销
USB CDC协议有固定开销，实际极限可能在2-4 MB/s

---

## 修改历史

| 日期 | 版本 | ASIZE | 说明 |
|------|------|-------|------|
| 2025-10-22 | 原始 | 6 (64B) | 原始配置 |
| 2025-10-22 | v1 | 9 (512B) | 首次修改，提升8倍 |

---

## 注意事项

1. **重新综合后需要重新烧录FPGA**
2. **测试前确保FPGA复位**
3. **记录测试结果对比修改前后的差异**
4. **如果有问题立即回退，不要强行使用**
