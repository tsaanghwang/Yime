# 本机独立开发版 0.1.0-local.5：“音元拼音”身份迁移

当前结果（2026-09-03 10:16）：`0.1.0-local.5` 已安装到 MYCOMPUTER 原生 x64，活动身份显示名为“音元拼音”，使用 CLSID `{E40FA752-BB96-461D-A51D-F40EB437EC65}` 与 Profile `{126F54C6-E9B1-4E22-8652-03224CBD49F9}`。冻结 x86 继续保留旧 CLSID/Profile 和 payload；默认输入法及生产 Rime/PIME 未改变。`local_product_ready=false`，`public_release_ready=false`。

## 固定包与安装

- 候选目录：`C:\dev\Yime\.tmp\yimecore-local-product\local5-name-migration-v2\package`
- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-4bfa828009d1-2631aeb3`
- package manifest SHA-256：`2631aeb3634f6bc103771e12e3a8d6748bd87123f890afb2ae874b1d06706c7a`
- 原生迁移归档：`C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-094523-3cadc5b7`
- 定向修复归档：`C:\Users\tsaan\YimeCore Recovery Archives\local5-identity-repair-20260903-101606-185a078c`

安装事务完成了新 x64 COM/Profile、普通用户 Runtime/Broker、数据继承和新包切换；原安装后审计正确保留为失败，因为实际观察到两个未建模的 TSF 行为：新 Profile 在 native/WOW TIP 视图共享，以及 `Set-WinUserLanguageList` 在事务末尾删除冻结旧身份的用户 TIP 子树。前者是本机 TSF 的必要共享镜像，新 WOW64 COM Server 仍保持缺失；后者违反冻结保护，必须恢复。

## 修复结论

固定证据修复只恢复迁移前旧用户 TIP 完整子树，未重装、未重启、未改变默认输入法或生产组件。最终摘要确认：

- 新 native/WOW TIP Profile 镜像一致，新 WOW64 COM Server 不存在；
- 冻结旧用户 TIP 完整恢复，值类型保持；
- Runtime PID 35272 与 Broker PID 16996 在修复前后均来自当前安装根，属于同一 SID 的非提权中完整性主令牌；
- `parent_runtime_verified=true`、`frozen_legacy_identity_preserved=true`、`local_product_ready=true` 仅表示本次修复出口通过，不等于总体产品 L6 就绪。

## 后续边界

已安装 local.5 的包内 `Manage-YimeCoreTrial.ps1` 与构包候选一致，但比当前仓库源码少最外层冻结用户 TIP 恢复。该缺口已在源码中修复：事务开始快照旧用户 TIP，并在最外层 `finally` 中再次恢复，以覆盖语言列表归一化发生在注册边界之后的情况。

因此不要重复 local.5 首次身份迁移，也暂不使用其 Upgrade、Restore 或 Uninstall。下一步把修复封装为 `0.1.0-local.6`，完成包内回归与原生升级验收后，再继续真实宿主、备份恢复、故障回退和自身卸载重装。只读诊断不受此限制。
