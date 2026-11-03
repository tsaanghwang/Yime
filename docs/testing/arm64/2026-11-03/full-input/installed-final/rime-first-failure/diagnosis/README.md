# Rime 首次安装失败的只读诊断

检查对象为源码 `6c1c01220b77406cfa5a90df111ea914882fa372`、版本 `0.1.0-rime-arm64.1` 的实际安装。未重新安装、注册、激活输入法或启动输入宿主。

首次安装日志 `7f49612bcf8a4479a689a94f166ffbba.admin.log` 显示安装已进入最后的注册核验：`Setup.ps1:233` 调用 `x86/PIMERegistrationStatus.exe verify-registered`，`Run-Native` 第 84 行的 `& $Path @Arguments | Out-Host` 报 `CantActivateDocumentInPipeline`。调用参数是 `verify-registered`，不是本文后续只读探针使用的 `verify-present`。

安装后的 366 个 payload 文件均与包清单一致；两个 COM 视图、用户启动值和卸载项已写入。原普通权限 helper 因管理员子进程返回 1 而没有启动 Launcher。安装不能据此标为成功。

原生 helper 为受保护 PowerShell 构造的环境位于 `go-backend/cmd/yime-maintenance/main_windows.go:461`，没有 `PATHEXT`。该执行分类问题的隔离复现及源码修复由维护入口专项记录负责。探针文件本身不是文档：x86 PE Machine 为 `0x014c`，ARM64 为 `0xaa64`，已安装文件与正式包的字节一致，直接 CreateProcess 均可运行。

## TSF 观测环境对照

以下两组均直接执行相同的已安装探针、相同参数 `verify-present`，并记录父进程 TokenElevation=false；普通本机组不经过 UAC。原始 stdout/stderr 与命令、哈希、时间和退出码保存在同目录。采集器为 `observe_registration_context.py`。

| 观察环境 | x86 / ARM64 退出码 | exact profile | description / enabled | categories |
| --- | --- | --- | --- | --- |
| 工具默认沙箱 | 4 / 4 | 0 / 0 | false / false | 6，集合精确 |
| 普通本机权限，沙箱外 | 0 / 0 | 1 / 1 | true / true | 6，集合精确 |

HKLM `SOFTWARE\Microsoft\CTF\TIP\{35F67E9D-A54D-4177-9697-8B0AB71A9E04}\LanguageProfile\0x00000804\{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}` 已有正确的 `音元` 描述及本次安装目录下的图标路径。普通本机 TSF API 同样确认该 profile 已注册并启用。

因此，沙箱组的零 profile 是本次工具环境下的 TSF 可见性限制，不是第二个注册缺陷。旧探针在未枚举到 exact profile 时会跳过 description/enabled 查询，输出的 false 不能单独证明这两项实际缺失。不可通过手工 register、修改 PIME 身份、弱化探针或用直接注册表读取替代真实 TSF 查询来“修复”该观测差异。

后续已安装 TSF API 核验应在普通本机权限下执行并保留原始结果。这里证明注册存在；没有证明 Launcher/后端运行、当前宿主 profile 激活或实际输入已验收。
