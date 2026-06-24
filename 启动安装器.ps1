# 双击运行也可以；如被系统阻止，请右键选择“使用 PowerShell 运行”。
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $base 'install-error.log'
try {
    Get-ChildItem -LiteralPath $base -File | Unblock-File -ErrorAction SilentlyContinue
    & (Join-Path $base 'setup-codex-sub2api.ps1') -Gui *>> $log
} catch {
    $_ | Out-String | Add-Content -LiteralPath $log
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '安装器启动失败', 'OK', 'Error') | Out-Null
    throw
}

