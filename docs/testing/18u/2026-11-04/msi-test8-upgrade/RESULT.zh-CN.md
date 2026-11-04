# MSI：test.7 → test.8 单次升级中止记录

日期：2026-11-04。范围仅为独立 18u 测试产品。

结论：卸载 test.7 返回错误码 `1`，在等待已安装文件释放阶段停止；test.8 安装未开始，记事本绑定与真人手指中文输入均未执行。遵照用户要求，没有自动重试。

- 升级前已保存记事本工作到本地 `saved-work/notepad-before-upgrade.txt`，退出触屏前端；用户随后确认关闭记事本。
- 已核对 test.8 完整包和解包内容，来源提交为 `1060e7a787b395484cf51df47d3583b9a20bc620`，CI 交付见[交付记录](../test8-development/DELIVERY.zh-CN.md)。
- test.7 原安装包保留，另有经 SHA-256 核对的副本；没有覆盖原包。
- 单次卸载于本机时间 13:08 结束。`YimeTextService18u.dll` 报共享冲突：`0x80070020` / Win32 `32`。Restart Manager 当时列出的占用者为 Windows 资源管理器（PID 8708）和 Codex（PID 9008）。这解释此次卸载中止，不证明此前记事本绑定失败的根因。
- 日志停止阶段为 `wait for installed files to be released`，尚未到注销输入法或删除产品文件阶段。未终止这两个占用进程、未注销登录或重启系统。
- 前后快照一致：已安装 45 个文件、独立 18u 用户数据、受保护产品文件及已列入检查的注册表项。安装标记仍为 `0.1.0-18u-test.7`。
- 未启动新版触屏前端，未尝试绑定，因此没有新生成的“最近诊断”。保留本次卸载诊断日志；首次[记事本触屏失败记录](../msi-finger-notepad/RESULT.zh-CN.md)不变。

包身份：

| 包 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `YimeCore-18u-0.1.0-18u-test.7-windows-amd64.zip` | 192137872 | `a9ee98aefc93bd3b579dcbd388bc7de34a8a2fcb5839666598d660b4e9d39e8a` |
| `YimeCore-18u-0.1.0-18u-test.8-windows-amd64.zip` | 192152515 | `b02c65ba6458299cc3d5e98a2aa991b886dbf41992eb3d1a6b847d93a0d58f0b` |

本机原始证据保存在 `C:\dev\Yime\.generated\installed18u-test8-msi-upgrade-r1\`，含 `preserved-test7/`、`saved-work/` 和 `evidence/`。原始日志与用户工作内容不纳入 Git。

关键证据为 `evidence/uninstall-result.json`、`evidence/0712919f47a044d7af1e9e48fbd04937.admin.log`、`evidence/before.json`、`evidence/after-failed-uninstall.json`、`evidence/failure-preservation.json`。`maintenance-attempt.json` 已占位，原单次执行入口不会自动重复执行。

当前已停止。本记录不登记新版安装通过或普通应用真人触屏中文输入通过。
