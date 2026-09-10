# 测试机“计算机”：当前开机的只读复核

用户已反馈“已重启并登录，输入法还在”。请在 i7-7820X 测试机“计算机”的独立检出中补齐此次开机证据。此次仅授权只读核对和写入脱敏报告，不重装、不重启/停止 Runtime、不改默认输入法、不读取学习正文。

1. 读取 AGENTS.md 与 TEST-PC-YIMECORE-BUILD-RESULT.md，确认当前确为“计算机”，同一发起用户，64 位 Windows。报告中的安装清单为 `133c91fe205fcae911fa701a278465dad040e7dadce006b541697b656e50405a`，安装根为 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-e346a1dad76d-133c91fe`。若已变化，记录新身份，不能沿用旧结论。
2. 核对清单原始哈希与全部 90 个载荷的大小和哈希；读取安装/运行状态元数据，仅提取版本、路径、PID、创建时间和本次开机时间等信息。核对真实 Runtime/Broker PID、映像、父子关系、SID，以及状态文件是否对应本次开机，不能只看 `running`。
3. 用进程外 `StdRegProv/HKEY_USERS` 核对发起用户的 Run 和卸载记录，不能用当前进程注册表视图代替；核对 x64/x86 COM 路径仍指向本包。核对默认输入法，没有基线时只报告当前值，不声称未变化。
4. 查询本次开机之后的 Shell-Core 9708 登录启动事件，要求 SID 和 Runtime PID 匹配。事件可能只记录程序名；完整路径由系统 Run 与当前映像交叉核对。若 Runtime 在开机后曾手动重启，或事件缺失，明确记为未证实，不能为了通过而启动程序或改日志设置。
5. 将脱敏 JSON 和中文说明提交到仓库，例如 `docs/testing/platform/2026-09-10-mainstream-x64-reboot.json` 与 `TEST-PC-YIMECORE-BUILD-RESULT.md`。原始日志保留在测试机本地新证据目录，记录原始文件哈希；不上传用户名、完整 SID、私人命令行、输入内容、候选或学习文件。报告明确哪些是直接系统观察、哪些是用户反馈，保留先前失败记录。
6. 原生维护边界继续遵守；如工具因 packaged-app 视图无法读取可信证据，准备 Explorer 启动的独立 Windows PowerShell 只读命令，不绕过保护。不要调用会启动进程或打开日用 Broker 会话的 Maintain Verify。

实际输入和完整维护矩阵仍分别记录；本次不要求重复已通过的 x64/x86 注册宿主测试。完成后提交并推送测试分支，供主开发机整合。
