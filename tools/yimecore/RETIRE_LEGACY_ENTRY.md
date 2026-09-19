# 旧 YimeCore 用户入口退役

该工具只移除当前开发机、当前用户语言列表中的固定旧 YimeCore TIP。它不卸载产品，
不注销机器级 COM/TIP，不删除历史目录、恢复档案或用户数据，也不修改默认输入法。

先运行只读计划：

```text
python tools/powershell/run_checked.py --script tools/yimecore/retire-legacy-entry.ps1 --edition ps5
```

计划会确认默认输入法不是旧入口，当前 YimeCore 与现有稳定 Rime/PIME 入口各保留一次；
新简版安装器的 Rime/PIME 身份若已存在也必须保持唯一，并记录
`historical_payloads_required=false`。旧安装目录的 `package-manifest.json` 不再是入口退役
的前置条件，因为本操作不读取、删除或重标记历史载荷。

实际执行必须由普通用户从文件资源管理器双击
`Retire-Legacy-YimeCore-Entry.cmd`。Apply 在写入前保存语言列表、相关用户注册表导出及
保护状态；Windows setter 运行后恢复当前 YimeCore 和 Rime/PIME 的精确 TIP 快照，
并验证语言顺序、默认输入法、机器注册、卸载项、启动项和保护树未变化。失败时会尝试
恢复原语言列表及注册表导出，并在 `YimeCore Recovery Archives` 下保留结果证据。

恢复属于有验证的补偿流程，不是原子事务。只有 `result.json` 中 `passed=true` 才能
宣称入口退役完成；源码测试或只读 Plan 不能替代实际执行结果。
