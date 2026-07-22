# YIME 安装态复核 · 2026-07-22

> 范围：本机 `C:\Program Files (x86)\YIME` 中的 `1.4.0-dev` 安装态。
> 本记录核对安装完整性和当前运行状态，不代表正式签名发行验收，也不替代真实宿主中的输入烟雾测试。

## 结论

项目自带的 `tools\verify-installed-runtime.ps1` 返回 `complete`。当前安装文件与仓库构建物一致，安装根和自启动注册表正确，`PIMELauncher` 从安装目录运行；安装树中没有等待重启替换的 `.new` 文件。本轮随后补齐了布局设计器 VERSIONINFO 和卸载项 `InstallLocation`，重新构建安装包并完成原位安装，两项均已在 Program Files 安装态复核通过。

本机安装包和关键二进制均未签名，因此此结论只适用于开发安装完整性。公开发布仍须使用可信代码签名，并在干净的 Smart App Control/WDAC 环境重新验证。

## 核对结果

| 项目 | 结果 | 证据 |
|------|------|------|
| 安装根 | 通过 | `HKLM\SOFTWARE\YIME` 指向 `C:\Program Files (x86)\YIME` |
| 安装版本 | 通过 | `version.txt`、启动器、安装包及 9 个 Go EXE 均带版本信息；Go 侧为 `1.4.0-dev`，TSF DLL 文件版本为 `1.4.0` |
| 启动器 | 通过 | 两个 `PIMELauncher.exe` 进程均从安装根运行 |
| Go 后端 | 通过 | `server.exe` 从 `go-backend` 运行 |
| 自启动 | 通过 | `HKLM\...\Run\PIMELauncher` 指向已安装启动器 |
| 文件同步 | 通过 | 启动器、x86/x64 TSF DLL、`server.exe`、8 个原生 Go 子工具（连同 `server.exe` 共 9 个 Go EXE）、`rime.dll` 和 `rime_deployer.exe` 全部为 `match` |
| TSF 待重启替换 | 通过 | 安装树中 `.new` 文件数为 0 |
| YIME-only 布局 | 通过 | `go-backend\input_methods` 下只有 `yime` |
| 卸载入口 | 通过 | Windows 卸载项显示 `YIME 输入法 1.4.0-dev`，指向安装根中的 `uninstall.exe`，`InstallLocation` 为 `C:\Program Files (x86)\YIME` |
| 代码签名 | 未完成 | 安装包、启动器、后端和 TSF DLL 均为 `NotSigned` |

## 关键哈希

| 文件 | SHA-256 |
|------|---------|
| `PIMELauncher.exe` | `71CD809A8E64CFBE659BA31E44C9E0443AF33086BCCF42F20BAD946EB63C6425` |
| `go-backend\server.exe` | `EE757995C3E9A20CC98FB66C4D4242B264B617EB8ECB8D00A1D50057C413F497` |
| `x86\PIMETextService.dll` | `351058CC1990FE1ABCC5508B051E9CF9E5CE0546AC645724B1443D28BA92C11E` |
| `x64\PIMETextService.dll` | `2AF133D38760E4B6484CAA5DB5F11654EFA1DE749F0B3B5FF83B1079732BAA3D` |
| `go-backend\yime-layout-designer.exe` | `ABF147DC5C9345691E9CC9717E3F3BEAD626F0C08278E9D4404F995982CD599B` |
| `installer\YIME-1.4.0-dev-setup.exe` | `24DED26E741AE4DF69813370A3DA7A541B326B70E5772C46DDF3758F976EA9EB` |

## 复核命令

在仓库根目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\verify-installed-runtime.ps1 `
  -RepoRoot . `
  -InstallRoot "C:\Program Files (x86)\YIME" `
  -RequireRunningLauncher
```

期望输出为 `Installed runtime verification: complete`。如果结果为 `partial`，只允许原因是被宿主持有的 TSF DLL 暂未替换；重启 Windows 后重新安装并复核。任何其它 `mismatch` 或 `missing` 都应按失败处理。

## 尚未由本轮覆盖

- 未在本轮重新执行 x86/x64 真实宿主的激活、组字、候选、语言栏点击和上屏测试。
- 未对未签名开发包做全新机器或 SAC/WDAC 阻止场景验收。
- 未把源码目录的未提交词库数据改动视为已安装内容；安装完整性以构建树和 Program Files 的哈希比较为准。

## 本轮补修

- `go-backend\build.bat` 现在也用 `go-winres` 为第 9 个 Go EXE `yime-layout-designer.exe` 嵌入图标、版本、产品名、描述和原始文件名；安装态文件属性已验证为 `1.4.0-dev` / `YIME` / `Yime Layout Designer`。
- NSIS 现在向 `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\YIME` 写入 `InstallLocation=$INSTDIR`；原位安装后实测值为 `C:\Program Files (x86)\YIME`。
- Go 构建脚本测试、发布管线测试和 PowerShell 构建守卫均增加了具体回归断言；NSIS 安装包重新编译成功。
