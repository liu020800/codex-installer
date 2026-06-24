<# 
.SYNOPSIS
  Install Microsoft Store Codex and configure it for a Sub2API/OpenAI-compatible endpoint.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-codex-sub2api.ps1 -ApiKey sk-xxx

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\setup-codex-sub2api.ps1 `
    -ApiBaseUrl https://api.liusq.icu/v1 -ApiKey sk-xxx -Model gpt-5.5 `
    -ProxyUrl http://127.0.0.1:7890 -UseSystemProxyForInstall
#>

[CmdletBinding()]
param(
    [string]$ApiBaseUrl = "https://api.liusq.icu/v1",
    [string]$ApiKey,
    [string]$Model = "gpt-5.5",
    [string]$ProviderName = "sub2api",
    [string]$ProxyUrl,
    [string]$MihomoSubscriptionUrl,
    [switch]$UseServerNodeForInstall,
    [switch]$UseSystemProxyForInstall,
    [switch]$KeepProxy,
    [switch]$SkipInstall,
    [switch]$Gui
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Escape-TomlString {
    param([string]$Value)
    if ($null -eq $Value) {
        return ""
    }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Backup-File {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backup = "$Path.bak.$stamp"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Host "Backed up: $backup"
    }
}

function Protect-FileForCurrentUser {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity,
            "FullControl",
            "Allow"
        )
        $acl.SetOwner([System.Security.Principal.NTAccount]$identity)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $acl
    } catch {
        Write-Warning "Could not tighten file permissions for ${Path}: $($_.Exception.Message)"
    }
}

function Test-CodexInstalled {
    if (Get-Command codex -ErrorAction SilentlyContinue) {
        return $true
    }
    try {
        $pkg = Get-AppxPackage -Name "OpenAI.Codex" -ErrorAction Stop
        return [bool]$pkg
    } catch {
        return $false
    }
}

function Test-CodexEnvironment {
    $results = New-Object System.Collections.Generic.List[string]
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $caption = $os.Caption

    if ($caption -match "Windows 11" -or ($caption -match "Windows 10" -and $build -ge 17763)) {
        $results.Add("OK  Windows: $caption build $build")
    } else {
        $results.Add("WARN Windows: $caption build $build. Codex for Windows is intended for Windows 11 or Windows 10 1809+.")
    }

    if ([Environment]::Is64BitOperatingSystem) {
        $results.Add("OK  Architecture: 64-bit Windows")
    } else {
        $results.Add("WARN Architecture: 64-bit Windows is recommended.")
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $results.Add("OK  winget/App Installer found")
    } else {
        $results.Add("WARN winget/App Installer not found. Microsoft Store may need manual installation.")
    }

    try {
        $storePkg = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction Stop
        if ($storePkg) {
            $results.Add("OK  Microsoft Store package found")
        }
    } catch {
        $results.Add("WARN Microsoft Store package not found or unavailable for this user.")
    }

    foreach ($tool in @("git", "node", "python", "gh", "wsl")) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) {
            $results.Add("OK  Optional dev tool found: $tool")
        } else {
            $results.Add("INFO Optional dev tool not found: $tool")
        }
    }

    return $results
}

function Write-CodexEnvironmentReport {
    Write-Step "Checking Windows environment"
    $items = Test-CodexEnvironment
    foreach ($item in $items) {
        if ($item.StartsWith("WARN")) {
            Write-Warning $item.Substring(5)
        } else {
            Write-Host $item
        }
    }
}

