# YIME 1.4.0 未签名发布演练 · 2026-07-15

> 范围：版本定稿后的本机构建、自动化回归、标准 NSIS 安装和原位升级；不包含可信签名及签名后的重复验收。

## 结果

| 项目 | 结果 |
|------|------|
| 版本与 VERSIONINFO | 通过；`version.txt`、PIMELauncher、安装器、卸载器、TSF DLL 和 Go EXE 均为 `1.4.0`，产品名为 YIME |
| Go / race | `go vet ./...`、`go test ./...`、`go test -race ./...` 全部通过 |
| Rust | `cargo fmt --check`、固定 i686 host 工具链单元与集成测试通过 |
| C++ / TSF | Win32 与 x64 构建、CTest 通过 |
| PE 架构 | x86 DLL/Launcher=`0x014C`，x64 DLL=`0x8664`，ARM64 DLL=`0xAA64` |
| 可复现 Go 构建 | 8 个 Go EXE 连续构建 SHA-256 全部一致 |
| YIME-only 打包 | 安装目录只有 `go-backend/input_methods/yime`；无 Python/Node/其他旧 PIME 输入法 |
| 法律文件 | 安装目录 `licenses` 含项目许可、PIME 来源声明、Rime/Rime Frost、字体、Unicode、Rust 等通知 |
| 标准安装 | 修复后静默安装退出码 0；安装根、启动项、卸载项和 `DisplayVersion=1.4.0` 正确 |

## 安装器

- 文件：`installer/YIME-1.4.0-setup.exe`
- SHA-256：`791A74EF03D92DBE811B23A124A6386038B1F25113EC05F0D316A08BC00ACE89`
- 状态：未签名测试安装器，不得作为公开发布产物。

## 演练中发现并修复的问题

标准升级演练曾返回退出码 2。旧安装器既会在发现 TSF DLL 哈希变化时递归删除架构目录，也会在仍保留 `go-backend/licenses` 的情况下对非空安装根执行 `RMDir /REBOOTOK`；两条路径都会设置重启标志并被误判为致命失败，造成安装目录只剩部分文件。

修复后的安装器采用真正的原位升级，只停止进程、反注册 DLL、清理退役目录和旧 PIME 注册表，不再预先删除 launcher、版本、卸载器或安装根。新 DLL 先写为 `PIMETextService.dll.new`：文件未锁定时立即替换；被宿主持有时通过 `/REBOOTOK` 安排下一次 Windows 启动时替换。其余 YIME payload 会正常完成安装，不再把设计内的 DLL 锁当成失败。构建守卫固定检查此升级机制及禁止恢复破坏性的预删除步骤。

同一轮还移除了开发安装脚本残留的 Python/Node 断言与复制逻辑，删除三种安装语言中已经不可达的旧 PIME 输入法字符串，并补齐标准安装完成后立即启动 PIMELauncher 的步骤，使全新安装无需注销或重启即可启动后端。

## 重启后补验

本轮 x86 DLL、PIMELauncher 和 `server.exe` 已与构建 SHA-256 一致。x64 DLL 被宿主持有，新文件位于：

```text
C:\Program Files (x86)\YIME\x64\PIMETextService.dll.new
```

Windows 重启后应确认 `.new` 消失，并验证：

```powershell
$installed = 'C:\Program Files (x86)\YIME\x64\PIMETextService.dll'
$built = '.\build64\PIMETextService\Release\PIMETextService.dll'
(Get-FileHash $installed -Algorithm SHA256).Hash -eq
    (Get-FileHash $built -Algorithm SHA256).Hash
```

随后启动 x64 宿主做一次简短激活、组字、候选和上屏检查。可信签名完成后仍须按发布指南重跑完整签名验收。

失败演练曾向 `PendingFileRenameOperations` 留下重复的 YIME 目录/DLL 操作；收尾时已按源/目标对清理，只保留最后一次成功安装所需的一组 x64 DLL 删除与重命名，不包含 YIME 根目录或架构目录删除。

重启后复核通过：`.new` 消失，x64/x86 DLL 与 `server.exe` 均和构建哈希一致，YIME 重启队列清空，PIMELauncher watchdog/worker 与 server 自动启动，本次开机以来没有 YIME 相关 Code Integrity 3033/3077/3118 事件。用户随后在多种可编辑和输入位置完成人工输入测试，未发现问题。
