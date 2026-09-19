# 本地非系统变更验证证据

2026-09-20 在 `codex/current-readiness-release-delivery` 的源码提交
`0ab8631266736775bf1386f456d4a1d53e8e2eb3` 上执行，13 个检查入口全部返回 0。
完整命令、UTC 时间、退出码、stdout/stderr 路径和 SHA-256 见 `summary.json`；
每个检查的独立 `.command.json` 和原始输出一并保存。

运行器：从仓库根执行 `python -X utf8 docs/testing/simple-maintenance/2026-09-20/current-readiness-release/raw/local-checks/run_checks.py`。
复跑会覆盖本目录的当次输出，历史证据由 Git 保存。

| 验证 | 边界 |
|---|---|
| Test-PackageValidation / Windows PowerShell 5 | 独立临时目录中的合成包、必需资源清单及拒绝路径；未执行二进制 |
| Test-ProfileRemoval / Windows PowerShell 5 | 提取真实脚本 AST 片段，全部外部 API 和操作替换为 mock |
| Test-Manage / Windows PowerShell 5 | 子 PowerShell 仅执行测试临时目录中即时生成的合成 Setup，记录调度顺序及失败停止 |
| legacy retirement / Windows PowerShell 5 | 22 项合成语言列表及进程祖先 mock 检查，未改变系统列表 |
| build contract / PowerShell 7 | 构建入口、依赖锁及 CI 不变量文本检查 |
| PowerShell wrapper | 2 项测试；wrapper 自身的 ps5/ps7 参数预检和执行契约，仅操作临时 marker |
| workflow contract / shard coverage | 2 + 3 项测试，检查 CI 依赖完整性及失败/缺片证据拒绝 |
| repository data boundary | 扫描受跟踪源码和活动导入批准，确认无未批准数据源回退 |
| toolchain lock / external archive lock | 仓库工具链与外部归档的锁定元数据，未恢复或读取外部归档实体 |
| vendored dependencies | Corrosion 263 文件、108 Cargo crates 共 7,310 文件、go-winres 135 文件的锁定完整性 |
| PSC outline snapshot | 205 文件、169,824,700 字节；7 源文档、197 OCR 页面、417 人工决定的仓库快照校验 |

`manage-synthetic-packages-ps5.stdout.txt` 中的 `Install completed` / `Uninstall completed`
是上述合成 Setup 的调度记录，不是实际安装或卸载。没有执行真实产品 Setup 的安装/卸载，
没有启动、停止或重启产品进程，没有改变注册表、默认输入法或用户数据。

本轮没有实际历史双产品包，因此没有执行需要实包的 `Test-Product.ps1`，不能将
合成包测试解释为历史 ZIP 的内容、SHA-256 或可复现性验证。`Test-Startup.ps1`
会写真实隔离注册表键，`Test-Logging.ps1` 会使用用户目录日志，`Test-ProcessWait.ps1`
会创建独立存活子进程，均不在本轮本地非系统变更运行内。原生注册宿主和真实输入验收未执行。
适用 CI 的历史完成状态及实际包缺失判断由上层核验报告单独记录。
