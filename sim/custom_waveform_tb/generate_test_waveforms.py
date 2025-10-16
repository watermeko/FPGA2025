#!/usr/bin/env python3
"""
测试波形生成器
为 custom_waveform_handler 仿真生成各种测试波形

Author: Claude Code Assistant
Date: 2025-01-15
"""

import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path


def generate_sine_wave(num_samples, cycles=1):
    """生成正弦波"""
    x = np.linspace(0, 2 * np.pi * cycles, num_samples)
    wave = np.sin(x)
    return wave


def generate_triangle_wave(num_samples, cycles=1):
    """生成三角波"""
    x = np.linspace(0, cycles, num_samples)
    wave = 2.0 * np.abs(2.0 * (x - np.floor(x + 0.5))) - 1.0
    return wave


def generate_sawtooth_wave(num_samples, cycles=1):
    """生成锯齿波"""
    x = np.linspace(0, cycles, num_samples)
    wave = 2.0 * (x - np.floor(x + 0.5))
    return wave


def generate_square_wave(num_samples, cycles=1, duty_cycle=0.5):
    """生成方波"""
    x = np.linspace(0, cycles, num_samples)
    wave = np.where((x % 1.0) < duty_cycle, 1.0, -1.0)
    return wave


def generate_chirp_wave(num_samples):
    """生成线性调频波(频率从低到高)"""
    t = np.linspace(0, 1, num_samples)
    f0 = 1.0   # 起始频率
    f1 = 10.0  # 结束频率
    phase = 2 * np.pi * (f0 * t + (f1 - f0) * t**2 / 2)
    wave = np.sin(phase)
    return wave


def generate_composite_wave(num_samples):
    """生成复合波(多个频率叠加)"""
    t = np.linspace(0, 2 * np.pi, num_samples)
    wave = (np.sin(t) + 0.5 * np.sin(3 * t) + 0.3 * np.sin(5 * t)) / 1.8
    return wave


def generate_pulse_train(num_samples, pulse_width=10):
    """生成脉冲串"""
    wave = np.zeros(num_samples)
    period = num_samples // 8
    for i in range(0, num_samples, period):
        wave[i:min(i+pulse_width, num_samples)] = 1.0
    wave = wave * 2.0 - 1.0  # 转换到[-1, 1]
    return wave


def generate_exponential_decay(num_samples):
    """生成指数衰减正弦波"""
    t = np.linspace(0, 4 * np.pi, num_samples)
    envelope = np.exp(-t / (4 * np.pi))
    wave = np.sin(t) * envelope
    return wave


def normalize_to_dac(wave):
    """
    归一化到14位DAC范围

    Args:
        wave: 浮点数组,范围[-1, 1]

    Returns:
        整数数组,范围[0, 16383]
    """
    wave = np.clip(wave, -1.0, 1.0)
    dac_values = ((wave + 1.0) * 8191.5).astype(np.uint16)
    dac_values = np.clip(dac_values, 0, 16383)
    return dac_values


def save_waveform(filename, wave_float, wave_dac):
    """保存波形到文件"""

    # 保存浮点版本(用于Python工具测试)
    float_file = filename.replace('.txt', '_float.csv')
    np.savetxt(float_file, wave_float, delimiter=',', fmt='%.6f')

    # 保存DAC版本(用于仿真验证)
    dac_file = filename.replace('.txt', '_dac.txt')
    np.savetxt(dac_file, wave_dac, fmt='%d')

    # 保存十六进制版本(用于SystemVerilog $readmemh)
    hex_file = filename.replace('.txt', '_hex.txt')
    with open(hex_file, 'w') as f:
        for val in wave_dac:
            f.write(f"{val:04X}\n")

    print(f"Saved: {float_file}, {dac_file}, {hex_file}")
    return float_file, dac_file, hex_file


def plot_waveforms(waveforms, titles, save_path=None):
    """绘制多个波形对比图"""
    num_waves = len(waveforms)
    fig, axes = plt.subplots(num_waves, 1, figsize=(12, 2*num_waves))

    if num_waves == 1:
        axes = [axes]

    for i, (wave, title) in enumerate(zip(waveforms, titles)):
        axes[i].plot(wave, linewidth=1)
        axes[i].set_title(title)
        axes[i].set_xlabel('Sample Index')
        axes[i].set_ylabel('Amplitude')
        axes[i].grid(True)
        axes[i].set_xlim(0, len(wave))

    plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150)
        print(f"Plot saved: {save_path}")

    plt.show()


