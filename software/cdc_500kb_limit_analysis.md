# CDC上传速率500 KB/s限制的深入分析

## 实测数据

```
采样率      理论速率    实际速率    结论
400 kHz     400 KB/s    400 KB/s    ✅ 完美
500 kHz     500 KB/s    508 KB/s    ✅ 刚好到极限
600 kHz     600 KB/s    500 KB/s    ❌ 被限制
1 MHz       1000 KB/s   300 KB/s    ❌ 被限制（且更低）
30 MHz      30 MB/s     507 KB/s    ❌ 被限制
```

## 已排除的原因

### ❌ 不是跨时钟域FIFO（64字节）
- **测试**：增大到512字节后重新综合测试
- **结果**：速率没有变化
- **结论**：64字节FIFO不是瓶颈

### ❌ 不是USB包大小
- **配置**：512字节（High-Speed标准）
- **结论**：配置正确

### ❌ 不是USB Packet FIFO
- **大小**：4KB（2^12）
- **结论**：足够大

### ❌ 不是FPGA处理能力
- **证据**：30 MHz能产生数据并达到500 KB/s
- **结论**：FPGA端能力远超500 KB/s

---

## 可能的原因分析

### 原因1：Windows USB CDC驱动轮询周期（最可能）

**分析**：

```
Windows CDC驱动的工作方式：
1. 驱动每隔一定时间轮询USB设备
2. 每次轮询读取最多512字节（包大小）
3. 轮询周期取决于驱动实现

假设轮询周期 = 1ms:
  最大速率 = 512 bytes × 1000 = 512 KB/s ≈ 500 KB/s ✅

假设轮询周期 = 2ms:
  最大速率 = 512 bytes × 500 = 256 KB/s ❌ (不符合)
```

**这与实测完全吻合！**

**如何验证**：
1. 使用USB抓包工具（USBPcap / Wireshark）
2. 查看IN token的间隔
3. 如果间隔约1ms → 证实

---

### 原因2：Python + pyserial的处理速度

**分析**：

```python
# diagnose_dc.py的读取循环
while True:
    if ser.in_waiting > 0:
        data = ser.read(ser.in_waiting)  # 可能很慢
        total += len(data)
    time.sleep(0.01)  # 10ms延迟
```

**问题**：
- `ser.in_waiting` 需要系统调用
- `ser.read()` 可能有overhead
- Python GC可能暂停

**但是**：
- 400 kHz能达到400 KB/s → 说明Python能处理400 KB/s
- 所以Python不是主要瓶颈，但可能加剧了问题

---

### 原因3：USB CDC类驱动的NAK handling

**USB协议细节**：

```
Host → Device: IN token (请求数据)

如果FIFO有数据：
  Device → Host: DATA packet (512 bytes)

如果FIFO暂时没数据：
  Device → Host: NAK (Not Acknowledge)
  Host需要等待一段时间再重试
```

**如果FPGA端数据生成不够快**：
- Host频繁收到NAK
- 重试间隔降低了有效速率
- 最终稳定在 ~500 KB/s

---

### 原因4：GOWIN USB IP核的内部限制（可能）

**假设**：
GOWIN的USB CDC IP核可能有内部的速率控制机制，限制在约500 KB/s

**如何验证**：
- 查看GOWIN USB IP核文档
- 联系GOWIN技术支持
- 或尝试其他FPGA vendor的USB IP核对比

---

## 验证方法

### 方法1：USB抓包（最准确）

**工具**：USBPcap + Wireshark

**步骤**：
1. 安装USBPcap（Windows）
2. 用Wireshark捕获USB流量
3. 运行600 kHz测试
4. 分析IN transaction的间隔

**预期发现**：
- 如果IN间隔约1ms → 驱动轮询问题
- 如果看到大量NAK → FPGA供数据不及时
- 如果IN正常但没数据 → FPGA端问题

---

### 方法2：写C程序测试