function Start-TemporaryMihomoProxy {
    param([string]$SubscriptionUrl)

    if ([string]::IsNullOrWhiteSpace($SubscriptionUrl)) {
        throw "Mihomo subscription URL is required when server-node install mode is enabled."
    }

    $workDir = Join-Path $env:TEMP ("sub2api-mihomo-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    $proxyPort = 7897
    $controllerPort = 9097

    Write-Host "Preparing temporary Mihomo proxy in $workDir"

    $zipPath = Join-Path $workDir "mihomo-windows-amd64.zip"
    try {
        Invoke-WebRequest -Uri "https://api.liusq.icu/downloads/mihomo-windows-amd64.zip" -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Warning "Hosted Mihomo download failed, falling back to GitHub: $($_.Exception.Message)"
        $apiHeaders = @{
            "User-Agent" = "sub2api-codex-installer"
        }
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" -Headers $apiHeaders
        $asset = $release.assets | Where-Object {
            $_.name -match "windows-amd64.*\.zip$" -and $_.name -notmatch "go120|compatible"
        } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -match "windows-amd64.*\.zip$" } | Select-Object -First 1
        }
        if (-not $asset) {
            throw "Could not find a Windows amd64 Mihomo release asset."
        }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $workDir -Force

    $mihomoExe = Get-ChildItem -LiteralPath $workDir -Recurse -Filter "*.exe" |
        Where-Object { $_.Name -match "mihomo|clash" } |
        Select-Object -First 1
    if (-not $mihomoExe) {
        throw "Mihomo executable was not found after extraction."
    }

    $configPath = Join-Path $workDir "config.yaml"
    Invoke-WebRequest -Uri $SubscriptionUrl -OutFile $configPath -UseBasicParsing

    Add-Content -LiteralPath $configPath -Encoding UTF8 -Value @"

mixed-port: $proxyPort
allow-lan: false
mode: rule
log-level: warning
external-controller: 127.0.0.1:$controllerPort
"@

    $proc = Start-Process -FilePath $mihomoExe.FullName -ArgumentList @("-f", $configPath, "-d", $workDir) -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        throw "Mihomo exited immediately. Check whether the subscription URL is a valid Clash/Mihomo YAML."
    }

    $oldProxyUrl = $script:ProxyUrl
    $script:ProxyUrl = "http://127.0.0.1:$proxyPort"

    return [pscustomobject]@{
        Process = $proc
        WorkDir = $workDir
        OldProxyUrl = $oldProxyUrl
        ProxyUrl = $script:ProxyUrl
    }
}

function Get-OneTimeNodeUrl {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "ApiKey is required before requesting a one-time node URL."
    }

    $issueUrl = $ApiBaseUrl.TrimEnd('/') -replace '/v1$', ''
    $issueUrl = $issueUrl.TrimEnd('/') + "/node-onetime/issue"

    $headers = @{
        Authorization = "Bearer $ApiKey"
        Accept = "application/json"
    }
    $response = Invoke-RestMethod -Uri $issueUrl -Method Post -Headers $headers -ContentType "application/json" -Body "{}"
    if (-not $response.url) {
        throw "Server did not return a one-time node URL."
    }
    return [string]$response.url
}

