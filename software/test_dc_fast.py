#!/usr/bin/env python3
"""
优化版 DC 测试脚本 - 使用大缓冲区提高接收速率
"""

import serial
import serial.tools.list_ports
import time
import threading

def calculate_checksum(data):
    """计算校验和"""
    return sum(data) & 0xFF

def generate_dc_start_command(sample_rate_hz):
    """生成 DC 启动命令"""
    SYSTEM_CLK = 60_000_000
    divider = SYSTEM_CLK // sample_rate_hz

    cmd = 0x0B
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    checksum = calculate_checksum([cmd, len_h, len_l, div_h, div_l])
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    return full_cmd, divider

def list_ports():
    """列出可用串口"""
    ports = serial.tools.list_ports.comports()
    print("\n可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device} - {port.description}")
    return [port.device for port in ports]

class HighSpeedReceiver:
    """高速接收器 - 使用后台线程"""

    def __init__(self, ser):
        self.ser = ser
        self.running = False
        self.total_bytes = 0
        self.data_buffer = []
        self.lock = threading.Lock()

    def start(self):
        """启动接收线程"""
        self.running = True
        self.thread = threading.Thread(target=self._receive_loop, daemon=True)
        self.thread.start()

    def stop(self):
        """停止接收"""
        self.running = False
        if hasattr(self, 'thread'):
            self.thread.join(timeout=1)

    def _receive_loop(self):
        """后台接收循环"""
        while self.running:
            try:
                # 一次读取大量数据
                if self.ser.in_waiting > 0:
                    chunk_size = min(self.ser.in_waiting, 8192)  # 最多 8KB
                    data = self.ser.read(chunk_size)

                    with self.lock:
                        self.total_bytes += len(data)
                        # 只保存前 100 字节用于分析
                        if len(self.data_buffer) < 100:
                            self.data_buffer.extend(data[:100 - len(self.data_buffer)])
            except:
                pass

    def get_stats(self):
        """获取统计信息"""
        with self.lock:
            return self.total_bytes, list(self.data_buffer)

