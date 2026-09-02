# tools/yimecore：YimeCore 替换试验脚本索引

本目录承载 YimeCore 替换试验（E0–E6）的全部实验、打包、试用安装与运维脚本。
阶段定义、门禁与证据要求见
[docs/project/YIMECORE_REPLACEMENT_EXPERIMENT.md](../../docs/project/YIMECORE_REPLACEMENT_EXPERIMENT.md)。

除特殊说明外，脚本在仓库根目录用 PowerShell 运行，证据输出到脚本内声明的
evidence 目录；失败即退出非零，不得静默降级。

## 阶段实验脚本（按门禁顺序）

| 脚本 | 阶段 | 验证内容 |
| --- | --- | --- |
| `run-e0-experiment.ps1` | E0 | 离线词典清洗/审计基线 |
| `run-e1-index-experiment.ps1` | E1 | 只读静态索引构建与哈希校验 |
| `run-e2-sentence-experiment.ps1` | E2 | 句子组合 lattice/beam |
| `run-e2b-segment-correction-experiment.ps1` | E2b | 句段纠错 |
| `run-e3-learning-experiment.ps1` | E3 | 用户学习/遗忘 |
| `run-e4-connected-speech-experiment.ps1` | E4 | 语流音变路径 |
| `run-e5a-broker-experiment.ps1` | E5a | Broker 协议与会话 |
| `run-e5b-broker-process-experiment.ps1` | E5b | Broker 进程生命周期 |
| `run-e5c-user-model-durability-experiment.ps1` | E5c | 用户模型快照/哈希链日志持久性 |
| `run-e5d-index-switch-experiment.ps1` | E5d | 索引代际租约与事务切换 |
| `run-e5e-concurrent-soak-experiment.ps1` | E5e | 并发浸泡 |
| `run-e5f-idempotency-experiment.ps1` | E5f | mutation ID 幂等/冲突 |
| `run-e5g-compaction-experiment.ps1` | E5g | journal 压实 |
| `run-e6a-named-pipe-experiment.ps1` | E6a | 命名管道生产形态 IPC 门禁 |
| `run-e6b1-text-service-shell-experiment.ps1` | E6-B1 | 最小 COM/TSF 外壳（不吃键） |
| `run-e6b2a-broker-bridge-experiment.ps1` | E6-B2a | 表层↔Broker 按键桥 |
| `run-e6b2b-tsf-composition-experiment.ps1` | E6-B2b | 真实 `ITfContext` 写入 |
| `run-e6b3a-host-termination-experiment.ps1` | E6-B3a | 宿主终止 composition 恢复 |
| `run-e6b3b-candidate-ui-experiment.ps1` | E6-B3b | 最小 TSF 候选 UI 元素 |
| `run-e6b4a-language-bar-experiment.ps1` | E6-B4a | 语言栏最小接口与降级 |
| `run-e6b4b-focus-experiment.ps1` | E6-B4b | key-sink 焦点隔离 |
| `run-e6b4c-registration-readiness.ps1` | E6-B4c | 独立 TIP 注册/回滚工具 readiness |
| `run-e6b4d-cross-context-experiment.ps1` | E6-B4d | 跨 `ITfContext` composition 隔离 |
| `run-e6b5-owned-candidate-popup-experiment.ps1` | E6-B5 | 自绘候选窗口与鼠标选择 |
| `run-e6b6-registered-host-experiment.ps1` | E6-B6 | 提权注册后的真实 TSF 宿主门禁（需管理员） |
| `run-e6b7-parallel-package-experiment.ps1` | E6-B7 | 独立试验包组装 + Program Files 试装验证（需管理员） |
| `record-e6b8-desktop-host-acceptance.ps1` | E6-B8 | 第三方桌面宿主人工验收记录 |
| `run-e6c-package-experiment.ps1` | E6-C | 多索引/显示设置/语言栏控制的自包含打包门禁 |
| `run-e6d-independence-readiness.ps1` | E6-D | 活动包清单、PE 导入、源码依赖和 Rime/PIME 注册隔离门禁 |
| `run-e7-cutover-readiness.ps1` | E7 preflight | 汇总干净构包、活动安装、签名、实体机宿主矩阵和回退证据；只报告，不执行切换 |

## 试用版安装与运维

| 脚本 | 用途 |
| --- | --- |
| `manage-e6c-trial-install.ps1` | 试用版安装/升级/卸载核心（staging→注册→回滚链）。一般不直接调用。 |
| `Install-YimeCore-Trial.cmd` | 包内首次安装入口（提权）。 |
| 仓库根 `Upgrade-YimeCore-Trial.cmd` | **仅升级**已安装试用版：构建→打包→升级→可选重启。首次安装请用上一行。旧 Build-Install v1/v2/v3 名称只保留兼容转发与明确提示。 |
| `Force-Uninstall-YimeCore-Trial.cmd` | 清理试用版；即使使用 `-Force`，注册清理或缺失架构工具仍会失败并保留安装内容，以便修复后重试。 |
| `deploy-e6c-trial-runtime.ps1` | 启用试验 TIP 并写入当前用户 HKCU Run 自启动。 |
| `start-e6c-trial-runtime.ps1` / `stop-e6c-trial-runtime.ps1` | 启停 `YimeCoreTrialRuntime.exe`（单实例监督 Broker 与工具栏）。 |
| `repair-e6c-trial-autostart.ps1` | 修复/移除自启动项。 |
| `verify-e6c-trial-runtime.ps1` | 运行时健康验证（管道、进程身份、索引）。 |
| `verify-e6c-language-bar-events.ps1` | 语言栏模式切换事件验证（部分断言为人工证明）。 |
| `test-e6c-installation-contract.ps1` | 安装契约回归（部分依赖源码正则匹配）。 |
| `open-e6c-trial-tool-center.ps1` | 打开试用版工具中心。 |
| `trial-help/` | 随包分发的用户帮助 HTML。 |

## 其它

| 脚本/目录 | 用途 |
| --- | --- |
| `run-daily-bcc-validation.ps1` / `register-daily-bcc-validation-task.ps1` | BCC 组合验证的每日任务 |
| `professional-lexicons/` | 专业词库实验数据 |
| `e6a/` | E6a 实验辅助文件 |

## 运行时布局（试用版）

- 安装根：`%ProgramFiles%\YimeCore Experimental Trial`（ARM64 + x64 + x86 表层 DLL、
  Broker、runtime、注册工具、三份系统索引）。
- 用户状态：`%LOCALAPPDATA%\YimeCore Experimental Trial`（快照、journal、
  索引控制、设置、诊断、维护错误记录）。普通卸载**不会**删除该目录，
  需 `-PurgeUserData`。
- 自启动：`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`（可用
  `repair-e6c-trial-autostart.ps1` 移除）。
- Broker 管道：`\\.\pipe\YimeBroker.YimeCoreTrial.v1`。
