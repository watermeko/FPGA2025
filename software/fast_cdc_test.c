// fast_cdc_test.c
// 编译: gcc fast_cdc_test.c -o fast_cdc_test.exe
// 运行: fast_cdc_test.exe

#include <windows.h>
#include <stdio.h>

int main() {
    // 打开COM口
    HANDLE hSerial = CreateFile("COM23",
        GENERIC_READ | GENERIC_WRITE,
        0, NULL, OPEN_EXISTING, 0, NULL);

    if (hSerial == INVALID_HANDLE_VALUE) {
        printf("错误：无法打开COM23\n");
        printf("Error code: %lu\n", GetLastError());
        return 1;
    }

    // 配置串口
    DCB dcbSerialParams = {0};
    dcbSerialParams.DCBlength = sizeof(dcbSerialParams);

    if (!GetCommState(hSerial, &dcbSerialParams)) {
        printf("错误：无法获取串口状态\n");
        CloseHandle(hSerial);
        return 1;
    }

    dcbSerialParams.BaudRate = CBR_115200;
    dcbSerialParams.ByteSize = 8;
    dcbSerialParams.StopBits = ONESTOPBIT;
    dcbSerialParams.Parity = NOPARITY;

    if (!SetCommState(hSerial, &dcbSerialParams)) {
        printf("错误：无法设置串口\n");
        CloseHandle(hSerial);
        return 1;
    }

    // 设置超时（尽可能短）
    COMMTIMEOUTS timeouts = {0};
    timeouts.ReadIntervalTimeout = 1;         // 字节间超时1ms
    timeouts.ReadTotalTimeoutConstant = 1;    // 总超时1ms
    timeouts.ReadTotalTimeoutMultiplier = 0;  // 不按字节计算

    if (!SetCommTimeouts(hSerial, &timeouts)) {
        printf("错误：无法设置超时\n");
        CloseHandle(hSerial);
        return 1;
    }

    printf("✅ 已连接到 COM23\n\n");

    // 发送600 kHz启动命令 (divider=100)
    unsigned char cmd[] = {0xAA, 0x55, 0x0B, 0x00, 0x02, 0x00, 0x64, 0x71};
    DWORD written;

    if (!WriteFile(hSerial, cmd, sizeof(cmd), &written, NULL)) {
        printf("错误：无法发送命令\n");
        CloseHandle(hSerial);
        return 1;
    }

    printf("✅ 已发送 600 kHz 启动命令\n");
    printf("   Divider: 100\n");
    printf("   理论速率: 600 KB/s\n\n");

    Sleep(200);  // 等待FPGA启动

    // 高速读取测试
    unsigned char buffer[65536];  // 64KB缓冲区
    DWORD bytesRead;
    long long totalBytes = 0;
    DWORD startTime = GetTickCount();
    DWORD lastPrintTime = startTime;

    printf("开始高速读取测试（10秒）...\n");
    printf("时间     已接收         速率\n");
    printf("-------------------------------\n");

    while (GetTickCount() - startTime < 10000) {  // 10秒
        // 疯狂读取，不做任何处理
        if (ReadFile(hSerial, buffer, sizeof(buffer), &bytesRead, NULL)) {
            totalBytes += bytesRead;
        }

        // 每秒显示一次进度
        DWORD now = GetTickCount();
        if (now - lastPrintTime >= 1000) {
            DWORD elapsed = now - startTime;
            double rate = (double)totalBytes / elapsed * 1000 / 1024;
            printf("%2lu秒  %10lld B  %8.1f KB/s\n",
                   elapsed/1000, totalBytes, rate);
            lastPrintTime = now;
        }
    }

    // 发送停止命令
    unsigned char stopCmd[] = {0xAA, 0x55, 0x0C, 0x00, 0x00, 0x0C};
    WriteFile(hSerial, stopCmd, sizeof(stopCmd), &written, NULL);

    DWORD elapsed = GetTickCount() - startTime;
    double avgRate = (double)totalBytes / elapsed * 1000 / 1024;

    printf("\n===============================\n");
    printf("测试完成\n");
    printf("===============================\n");
    printf("总接收: %lld bytes (%.1f KB)\n", totalBytes, (double)totalBytes/1024);
    printf("时间: %.1f 秒\n", (double)elapsed/1000);
    printf("平均速率: %.1f KB/s\n", avgRate);
    printf("===============================\n\n");

    // 判断结果
    if (avgRate > 550) {
        printf("✅ 速率超过550 KB/s - Python可能是瓶颈\n");
    } else if (avgRate > 450 && avgRate < 550) {
        printf("⚠️  速率在450-550 KB/s - 可能是Windows驱动限制\n");
        printf("   证据：C程序也无法突破500 KB/s\n");
    } else {
        printf("❌ 速率低于450 KB/s - 可能FPGA或其他问题\n");
    }

    CloseHandle(hSerial);
    return 0;
}
