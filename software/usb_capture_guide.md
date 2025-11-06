# USB抓包验证指南

## 工具安装

### 1. 安装USBPcap
下载地址：https://desowin.org/usbpcap/
或使用Wireshark自带的USBPcap

### 2. 安装Wireshark
下载地址：https://www.wireshark.org/

---

## 抓包步骤

### 步骤1：启动Wireshark
1. 以管理员权限运行Wireshark
2. 选择USBPcap接口
3. 找到你的USB CDC设备（COM23）

### 步骤2：设置过滤器
在Wireshark中设置显示过滤器：
```
usb.endpoint_address.direction == 1
```
这样只显示IN传输（从设备到主机）

### 步骤3：开始抓包
```bash
# 在另一个终端运行
python diagnose_dc.py
# 选择600 kHz测试
```

### 步骤4：分析数据

**查看内容**：
1. **IN token间隔**
   - 右键某个IN token → Follow → USB Stream
   - 查看时间戳（Time列）
   - 计算相邻两个IN token的时间差

2. **查找模式**
   - 如果间隔约1ms → 证明是驱动轮询限制
   - 如果间隔更短但有NAK → FPGA供数据不及时
   - 如果间隔不规则 → 其他因素

---

## 预期结果

### 情况A：如果是驱动1ms轮询
```
Packet | Time    | Type  | Length | 说明
-------|---------|-------|--------|-----
100    | 1.000   | IN    | 0      | Host请求数据
101    | 1.000   | DATA0 | 512    | Device发送512字节
102    | 1.001   | IN    | 0      | 1ms后再次请求 ← 关键！
103    | 1.001   | DATA0 | 512    | Device发送512字节
104    | 1.002   | IN    | 0      | 又是1ms间隔
...
```

**计算**：512字节 × 1000次/秒 = 512 KB/s

### 情况B：如果是FPGA端问题
```
Packet | Time    | Type  | Length | 说明
-------|---------|-------|--------|-----
100    | 1.000   | IN    | 0      | Host请求数据
101    | 1.000   | NAK   | 0      | Device暂无数据 ← 关键！
102    | 1.000   | IN    | 0      | 立即重试
103    | 1.000   | NAK   | 0      | 还是没有
104    | 1.001   | IN    | 0      |
105    | 1.001   | DATA0 | 512    | 终于有数据
...
```

### 情况C：如果是Python读取慢
```
Packet | Time    | Type  | Length | 说明
-------|---------|-------|--------|-----
100    | 1.000   | IN    | 0      | Host请求
101    | 1.000   | DATA0 | 512    | Device发送
...（多次成功传输）
110    | 1.005   | IN    | 0      | Host请求
111    | 1.005   | DATA0 | 512    | Device发送
...（突然中断）
150    | 1.020   | IN    | 0      | 15ms后才再次请求 ← Python处理慢
```

---

## 如何判断

| 现象 | 原因 | 证据 |
|------|------|------|
| IN间隔固定约1ms | Windows驱动轮询限制 | 规律的1ms间隔 |
| IN频繁但收到NAK | FPGA供数据不及时 | 大量NAK响应 |
| IN间隔不规则，时长时短 | Python读取速度限制 | 有时快有时慢 |
| IN正常但数据量突然减少 | FIFO或FPGA问题 | 传输中断或变慢 |

---

## 快速判断脚本

如果你不想手动分析Wireshark，可以用这个脚本：

```python
# analyze_usb_capture.py
import pyshark

capture = pyshark.FileCapture('usb_capture.pcapng',
                               display_filter='usb.endpoint_address.direction == 1')

in_times = []
nak_count = 0
data_count = 0

for packet in capture:
    try:
        if 'IN' in str(packet.usb.type):
            in_times.append(float(packet.sniff_timestamp))
        if 'NAK' in str(packet.usb.response):
            nak_count += 1
        if 'DATA' in str(packet.usb.type):
            data_count += 1
    except:
        pass

# 计算IN间隔
intervals = [in_times[i+1] - in_times[i] for i in range(len(in_times)-1)]
avg_interval = sum(intervals) / len(intervals) if intervals else 0

print(f"平均IN间隔: {avg_interval*1000:.3f} ms")
print(f"NAK次数: {nak_count}")
print(f"DATA次数: {data_count}")
print(f"NAK比例: {nak_count/(nak_count+data_count)*100:.1f}%")

if avg_interval > 0.0009 and avg_interval < 0.0011:
    print("\n结论：Windows驱动1ms轮询限制！")
elif nak_count > data_count * 0.5:
    print("\n结论：FPGA供数据不及时！")
else:
    print("\n结论：其他因素")
```

---

## 简化方法：不用抓包

如果你觉得抓包太复杂，可以用这个简单测试：

### 测试Python是否瓶颈

运行这个优化的Python脚本：

```python
import serial
import time

ser = serial.Serial('COM23', 115200, timeout=0.001)

# 发送600 kHz命令
cmd = bytes([0xAA, 0x55, 0x0B, 0x00, 0x02, 0x00, 0x64, 0x71])
ser.write(cmd)
time.sleep(0.2)

# 疯狂读取，不做任何处理
total = 0
start = time.time()

while time.time() - start < 10:
    data = ser.read(65536)  # 尝试读64KB
    total += len(data)
    # 不sleep，不print，不做任何处理

elapsed = time.time() - start
print(f"速率: {total/elapsed/1024:.1f} KB/s")

ser.close()
```

**如果这个脚本也是500 KB/s** → 说明不是Python慢
**如果能达到600+ KB/s** → 说明是原脚本的问题
