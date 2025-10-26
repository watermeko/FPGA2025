Import-Module BurntToast

$logFilePath = "C:\Development\GOWIN\FPGA2025\impl\pnr\fpga_project.log"
$searchPattern = 'Generate file "(.+?)\.tr\.html" completed'
$checkInterval = 2  # 检查间隔（秒）

Write-Host "开始监控日志文件: $logFilePath" -ForegroundColor Green
Write-Host "按 Ctrl+C 停止监控..." -ForegroundColor Yellow

$lastPosition = 0
$lastFileSize = 0

try {
    while ($true) {
        if (Test-Path $logFilePath) {
            $currentFileSize = (Get-Item $logFilePath).Length
            
            # 检测文件是否被重写
            if ($currentFileSize -lt $lastFileSize) {
                Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 检测到日志文件被重写，重置读取位置" -ForegroundColor Yellow
                $lastPosition = 0
            }
            
            $lastFileSize = $currentFileSize
            
            # 读取新内容
            if ($currentFileSize -gt $lastPosition) {
                $fileStream = [System.IO.File]::Open($logFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fileStream.Seek($lastPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = New-Object System.IO.StreamReader($fileStream)
                
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ($line -match $searchPattern) {
                        $fileName = $matches[1]
                        
                        New-BurntToastNotification -Text "文件生成完成", "已生成: $fileName.tr.html"
                        
                        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 检测到文件生成: $fileName.tr.html" -ForegroundColor Cyan
                    }
                }
                
                $lastPosition = $fileStream.Position
                $reader.Close()
                $fileStream.Close()
            }
        }
        else {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 等待日志文件创建..." -ForegroundColor Yellow
            $lastPosition = 0
            $lastFileSize = 0
        }
        
        Start-Sleep -Seconds $checkInterval
    }
}
catch {
    Write-Host "发生错误: $_" -ForegroundColor Red
}