function Stop-TemporaryMihomoProxy {
    param($Handle)
    if (-not $Handle) {
        return
    }
    try {
        if ($Handle.Process -and -not $Handle.Process.HasExited) {
            Stop-Process -Id $Handle.Process.Id -Force -ErrorAction SilentlyContinue
        }
    } finally {
        $script:ProxyUrl = $Handle.OldProxyUrl
        if ($Handle.WorkDir -and (Test-Path -LiteralPath $Handle.WorkDir)) {
            Remove-Item -LiteralPath $Handle.WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WithOptionalServerNode {
    param([scriptblock]$Script)

    $mihomoHandle = $null
    try {
        if ($UseServerNodeForInstall -and -not $SkipInstall) {
            if ([string]::IsNullOrWhiteSpace($MihomoSubscriptionUrl)) {
                Write-Host "Requesting one-time node URL with the provided Sub2API API Key..."
                $script:MihomoSubscriptionUrl = Get-OneTimeNodeUrl
            }
            $mihomoHandle = Start-TemporaryMihomoProxy -SubscriptionUrl $script:MihomoSubscriptionUrl
            Write-Host "Temporary node proxy started: $($mihomoHandle.ProxyUrl)"
        }
        & $Script
    } finally {
        Stop-TemporaryMihomoProxy $mihomoHandle
    }
}

function Invoke-WithTemporaryProxy {
    param([scriptblock]$Script)

    $oldEnv = @{
        HTTP_PROXY  = $env:HTTP_PROXY
        HTTPS_PROXY = $env:HTTPS_PROXY
        ALL_PROXY   = $env:ALL_PROXY
        NO_PROXY    = $env:NO_PROXY
    }
    $oldWinHttp = $null
    $oldUserProxy = $null

    try {
        if ($ProxyUrl) {
            Write-Host "Using temporary proxy for this process: $ProxyUrl"
            $env:HTTP_PROXY = $ProxyUrl
            $env:HTTPS_PROXY = $ProxyUrl
            $env:ALL_PROXY = $ProxyUrl
            if (-not $env:NO_PROXY) {
                $env:NO_PROXY = "localhost,127.0.0.1,::1"
            }

            if ($UseSystemProxyForInstall) {
                Write-Host "Temporarily applying current-user proxy for Store/App Installer."
                try {
                    $oldWinHttp = (& netsh winhttp show proxy 2>$null) -join "`n"
                    & netsh winhttp set proxy $ProxyUrl 2>$null | Out-Null
                } catch {
                    Write-Warning "WinHTTP proxy could not be changed. Continuing with current-user proxy only. Run as administrator only if Store still cannot download."
                }

                $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
                $oldUserProxy = @{
                    ProxyEnable = (Get-ItemProperty -Path $internetSettings -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
                    ProxyServer = (Get-ItemProperty -Path $internetSettings -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
                }
                Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Type DWord -Value 1
                Set-ItemProperty -Path $internetSettings -Name ProxyServer -Type String -Value $ProxyUrl
                rundll32.exe inetcpl.cpl,ClearMyTracksByProcess 8 | Out-Null
            }
        }

        & $Script
    }
    finally {
        $env:HTTP_PROXY = $oldEnv.HTTP_PROXY
        $env:HTTPS_PROXY = $oldEnv.HTTPS_PROXY
        $env:ALL_PROXY = $oldEnv.ALL_PROXY
        $env:NO_PROXY = $oldEnv.NO_PROXY

        if ($ProxyUrl -and $UseSystemProxyForInstall -and -not $KeepProxy) {
            Write-Host "Restoring previous proxy settings."
            try {
                & netsh winhttp reset proxy 2>$null | Out-Null
            } catch {
                Write-Warning "WinHTTP proxy restore failed. Current-user proxy will still be restored."
            }
            $internetSettings = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
            if ($oldUserProxy -and $null -ne $oldUserProxy.ProxyEnable) {
                Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Type DWord -Value $oldUserProxy.ProxyEnable
            } else {
                Set-ItemProperty -Path $internetSettings -Name ProxyEnable -Type DWord -Value 0
            }
            if ($oldUserProxy -and $oldUserProxy.ProxyServer) {
                Set-ItemProperty -Path $internetSettings -Name ProxyServer -Type String -Value $oldUserProxy.ProxyServer
            } else {
                Remove-ItemProperty -Path $internetSettings -Name ProxyServer -ErrorAction SilentlyContinue
            }
            rundll32.exe inetcpl.cpl,ClearMyTracksByProcess 8 | Out-Null
        }
    }
}

function Install-CodexIfNeeded {
    if ($SkipInstall) {
        Write-Host "Skipping Codex installation by request."
        return $true
    }

    if (Test-CodexInstalled) {
        Write-Host "Codex already appears to be installed."
        return $true
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning "winget/App Installer was not found. Opening Microsoft Store search page."
        Start-Process "ms-windows-store://search/?query=OpenAI%20Codex"
        return $false
    }

    Write-Host "Installing Codex from Microsoft Store via winget..."
    $installArgs = @(
        "install",
        "--id", "OpenAI.Codex",
        "--source", "msstore",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--silent"
    )
    $proc = Start-Process -FilePath $winget.Source -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Warning "winget install by id failed with exit code $($proc.ExitCode). Opening Microsoft Store search page."
        Start-Process "ms-windows-store://search/?query=OpenAI%20Codex"
        return $false
    }

    Start-Sleep -Seconds 2
    return (Test-CodexInstalled)
}

function Ensure-CodexReadyForConfig {
    if ($SkipInstall) {
        return
    }
    if (-not (Test-CodexInstalled)) {
        throw "Codex 还没有安装完成。请先在 Microsoft Store/winget 完成 Codex 安装，然后重新运行本工具写入配置。"
    }
}

function Set-CodexConfig {
    if (-not $ApiKey) {
        $secure = Read-Host "Enter Sub2API API Key" -AsSecureString
        $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        )
    }
    if (-not $ApiKey) {
        throw "ApiKey is required."
    }

    $codexHome = Join-Path $env:USERPROFILE ".codex"
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null

    $authPath = Join-Path $codexHome "auth.json"
    $configPath = Join-Path $codexHome "config.toml"

    Write-Step "Writing Codex auth"
    Backup-File $authPath
    $auth = [ordered]@{}
    if (Test-Path -LiteralPath $authPath) {
        try {
            $existing = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) {
                $auth[$p.Name] = $p.Value
            }
        } catch {
            Write-Warning "Existing auth.json could not be parsed; replacing it after backup."
        }
    }
    $auth["OPENAI_API_KEY"] = $ApiKey
    ($auth | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $authPath -Encoding UTF8
    Protect-FileForCurrentUser $authPath

    Write-Step "Writing Codex provider config"
    Backup-File $configPath
    $lines = @()
    if (Test-Path -LiteralPath $configPath) {
        $lines = @(Get-Content -LiteralPath $configPath)
    }

    $modelLine = 'model = "' + (Escape-TomlString $Model) + '"'
    $providerLine = 'model_provider = "' + (Escape-TomlString $ProviderName) + '"'

    $hasModel = $false
    $hasProvider = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*model\s*=') {
            $lines[$i] = $modelLine
            $hasModel = $true
        } elseif ($lines[$i] -match '^\s*model_provider\s*=') {
            $lines[$i] = $providerLine
            $hasProvider = $true
        }
    }
    if (-not $hasModel) {
        $lines = @($modelLine) + $lines
    }
    if (-not $hasProvider) {
        $insertAt = if ($hasModel) { 1 } else { [Math]::Min(1, $lines.Count) }
        $before = if ($insertAt -gt 0) { $lines[0..($insertAt-1)] } else { @() }
        $after = if ($insertAt -lt $lines.Count) { $lines[$insertAt..($lines.Count-1)] } else { @() }
        $lines = @($before) + @($providerLine) + @($after)
    }

    $sectionPattern = '^\s*\[model_providers\."' + [regex]::Escape($ProviderName) + '"\]\s*$|^\s*\[model_providers\.' + [regex]::Escape($ProviderName) + '\]\s*$'
    $filtered = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
        if ($line -match $sectionPattern) {
            $skip = $true
            continue
        }
        if ($skip -and $line -match '^\s*\[') {
            $skip = $false
        }
        if (-not $skip) {
            $filtered.Add($line)
        }
    }

    $escapedProviderName = Escape-TomlString $ProviderName
    $escapedBaseUrl = Escape-TomlString $ApiBaseUrl.TrimEnd('/')
    $providerNameLine = "name = `"$escapedProviderName`""
    $baseUrlLine = "base_url = `"$escapedBaseUrl`""

    $providerSection = @(
        "",
        "[model_providers.$ProviderName]",
        $providerNameLine,
        'wire_api = "responses"',
        "requires_openai_auth = true",
        $baseUrlLine
    )
    $final = @($filtered) + $providerSection
    $final | Set-Content -LiteralPath $configPath -Encoding UTF8

    Write-Host "Configured Codex:"
    Write-Host "  Provider : $ProviderName"
    Write-Host "  Base URL : $($ApiBaseUrl.TrimEnd('/'))"
    Write-Host "  Model    : $Model"
}

