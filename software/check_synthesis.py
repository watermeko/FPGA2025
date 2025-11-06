#!/usr/bin/env python3
"""
检查综合报告中是否包含 DC 模块
"""

import os
import re

def check_synthesis_report():
    """检查综合报告"""

    # 可能的报告文件路径
    report_paths = [
        "F:/FPGA2025/impl/pnr/cdc.rpt.txt",
        "F:/FPGA2025/impl/synthesis/cdc_syn.rpt",
        "F:/FPGA2025/impl/gwsynthesis/cdc_syn.log"
    ]

    print("="*60)
    print("🔍 检查 DC 模块是否被综合")
    print("="*60)

    found_report = None
    for path in report_paths:
        if os.path.exists(path):
            found_report = path
            print(f"\n✅ 找到报告: {path}")
            break

    if not found_report:
        print("\n❌ 未找到综合报告文件")
        print("   请在 GOWIN IDE 中查看综合报告")
        return

    # 读取报告
    with open(found_report, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    # 检查关键模块
    modules_to_check = [
        "digital_capture_handler",
        "dc_handler",
        "dc_signal_in",
        "dc_upload"
    ]

    print("\n检查关键模块:")
    found_any = False
    for module in modules_to_check:
        if module in content:
            print(f"   ✅ {module} - 存在")
            found_any = True
        else:
            print(f"   ❌ {module} - 未找到")

    if found_any:
        print("\n✅ DC 模块已被综合")
    else:
        print("\n❌ DC 模块可能未被综合！")
        print("   建议:")
        print("   1. 检查 cdc.v 中 DC handler 是否被注释")
        print("   2. 重新综合项目")

if __name__ == "__main__":
    check_synthesis_report()
