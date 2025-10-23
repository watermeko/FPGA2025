$process = Start-Process python -ArgumentList ".\software\diagnose_dc.py" -PassThru -NoNewWindow
$process | Wait-Process -Timeout 1800 -ErrorAction SilentlyContinue

if (!$process.HasExited) {
    $process | Stop-Process -Force
    Write-Host "Python脚本执行超时（30秒），已终止"
}

