# 原包短路径 Resume 失败：注册子进程后代未退出

影响产品：原 Rime/PIME 失败事务恢复。用户授权先恢复旧事务、复核后测试新包；旧事务未闭合，因此新包尚未安装。

## 执行与结果

交付提交 `79f8b10ca8eee1f5a55f0576128ff730213ad02f` 的 CI 34593710958 已成功。新 `-request` 包六项完整性验证通过，但没有运行它。

用户从资源管理器启动同用户原生 PS5。原票据、授权摘要及状态前置检查通过；新授权 `85a63a67-b423-4ea2-959c-ec43c3aba0f9` 保持原产品根和票据摘要。短路径目录 `YRP-e76b286a491a` 的 p.exe/r.json 与固定旧包及收据字节摘要一致；只有这两个传入路径改变。transport.json 记录旧 NSIS 命令长度上界 **939**，不超过 1000。

只执行一次本方案 Resume。子 Python 捕获执行入口 returncode=1，原 EXE 返回 51。精确执行时间为 **2026-09-11 11:59:23.666826–12:01:39.378479 UTC**，即本地 **19:59:23–20:01:39 +08:00**。没有重试、手工清理或补写终态。

执行后：191 项计划载荷仍全部存在且大小/哈希/身份匹配；原注册及指定 Run/uninstall 缺失；无匹配候选进程；默认输入三字段匹配。安装 commit/terminal 仍缺失；移除 remove-requested 保留、terminal 缺失。两组新 peer 比较 unchanged=true，原 before/after 文件摘要独立复核通过。**回滚完成判据未满足。**

## 本次准确时段的事件链

只读查询 Microsoft-Windows-PowerShell/Operational，范围为执行起止前后各两分钟（UTC 11:57:23–12:03:39），以本地时间传给 Get-WinEvent。相关筛选命中 109 条记录；原消息和 XML 留在外部。

| UTC 时间 | RecordId / ID | 错误 |
| --- | --- | --- |
| 12:00:17.5761600 | 5950 / 4100 | Registration child left active descendants; its job was terminated and drained; partial state retained for recovery. |
| 12:01:24.2413030 | 5952 / 4100 | 同上 |
| 12:01:30.5618927 | 5953 / 4100 | 同上 |
| 12:01:38.4059833 | 5954 / 4100 | Candidate elevated worker failed with exit code 51; persistent plan retained. |
| 12:01:38.4920053 | 5955 / 4100 | 系统错误 |
| 12:01:39.3331517 | 5956 / 4100 | Candidate failed with exit code 51; retain all evidence and recovery tickets. |

这是本次不同于此前摘要格式错误的直接事件线索，表明已进入提升 worker/注册子进程阶段。三条子进程错误不代表外层 Resume 重试三次；外层只运行一次。具体遗留的后代进程及内部操作仍需开发端从调用链审阅，不能归因为安全软件或擅自关闭子进程保护。

首次事件查询直接传 UTC DateTime 给筛选器返回 NoMatchingEventsFound；原错误保留在 `short-resume-events-c291ac1816cc44a0bfe88d88e58007e0`。改为显式 ToLocalTime 后读取同一目标时段，成功结果在 `short-resume-events-4f1b2abad6f04e199de0c2340a57a715`。没有因此重演恢复。

## 交回与暂停点

[脱敏错误事件](../../testing/platform/2026-09-11-exit51-short-resume/error-events-redacted.json)及[证据索引](../../testing/platform/2026-09-11-exit51-short-resume/index.json)已提交；原事件、命令、身份和新旧授权均留在 Git 外。索引内 transport 的 maintenance_executed=false 是准备时记录，不代表之后没有执行 Resume。

原载荷、journal、票据、恢复 EXE 和短路径副本保持现场。请开发端基于新的 active-descendants 错误制定下一步诊断或专项恢复；不重用已执行暂存目录，不新建目录盲重试。新包安装测试继续等待旧事务复核闭合。
