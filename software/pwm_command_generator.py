#!/usr/bin/env python3
import argparse

# --- Configuration Constants ---
# 确保这个时钟频率与您FPGA设计中的 `CLK_FREQ` 参数完全一致
SYSTEM_CLOCK_HZ = 50_000_000

# 协议中定义的常量
CMD_PWM_CONFIG = 0x04
FRAME_HEADER = [0xAA, 0x55]
PAYLOAD_LENGTH = 5

def generate_pwm_command(channel: int, frequency: int, duty_cycle: float):
    """
    Calculates and assembles a PWM configuration command frame.

    Args:
        channel (int): The PWM channel to configure (0-7).
        frequency (int): The desired frequency in Hz.
        duty_cycle (float): The desired duty cycle in percent (0.0 to 100.0).

    Returns:
        str: A formatted hex string of the command, or None if inputs are invalid.
    """
    print("--- Calculating PWM Parameters ---")
    
    # 1. 参数范围检查
    if not (0 <= channel <= 7):
        print(f"Error: Channel must be between 0 and 7. Got: {channel}")
        return None
    if not (0.0 <= duty_cycle <= 100.0):
        print(f"Error: Duty cycle must be between 0.0 and 100.0. Got: {duty_cycle}")
        return None
    if frequency <= 0:
        print(f"Error: Frequency must be positive. Got: {frequency}")
        return None

    # 2. 根据公式计算 Period 和 Duty 的硬件值
    try:
        # Period_Value = System_Clock / PWM_Frequency
        period_val = int(SYSTEM_CLOCK_HZ / frequency)

        # Duty_Value = Period_Value * (Duty_Cycle / 100)
        duty_val = int(period_val * (duty_cycle / 100.0))

    except ZeroDivisionError:
        print("Error: Frequency cannot be zero.")
        return None

    print(f"  System Clock: {SYSTEM_CLOCK_HZ / 1_000_000} MHz")
    print(f"  Target Freq:  {frequency} Hz")
    print(f"  Target Duty:  {duty_cycle}%")
    print(f"  ---------------------------------")
    print(f"  Calculated Period Value: {period_val} (0x{period_val:04X})")
    print(f"  Calculated Duty Value:   {duty_val} (0x{duty_val:04X})")

    # 3. 再次检查计算出的硬件值是否有效
    if not (0 < period_val <= 65535):
        min_freq = SYSTEM_CLOCK_HZ / 65535
        print(f"\nError: Calculated Period value ({period_val}) is out of the 16-bit range (1-65535).")
        print(f"       With a {SYSTEM_CLOCK_HZ / 1_000_000} MHz clock, the minimum possible frequency is ~{min_freq:.2f} Hz.")
        return None

    # 确保duty value不大于period value
    if duty_val > period_val:
        duty_val = period_val

    # 4. 构建 Payload
    payload = [
        channel,
        (period_val >> 8) & 0xFF,  # Period High Byte
        period_val & 0xFF,         # Period Low Byte
        (duty_val >> 8) & 0xFF,    # Duty High Byte
        duty_val & 0xFF            # Duty Low Byte
    ]

    # 5. 构建需要计算校验和的帧部分
    frame_for_checksum = [
        CMD_PWM_CONFIG,
        (PAYLOAD_LENGTH >> 8) & 0xFF, # Length High Byte
        PAYLOAD_LENGTH & 0xFF,        # Length Low Byte
    ]
    frame_for_checksum.extend(payload)

    # 6. 计算校验和
    checksum = sum(frame_for_checksum) & 0xFF

    # 7. 组合成最终的完整指令
    final_frame = FRAME_HEADER + frame_for_checksum + [checksum]

    # 8. 格式化为十六进制字符串
    hex_string = ' '.join(f"{byte:02X}" for byte in final_frame)

    return hex_string, final_frame

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate a PWM configuration command for the FPGA Multifunctional Debugger.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("-c", "--channel", type=int, required=True, choices=range(8),
                        help="PWM channel index to configure (0-7).")
    parser.add_argument("-f", "--frequency", type=int, required=True,
                        help="Desired PWM frequency in Hz.")
    parser.add_argument("-d", "--duty", type=float, required=True,
                        help="Desired duty cycle in percent (e.g., 25.5).")

    args = parser.parse_args()

    result = generate_pwm_command(args.channel, args.frequency, args.duty)

    if result:
        hex_str, frame_bytes = result
        print("\n--- Generated Command ---")
        print(f"Instruction Frame (Hex):")
        print(f"\n{hex_str}\n")
        print("Action: Copy the line above and send it using your serial terminal's hex mode.")