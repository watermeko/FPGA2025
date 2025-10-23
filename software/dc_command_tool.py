#!/usr/bin/env python3
"""
Digital Capture Command Generator & Waveform Plotter
生成DC模块控制命令并实时绘制8通道波形的工具
"""

import serial
import serial.tools.list_ports
import time
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from collections import deque
import threading
import sys

def calculate_checksum(data):
    """计算校验和（从功能码开始的所有字节累加，取低8位）"""
    return sum(data) & 0xFF

def generate_dc_start_command(sample_rate_hz):
    """
    生成DC启动命令

    Args:
        sample_rate_hz: 目标采样率（Hz），例如 1000000 表示 1MHz

    Returns:
        bytes: 完整的命令字节序列
    """
    # 系统时钟 60MHz
    SYSTEM_CLK = 60_000_000

    # 计算分频系数
    divider = SYSTEM_CLK // sample_rate_hz

    # 限制范围
    if divider < 50:
        print(f"警告: 分频系数 {divider} 太小，最小推荐值 50 (对应 1.2MHz)")
        divider = 50
    if divider > 65535:
        print(f"警告: 分频系数 {divider} 太大，最大值 65535 (对应 915Hz)")
        divider = 65535

    actual_rate = SYSTEM_CLK / divider

    # 构建命令
    cmd = 0x0B  # DC启动命令
    len_h = 0x00
    len_l = 0x02
    div_h = (divider >> 8) & 0xFF
    div_l = divider & 0xFF

    # 计算校验和
    checksum = calculate_checksum([cmd, len_h, len_l, div_h, div_l])

    # 完整命令
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, div_h, div_l, checksum])

    print(f"目标采样率: {sample_rate_hz} Hz")
    print(f"分频系数: {divider} (0x{divider:04X})")
    print(f"实际采样率: {actual_rate:.2f} Hz")
    print(f"完整命令: {' '.join([f'{b:02X}' for b in full_cmd])}")
    print(f"命令长度: {len(full_cmd)} 字节")

    return full_cmd

def generate_dc_stop_command():
    """
    生成DC停止命令

    Returns:
        bytes: 完整的命令字节序列
    """
    cmd = 0x0C  # DC停止命令
    len_h = 0x00
    len_l = 0x00

    # 计算校验和
    checksum = calculate_checksum([cmd, len_h, len_l])

    # 完整命令
    full_cmd = bytes([0xAA, 0x55, cmd, len_h, len_l, checksum])

    print(f"DC停止命令: {' '.join([f'{b:02X}' for b in full_cmd])}")

    return full_cmd

def main():
    print("=" * 60)
    print("Digital Capture 命令生成工具")
    print("=" * 60)
    print()

    # 预设采样率
    preset_rates = [
        ("1 MHz (推荐最高)", 1_000_000),
        ("500 kHz", 500_000),
        ("100 kHz", 100_000),
        ("10 kHz", 10_000),
        ("1 kHz", 1_000)
    ]

    print("预设采样率:")
    for i, (name, rate) in enumerate(preset_rates, 1):
        print(f"{i}. {name}")
    print()

    # 生成所有预设命令
    for name, rate in preset_rates:
        print(f"\n{name}:")
        print("-" * 40)
        cmd = generate_dc_start_command(rate)
        print()

    print("\n" + "=" * 60)
    print("DC停止命令:")
    print("-" * 40)
    generate_dc_stop_command()
    print()

    print("\n" + "=" * 60)
    print("使用说明:")
    print("=" * 60)
    print("1. 通过串口发送启动命令")
    print("2. FPGA开始以指定采样率连续上传数据")
    print("3. 每个字节代表8个通道的状态 (Bit[7:0] = [CH7:CH0])")
    print("4. 数据流为直通模式，无协议头")
    print("5. 发送停止命令终止捕获")


