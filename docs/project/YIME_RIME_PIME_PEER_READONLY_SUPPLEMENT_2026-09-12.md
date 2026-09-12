# 只读补证报告：已存阶段快照与尚缺材料

影响产品：Rime/PIME、YimeCore。针对唯一事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`，按 `376ca35a` 交接整理现有外部证据，响应用户“制作报告并推送”的要求。本报告未执行安装、恢复、注册、重启或新授权；**是现存材料补证，不代表交接全部完成**。

## 阶段对应及用户 TIP 变化

外部 peer JSON 本身没有时间、PID 或阶段字段。下表以原文件最后写入 UTC 排序，结合已存 failure JSON 的 UTC/PID/阶段及源码 Start/Complete-MaintenancePeerProtection 调用范围关联。阶段/PID 属于有依据的推定，不伪称为快照内直接记录；文件写入时间也不等于每项注册读取的精确时间。未按随机 ID 排序。原件哈希与上一轮外部索引核对一致。

| 推定范围 / PID | 快照组前缀 | before 文件 UTC | after 文件 UTC | 两视图用户 TIP |
|---|---|---|---|---|
| controller-Install / 21372 | 09f2d928 | 23:39:59.551816 | 23:42:32.851793 | 存在 → 缺失 |
| elevated-Register / 6756 | 8a0baff9 | 23:40:24.500208 | 23:41:40.057172 | 存在 → 缺失 |
| elevated-Remove / 43720 | 35668441 | 23:41:57.838636 | 23:42:24.899942 | 缺失 → 缺失 |

日期均为 UTC 2026-09-11，即北京时间 2026-09-12。Register 前的两视图快照仍有 YimeCore TIP 子树及 LanguageProfile/0x00000804/{126F54C6-E9B1-4E22-8652-03224CBD49F9} 的 Enable DWORD=1；Remove 前已缺失。证据将变化缩小到 Register 范围内，但仍不能分辨 AssertVacant、RegisterNative、RegisterWow64、EnableTip 中哪个步骤触发，也不能确定具体写入者。

Remove 组唯一的 result.json 显示 unchanged=true，只表示该组开始时已缺失的状态没有进一步变化，**不能解释为 YimeCore 已恢复**。其余两组无 result 文件，与保护断言抛错后尚未写 result 的代码路径一致。JSON 附件保留各视图的子键、值名称和种类，以及同期机器注册观察；这些都是安装期间留存数据，不作为新采集的当前注册状态。

## 错误追溯与缺失项

已存五份 failure JSON 的 UTC、PID、异常和调用栈一并回传。最早留存的 Register 错误是 23:41:40.1001000Z 的 finally peer 保护失败。现有控制台只保留总退出 51，没有更早 Register 原始异常和逐步骤快照；本次材料中无法追溯被 finally 遮住的异常，不能据此推定 EnableTip 成功。

以下仍缺，未用回滚后观察或猜测补齐：

- Control Panel/International/User Profile 及直接子键中触发拒绝的完整值名称、类型和限定字符串内容。现存错误只记录引用匹配失败，没有原名称。
- 新的系统 StdRegProv YimeCore COM/Profile/用户 TIP 观察。须由同一用户从 Explorer 原生 PS5 执行限定只读采集；本次没有启动该采集。
- 用户物理选择当前 YimeCore 的空白记事本输入结果。此前用户确认的是 Rime/PIME 图标不能输入，不能替代 YimeCore 对照。

安装与回滚未完成、YimeCore 用户 TIP 保护失败的结论不变。保留现场，等待补足上述原生只读观察和开发端限定恢复交接。

## 证据索引

[阶段快照摘要](../testing/platform/2026-09-12-peer-readonly-supplement/peer-stage-observations.json)、[已存错误](../testing/platform/2026-09-12-peer-readonly-supplement/retained-errors.json)、[缺失清单](../testing/platform/2026-09-12-peer-readonly-supplement/gaps.json)、[外部原件索引](../testing/platform/2026-09-12-peer-readonly-supplement/external-index.json)、[仓库副本索引](../testing/platform/2026-09-12-peer-readonly-supplement/index.json)。

外部原件保留在 Git 外，索引单列原件哈希、大小和原文件 UTC；仓库 JSON 经用户目录/SID 替换后独立计算哈希。原快照未记载精确采集时间，明确标为缺失，并另记本报告整理时间。授权及个人设置原文未提交。