function Show-CodexSetupGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Sub2API Codex 一键配置"
    $form.StartPosition = "CenterScreen"
    $form.ClientSize = New-Object System.Drawing.Size(680, 680)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
    $form.Font = $font

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Sub2API Codex 一键配置"
    $title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 15, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(18, 16)
    $title.Size = New-Object System.Drawing.Size(600, 32)
    $form.Controls.Add($title)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text = "填入 Sub2API 后台创建的 API Key，点击开始即可安装/配置 Codex。工具不内置服务器节点。"
    $desc.Location = New-Object System.Drawing.Point(20, 54)
    $desc.Size = New-Object System.Drawing.Size(600, 24)
    $form.Controls.Add($desc)

    function Add-Label {
        param([string]$Text, [int]$Y)
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text
        $label.Location = New-Object System.Drawing.Point(22, $Y)
        $label.Size = New-Object System.Drawing.Size(130, 24)
        $form.Controls.Add($label)
        return $label
    }

    function Add-TextBox {
        param([string]$Text, [int]$Y, [bool]$Password = $false)
        $box = New-Object System.Windows.Forms.TextBox
        $box.Text = $Text
        $box.Location = New-Object System.Drawing.Point(170, $Y)
        $box.Size = New-Object System.Drawing.Size(470, 26)
        if ($Password) {
            $box.UseSystemPasswordChar = $true
        }
        $form.Controls.Add($box)
        return $box
    }

    Add-Label "API Key" 98 | Out-Null
    $apiKeyBox = Add-TextBox "" 94 $true

    Add-Label "模型" 138 | Out-Null
    $modelBox = Add-TextBox $Model 134

    Add-Label "Base URL" 178 | Out-Null
    $baseUrlBox = Add-TextBox $ApiBaseUrl 174

    Add-Label "代理地址" 218 | Out-Null
    $proxyBox = Add-TextBox $ProxyUrl 214

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = "代理只填写用户自己电脑上的本机代理，例如：http://127.0.0.1:7890。网络正常可留空。"
    $hint.Location = New-Object System.Drawing.Point(170, 242)
    $hint.Size = New-Object System.Drawing.Size(470, 22)
    $hint.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($hint)

    $serverNodeBox = New-Object System.Windows.Forms.CheckBox
    $serverNodeBox.Text = "下载安装 Codex 时临时使用服务器节点"
    $serverNodeBox.Location = New-Object System.Drawing.Point(170, 270)
    $serverNodeBox.Size = New-Object System.Drawing.Size(470, 24)
    $serverNodeBox.Checked = [bool]$UseServerNodeForInstall
    $form.Controls.Add($serverNodeBox)

    Add-Label "一次性节点URL" 302 | Out-Null
    $mihomoSubscriptionBox = Add-TextBox $MihomoSubscriptionUrl 298

    $nodeHint = New-Object System.Windows.Forms.Label
    $nodeHint.Text = "可留空自动申请一次性 URL；也可手动填写。不会保存进 Codex 配置。"
    $nodeHint.Location = New-Object System.Drawing.Point(170, 326)
    $nodeHint.Size = New-Object System.Drawing.Size(470, 22)
    $nodeHint.ForeColor = [System.Drawing.Color]::DimGray
    $form.Controls.Add($nodeHint)

    $systemProxyBox = New-Object System.Windows.Forms.CheckBox
    $systemProxyBox.Text = "下载安装时临时写入 Windows 系统代理，结束后自动恢复"
    $systemProxyBox.Location = New-Object System.Drawing.Point(170, 354)
    $systemProxyBox.Size = New-Object System.Drawing.Size(470, 24)
    $systemProxyBox.Checked = [bool]$UseSystemProxyForInstall
    $form.Controls.Add($systemProxyBox)

    $skipInstallBox = New-Object System.Windows.Forms.CheckBox
    $skipInstallBox.Text = "只写配置，不安装 Codex"
    $skipInstallBox.Location = New-Object System.Drawing.Point(170, 384)
    $skipInstallBox.Size = New-Object System.Drawing.Size(470, 24)
    $skipInstallBox.Checked = [bool]$SkipInstall
    $form.Controls.Add($skipInstallBox)

    $showKeyBox = New-Object System.Windows.Forms.CheckBox
    $showKeyBox.Text = "显示 API Key"
    $showKeyBox.Location = New-Object System.Drawing.Point(170, 414)
    $showKeyBox.Size = New-Object System.Drawing.Size(160, 24)
    $showKeyBox.Add_CheckedChanged({
        $apiKeyBox.UseSystemPasswordChar = -not $showKeyBox.Checked
    })
    $form.Controls.Add($showKeyBox)

    $statusBox = New-Object System.Windows.Forms.TextBox
    $statusBox.Location = New-Object System.Drawing.Point(22, 454)
    $statusBox.Size = New-Object System.Drawing.Size(618, 150)
    $statusBox.Multiline = $true
    $statusBox.ScrollBars = "Vertical"
    $statusBox.ReadOnly = $true
    $statusBox.Text = "准备就绪。不会使用或暴露服务器节点；API Key 只写入当前用户的 Codex 配置。`r`n"
    $form.Controls.Add($statusBox)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = "开始安装并配置"
    $startButton.Location = New-Object System.Drawing.Point(360, 624)
    $startButton.Size = New-Object System.Drawing.Size(140, 34)
    $form.Controls.Add($startButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "关闭"
    $closeButton.Location = New-Object System.Drawing.Point(528, 624)
    $closeButton.Size = New-Object System.Drawing.Size(112, 34)
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    $openSiteButton = New-Object System.Windows.Forms.Button
    $openSiteButton.Text = "打开 Sub2API"
    $openSiteButton.Location = New-Object System.Drawing.Point(22, 624)
    $openSiteButton.Size = New-Object System.Drawing.Size(130, 34)
    $openSiteButton.Add_Click({ Start-Process "https://api.liusq.icu" })
    $form.Controls.Add($openSiteButton)

    $appendStatus = {
        param([string]$Text)
        $statusBox.AppendText("[$(Get-Date -Format HH:mm:ss)] $Text`r`n")
        $statusBox.SelectionStart = $statusBox.TextLength
        $statusBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $startButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($apiKeyBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("请先粘贴 Sub2API API Key。", "缺少 API Key", "OK", "Warning") | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($baseUrlBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Base URL 不能为空。", "缺少 Base URL", "OK", "Warning") | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($modelBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("模型不能为空。", "缺少模型", "OK", "Warning") | Out-Null
            return
        }
        $startButton.Enabled = $false
        $closeButton.Enabled = $false
        try {
            Set-Variable -Name ApiKey -Scope Script -Value $apiKeyBox.Text.Trim()
            Set-Variable -Name ApiBaseUrl -Scope Script -Value $baseUrlBox.Text.Trim()
            Set-Variable -Name Model -Scope Script -Value $modelBox.Text.Trim()
            Set-Variable -Name ProxyUrl -Scope Script -Value $proxyBox.Text.Trim()
            Set-Variable -Name UseServerNodeForInstall -Scope Script -Value ([bool]$serverNodeBox.Checked)
            Set-Variable -Name MihomoSubscriptionUrl -Scope Script -Value $mihomoSubscriptionBox.Text.Trim()
            Set-Variable -Name UseSystemProxyForInstall -Scope Script -Value ([bool]$systemProxyBox.Checked)
            Set-Variable -Name SkipInstall -Scope Script -Value ([bool]$skipInstallBox.Checked)

            & $appendStatus "开始处理..."
            & $appendStatus "检测 Windows / Store / winget 环境..."
            foreach ($item in (Test-CodexEnvironment)) {
                & $appendStatus $item
            }
            & $appendStatus "检查/安装 Codex..."
            if ($serverNodeBox.Checked -and [string]::IsNullOrWhiteSpace($mihomoSubscriptionBox.Text) -and -not $skipInstallBox.Checked) {
                & $appendStatus "将使用 API Key 自动申请一次性节点 URL..."
            }
            $installed = Invoke-WithOptionalServerNode {
                Invoke-WithTemporaryProxy {
                    Install-CodexIfNeeded
                }
            }
            Ensure-CodexReadyForConfig
            & $appendStatus "写入 Codex 配置..."
            Set-CodexConfig
            & $appendStatus "完成。请关闭并重新打开 Codex。"
            [System.Windows.Forms.MessageBox]::Show("配置完成。请关闭并重新打开 Codex 后使用。", "完成", "OK", "Information") | Out-Null
        } catch {
            & $appendStatus "失败：$($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "配置失败", "OK", "Error") | Out-Null
        } finally {
            $startButton.Enabled = $true
            $closeButton.Enabled = $true
        }
    })

    [void]$form.ShowDialog()
}

if ($Gui -or $PSBoundParameters.Count -eq 0) {
    Show-CodexSetupGui
    return
}

Write-CodexEnvironmentReport

Write-Step "Preparing network and installing Codex"
Invoke-WithOptionalServerNode {
    Invoke-WithTemporaryProxy {
        Install-CodexIfNeeded
    }
}
Ensure-CodexReadyForConfig

Set-CodexConfig

Write-Step "Done"
Write-Host "Restart Codex if it is already open, then choose/use model '$Model'."



