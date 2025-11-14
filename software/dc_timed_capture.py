#!/usr/bin/env python3
"""
DC 定时捕获和统计工具（无 GUI 版本）
用于诊断定时捕获问题
"""

import serial
import serial.tools.list_ports
import time
import threading
from collections import deque

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

    actual_rate = SYSTEM_CLK / divider
    print(f"目标采样率: {sample_rate_hz} Hz")
    print(f"分频系数: {divider} (0x{divider:04X})")
    print(f"实际采样率: {actual_rate:.2f} Hz")
    print(f"完整命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def generate_dc_stop_command():
    """生成 DC 停止命令"""
    cmd = 0x0C
    len_h = 0x00
    len_l = 0x00
    checksum = calculate_checksum([cmd, len_h, len_l])
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, checksum])
    return full_cmd

class TimedCapture:
    """定时捕获类（无 GUI）"""

    def __init__(self, port, baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.serial_port = None
        self.running = False

        # 数据缓冲（只保留所有数据用于统计）
        self.all_data = []
        self.total_bytes = 0
        self.start_time = None

    def connect(self):
        """连接串口"""
        try:
            self.serial_port = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=0.1
            )
            print(f"✅ 已连接到 {self.port}")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False

    def disconnect(self):
        """断开串口"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            print("串口已关闭")

    def start_capture(self, sample_rate_hz):
        """启动捕获"""
        cmd = generate_dc_start_command(sample_rate_hz)
        self.serial_port.write(cmd)
        self.running = True
        self.start_time = time.time()
        self.total_bytes = 0
        self.all_data = []
        print(f"✅ 开始捕获，采样率: {sample_rate_hz} Hz\n")

    def stop_capture(self):
        """停止捕获"""
        self.running = False
        stop_cmd = generate_dc_stop_command()
        self.serial_port.write(stop_cmd)
        print("\n✅ 已发送 STOP 命令")

    def read_data_thread(self):
        """后台线程：读取数据"""
        print("🔄 数据读取线程已启动\n")
        last_print = time.time()

        while self.running:
            if self.serial_port and self.serial_port.in_waiting > 0:
                try:
                    # 批量读取
                    chunk = self.serial_port.read(min(self.serial_port.in_waiting, 4096))
                    self.all_data.extend(chunk)
                    self.total_bytes += len(chunk)

                    # 每秒打印一次进度
                    now = time.time()
                    if now - last_print >= 1.0:
                        elapsed = now - self.start_time
                        rate = self.total_bytes / elapsed if elapsed > 0 else 0
                        print(f"[{elapsed:.1f}s] 接收: {self.total_bytes:,} bytes | 速率: {rate:,.0f} bytes/s")
                        last_print = now

                except Exception as e:
                    print(f"❌ 读取错误: {e}")
                    break
            else:
                time.sleep(0.001)

        print(f"\n🛑 数据读取线程已停止 (总接收: {self.total_bytes} bytes)")

    def calculate_statistics(self, sample_rate_hz):
        """计算统计信息"""
        print("\n" + "=" * 60)
        print("📊 统计分析结果")
        print("=" * 60)

        if self.total_bytes == 0:
            print("❌ 未采集到数据")
            return

        elapsed = time.time() - self.start_time if self.start_time else 0
        actual_rate = self.total_bytes / elapsed if elapsed > 0 else 0
        efficiency = (actual_rate / sample_rate_hz * 100) if sample_rate_hz > 0 else 0

        print(f"\n总采样数: {self.total_bytes:,} samples")
        print(f"采集时长: {elapsed:.2f} 秒")
        print(f"实际采样率: {actual_rate:.1f} samples/s")
        print(f"理论采样率: {sample_rate_hz:.1f} samples/s")
        print(f"接收效率: {efficiency:.1f}%")

        # 分析每个通道
        print(f"\n{'通道':<6} {'高电平':<10} {'低电平':<10} {'占空比':<10} {'翻转次数':<10} {'估计频率':<12}")
        print("-" * 60)

        # 解析每个字节到 8 个通道
        channels = [[] for _ in range(8)]
        for byte_val in self.all_data:
            for ch in range(8):
                bit_val = (byte_val >> ch) & 0x01
                channels[ch].append(bit_val)

        for ch in range(8):
            ch_data = channels[ch]
            if len(ch_data) == 0:
                continue

            total_samples = len(ch_data)
            high_count = sum(ch_data)
            low_count = total_samples - high_count
            duty_cycle = (high_count / total_samples * 100) if total_samples > 0 else 0

            # 计算翻转次数
            transitions = 0
            for i in range(1, len(ch_data)):
                if ch_data[i] != ch_data[i-1]:
                    transitions += 1

            # 估计频率
            est_freq = (transitions / 2 / elapsed) if elapsed > 0 and transitions > 0 else 0

            ch_name = f"CH{ch}"
            high_pct = f"{duty_cycle:.1f}%"
            low_pct = f"{100-duty_cycle:.1f}%"
            duty_str = f"{duty_cycle:.1f}%"
            trans_str = f"{transitions}"
            freq_str = f"{est_freq:.2f} Hz" if est_freq > 0 else "静态"

            print(f"{ch_name:<6} {high_pct:<10} {low_pct:<10} {duty_str:<10} {trans_str:<10} {freq_str:<12}")

        print("=" * 60 + "\n")

    def run(self, sample_rate_hz, duration_sec):
        """运行定时捕获"""
        if not self.connect():
            return

        # 启动捕获
        self.start_capture(sample_rate_hz)

        # 启动后台读取线程
        read_thread = threading.Thread(target=self.read_data_thread, daemon=True)
        read_thread.start()

        # 主线程等待指定时间
        print(f"⏱️  捕获 {duration_sec} 秒...\n")
        time.sleep(duration_sec)

        # 停止捕获
        self.stop_capture()
        time.sleep(0.5)

        # 显示统计
        self.calculate_statistics(sample_rate_hz)

        # 断开连接
        self.disconnect()


def list_ports():
    """列出可用串口"""
    ports = serial.tools.list_ports.comports()
    print("\n可用串口:")
    for i, port in enumerate(ports, 1):
        print(f"{i}. {port.device} - {port.description}")
    return [port.device for port in ports]


if __name__ == "__main__":
    print("=" * 60)
    print("🔬 DC 定时捕获和统计工具（无 GUI 版本）")
    print("=" * 60)

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
        ("1 MHz", 1_000_000),
        ("500 kHz", 500_000),
        ("100 kHz", 100_000),
        ("10 kHz", 10_000),
        ("1 kHz", 1_000)
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

    # 选择捕获时长
    print("\n选择捕获时长:")
    print("1. 10 秒")
    print("2. 30 秒")
    print("3. 60 秒")

    print("\n请输入时长编号:", end=" ")
    try:
        dur_idx = int(input()) - 1
        durations = [10, 30, 60]
        if dur_idx < 0 or dur_idx >= len(durations):
            print("❌ 无效选择")
            exit(1)
        selected_duration = durations[dur_idx]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        exit(1)

    print("\n" + "=" * 60 + "\n")

    # 运行捕获
    capture = TimedCapture(selected_port)
    capture.run(selected_rate, selected_duration)

    print("\n✅ 测试完成！")
