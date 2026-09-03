# tools/yimecore：YimeCore 替换试验脚本索引

本目录承载 YimeCore 替换试验（E0–E6）的全部实验、打包、试用安装与运维脚本。

当前按[本机独立产品实施计划](../../docs/project/YIMECORE_LOCAL_PRODUCT_IMPLEMENTATION_PLAN.md)推进。源码构包已接入 L3 包内维护；新候选使用独立的 `yimecore-local-product-package-v1` 契约。旧 L2 runtime-only 包仍不可安装，旧 E6-C 多架构完整性要求不变。

## 本机独立产品新入口

**11:25 原生 `.6` 状态**：`0.1.0-local.6` 已以“音元拼音”独立 x64 身份升级，冻结用户 TIP 最终恢复、普通用户 Runtime/Broker、三模式、数据、语言列表与生产/冻结注册保护通过；真实记事本五项、实际备份恢复和启动失败升级回退也已通过。Word/浏览器/开发工具宿主、自身卸载重装及后续登录启动仍待验收。见 [local.6 记录](../../docs/YIMECORE_LOCAL_PRODUCT_LOCAL6_2026-09-03.md)。

活动 x64 已使用“音元拼音”的独立 CLSID/Profile；冻结 WOW64 继续保留旧 CLSID/Profile 和原始 payload。不要把冻结旧身份改名、重注册或当作当前活动产品执行。

**08:12 原生 `.3` 历史状态**：安装后的 OneDrive 自启动值丢失、冻结 x86 profile 描述/图标改变已由定向入口恢复。该维护器随后由 `.4` 替代；`test-local3-repair.ps1` 继续保留事故的固定证据回归，见[诊断](../../docs/YIMECORE_LOCAL3_REGISTRY_PRESERVATION_2026-09-03.md)。

- `local-product.json`：唯一构包描述，保留现有 GUID/学习空间，限定 MYCOMPUTER x64。
- `test-local-product-build.ps1`：38 项路径、身份、范围、依赖、源码变更和 PS5 纯文本证据序列化保护。
- `build-local-product.ps1`：从源码和仓内数据构建，不依赖旧安装；输出到新建的 `.tmp/yimecore-local-product/<run>/`。
- `test-local-product-runtime.ps1`：由构包器调用，在仓库外隔离目录验证新包、三模式、恢复和 TSF，不做机器注册或真实 Word 验收。
- `test-local-product-maintenance.ps1`：共享维护器的正常 x64、冻结引用保留、实际进程身份、首次安装失败状态恢复及标准令牌策略回归；带旧包只读 Plan 时共 55 项，PS5.1/PS7 已验证。
- `local-runtime-launcher.cs`：同 SID/会话的标准用户启动帮助程序。使用明确保留的普通 PowerShell 主令牌，核对 PID/时间/映像/祖先/身份，并挂起验证实际子进程；只请求 `0x018b` 句柄权限。2026-09-03 07:32 原生启动验证已通过。`-NativeX64Only` 仍是正常 x64 模式，与故障演练分离。
- `test-native-standard-user-launch.ps1` / `test-standard-user-launch-contract.ps1`：原生只读启动验证及当前 56 项隔离契约。`native-launch-fix-20260903-073233-5efe1c97` 已证明普通启动对照及 UAC 后实际普通主令牌子进程均通过，五份源码哈希一致；没有安装或停止输入法。探针无需重复。见[1346 / 错误 5 修复记录](../../docs/YIMECORE_STANDARD_USER_LAUNCH_FIX_2026-09-03.md)。
- 仓库根 `Test-YimeCore-Standard-Launch.cmd`：普通资源管理器双击入口，只调用上述探针并保留结果窗口；不自己提权，不接受内部工作进程参数，不修改安全设置。由普通 PowerShell 保持发起进程，再按需请求 UAC。不要从管理员终端或 Codex 中启动。
- `invoke-local-product-native-install.ps1`：固定新候选及原安装基线的外部验收编排，默认只读 Plan。必须普通权限启动；先请求只读启动探针 UAC，再在普通父进程中备份旧包，最后调用包内安装事务及其同账户 UAC。普通父进程保持等待，备份不能把旧 runtime 重启成管理员权限。完整执行仍须原生人工启动，不从 Codex 提权。
- 仓库根 `Install-YimeCore-Local-Dev.cmd`：本次首次晋级的一键验收入口，普通资源管理器双击；无需复制 PowerShell 命令。自动停写备份、安装和核验，不自动重启。安装后真实宿主、实际恢复/回退和重启另行验收；不要把它当作可反复执行的通用升级入口。
- `local-token-diagnostics.ps1` / `test-local-token-diagnostics.ps1`：只查询当前/关联令牌类型，保留嵌套 Win32 错误码及系统说明；不复制令牌、不改变权限、不启动进程。夹具测试不算真实提权启动通过。
- `manage-local-product.ps1`：包内入口，默认只读 Plan；安装/升级/卸载调用同一共享事务器，备份/安全恢复/验证从当前安装包解析依赖。
- `local-package-contract.ps1`：完整清单、路径和字节核对后调用包内 x64 审计，不编译、不要求仓库。
- `local-product-runtime.ps1`：包内恢复后的标准用户启动和真实进程/令牌验证；没有以长期管理员运行代替普通用户运行的回退。
- `test-local-product-package.ps1`：新包只读 Plan、入口/语法、恢复精确文件集和未列出文件拒绝测试；不冒充真实安装或恢复。
- `invoke-local6-uninstall-reinstall.ps1` / 仓库根 `Test-YimeCore-Local6-Uninstall-Reinstall.cmd`：local.6 自身卸载保留数据与完整包重装门禁。先做新鲜原生备份，保留含原路径绑定元数据的 `previous-package` 原字节恢复材料，再从其 manifest 文件生成并审计仓库外 `reinstall-package` 后重装；中间核对活动注册/进程/配置确已移除，前后核对用户数据及完整系统保护。

当前源码描述和本机安装版本均为 `0.1.0-local.6`；构包、隔离、原生升级、真实记事本、实际备份恢复和失败升级回退验收均通过。**总体是否就绪仍必须看剩余宿主、自身卸载重装和登录启动证据，不以单次升级 PASS 代替**。`local_product_ready` 和公开发行仍为 false。

维护只能从资源管理器启动的独立 Windows PowerShell 运行。备份/Restore 当前继承已验证的“新鲜归档安全恢复演练”：备份后数据变化即拒绝覆盖，不提供任意历史数据的强制覆盖。local.6 的实际普通用户启动、原位晋级、恢复和失败回退已经验收；自身卸载重装、剩余真实宿主和后续重启仍须分别验收。晋级后不要混用旧的仓库 Trial 升级命令。

L3 的新增源码与未完成边界见[维护基础验收](../../docs/YIMECORE_LOCAL_PRODUCT_MAINTENANCE_2026-09-02.md)。当前旧安装包缺少新启动帮助程序，不能把它直接当成 `NativeX64Only` 候选包；Plan 会明确报告该缺口。

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