# ============================================================================
# 实时波形绘制类
# ============================================================================
class DigitalCaptureWaveform:
    """实时8通道数字波形绘制器"""

    def __init__(self, port, baudrate=115200, buffer_size=1000):
        """
        初始化波形绘制器

        Args:
            port: 串口名称，例如 'COM3' 或 '/dev/ttyUSB0'
            baudrate: 波特率，默认115200
            buffer_size: 每个通道的缓冲区大小（显示点数）
        """
        self.port = port
        self.baudrate = baudrate
        self.buffer_size = buffer_size
        self.running = False
        self.serial_port = None

        # 8通道数据缓冲区（使用deque实现循环缓冲）
        self.channels = [deque(maxlen=buffer_size) for _ in range(8)]
        self.time_axis = deque(maxlen=buffer_size)
        self.sample_count = 0

        # 统计信息
        self.total_bytes = 0
        self.start_time = None

    def list_ports(self):
        """列出所有可用串口"""
        ports = serial.tools.list_ports.comports()
        print("\n可用串口:")
        for i, port in enumerate(ports, 1):
            print(f"{i}. {port.device} - {port.description}")
        return [port.device for port in ports]

    def connect(self):
        """连接串口"""
        try:
            self.serial_port = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                timeout=0.1
            )
            print(f"✅ 已连接到 {self.port}, 波特率 {self.baudrate}")
            return True
        except Exception as e:
            print(f"❌ 连接失败: {e}")
            return False

    def disconnect(self):
        """断开串口"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            print("串口已关闭")

    def send_command(self, command_bytes):
        """发送命令"""
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.write(command_bytes)
            print(f"✅ 已发送命令: {' '.join([f'{b:02X}' for b in command_bytes])}")
        else:
            print("❌ 串口未打开")

    def start_capture(self, sample_rate_hz):
        """启动数字捕获"""
        cmd = generate_dc_start_command(sample_rate_hz)
        self.send_command(cmd)
        self.running = True
        self.start_time = time.time()
        self.total_bytes = 0
        print(f"✅ 开始捕获，采样率: {sample_rate_hz} Hz")

    def stop_capture(self):
        """停止数字捕获"""
        cmd = generate_dc_stop_command()
        self.send_command(cmd)
        self.running = False
        print("✅ 已停止捕获")

    def read_data_thread(self):
        """后台线程：读取串口数据"""
        while self.running:
            if self.serial_port and self.serial_port.in_waiting > 0:
                try:
                    # 读取一个字节
                    data = self.serial_port.read(1)
                    if len(data) == 1:
                        byte_val = data[0]
                        self.total_bytes += 1

                        # 解析8个通道
                        for ch in range(8):
                            bit_val = (byte_val >> ch) & 0x01
                            self.channels[ch].append(bit_val)

                        # 时间轴（采样序号）
                        self.time_axis.append(self.sample_count)
                        self.sample_count += 1

                except Exception as e:
                    print(f"❌ 读取错误: {e}")
                    break
            else:
                time.sleep(0.001)  # 避免空转占用CPU

    def init_plot(self):
        """初始化绘图"""
        self.fig, self.axes = plt.subplots(8, 1, figsize=(12, 10), sharex=True)
        self.fig.suptitle('8-Channel Digital Capture Waveform', fontsize=14, fontweight='bold')

        self.lines = []
        for i, ax in enumerate(self.axes):
            line, = ax.plot([], [], 'b-', linewidth=1.5)
            self.lines.append(line)

            ax.set_ylabel(f'CH{i}', fontsize=10, fontweight='bold')
            ax.set_ylim(-0.2, 1.2)
            ax.set_yticks([0, 1])
            ax.set_yticklabels(['LOW', 'HIGH'])
            ax.grid(True, alpha=0.3)
            ax.axhline(y=0.5, color='gray', linestyle='--', alpha=0.3)

        self.axes[-1].set_xlabel('Sample Count', fontsize=10)

        # 状态文本
        self.status_text = self.fig.text(
            0.02, 0.98, '',
            fontsize=9,
            verticalalignment='top',
            family='monospace',
            bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.5)
        )

        plt.tight_layout(rect=[0, 0, 1, 0.96])

    def update_plot(self, frame):
        """更新绘图（动画回调函数）"""
        if len(self.time_axis) > 0:
            time_data = np.array(self.time_axis)

            # 更新每个通道的波形
            for i, line in enumerate(self.lines):
                ch_data = np.array(self.channels[i])
                line.set_data(time_data, ch_data)

            # 自动调整X轴范围
            if len(time_data) > 0:
                x_min = max(0, time_data[-1] - self.buffer_size)
                x_max = time_data[-1] + 10
                for ax in self.axes:
                    ax.set_xlim(x_min, x_max)

            # 更新状态信息
            if self.start_time:
                elapsed = time.time() - self.start_time
                rate = self.total_bytes / elapsed if elapsed > 0 else 0
                status_str = (
                    f"Samples: {self.total_bytes:,} | "
                    f"Time: {elapsed:.1f}s | "
                    f"Rate: {rate:.1f} samples/s"
                )
                self.status_text.set_text(status_str)

        return self.lines + [self.status_text]

    def run(self, sample_rate_hz, duration_sec=None):
        """
        运行捕获和绘图

        Args:
            sample_rate_hz: 采样率
            duration_sec: 持续时间（秒），None表示持续运行
        """
        if not self.connect():
            return

        # 启动捕获
        self.start_capture(sample_rate_hz)

        # 启动数据读取线程
        read_thread = threading.Thread(target=self.read_data_thread, daemon=True)
        read_thread.start()

        # 初始化绘图
        self.init_plot()

        # 启动动画（30fps更新）
        anim = FuncAnimation(
            self.fig,
            self.update_plot,
            interval=33,  # ~30fps
            blit=False,  # 禁用blit以避免matplotlib 3.10兼容性问题
            cache_frame_data=False
        )

        print("\n📊 波形窗口已打开")
        print("💡 关闭窗口或按 Ctrl+C 停止捕获\n")

        try:
            plt.show()
        except KeyboardInterrupt:
            print("\n用户中断")
        finally:
            self.stop_capture()
            time.sleep(0.5)
            self.disconnect()


# ============================================================================
# 交互式主程序
# ============================================================================
def interactive_mode():
    """交互式运行模式"""
    print("\n" + "=" * 60)
    print("🔬 Digital Capture 实时波形绘制工具")
    print("=" * 60)

    # 列出串口
    plotter = DigitalCaptureWaveform(port="", buffer_size=1000)
    ports = plotter.list_ports()

    if not ports:
        print("❌ 未找到可用串口")
        return

    # 选择串口
    print("\n请输入串口编号:", end=" ")
    try:
        port_idx = int(input()) - 1
        if port_idx < 0 or port_idx >= len(ports):
            print("❌ 无效选择")
            return
        selected_port = ports[port_idx]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        return

    # 选择采样率
    print("\n选择采样率:")
    rates = [
        ("1 MHz (最高)", 1_000_000),
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
            return
        selected_rate = rates[rate_idx][1]
    except (ValueError, IndexError):
        print("❌ 无效输入")
        return

    # 创建绘图器
    plotter = DigitalCaptureWaveform(
        port=selected_port,
        baudrate=115200,
        buffer_size=1000
    )

    # 运行
    plotter.run(sample_rate_hz=selected_rate)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--generate":
        # 仅生成命令模式
        main()
    else:
        # 交互式波形绘制模式
        interactive_mode()
