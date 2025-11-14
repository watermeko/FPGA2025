#!/usr/bin/env python3
"""
自动安装 libusb 后端
解决 PyUSB "No backend available" 错误
"""

import os
import sys
import urllib.request
import zipfile
import shutil
import platform

def is_admin():
    """检查是否有管理员权限"""
    try:
        import ctypes
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except:
        return False

def download_file(url, filename):
    """下载文件"""
    print(f"📥 下载 {filename}...")
    try:
        urllib.request.urlretrieve(url, filename)
        print(f"✅ 下载完成: {filename}")
        return True
    except Exception as e:
        print(f"❌ 下载失败: {e}")
        return False

def install_libusb_windows():
    """在 Windows 上安装 libusb"""
    print("=" * 70)
    print("🔧 安装 libusb (Windows)")
    print("=" * 70)
    print()

    # 检测系统架构
    is_64bit = platform.machine().endswith('64')
    arch = "x64" if is_64bit else "x86"
    print(f"📊 检测到系统架构: {arch}")
    print()

    # libusb 下载链接 (使用最新版本)
    LIBUSB_VERSION = "1.0.27"
    LIBUSB_URL = f"https://github.com/libusb/libusb/releases/download/v{LIBUSB_VERSION}/libusb-{LIBUSB_VERSION}.7z"

    # 备用下载链接 (如果 GitHub 下载失败)
    LIBUSB_URL_BACKUP = "https://sourceforge.net/projects/libusb/files/libusb-1.0/libusb-1.0.27/libusb-1.0.27.7z/download"

    zip_file = "libusb.7z"

    # 方法1: 使用预编译的 DLL (推荐)
    print("📦 方法1: 下载预编译 DLL")
    print(f"   从: https://github.com/libusb/libusb/releases")
    print()

    # 简化方法：直接下载单个 DLL
    if is_64bit:
        dll_url = "https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.dll"
    else:
        dll_url = "https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.dll"

    dll_file = "libusb-1.0.dll"

    print("💡 尝试简单方法：直接复制 DLL 到脚本目录")
    print()

    # 获取当前脚本目录
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dll_path = os.path.join(script_dir, dll_file)

    # 检查是否已存在
    if os.path.exists(dll_path):
        print(f"✅ libusb-1.0.dll 已存在于脚本目录")
        print(f"   路径: {dll_path}")
        return True

    # 尝试从几个常见位置复制
    common_locations = [
        os.path.join(script_dir, dll_file),
        os.path.join(os.environ.get('WINDIR', 'C:\\Windows'), 'System32', dll_file),
        os.path.join(os.environ.get('WINDIR', 'C:\\Windows'), 'SysWOW64', dll_file),
    ]

    for loc in common_locations:
        if os.path.exists(loc):
            print(f"✅ 找到现有 DLL: {loc}")
            if loc != dll_path:
                try:
                    shutil.copy(loc, dll_path)
                    print(f"✅ 已复制到脚本目录")
                    return True
                except:
                    pass

    # 如果没找到，提供手动下载指引
    print("=" * 70)
    print("📝 libusb 手动安装指南")
    print("=" * 70)
    print()
    print("由于自动下载可能失败，请手动安装 libusb:")
    print()
    print("步骤 1: 下载 libusb")
    print(f"   访问: https://github.com/libusb/libusb/releases/latest")
    print(f"   下载: libusb-{LIBUSB_VERSION}.7z 或 .zip")
    print()
    print("步骤 2: 解压并找到 DLL")
    if is_64bit:
        print(f"   路径: VS2019\\MS64\\dll\\libusb-1.0.dll")
    else:
        print(f"   路径: VS2019\\MS32\\dll\\libusb-1.0.dll")
    print()
    print("步骤 3: 复制 DLL (选择一种方法)")
    print(f"   方法A: 复制到脚本目录 (推荐)")
    print(f"          {script_dir}")
    print()
    print(f"   方法B: 复制到 System32")
    if is_64bit:
        print(f"          C:\\Windows\\System32\\libusb-1.0.dll")
    else:
        print(f"          C:\\Windows\\SysWOW64\\libusb-1.0.dll")
    print()
    print("步骤 4: 重新运行测试脚本")
    print(f"   python diagnose_dc_winusb.py")
    print()
    print("=" * 70)
    print()

    # 尝试打开浏览器到下载页面
    try:
        import webbrowser
        print("🌐 正在打开浏览器到下载页面...")
        webbrowser.open("https://github.com/libusb/libusb/releases/latest")
    except:
        pass

    return False

def test_libusb():
    """测试 libusb 是否可用"""
    print()
    print("=" * 70)
    print("🧪 测试 PyUSB 后端")
    print("=" * 70)
    print()

    try:
        import usb.core
        import usb.backend.libusb1

        backend = usb.backend.libusb1.get_backend()
        if backend is None:
            print("❌ libusb 后端不可用")
            return False

        print("✅ libusb 后端可用!")
        print(f"   后端: {backend}")

        # 尝试列出设备
        print()
        print("🔍 扫描 USB 设备...")
        devices = list(usb.core.find(find_all=True))
        print(f"✅ 找到 {len(devices)} 个 USB 设备")

        if len(devices) > 0:
            print()
            print("前 5 个设备:")
            for i, dev in enumerate(devices[:5], 1):
                print(f"   {i}. VID: 0x{dev.idVendor:04X}, PID: 0x{dev.idProduct:04X}")

        return True

    except Exception as e:
        print(f"❌ 测试失败: {e}")
        return False

def install_pyusb():
    """安装 PyUSB"""
    print()
    print("=" * 70)
    print("📦 检查 PyUSB 安装")
    print("=" * 70)
    print()

    try:
        import usb.core
        print("✅ PyUSB 已安装")
        return True
    except ImportError:
        print("⚠️  PyUSB 未安装")
        print()
        print("正在安装 PyUSB...")

        import subprocess
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "pyusb"])
            print("✅ PyUSB 安装成功")
            return True
        except:
            print("❌ PyUSB 安装失败")
            print()
            print("请手动安装:")
            print("   pip install pyusb")
            return False

def main():
    print("=" * 70)
    print("🚀 PyUSB libusb 后端安装工具")
    print("=" * 70)
    print()

    if platform.system() != "Windows":
        print("⚠️  此脚本仅支持 Windows")
        print()
        print("Linux/Mac 用户请使用包管理器安装 libusb:")
        print("   Ubuntu/Debian: sudo apt-get install libusb-1.0-0")
        print("   Fedora: sudo dnf install libusb")
        print("   macOS: brew install libusb")
        return

    # 检查 PyUSB
    if not install_pyusb():
        return

    # 安装 libusb
    if not install_libusb_windows():
        print()
        print("⚠️  自动安装未完成，请按照上面的手动安装指南操作")
        return

    # 测试
    if test_libusb():
        print()
        print("=" * 70)
        print("🎉 安装成功!")
        print("=" * 70)
        print()
        print("现在可以运行:")
        print("   python diagnose_dc_winusb.py")
        print()
    else:
        print()
        print("=" * 70)
        print("⚠️  安装可能未成功，请查看上面的错误信息")
        print("=" * 70)
        print()

if __name__ == "__main__":
    main()
