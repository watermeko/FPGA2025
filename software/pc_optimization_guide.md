# PC端CDC速率优化方案

## 问题分析

如果现象是"逐渐变慢然后完全停止"，最可能的原因是：

```
Python读取循环：
  ↓ 太慢，只有几KB/s
Windows CDC缓冲区（~24KB）：
  ↓ 逐渐填满（3秒填满）
USB FIFO（4KB）：
  ↓ 也满了
FPGA继续发送：
  ↓ 数据丢失或阻塞
结果：完全卡住
```

---

## 解决方案层次

### 🟢 初级方案：优化Python代码（最简单）

#### 方案1：增大读取缓冲区

**当前可能的问题**：
```python
while True:
    data = ser.read(ser.in_waiting)  # 每次只读一点
    time.sleep(0.01)  # 还有延迟！
```

**优化后**：
```python
while True:
    # 一次读取更大块
    data = ser.read(65536)  # 64KB缓冲区
    # 不要sleep，持续读取
```

**创建优化版本**：

```python
#!/usr/bin/env python3
"""
优化的CDC读取工具
"""

import serial
import time

def optimized_read(port, sample_rate, duration=10):
    """优化的读取方法"""

    ser = serial.Serial(
        port=port,
        baudrate=115200,
        timeout=0.01,  # 短超时
        # 增大OS缓冲区
        write_timeout=None,
        inter_byte_timeout=None
    )

    # 设置更大的接收缓冲区（Windows）
    # 这可能需要管理员权限
    try:
        ser.set_buffer_size(rx_size=65536, tx_size=4096)
    except:
        print("⚠️  无法设置缓冲区大小（可能需要管理员权限）")

    # 发送启动命令
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate
    cmd = 0x0B
    len_h, len_l = 0x00, 0x02
    div_h, div_l = (divider >> 8) & 0xFF, divider & 0xFF
    checksum = (cmd + len_h + len_l + div_h + div_l) & 0xFF
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    ser.write(full_cmd)
    time.sleep(0.1)

    # 优化的读取循环
    total_bytes = 0
    start_time = time.time()

    print("开始优化读取...")

    while time.time() - start_time < duration:
        # 方法1：读取尽可能多的数据
        chunk = ser.read(65536)  # 尝试读取64KB

        if chunk:
            total_bytes += len(chunk)

    elapsed = time.time() - start_time
    avg_rate = total_bytes / elapsed

    # 停止
    stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
    ser.write(stop_cmd)
    ser.close()

    print(f"\n优化结果:")
    print(f"总接收: {total_bytes:,} bytes ({total_bytes/1024:.1f} KB)")
    print(f"速率: {avg_rate/1024:.1f} KB/s ({avg_rate/1024/1024:.2f} MB/s)")

    return avg_rate

if __name__ == "__main__":
    import serial.tools.list_ports

    ports = list(serial.tools.list_ports.comports())
    print("可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device}")

    port_idx = int(input("\n选择串口: ")) - 1
    selected_port = ports[port_idx].device

    rate = optimized_read(selected_port, 10000, 10)

    if rate > 100 * 1024:  # > 100 KB/s
        print("\n✅ 优化有效！速率显著提升")
    else:
        print("\n⚠️  速率仍然很低，需要更深层次的优化")
```

保存为 `F:\FPGA2025\software\optimized_read.py`

---

#### 方案2：使用线程分离读取和处理

**当前问题**：读取和处理在同一线程，可能互相阻塞

**优化**：
```python
import threading
import queue

def reader_thread(ser, data_queue):
    """专门的读取线程"""
    while True:
        chunk = ser.read(65536)
        if chunk:
            data_queue.put(chunk)

def main():
    data_queue = queue.Queue(maxsize=100)

    # 启动读取线程
    thread = threading.Thread(target=reader_thread, args=(ser, data_queue))
    thread.daemon = True
    thread.start()

    # 主线程处理数据
    while True:
        try:
            chunk = data_queue.get(timeout=1)
            # 处理数据
        except queue.Empty:
            pass
```

---

### 🟡 中级方案：调整系统配置

#### 方案3：增大Windows USB缓冲区

**步骤**：

1. 打开设备管理器
2. 找到你的USB CDC设备（端口 COM3/COM4等）
3. 右键 → 属性 → 端口设置 → 高级
4. 设置：
   - 接收缓冲区：4096 → **65536**
   - 传输缓冲区：4096 → **65536**

**注意**：不是所有驱动都支持这个设置

---

#### 方案4：禁用流控制

在Python代码中：
```python
ser = serial.Serial(
    port='COM3',
    baudrate=115200,
    rtscts=False,   # 禁用硬件流控
    dsrdtr=False,   # 禁用DTR/DSR
    xonxoff=False   # 禁用软件流控
)
```

---

### 🔴 高级方案：替换Python

#### 方案5：使用C/C++程序

**为什么C更快**：
- 无GC（垃圾回收）开销
- 直接系统调用
- 更高效的内存管理