def test_dc_high_speed(port, sample_rate_hz, duration=5):
    """
    高速 DC 测试

    Args:
        port: 串口名称
        sample_rate_hz: 采样率
        duration: 测试时长（秒）
    """
    try:
        # 打开串口，设置大缓冲
        ser = serial.Serial(
            port=port,
            baudrate=115200,
            timeout=0.01,
            write_timeout=1,
            # 增加缓冲区大小
            # write_buffer_size=65536,
            # read_buffer_size=65536
        )
        print(f"\n✅ 已连接到 {port}")

        # 生成命令
        cmd, divider = generate_dc_start_command(sample_rate_hz)
        actual_rate = 60_000_000 / divider

        print(f"\n📊 配置:")
        print(f"   目标采样率: {sample_rate_hz} Hz")
        print(f"   分频系数:   {divider}")
        print(f"   实际采样率: {actual_rate:.2f} Hz")
        print(f"   命令 (HEX): {' '.join([f'{b:02X}' for b in cmd])}")

        # 创建高速接收器
        receiver = HighSpeedReceiver(ser)

        # 发送命令
        print(f"\n📤 发送 DC START 命令...")
        ser.write(cmd)
        time.sleep(0.2)  # 等待命令处理

        # 启动后台接收
        print(f"⏱️  高速接收数据 {duration} 秒...\n")
        receiver.start()

        start = time.time()
        last_print = start

        # 主线程只负责打印统计
        while time.time() - start < duration:
            time.sleep(0.5)  # 每 0.5 秒打印一次

            elapsed = time.time() - start
            count, _ = receiver.get_stats()
            rate = count / elapsed if elapsed > 0 else 0

            print(f"[{elapsed:.1f}s] 接收: {count:,} bytes | 速率: {rate:,.0f} bytes/s ({rate/1000:.1f} KB/s)")

        # 停止接收
        receiver.stop()

        # 发送停止命令
        stop_cmd = bytes([0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C])
        print(f"\n📤 发送 DC STOP 命令: {' '.join([f'{b:02X}' for b in stop_cmd])}")
        ser.write(stop_cmd)
        time.sleep(0.2)

        # 最终统计
        total_time = time.time() - start
        final_count, first_bytes = receiver.get_stats()
        avg_rate = final_count / total_time if total_time > 0 else 0

        print(f"\n{'='*60}")
        print(f"📊 测试结果")
        print(f"{'='*60}")
        print(f"总接收字节: {final_count:,} bytes")
        print(f"测试时长:   {total_time:.2f} 秒")
        print(f"平均速率:   {avg_rate:,.0f} bytes/s ({avg_rate/1000:.1f} KB/s)")
        print(f"理论速率:   {actual_rate:,.0f} bytes/s ({actual_rate/1000:.1f} KB/s)")

        if avg_rate > 0:
            efficiency = (avg_rate / actual_rate) * 100
            print(f"实际效率:   {efficiency:.1f}%")

        if len(first_bytes) > 0:
            print(f"\n前 20 字节 (HEX):")
            hex_str = ' '.join([f'{b:02X}' for b in first_bytes[:20]])
            print(f"   {hex_str}")

            print(f"\n数据模式分析:")
            # 分析重复模式
            unique_bytes = set(first_bytes[:20])
            print(f"   唯一字节数: {len(unique_bytes)}")
            print(f"   唯一字节值: {', '.join([f'0x{b:02X}' for b in sorted(unique_bytes)])}")

            # 显示每个 bit 的状态
            if len(first_bytes) >= 2:
                byte0 = first_bytes[0]
                byte1 = first_bytes[1]

                print(f"\n   Byte[0] = 0x{byte0:02X} = {byte0:08b}")
                print(f"   Byte[1] = 0x{byte1:02X} = {byte1:08b}")
                print(f"   差异位:")

                diff = byte0 ^ byte1
                for i in range(8):
                    if diff & (1 << i):
                        print(f"      → Bit[{i}] (dc_signal_in[{i}]) 在变化")

        print(f"{'='*60}\n")

        # 诊断
        if final_count == 0:
            print("❌ 未接收到任何数据")
        elif avg_rate > actual_rate * 0.8:
            print(f"✅ 接收速率优秀！（> 80% 理论值）")
        elif avg_rate > actual_rate * 0.5:
            print(f"⚠️  接收速率中等（50-80% 理论值）")
            print(f"   可能原因: PC USB 驱动延迟")
        else:
            print(f"⚠️  接收速率较低（< 50% 理论值）")
            print(f"   可能原因:")
            print(f"   1. USB CDC 驱动限速")
            print(f"   2. FPGA 端 FIFO 溢出")
            print(f"   3. 采样率过高，建议降低到 500kHz 以下")

        ser.close()

    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    print("="*60)
    print("🚀 高速 DC 接收测试工具（优化版）")
    print("="*60)

    # 列出串口
    ports = list_ports()
    if not ports:
        print("❌ 未找到可用串口")
        exit(1)

    # 选择串口
    print("\n请输入串口编号:", end=" ")
    try:
        port_idx = int(input()) - 1
        if port_idx < 0 or port_idx >= len(ports):
            print("❌ 无效选择")
            exit(1)
        selected_port = ports[port_idx]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        exit(1)

    # 选择采样率
    print("\n选择采样率:")
    rates = [
        ("100 kHz (推荐)", 100_000),
        ("500 kHz", 500_000),
        ("1 MHz", 1_000_000)
    ]
    for i, (name, _) in enumerate(rates, 1):
        print(f"{i}. {name}")

    print("\n请输入采样率编号:", end=" ")
    try:
        rate_idx = int(input()) - 1
        if rate_idx < 0 or rate_idx >= len(rates):
            print("❌ 无效选择")
            exit(1)
        selected_rate = rates[rate_idx][1]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        exit(1)

    # 运行测试
    test_dc_high_speed(selected_port, selected_rate, duration=5)

    print("\n💡 提示:")
    print("   - 如果效率 > 80%，说明性能良好")
    print("   - 如果效率 < 50%，建议降低采样率")
    print("   - 使用 dc_command_tool.py 可以查看实时波形\n")
