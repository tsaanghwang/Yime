# PR #85 两项修复验证（2026-10-31）

- 原机确认：本机 `COMPUTERNAME=计算机`，与历史 W01/W02 证据的 machine 一致；原工作树 `C:\dev\Yime-pr83-mouse-results`，分支 `codex/pr84-host-codepoints`，起点及远程 head 均为 `cc613b04e80ed0f0430ce3c04f75582b894815d3`，修改前工作树干净。
- 影响范围：Word 证据采集脚本、定向模拟测试及本报告。未运行输入、触屏或笔测试，未启动/关闭 Word，未修改已安装输入法、默认设置或用户文档。

## 严格字符比较

生产 `exactMatch` 与自测共享 `Test-Exact`，调用 `[string]::Equals(..., [StringComparison]::Ordinal)`。只移除 Word 最后一个 CR，不 trim 或 normalize。W01/W02 正确正文均通过；U+00AD、U+200B、U+FEFF 在前/中/后插入的 18 个反例均失败；原有额外空格、段落、标点及 Unicode scalar 检查仍通过。

## Word 身份门控

只允许系统进程快照中恰好一个 WINWORD；先枚举再 attach，不创建实例。通过 COM Application.Hwnd 和 GetWindowThreadProcessId 核对该唯一 PID，在文档定位后、正文读取前与读取后重复核对 PID/HWND。无法枚举、零/多进程、缺失 HWND、PID 不匹配或变化均抛错。记录生成和 CreateNew 输出在门控成功之后，因此失败不能产生通过记录。记录新增 PID/HWND 和身份策略。

`Test-WordCaptureGuards.ps1` 使用模拟进程列表、模拟 HWND 解析器及带读取计数的模拟 Content，运行生产读取门控：唯一进程允许；无进程、多进程、HWND 所属 PID 不匹配、缺失 HWND、枚举失败均在 Content 读取前拒绝（读取数 0）；读取期间进程变化拒绝返回正文（读取数 1）。所有 7 场景通过。此为隔离模拟验证，不声称真实多实例 COM 或新的宿主输入验收。进程快照与读取不是 OS 原子事务；前后身份检查拒绝可观察到的变化，不能保证观察到瞬时创建又退出的进程。

## 命令与结果

在仓库根目录通过规定入口执行，Windows PowerShell 5.1：

```text
python tools/powershell/run_checked.py --edition ps5 --script docs/testing/touch-keyboard/2026-10-31/pr84-codepoint-supplement/Read-WordCodepoints.ps1 --params-file docs/testing/touch-keyboard/2026-10-31/pr84-codepoint-supplement/fix85-validation-20261031/selftest-params.json
python tools/powershell/run_checked.py --edition ps5 --script docs/testing/touch-keyboard/2026-10-31/pr84-codepoint-supplement/Test-WordCaptureGuards.ps1
```

两命令 exit 0，日志分别为 `selftest.log`、`guards.log`。入口合并预检与执行，无另行重复预检或双版本验证。固定键盘 exe SHA256、attach-only、未保存文档检查及 CreateNew 仍保留。

## 历史证据保护

`evidence-integrity.json` 列出原 `results-20261031` 全部文件的 SHA256。七项原始证据与 manifest 均逐字节等同起点提交；七项哈希全部符合历史 manifest。`.gitattributes` 的现有工作树 CRLF 与 Git blob LF 不同，仅换行不同，该文件未修改。历史证据、历史哈希和既有验证记录均未改写。本次日志写入新的独立目录。

CI 结果按推送后精确提交在 PR 审查回复及任务反馈中提供；不以本地模拟验证代替 CI。未合并，未启用自动合并，PR #86 未修改。
