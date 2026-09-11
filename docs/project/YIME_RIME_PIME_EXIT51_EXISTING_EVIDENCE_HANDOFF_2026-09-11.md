# Resume 失败：已有证据与辅助入口源码交回

响应 `e9efd4dc` 测试端交接。仅读取现有文件、脱敏并导出审阅材料；没有运行 Install/Remove/Resume，没有新授权，没有修改产品或原事务锁。

## 控制台

[现存错误段及阶段上下文](exit51-review-evidence-2026-09-11/console-error-excerpt.txt)来自已归档的 preflight2/console.txt。前置检查通过、新授权准备完成、单次 Resume 开始后，记录只有外层 `Candidate failed with exit code 51`，随后执行只读采集。没有更具体的旧包控制器或隐藏提升 worker 异常、错误行或堆栈。未为补日志重新运行维护。

## 辅助脚本

[文件与 SHA-256 索引](exit51-review-evidence-2026-09-11/index.json)同时记录原本机脚本哈希和脱敏副本哈希。副本使用 `.txt` 后缀，带不可执行声明，所有个人绝对路径替换为占位符；不是新执行入口。变量名和真实 PowerShell 调用顺序保留，未包含授权内容或身份值。

- `Collect-Coexistence-Readonly.ps1.txt` / `.cmd.txt`：只读采集。对原 journal 只复制与计算哈希，在新目录副本上使用原事务解析器。
- `Resume-Coexistence-Once.ps1.txt` / `.cmd.txt`：此前已运行的单次 Resume 入口，含前置检查、备份、新授权、执行及后置采集，**仅供审阅，禁止再次执行**。
- `Test-Resume-Registry-Shape.ps1.txt`：PS5 复现与修正方法。原 `$reg=@(ReadJson ...)` 得到外层 Count=1；改为 `$reg=ReadJson ...` 后保留真实数组。已运行结果：37 项 accepted=True，36 项 accepted=False；两例 old-wrapper-count 均为 1。
- `Test-Coexistence-Readonly-Save.ps1.txt`：空数组/null/单元素数组保存回归；避免空结果管道丢失引发 GetBytes 空参数异常。
- `Inspect-Archived-Plan-Types.ps1.txt`：本轮类型导出方法，只读取现有归档副本的二进制记录；不打开任何 transaction store。

## 计划元数据及证据边界

[PS5 解析字段类型](exit51-review-evidence-2026-09-11/plan-types.json)来源为已有执行后归档 `install-journal-copy/prepared.bin`。先只读校验魔数、记录长度和嵌入 SHA-256，再用原编译提交 `6321067de503463a71262a84239b8f5c3064f10d` 的 `ConvertFrom-CandidateJson` 解析 payload。没有调用 Open-CandidateJournal 或 Read-MaintenancePreparedPlan；本轮解析运行在 Codex 工具环境，只用于文件格式/PS5 类型观察，不作为原生注册或进程事实。

- 顶层 18 个字段名和类型已逐项导出，不发布身份/路径值。
- files：`System.Object[]`，191 项；generated_files：`System.Object[]`，2 项。
- default_input 为 PSCustomObject；override、first_language、first_tip 均为 `System.String`，未发布值。
- product_version：`1.4.0-dev.1`。
- file_field_types 仅记录第一条文件记录的字段类型，不扩称全部记录类型验证。
- **install/state 目录身份此前未独立核验**。计划中的目录身份字段存在且为字符串，不等于当前目录身份已匹配。
- **独立恢复 EXE 的文件身份此前未独立核验**。对 191 项已列安装载荷的大小/哈希/文件身份核验，不能替代对 recovery 根 EXE 的身份核验。
- 此前 collector 校验原授权的七项绑定，但没有逐项输出新授权七项绑定的完整验证结果。执行包装器只显式核对新授权根路径、包身份、Mode/PreparedSha256 和新 run。旧包是否在全部 Read-MaintenancePreparedPlan 不变量上通过，仍无具体异常证据。

本轮没有认定这些缺失项是根因，也没有绕过完整计划验证。交开发端审阅解析和入口差异，再设计不会执行维护分支的诊断桥接或专项恢复方案。原固定包、载荷、新旧授权、票据及 journal 保留；安装与恢复继续暂停。
