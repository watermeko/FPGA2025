#!/usr/bin/env python3
"""
检查 digital_capture_handler.v 是否已应用高速优化
"""

import os
import sys

def check_optimization(file_path):
    """检查文件是否已优化"""
    if not os.path.exists(file_path):
        return {
            'exists': False,
            'error': f"文件不存在: {file_path}"
        }

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        lines = content.split('\n')

    # 检查关键标识
    checks = {
        'has_optimized_marker': 'HIGH-SPEED OPTIMIZED' in content,
        'has_old_upload_state': 'localparam UP_WAIT' in content,
        'has_new_sample_flag': 'new_sample_flag' in content,
        'has_captured_data_sync': 'captured_data_sync' in content,
        'has_single_cycle_upload': 'single-cycle upload' in content.lower() or 'direct upload' in content.lower(),
    }

    # 统计状态机复杂度
    upload_state_lines = [i for i, line in enumerate(lines) if 'upload_state' in line and '//' not in line[:line.find('upload_state')] if line.find('upload_state') >= 0]

    return {
        'exists': True,
        'checks': checks,
        'upload_state_references': len(upload_state_lines),
        'lines': lines,
        'content': content
    }

def main():
    file_path = "rtl/logic/digital_capture_handler.v"

    print("=" * 80)
    print("🔍 Digital Capture Handler 优化状态检查")
    print("=" * 80)
    print()

    result = check_optimization(file_path)

    if not result['exists']:
        print(f"❌ {result['error']}")
        sys.exit(1)

    checks = result['checks']
    upload_refs = result['upload_state_references']

    print(f"文件路径: {file_path}")
    print()

    # 显示检查结果
    print("检查项:")
    print("-" * 80)

    if checks['has_optimized_marker']:
        print("✅ 包含 'HIGH-SPEED OPTIMIZED' 标记")
    else:
        print("❌ 未找到优化标记")

    if checks['has_old_upload_state']:
        print("❌ 仍然存在旧的 UP_WAIT 状态 (应该移除)")
    else:
        print("✅ 已移除 UP_WAIT 状态")

    if checks['has_new_sample_flag']:
        print("❌ 仍然存在 new_sample_flag (应该移除)")
    else:
        print("✅ 已移除 new_sample_flag")

    if checks['has_captured_data_sync']:
        print("❌ 仍然存在 captured_data_sync (应该移除)")
    else:
        print("✅ 已移除 captured_data_sync")

    if checks['has_single_cycle_upload']:
        print("✅ 包含单周期上传逻辑")
    else:
        print("❌ 未找到单周期上传逻辑")

    print()
    print(f"upload_state 引用次数: {upload_refs}")
    if upload_refs == 0:
        print("  ✅ upload_state 状态机已完全移除")
    else:
        print(f"  ⚠️  仍有 {upload_refs} 处引用 upload_state")

    print()
    print("=" * 80)

    # 最终判定
    is_optimized = (
        checks['has_optimized_marker'] and
        not checks['has_old_upload_state'] and
        not checks['has_new_sample_flag'] and
        not checks['has_captured_data_sync'] and
        upload_refs == 0
    )

    if is_optimized:
        print("✅ 文件已成功应用高速优化！")
        print()
        print("下一步:")
        print("  1. 在 GOWIN EDA 中打开项目")
        print("  2. 运行 Synthesize")
        print("  3. 运行 Place & Route")
        print("  4. 生成并烧录 bitstream")
        print("  5. 运行 python software/verify_optimization.py 验证")
    else:
        print("❌ 文件尚未应用高速优化")
        print()
        print("请执行以下步骤:")
        print("  1. 备份原文件:")
        print("     cp rtl/logic/digital_capture_handler.v rtl/logic/digital_capture_handler.v.bak")
        print("  2. 替换为优化版本:")
        print("     cp rtl/logic/digital_capture_handler_optimized.v rtl/logic/digital_capture_handler.v")
        print("  3. 重新运行此脚本验证")

    print("=" * 80)

    # 显示关键代码片段（仅在未优化时）
    if not is_optimized:
        print("\n📝 当前上传逻辑代码片段:")
        print("-" * 80)

        # 查找上传逻辑部分
        in_upload_section = False
        upload_lines = []
        for i, line in enumerate(result['lines']):
            if 'Upload logic' in line or 'upload state machine' in line.lower():
                in_upload_section = True
            if in_upload_section:
                upload_lines.append(f"{i+1:4d} {line}")
                if len(upload_lines) > 30:  # 最多显示 30 行
                    break

        if upload_lines:
            for line in upload_lines[:20]:
                print(line)
            if len(upload_lines) > 20:
                print("     ...")
        else:
            print("(未找到上传逻辑部分)")

        print("-" * 80)

if __name__ == "__main__":
    main()
