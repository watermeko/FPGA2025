# WinUSB 驱动安装和使用指南

## 为什么使用 WinUSB？

### CDC 驱动 vs WinUSB

| 特性 | CDC 驱动 | WinUSB |
|------|---------|--------|
| **速率限制** | ~500 KB/s | 10-40 MB/s |
| **安装** | 自动（即插即用） | 需要手动安装 |
| **兼容性** | 串口工具通用 | 需要专用程序 |
| **适用场景** | 低速通信 | 高速数据采集 |

**结论**: 如果需要突破 500 KB/s 限制，必须使用 WinUSB！

---

## 步骤 1: 安装 Python 依赖

```bash
pip install pyusb
```

---

## 步骤 2: 下载 Zadig 工具

1. 访问 https://zadig.akeo.ie/
2. 下载 Zadig (无需安装，直接运行)
3. 以管理员权限运行 `zadig.exe`

---

## 步骤 3: 使用 Zadig 安装 WinUSB 驱动

### 3.1 找到你的设备

1. 将 FPGA 板连接到 PC
2. 在 Zadig 中，点击 **Options** → **List All Devices**
3. 在下拉列表中找到你的设备:
   ```
   USB Serial (USB\VID_33AA&PID_0000)
   或
   Gowinsemi USB2Serial
   ```

### 3.2 选择 WinUSB 驱动

1. 确保选择了正确的设备
2. 在驱动选择框中，选择 **WinUSB** (如图所示)
   ```
   [当前驱动] → [WinUSB (v6.1.7600.16385)]
   ```
3. 点击 **Replace Driver** 或 **Install Driver**

### 3.3 等待安装完成

- 安装过程大约 10-30 秒
- 完成后会显示 "The driver was installed successfully"

**⚠️ 重要提示**:
- 安装 WinUSB 后，CDC 串口功能会失效
- 原来的 COM 口会消失
- 只能使用 `diagnose_dc_winusb.py` 访问设备
- 如需恢复 CDC 驱动，需要重新安装原驱动或重新插拔设备

---

## 步骤 4: 验证安装

### 方法 1: 使用 Zadig 验证

再次打开 Zadig，检查驱动是否显示为 **WinUSB**

### 方法 2: 使用设备管理器

1. 打开设备管理器 (`devmgmt.msc`)
2. 查找 **通用串行总线设备** (Universal Serial Bus devices)
3. 应该看到 `USB Serial` 或类似名称的设备
4. 右键 → 属性 → 驱动程序 → 驱动程序提供商应为 **Microsoft**

### 方法 3: 使用 Python 脚本验证

```bash
python diagnose_dc_winusb.py --list
```

应该能看到:
```
🔍 系统中的所有 USB 设备

1. VID: 0x33AA, PID: 0x0000
   制造商: Gowinsemi
   产品:   USB2Serial
   总线:   1, 地址: 5
```

---

## 步骤 5: 运行 WinUSB 版本测试

```bash
python diagnose_dc_winusb.py
```

### 预期输出

```
🚀 DC 数据流诊断工具 - WinUSB 版本

⚡ 使用 USB Bulk 传输，可达到 10-40 MB/s

🔍 查找 USB 设备...
   VID: 0x33AA
   PID: 0x0000

✅ 找到设备!
   制造商: Gowinsemi
   产品:   USB2Serial
   总线:   1
   地址:   5

✅ 设备配置完成

📊 端点信息:
   EP 0x82 (IN ): Bulk, 512 bytes
   EP 0x02 (OUT): Bulk, 512 bytes

📊 选择采样率:
  1. 10 kHz (测试)
  2. 100 kHz
  3. 400 kHz
  4. 500 kHz (CDC 极限)
  5. 600 kHz
  6. 1 MHz
  ...
```

---

## 常见问题

### Q1: Zadig 找不到我的设备

**解决方案**:
1. 确保设备已连接并上电
2. 点击 Zadig 的 **Options** → **List All Devices**
3. 尝试拔插 USB 线
4. 检查设备管理器中是否有未知设备

---

### Q2: PyUSB 报错 "No backend available"

**原因**: 缺少 libusb 后端

