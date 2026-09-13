# 新授权验证停止：YimeCore 进程身份与状态摘要变化

影响产品：Rime/PIME 固定恢复、YimeCore 保护。按 `a3f25e7d` 授权更新交接，新建授权 `2576a4fe-5203-4eb2-82be-e2503a5ddc4a`，继续绑定事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`、原始 baseline 和旧独立 original-bundle。未覆盖旧授权或重新复制残余载荷。

准备 UTC 2026-09-13 13:58:52.067881 至 13:59:02.736072，退出 0。验证 13:59:02.739064 至 13:59:14.772035，退出 1。原错误时间 13:59:14.6912497Z、PID 23088，`Protected YimeCore peer changed; preserve both observations and do not report completion.`，位于 Assert-DefaultstringPeerDifference 调用的比较器，经恢复入口第 72 行。

该位置在第 79 行导入应用使用检查模块之前，因此本次未进入应用退出提示、重新检查或取消流程。VALIDATED 未出现，未生成 Apply 参数、未执行 Apply 或 TIP 修复。不是新的授权过期错误。

## 原始基线与当前快照差异

- 用户 TIP 在两个视图仍缺失，与已知差异相同。
- `language-bar-host.log` 从 13119 字节变为 13786 字节，属于已有精确诊断日志元数据例外；原数据保留。
- **index-control/status.json** 长度仍为 1569，但 SHA-256 从 `c468ec930a39ae891bbbb3201b6e442b1916ab54f93133c96f3ed3dd39402efd` 变为 `93d2fdbb8cc45784f7baee475cb6cd667eb7a21a297d6cfd8c90003f118f6242`，不属于现有例外。未读取该文件内容，不推定变化原因。
- **YimeCoreTrialRuntime.exe** 原 PID 27144、创建 UTC 2026-09-11 05:25:55.1527780，现 PID 1328、创建 UTC 2026-09-13 12:07:08.4837980。
- **YimeBroker.exe** 原 PID 28104、创建 UTC 2026-09-11 05:25:56.6010150，现 PID 12696、创建 UTC 2026-09-13 12:07:09.7647030。两者映像路径、SID 与原快照相同，但进程身份不同；不能据此单独确定是否发生系统重启。

顶层仅 registry、state、processes 不同。新准备快照与验证快照结构一致；差异不是由“新授权替换原基线”所消除，新入口仍如设计对原基线拒绝。

依交接停止于修改前，不自行补正 PID、覆盖快照、忽略 status.json 或再次续期。请开发端审阅进程变化及状态差异，并提供限定的当前状态验证／基线处置方案。本轮不授权或执行跨会话基线重建，恢复仍未完成，旧候选继续停用。

[脱敏差异](../testing/platform/2026-09-13-reauthorize-peer-stop/peer-differences.json)、[新授权时间及结果摘要](../testing/platform/2026-09-13-reauthorize-peer-stop/verified-result.json)、[错误](../testing/platform/2026-09-13-reauthorize-peer-stop/failure.json)、[外部索引](../testing/platform/2026-09-13-reauthorize-peer-stop/external-index.json)、[仓库索引](../testing/platform/2026-09-13-reauthorize-peer-stop/index.json)。完整快照、授权和控制台留在 Git 外，用户路径和 SID 已脱敏，原件和仓库副本分别列摘要。
