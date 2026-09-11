# 原事务专用收尾完成并复核

影响产品：Rime/PIME 原失败事务 `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`；YimeCore 为保护对象。使用修复提交 `40e45635` 的专用入口，CI 34606641192 成功。用户从资源管理器、同用户非提权原生 PS5 启动，没有运行旧 Resume 或新候选安装器。

## 结果

**本次原事务回滚完成判据全部满足。** 预检和 Apply 各一次，Python subprocess.returncode 均为 0；预检 eligible=true、applied=false、payload_count=191；Apply applied=true、disposition=rolled-back。各自 finally 阶段 peer 比较均成功，两个 before/after 摘要已独立核对。

执行 UTC 时间：预检 14:23:39.837706–14:24:23.874864；Apply 14:24:23.878112–14:25:19.611715，日期为 2026-09-11。对应本地时区为 +08:00。

## 独立后置核验

| 完成判据 | 结果 |
| --- | --- |
| 原安装 commit | 仍缺失 |
| 原安装 terminal | 与原票据 PreparedSha256 合法关联，rolled-back |
| 原移除 commit / terminal | 原 remove-requested 保留，新增合法关联 remove-complete |
| 原计划载荷 | 191 项全部缺失；另用 os.lstat 逐项复验，仅接受 FileNotFoundError，不将权限错误当缺失 |
| 注册/Run/uninstall | 36 个原布局节点及指定 Run 值均缺失，37 项观察无错误 |
| 原候选进程 | 按计划映像路径观察为空 |
| YimeCore peer | 预检及 Apply 两组前后比较均 unchanged；原始快照哈希匹配 |
| 默认输入 | override、first_language、first_tip 与原计划一致 |
| 保留材料 | install/state/recovery 目录仍在，独立 recovery EXE 哈希仍匹配旧包，原既有票据/授权/journal 文件哈希未变；新增两个 terminal |

原通用载荷采集器按“文件应存在”的方式调用 Inspect，因此后置 summary.json 中 payload_errors=191。这是载荷删除后的缺失记录，不代表额外 191 个收尾故障；对应逐项 exists=false，已用独立只读 lstat 校验确认。原 summary 未改写。

此前用户状态、未知文件没有作为删除对象；本轮不发布其内容。专用入口只精确删除原计划载荷，恢复根、状态根、历史材料继续保留，不要求目录消失。

## 证据与下一步

新授权目录为 `approval-b5e657c6-084f-4ab2-87c7-9c4b998ce2eb`；外部执行目录 `original-finalizer-40e45635-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`；后置采集目录 `readonly-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0-2bbf184c051b428fa86e93e37038d675`，均在用户的 Yime Rime-PIME Test Archives 下。

- [独立复核结果](../../testing/platform/2026-09-11-original-finalizer-complete/verified-result.json)
- [关联决策](../../testing/platform/2026-09-11-original-finalizer-complete/decisions.json)
- [证据索引](../../testing/platform/2026-09-11-original-finalizer-complete/index.json)

按本轮交接停在收尾报告回传点，供开发端审阅后另行启动 `-jobexit` 新包测试。新候选尚未 prepare/Install，本次成功仅证明原事务回滚完成，不提升共存安装、宿主输入或重启验收状态。
