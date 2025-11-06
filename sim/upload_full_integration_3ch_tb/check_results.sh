#!/bin/bash
# 仿真结果分析脚本

echo "=========================================="
echo "DSM上传集成仿真结果分析"
echo "=========================================="
echo ""

# 检查关键输出
echo "1. 检查DSM handler输出..."
echo "   期望: 9字节 (1个通道的测量数据)"
echo ""

echo "2. 检查Merged arbiter输出..."
echo "   期望: 15字节 (0xAA44 + 0x0A + 0x0009 + 9字节数据 + checksum)"
echo ""

echo "3. 数据格式验证..."
echo "   字节1-2: 0xAA 0x44 (帧头)"
echo "   字节3:   0x0A (DSM source)"
echo "   字节4-5: 0x00 0x09 (长度，大端)"
echo "   字节6:   通道号 (0x00)"
echo "   字节7-14: 测量数据 (高电平、低电平、周期、占空比)"
echo "   字节15:  校验和"
echo ""

echo "=========================================="
echo "请在ModelSim控制台中查看:"
echo "=========================================="
echo "1. DSM handler输出计数 (dsm_byte_count)"
echo "2. Merged输出计数 (merged_byte_count)"
echo "3. 输出数据内容 (MERGED OUTPUT行)"
echo ""
echo "如果看到:"
echo "  - DSM handler output: 9 bytes"
echo "  - Merged arbiter output: 15 bytes"
echo "  - 数据为有效值而非0xxx"
echo "则表示测试通过！"
echo ""