def main():
    """生成所有测试波形"""

    output_dir = Path("sim/custom_waveform_tb/test_waveforms")
    output_dir.mkdir(parents=True, exist_ok=True)

    print("Generating test waveforms...")
    print("=" * 60)

    # 测试波形配置
    test_cases = [
        ("sine_256", generate_sine_wave(256, 2), "256-point Sine Wave (2 cycles)"),
        ("sine_512", generate_sine_wave(512, 4), "512-point Sine Wave (4 cycles)"),
        ("sine_1024", generate_sine_wave(1024, 8), "1024-point Sine Wave (8 cycles)"),
        ("triangle_256", generate_triangle_wave(256, 2), "256-point Triangle Wave"),
        ("sawtooth_256", generate_sawtooth_wave(256, 2), "256-point Sawtooth Wave"),
        ("square_256", generate_square_wave(256, 4), "256-point Square Wave"),
        ("square_25pct", generate_square_wave(256, 4, 0.25), "256-point Square Wave (25% duty)"),
        ("chirp_512", generate_chirp_wave(512), "512-point Chirp Signal"),
        ("composite_256", generate_composite_wave(256), "256-point Composite Wave"),
        ("pulse_train", generate_pulse_train(256, 20), "256-point Pulse Train"),
        ("exp_decay", generate_exponential_decay(512), "512-point Exponential Decay"),
        ("dc_zero", np.zeros(128), "128-point DC (Zero)"),
        ("dc_max", np.ones(128), "128-point DC (Max)"),
    ]

    all_waveforms = []
    all_titles = []

    for name, wave_float, title in test_cases:
        # 归一化到DAC范围
        wave_dac = normalize_to_dac(wave_float)

        # 保存文件
        filename = output_dir / f"{name}.txt"
        save_waveform(str(filename), wave_float, wave_dac)

        # 统计信息
        print(f"\n{title}:")
        print(f"  Samples: {len(wave_float)}")
        print(f"  Range (float): [{wave_float.min():.3f}, {wave_float.max():.3f}]")
        print(f"  Range (DAC): [{wave_dac.min()}, {wave_dac.max()}]")
        print(f"  Mean: {wave_dac.mean():.1f}")

        all_waveforms.append(wave_dac)
        all_titles.append(title)

    print("\n" + "=" * 60)
    print(f"Total waveforms generated: {len(test_cases)}")
    print(f"Output directory: {output_dir}")

    # 生成波形对比图
    print("\nGenerating comparison plots...")
    plot_waveforms(
        all_waveforms[:6],  # 前6个波形
        all_titles[:6],
        output_dir / "waveforms_comparison.png"
    )

    # 生成README
    readme_path = output_dir / "README.md"
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write("# 测试波形文件\n\n")
        f.write("此目录包含用于 custom_waveform_handler 仿真的测试波形。\n\n")
        f.write("## 文件格式\n\n")
        f.write("每个波形有3个版本:\n\n")
        f.write("- `*_float.csv`: 归一化浮点数 [-1.0, 1.0]\n")
        f.write("- `*_dac.txt`: 14位DAC整数 [0, 16383]\n")
        f.write("- `*_hex.txt`: 十六进制格式(用于 $readmemh)\n\n")
        f.write("## 波形列表\n\n")

        for name, _, title in test_cases:
            f.write(f"### {name}\n")
            f.write(f"{title}\n\n")

        f.write("## 使用方法\n\n")
        f.write("```python\n")
        f.write("# Python工具\n")
        f.write("python software/custom_waveform_tool.py --file sim/custom_waveform_tb/test_waveforms/sine_256_float.csv --port COM3\n")
        f.write("```\n\n")
        f.write("```systemverilog\n")
        f.write("// SystemVerilog testbench\n")
        f.write('$readmemh("test_waveforms/sine_256_hex.txt", test_waveform);\n')
        f.write("```\n")

    print(f"README created: {readme_path}")
    print("\nAll done!")


if __name__ == "__main__":
    main()