**简单的C程序**：
```c
// fast_read.c
#include <windows.h>
#include <stdio.h>

int main() {
    HANDLE hSerial = CreateFile("COM3",
        GENERIC_READ | GENERIC_WRITE,
        0, NULL, OPEN_EXISTING, 0, NULL);

    if (hSerial == INVALID_HANDLE_VALUE) {
        printf("Error opening COM port\n");
        return 1;
    }

    // 设置串口参数
    DCB dcbSerialParams = {0};
    dcbSerialParams.DCBlength = sizeof(dcbSerialParams);
    GetCommState(hSerial, &dcbSerialParams);
    dcbSerialParams.BaudRate = CBR_115200;
    SetCommState(hSerial, &dcbSerialParams);

    // 设置超时
    COMMTIMEOUTS timeouts = {0};
    timeouts.ReadIntervalTimeout = 50;
    timeouts.ReadTotalTimeoutConstant = 50;
    timeouts.ReadTotalTimeoutMultiplier = 10;
    SetCommTimeouts(hSerial, &timeouts);

    // 发送启动命令
    unsigned char cmd[] = {0xAA, 0x55, 0x0B, 0x00, 0x02, 0x09, 0xC4, 0xDA};
    DWORD written;
    WriteFile(hSerial, cmd, sizeof(cmd), &written, NULL);

    // 快速读取
    unsigned char buffer[65536];
    DWORD read;
    long long total = 0;
    DWORD start = GetTickCount();

    while (GetTickCount() - start < 10000) {  // 10秒
        if (ReadFile(hSerial, buffer, sizeof(buffer), &read, NULL)) {
            total += read;
        }
    }

    DWORD elapsed = GetTickCount() - start;
    double rate = (double)total / elapsed * 1000 / 1024;

    printf("Total: %lld bytes\n", total);
    printf("Rate: %.1f KB/s\n", rate);

    CloseHandle(hSerial);
    return 0;
}
```

编译：
```bash
gcc fast_read.c -o fast_read.exe
```

---

#### 方案6：使用PyUSB/libusb直接访问USB

**跳过CDC层，直接USB Bulk传输**：

```python
import usb.core
import usb.util

# 找到设备
dev = usb.core.find(idVendor=0x33AA, idProduct=0x0120)

if dev is None:
    raise ValueError('Device not found')

# 声明接口
dev.set_configuration()
cfg = dev.get_active_configuration()
intf = cfg[(0,0)]

# 找到端点
ep_in = usb.util.find_descriptor(
    intf,
    custom_match=lambda e: usb.util.endpoint_direction(e.bEndpointAddress) == usb.util.ENDPOINT_IN
)

# 直接读取
while True:
    data = ep_in.read(512, timeout=100)
    # 处理数据
```

**优点**：
- 绕过CDC驱动
- 直接USB Bulk传输
- 理论速度更快

**缺点**：
- 需要修改FPGA USB配置（从CDC改为Bulk）
- 需要自定义驱动或libusb驱动

---

### 🟣 终极方案：修改FPGA USB架构

#### 方案7：改用USB Bulk而非CDC

**当前**：USB CDC (虚拟串口)
- 优点：Windows自动识别
- 缺点：速率限制（10-15 MB/s实际）

**改为**：USB Bulk传输
- 优点：速率高（30-40 MB/s）
- 缺点：需要自定义驱动

这需要修改FPGA的USB部分，工作量大。

---

## 推荐的实施顺序

### 第1步：运行优化的Python代码（5分钟）

```bash
# 创建优化版本
python F:\FPGA2025\software\optimized_read.py
```

**预期**：
- 如果速率提升到 100+ KB/s：说明是Python代码问题 ✅
- 如果仍然只有 10-20 KB/s：说明是更深层的问题

---

### 第2步：调整Windows设置（10分钟）

1. 增大USB缓冲区（设备管理器）
2. 禁用流控制
3. 再次测试

---

### 第3步：如果仍然慢，考虑C程序（30分钟）

编译运行C程序，看速率是否提升

---

### 第4步：如果还是慢，深入排查

可能原因：
- Windows USB驱动配置
- USB线缆质量
- FPGA USB时序问题
- 其他系统级问题

---

## 诊断决策树

```
运行优化Python
    ↓
速率 > 100 KB/s?
  ├─ 是 → ✅ Python代码问题，已解决
  └─ 否 → 调整Windows设置
             ↓
         速率 > 100 KB/s?
           ├─ 是 → ✅ Windows配置问题，已解决
           └─ 否 → 使用C程序测试
                      ↓
                  速率 > 1 MB/s?
                    ├─ 是 → ✅ Python性能问题
                    └─ 否 → 深入排查USB驱动/硬件
```

---

## 我现在帮你做什么？

1. **创建优化的Python测试脚本** ✅
2. **创建C测试程序代码**
3. **创建诊断工具**
4. **写详细的Windows配置指南**

你想先试哪个方案？我建议从最简单的优化Python代码开始！