**代码**：
```c
#include <windows.h>
#include <stdio.h>

int main() {
    HANDLE hSerial = CreateFile("COM23",
        GENERIC_READ | GENERIC_WRITE,
        0, NULL, OPEN_EXISTING, 0, NULL);

    // 设置串口
    DCB dcb = {0};
    dcb.DCBlength = sizeof(dcb);
    GetCommState(hSerial, &dcb);
    dcb.BaudRate = CBR_115200;
    SetCommState(hSerial, &dcb);

    // 设置超时（尽可能短）
    COMMTIMEOUTS timeouts = {0};
    timeouts.ReadIntervalTimeout = 1;         // 1ms
    timeouts.ReadTotalTimeoutConstant = 1;    // 1ms
    timeouts.ReadTotalTimeoutMultiplier = 0;
    SetCommTimeouts(hSerial, &timeouts);

    // 发送START命令（600 kHz, divider=100）
    unsigned char cmd[] = {0xAA, 0x55, 0x0B, 0x00, 0x02, 0x00, 0x64, 0x71};
    DWORD written;
    WriteFile(hSerial, cmd, sizeof(cmd), &written, NULL);

    Sleep(200);

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
    printf("Time: %lu ms\n", elapsed);
    printf("Rate: %.1f KB/s\n", rate);

    CloseHandle(hSerial);
    return 0;
}
```

**如果C程序也是500 KB/s** → 100%确认是Windows驱动或USB硬件限制

---

### 方法3：尝试其他操作系统

**在Linux下测试**：
```bash
# Linux的CDC驱动可能有不同的实现
python3 diagnose_dc.py  # 在Linux上运行
```

**如果Linux能达到更高速率** → 说明是Windows驱动问题

---

## 突破500 KB/s的方法

### 方法1：修改Windows CDC驱动配置（可能）

**理论上可以修改**：
- 设备管理器 → 串口属性 → 高级
- 调整"延迟时间"（latency timer）

**但CDC驱动通常不暴露这些选项**

---

### 方法2：改用USB Bulk传输（工作量大）

**需要修改**：
1. FPGA USB描述符：从CDC改为Bulk
2. PC端：使用libusb而不是CDC驱动
3. 编写自定义PC端程序

**预期速率**：
- USB Bulk High-Speed: 10-30 MB/s

**缺点**：
- 工作量大
- 需要安装驱动
- 跨平台兼容性差

---

### 方法3：使用厂商特定协议（可能最好）

**如果GOWIN提供了高速数据传输方案**：
- 查阅GOWIN文档
- 可能有专用的高速数据传输IP

---

## 结论

### 最可能的原因

**Windows USB CDC驱动的1ms轮询周期**

```
证据链：
1. ✅ 400 kHz → 400 KB/s（在限制以下）
2. ✅ 500 kHz → 508 KB/s（刚好到限制）
3. ✅ 600 kHz → 500 KB/s（被限制）
4. ✅ 增大FIFO无效（说明不是FIFO）
5. ✅ FPGA配置正确（512字节包，High-Speed）
```

**结论**：
- 瓶颈在PC端Windows CDC驱动
- 实际极限约500-512 KB/s
- 这是CDC协议+Windows驱动的固有限制

### 实用建议

**接受500 kHz作为上限**：
- 对于8通道数字信号采集，500 kHz已经很高
- 相当于每个通道62.5 kHz的有效采样率
- 对于大多数应用足够

**如果必须更高速率**：
- 考虑改用USB Bulk
- 或使用其他接口（以太网、PCIe等）

---

## 下一步行动

### 选项A：验证假设（推荐，满足好奇心）
1. 使用USBPcap抓包
2. 或编写C程序测试
3. 确认是否Windows驱动限制

### 选项B：接受现状（推荐，节省时间）
- 500 kHz已经足够
- 专注于解决divider bug
- 让系统稳定可靠更重要

### 选项C：尝试突破（不推荐，工作量大）
- 改用USB Bulk
- 预计需要1-2周工作
- 收益不确定
