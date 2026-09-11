# defaultstring 单次安装失败：YimeCore 用户 TIP 变化，回滚未完成

影响产品：Rime/PIME 和受保护的 YimeCore。按 defaultstring 交接，从 Explorer 原生入口执行一次新 Install；当前不能报告安装成功、peer 保护通过或回滚完成。未重试、未手动恢复、未清理，前两轮恢复材料保留。

## 版本与执行

- 执行源码：`3182c545d30d977c57682fbc018f1cf44b0b42b0`；已核对 CI [34622111652](https://github.com/tsaanghwang/Yime/actions/runs/34622111652) 成功。
- 包：`test-delivery/rime-pime-coexistence-20260911-defaultstring`，1.4.0-dev.1；六项完整性校验通过。
- EXE SHA-256：`0602438008d5110767857ff9b5facd23a1bd54a74baff1f81fba5b1e56e2bdd3`。
- 新事务：`9fe7f28d-0889-4828-85b5-1f481431b43a`，全新授权和目录，Mode=Install，PreparedSha256 为空。
- UTC 2026-09-11 23:39:36.321202 至 23:42:33.971295，即北京时间 2026-09-12 07:39 至 07:42；一次执行，安装器退出 51，Python 执行进程退出 1。
- integrity/prepare/before 返回 0；after 返回 1；collect 返回 0。取证成功不代表产品验收通过。

## 失败与保护变化

执行期首份错误为 23:41:40.1001000Z 的 elevated-Register：`Protected YimeCore peer changed; preserve both observations and do not report completion.`。独立 before/after 快照确认唯一变化的顶层字段为 registry：

`HKEY_USERS/<initiating-SID>/SOFTWARE/Microsoft/CTF/TIP/{E40FA752-BB96-461D-A51D-F40EB437EC65}` 在 Registry32、Registry64 两个视图均由 exists=true 变为 false。原子树包含 LanguageProfile/0x00000804/{126F54C6-E9B1-4E22-8652-03224CBD49F9} 的 Enable DWORD=1。这里记录的是系统提供程序观察到的缺失，尚未定位具体写入者或底层触发原因；两个视图不代表已证明发生两次独立删除。

其余 peer 快照字段（run、payload、state、recovery、processes 等）结构相等；不能据此忽略 TIP 变化。只读采集的默认输入比较仍为 true。after 辅助流程因 peer 断言抛错，未生成独立默认比较结果，默认不变结论来自随后 collector 与本次 prepared plan 的比较。

自动回滚在 23:42:24.9890867Z 的 elevated-Remove 失败：`Ambiguous mixed Control Panel profile reference; cleanup is forbidden.`，位置为包内 rime-pime-ownership.ps1 第 491 行，经 Test-YimePimeTargetUserControlPanelReference 第 515 行及注册模块第 330 行。随后 rollback 记录 worker 返回 51，controller-Install 再次报告 peer 变化。本轮未出现 com-x64 默认值断言错误，但整体安装仍失败，不能提升为安装验收通过。

## 当前事务状态与暂停点

严格解析器仅打开复制的 journal：prepared 绑定通过，install commit/terminal 均为空；removal commit 为 remove-requested，removal terminal 为空。原证据采集前后哈希未变。

192 个计划载荷仍在且大小、哈希、文件身份匹配；37 项注册观察中 30 项存在、无读取错误。候选 Launcher/server 当前进程为空，native Rime readiness 未执行。**新事务未闭合，候选注册和载荷残留，同时 YimeCore 用户 TIP 保护未通过。** 不运行 Resume/Remove/finalizer，不改写 TIP 来掩盖现场；请开发端先审阅注册过程的跨产品影响和回滚混合引用拒绝，再交付有明确保护条件的处置步骤。

宿主输入、重启登录、自启和升级/卸载矩阵未验。当前检查只描述本次留存证据；不声称已验证 YimeCore 当前可重新激活或重启后可用。

## 证据

[复核结果](../testing/platform/2026-09-12-defaultstring-peer-failure/verified-result.json)、[脱敏 peer 差异](../testing/platform/2026-09-12-defaultstring-peer-failure/peer-diff-redacted.json)、[五份失败详情](../testing/platform/2026-09-12-defaultstring-peer-failure/failure-details-redacted.json)、[注册存在性](../testing/platform/2026-09-12-defaultstring-peer-failure/registration-presence.json)、[事务决定](../testing/platform/2026-09-12-defaultstring-peer-failure/decisions.json)、[外部证据索引](../testing/platform/2026-09-12-defaultstring-peer-failure/external-evidence-index.json)、[仓库副本索引](../testing/platform/2026-09-12-defaultstring-peer-failure/index.json)。

原始授权、完整快照、控制台和日志继续留在 Git 外 `%USERPROFILE%\Yime Rime-PIME Test Archives`，本次入口目录为 `defaultstring-install-3182c545-once`，只读目录为 `readonly-9fe7f28d-0889-4828-85b5-1f481431b43a-17b56960a495491b94bb0c2ce462c630`。仓库只提交必要非敏感结果；用户目录和 SID 已替换，未提交授权或用户数据原文。
