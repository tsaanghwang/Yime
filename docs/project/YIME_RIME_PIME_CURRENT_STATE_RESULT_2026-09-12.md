# 当前只读采集结果：精确引用名称及 YimeCore 用户 TIP 缺失

影响产品：Rime/PIME、YimeCore。按 `bd141312` 交接，用户从 Explorer 原生非管理员 PS5 运行正式采集器，经 run_checked.py，退出码 0。目标事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`。本次没有安装、恢复、新授权、注册或重启。

## 当前观察

采集 UTC 2026-09-12 00:25:48.1888596 至 00:25:49.1270275（北京时间 08:25），31 条系统 StdRegProv 观察：21 条返回 0，10 条返回 2（缺失），无异常、无其他返回码。返回 2 未当作读取成功或 DWORD=0。

Control Panel/International/User Profile/zh-Hans-CN 中唯一包含目标 Rime/PIME CLSID 的完整值名称为：

```text
0804:{35F67E9D-A54D-4177-9697-8B0AB71A9E04}{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}
```

类型为 4（REG_DWORD），不是字符串，因此采集器没有读取其值内容；名称没有 trim、分隔或格式归一化。该名称本身不含 YimeCore CLSID；同一个 zh-Hans-CN 键中另有独立的 YimeCore 引用名称。它是当前精确名称候选，不把当前采集伪称为失败瞬间被检查名称的直接日志。开发端可据此构造回归，仍需保留真正混合引用的拒绝保护。

Registry32/Registry64 均观察到 YimeCore 的机器 COM 根、InprocServer32、机器 TIP 根及具体 LanguageProfile 键存在。COM 根 EnumValues 返回空数组不表示默认值缺失，本轮没有读取默认字符串内容，也不声称机器注册全部值已重新验真。InprocServer32 枚举有默认值与 ThreadingModel，具体机器 Profile 枚举有 Description、IconFile、IconIndex、Enable。

两视图的目标用户 TIP 根和具体 LanguageProfile 键均返回 2；读取用户 Enable 也返回 2，表示缺失而非值为 0。与封存安装前用户 TIP 存在、Enable DWORD=1 的快照相比，保护变化仍未恢复。机器层键存在与原快照相符，但不能代替用户层恢复。

用户尚未提供取证后的 YimeCore 物理输入测试结果，记为未测；此前 Rime/PIME 图标可见但不能输入的反馈仍独立保留。本次不重做安装或恢复判断，前次未闭合事务的结论不变。完成回传后暂停，等待开发端限定恢复步骤。

## 证据

[检查后的脱敏原副本](../testing/platform/2026-09-12-peer-current-state/current-redacted.json)、[核验摘要](../testing/platform/2026-09-12-peer-current-state/verified-summary.json)、[执行记录](../testing/platform/2026-09-12-peer-current-state/execution.json)、[仓库索引](../testing/platform/2026-09-12-peer-current-state/index.json)、[外部原件索引](../testing/platform/2026-09-12-peer-current-state/external-index.json)。

已核对采集器 index 的两个原件大小与 SHA-256；仓库 current-redacted.json 保持该副本原字节，检查未含原 SID 或用户主目录，保留精确名称和类型。current-private.json 与完整控制台均留在 Git 外 `current-peer-bb515e4fe04f493e82d220c5ca8f5300`、`current-peer-console-edcf7997d60f4e2786ee7e0bdcfaa51c`；原件与仓库副本分别列哈希，不提交授权或私人设置值。
