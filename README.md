# Codex Sub2API 一键配置工具

这个工具用于 Windows 用户：

- 检查并尝试安装 Microsoft Store 版 Codex
- 可临时使用用户电脑上的本机代理，帮助下载安装 Codex
- 可临时使用管理员提供的 Clash/Mihomo 订阅启动本机代理，帮助下载安装 Codex
- 写入 Sub2API 的 Codex 配置
- 把 API Key 写入 `%USERPROFILE%\.codex\auth.json`
- 自动备份原始 `config.toml` 和 `auth.json`
- 写入 API Key 后尽量把 `auth.json` 权限收紧到当前 Windows 用户

## 推荐用法：双击安装

解压后优先双击：

```text
启动安装器.vbs
```

会打开一个简单窗口：

1. 粘贴 Sub2API 后台创建的 API Key。
2. 默认模型保持 `gpt-5.5`。
3. 网络正常时代理留空。
4. 如果 Microsoft Store 下载困难，只填写这台电脑自己的本机代理，例如 `http://127.0.0.1:7890`，并勾选“临时写入 Windows 系统代理”。
5. 如果需要临时使用服务器节点，勾选“下载安装 Codex 时临时使用服务器节点”。一次性节点 URL 可以留空，工具会用用户填写的 API Key 自动申请。
6. 点击“开始安装并配置”。

如果工具打开了 Microsoft Store 页面，但没有自动装完 Codex，请先在商店里点安装并等它完成。完成后再次运行本工具，工具检测到 Codex 已安装后才会写入配置。

如果某台电脑不能执行 `.cmd` 文件，按这个顺序尝试：

1. 双击 `启动安装器.vbs`
2. 双击 `install.bat`
3. 右键 `启动安装器.ps1`，选择“使用 PowerShell 运行”

这几个入口调用的是同一个安装脚本，功能完全一样。

## Windows 环境检测

工具会在安装前检查：

- Windows 版本和 64 位系统
- `winget` / App Installer
- Microsoft Store 包
- 可选开发工具：Git、Node.js、Python、GitHub CLI、WSL

Codex 官方 Windows 文档说明：Windows 版可以使用原生 Codex app、CLI 或 IDE 扩展；Windows app 默认走 PowerShell 原生 agent，并支持 Windows sandbox；WSL2 是需要 Linux 环境时的可选路径。Microsoft Store 页面当前标注的最低系统要求是 Windows 10 version 19041.0 或更高。

完成后重启 Codex 即可使用。

## 命令行用法

```powershell
cd H:\code\codex-sub2api-installer
.\install.cmd -ApiKey sk-你的key
```

默认配置：

- Base URL: `https://api.liusq.icu/v1`
- Model: `gpt-5.5`
- Provider: `sub2api`

## 带代理安装

如果 Microsoft Store 或 winget 下载失败，可以临时走用户电脑自己的本机代理：

```powershell
.\install.cmd -ApiKey sk-你的key -ProxyUrl http://127.0.0.1:7890
```

如果 Store/App Installer 仍然连不上，可以临时写入 WinHTTP 和当前用户代理，安装结束后自动恢复：

```powershell
.\install.cmd -ApiKey sk-你的key -ProxyUrl http://127.0.0.1:7890 -UseSystemProxyForInstall
```

## 使用一次性服务器节点安装 Codex

这个模式只用于下载安装 Codex，不会写入 Codex 配置，也不会长期运行。

推荐方式：用户不需要手动拿节点链接。勾选服务器节点后，工具会用用户填写的 Sub2API API Key 自动向服务器申请一次性 URL。

管理员也可以手动生成一次性 URL：

```bash
codex-node-url 60 codex-install
```

第一参数是有效分钟数，第二参数是备注。手动生成的 URL 形如：

```text
https://api.liusq.icu/node-onetime/<token>/clmi.yaml
```

这个 URL 只能下载一次，过期或用过后会返回 410/404。

```powershell
.\install.cmd -ApiKey sk-你的key `
  -UseServerNodeForInstall `
  -UseSystemProxyForInstall
```

也可以手动指定一次性 URL：

```powershell
.\install.cmd -ApiKey sk-你的key `
  -UseServerNodeForInstall `
  -MihomoSubscriptionUrl "https://api.liusq.icu/node-onetime/<token>/clmi.yaml" `
  -UseSystemProxyForInstall
```

执行时工具会：

1. 优先从 `https://api.liusq.icu/downloads/mihomo-windows-amd64.zip` 下载 Mihomo Windows amd64 核心到临时目录，失败时回退 GitHub。
2. 拉取你粘贴的一次性 Clash/Mihomo YAML。
3. 在本机启动 `127.0.0.1:7897` 临时代理。
4. 临时设置当前进程代理；勾选系统代理时也会临时设置 WinHTTP/当前用户代理。
5. 安装结束后关闭 Mihomo，并删除临时目录。