**解决方案 (Windows)**:
1. 下载 libusb (https://github.com/libusb/libusb/releases)
2. 解压 `libusb-1.0.dll` 到以下位置之一:
   - `C:\Windows\System32\`
   - 或 Python 安装目录
   - 或脚本同目录

**或者安装 libusb-win32**:
```bash
pip install libusb-win32
```

---

### Q3: 运行脚本时报错 "Access denied"

**原因**: 权限不足

**解决方案**:
1. 以管理员权限运行 PowerShell 或 CMD
2. 或在 Zadig 安装驱动时勾选 "Create a Device Interface GUID"

---

### Q4: 速度仍然只有 500 KB/s

**可能原因**:
1. **WinUSB 驱动未正确安装**
   - 使用 Zadig 再次检查驱动
   - 确认是 WinUSB 而非 CDC

2. **仍在使用 CDC 版本脚本**
   - 确保运行的是 `diagnose_dc_winusb.py`
   - 不是 `diagnose_dc.py`

3. **FPGA 端 FIFO 瓶颈**
   - 检查跨时钟 FIFO 大小 (见下方优化建议)

---

### Q5: 如何恢复 CDC 驱动？

**方法 1: 重新插拔**
- 拔掉 USB 线
- 重新插入
- Windows 会自动重新安装 CDC 驱动

**方法 2: 设备管理器**
1. 设备管理器 → 找到设备
2. 右键 → 卸载设备
3. 勾选 "删除此设备的驱动程序软件"
4. 拔插 USB，Windows 重新安装 CDC 驱动

**方法 3: 使用 Zadig 切换回**
- 在 Zadig 中选择设备
- 选择 "usbser (v10.x.x.x)" 驱动
- 点击 "Replace Driver"

---

## FPGA 端优化建议

如果 WinUSB 速率仍然不理想，可以优化 FPGA 端 FIFO:

### 优化 1: 增大跨时钟 FIFO

编辑 `rtl/usb/sync_fifo/usb_fifo.v` 第 1318-1321 行:

**修改前**:
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (6  )  // 64 字节
  ,.AEMPT (1  )
  ,.AFULL (32 )  // 32 字节报满
)
```

**修改后**:
```verilog
clk_cross_fifo #(
   .DSIZE (8  )
  ,.ASIZE (10 )  // 1KB (从 64 字节增大)
  ,.AEMPT (1  )
  ,.AFULL (512)  // 512 字节报满
)
```

**预期效果**:
- 减少 FIFO 满导致的停-走行为
- 可能提升到 5-10 MB/s

---

### 优化 2: 增大 USB TX FIFO

编辑 `rtl/usb/sync_fifo/usb_fifo.v` 第 45 行:

**修改前**:
```verilog
`define EP2_IN_BUF_ASIZE  4'd12  // 4KB
```

**修改后**:
```verilog
`define EP2_IN_BUF_ASIZE  4'd13  // 8KB
```

---

## 性能对比测试

### CDC 驱动 (原版)

```bash
python diagnose_dc.py
```

**预期速率**: ~500 KB/s (极限)

---

### WinUSB 驱动 (新版)

```bash
python diagnose_dc_winusb.py
```

**预期速率**:
- **未优化 FIFO**: 1-5 MB/s (2-10x 提升)
- **优化后 FIFO**: 5-15 MB/s (10-30x 提升)
- **理论极限**: 30-40 MB/s (受 FPGA 处理能力限制)

---

## 对比 CDC vs WinUSB

| 测试场景 | CDC 驱动 | WinUSB (未优化) | WinUSB (优化) |
|---------|---------|----------------|--------------|
| 10 kHz | 10 KB/s | 10 KB/s | 10 KB/s |
| 100 kHz | 100 KB/s | 100 KB/s | 100 KB/s |
| 400 kHz | 400 KB/s | 400 KB/s | 400 KB/s |
| 500 kHz | 500 KB/s ⚠️ | 500 KB/s | 500 KB/s |
| 600 kHz | **500 KB/s 被限** ❌ | 600 KB/s ✅ | 600 KB/s ✅ |
| 1 MHz | **500 KB/s 被限** ❌ | 1 MB/s ✅ | 1 MB/s ✅ |
| 2 MHz | **500 KB/s 被限** ❌ | 2-3 MB/s ⚠️ | 2 MB/s ✅ |
| 5 MHz | **500 KB/s 被限** ❌ | 3-5 MB/s ⚠️ | 5 MB/s ✅ |
| 10 MHz | **500 KB/s 被限** ❌ | 5 MB/s ⚠️ | 8-10 MB/s ⚠️ |

**说明**:
- ✅ = 达到预期
- ⚠️ = 可能不稳定或低于理论值
- ❌ = 被限制

---

## 总结

### 何时使用 CDC？
- 速率要求 < 500 KB/s
- 需要即插即用
- 使用串口工具 (PuTTY, minicom)

### 何时使用 WinUSB？
- 速率要求 > 500 KB/s ✅
- 高速数据采集 ✅
- 可以接受手动安装驱动
- 需要使用专用 Python 脚本

---

## 下一步

1. **安装 WinUSB 驱动** (使用 Zadig)
2. **运行测试** (`python diagnose_dc_winusb.py`)
3. **对比 CDC 和 WinUSB 性能**
4. **如需进一步优化，修改 FPGA FIFO**
5. **确定最终方案** (CDC 或 WinUSB)

祝测试顺利！🚀
