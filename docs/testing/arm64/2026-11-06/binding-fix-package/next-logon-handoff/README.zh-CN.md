# 一次性登录安装交接

2026-11-06，北京时间 08:05。用户明确要求解决占用完成 `.5` 升级，并在本轮确认：**“已保存，可以正常重启”**。此前仍安装 `.4`，旧组件由 Explorer、Codex、Notepad 使用；不强停宿主、不绕过安装器的文件检查。

已通过仓库 `run_checked.py --edition ps7` 登记并由进程外 `StdRegProv` 回读确认，当前用户唯一 RunOnce 值 `Yime18uRepair-636cef68` 将在下次正常登录时运行已修好的完整包入口。登记前该值不存在，写入后类型和完整命令精确一致。当前令牌是管理员账户的普通 Limited 令牌，没有请求最高权限任务或改变产品持久自启、默认输入法。

命令为系统 `cmd.exe /d /c` 调用 `C:\dev\Yime-deliveries\18u-binding-636cef68-20261106\开始安装18u修复版.cmd`。固定 CMD、Python 辅助入口、原生维护程序、维护计划、安装 manifest 的 SHA-256 都匹配；CMD 已为 20 个 CRLF。只有入口最终执行 `YimeMaintenance.exe -action Install` 并通过后，才可核验实际安装状态。

登记及回读没有执行安装或重启。原始登记回执保留在本地交付目录的 `next-logon-registration-receipt.json`；仓库 [summary](registration-summary.json) 只遮盖当前用户 SID，并记录原始回执 SHA-256，不冒充逐字节原始副本。

后续正常重启将单独记录于 `C:\dev\Yime-deliveries\18u-binding-636cef68-20261106\18u-restart-request-20261106.json`。命令选用 `shutdown.exe /r /t 0 /d p:4:2`，不带强制关闭参数，不使用会隐含强制关闭的正数超时。请求返回成功只能证明请求被接受，不能代替重启后新启动时间/进程观察。[微软 shutdown 参数说明](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown)

RunOnce 不保证先于恢复应用执行；该值默认在执行前移除，失败也不会自动重试。本轮入口不会重建该启动项，仍遇占用便保留新日志、在 Install 前停止；不把 RunOnce 值消失当作安装成功。[微软 RunOnce 说明](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)

登录后正常处理 Windows 安装确认，先让安装窗口运行到结果，再回到本对话。下一轮读取新的入口 JSON、原生 Install 输出和 `Yime Setup Logs`；确认 `.5 / 636cef681ee995a21a9c45fd750f8cb4b0acb4a1` 的完整 20 载荷及普通用户 Runtime/Broker/GUI，再在记事本新空白标签选择并绑定已安装 18u，使用 N08、M03、M03、M03 得到 `niii` 候选“你”，点击候选并观察正文实写。不得直接填 Unicode 冒充输入法提交。

此交接仍不是 `.5` 已安装、记事本绑定或中文输入通过的结论。安装和测试授权持续有效。