不要把长期订阅 URL 写死在公开安装包里。只要写进脚本、exe 或配置文件，别人就能提取并长期使用节点。

## 只写配置，不安装

```powershell
.\install.cmd -ApiKey sk-你的key -SkipInstall
```

## 自定义模型

```powershell
.\install.cmd -ApiKey sk-你的key -Model gpt-5.4
```

## 配置结果

工具会写入：

`%USERPROFILE%\.codex\config.toml`

```toml
model = "gpt-5.5"
model_provider = "sub2api"

[model_providers.sub2api]
name = "sub2api"
wire_api = "responses"
requires_openai_auth = true
base_url = "https://api.liusq.icu/v1"
```

`%USERPROFILE%\.codex\auth.json`

```json
{
  "OPENAI_API_KEY": "sk-你的key"
}
```

## 给用户的最短说明

1. 在 Sub2API 后台创建 API Key。
2. 下载并解压这个工具。
3. 双击 `启动安装器.vbs`；如果打不开，再试 `install.bat`。
4. 粘贴 API Key，点击开始。
5. 打开或重启 Codex，即可使用。

## 注意

- API Key 不会写进 `config.toml`，只写进 Codex 使用的 `auth.json`。
- 工具包不内置你的服务器节点、代理账号、代理密码或任何公共可复用网络入口。
- 不建议把服务器节点写入客户端工具。只要写进脚本、exe 或配置文件，别人都可以提取并滥用，最终会消耗你的服务器流量、CPU、带宽和 IP 信誉。
- 服务器节点模式只接受运行时手动粘贴的一次性 Clash/Mihomo URL，不要粘贴 sing-box 原始长期订阅。
- 使用 `-UseSystemProxyForInstall` 时，脚本会临时修改 WinHTTP 和当前用户代理，安装结束后自动恢复。
- 如果 Microsoft Store 无法被脚本自动安装，脚本会打开 Store 搜索页，用户可以手动安装后再运行 `-SkipInstall` 写配置。
- 工具不会再在 Codex 未安装完成时提示“配置完成”。如果商店安装还没完成，会要求你安装完成后重新运行。

## 重新配置 API Key

以后用户换了 API Key，仍然可以继续使用这个工具：

1. 双击 `启动安装器.vbs`；如果打不开，再试 `install.bat`。
2. 粘贴新的 Sub2API API Key。
3. 勾选“只写配置，不安装 Codex”。
4. 点击开始。

这样只会更新 `%USERPROFILE%\.codex\auth.json` 和 `config.toml`，不会重新下载安装 Codex。

## 安全设计

这个最终版只包含公开服务地址：

```text
https://api.liusq.icu/v1
```

用户需要自己在 Sub2API 后台创建 API Key，然后粘贴到工具里。工具不会生成、内置或共享 API Key。

下载安装 Codex 的网络问题可以由用户本机代理解决，也可以让工具自动申请一次性服务器节点 URL。不要把服务器原始长期订阅写进这里。

## 给测试电脑的流程

1. 下载并解压工具包。
2. 双击 `启动安装器.vbs`；如果打不开，再试 `install.bat`。
3. 粘贴 Sub2API API Key。
4. 模型默认 `gpt-5.5`。
5. 网络正常时代理留空。
6. 如果商店下载失败，先在测试电脑配置本机代理，再在工具里填 `http://127.0.0.1:7890`。
7. 完成后关闭并重新打开 Codex。

## 启动失败处理

有些电脑因为公司策略、杀毒软件、文件关联损坏或 Windows SmartScreen，可能无法双击 `.cmd`。

处理顺序：

0. 必须先解压 zip，再运行里面的文件；不要在压缩包预览窗口里直接双击。
1. 先用 `启动安装器.vbs`。
2. 如果 VBS 被禁用，用 `install.bat`。
3. 如果 BAT/CMD 都被禁用，用 `启动安装器.ps1`，右键选择“使用 PowerShell 运行”。
4. 如果提示文件来自互联网被阻止，右键 zip 或脚本文件，打开“属性”，勾选“解除锁定”。
5. 如果仍然不能运行，把同目录下的 `install-error.log` 发给管理员排查。

新版启动器会自动尝试解除 Windows 下载文件锁定，并把启动错误写入 `install-error.log`。如果 PowerShell 或系统策略完全禁止脚本执行，这台电脑需要使用管理员账号调整策略，或换一台电脑配置。
