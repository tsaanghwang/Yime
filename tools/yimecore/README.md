# tools/yimecore：YimeCore 替换试验脚本索引

本目录承载 YimeCore 替换试验（E0–E6）的全部实验、打包、试用安装与运维脚本。

当前开发过程遵循[双独立产品开发计划](../../docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)：Rime/PIME 版与 YimeCore 版可分别安装或同时安装，各自独立运行、维护及保存数据，互不依赖。YimeCore 是主要开发线，Rime/PIME 保持稳定维护及可选对照，不默认退役。单装／共存安装矩阵和薄三选一入口待实施；本目录脚本仍只负责各自声明的 YimeCore 范围，不因此获准维护生产 Rime/PIME。

YimeCore 继续按[本机独立产品实施计划](../../docs/project/YIMECORE_LOCAL_PRODUCT_IMPLEMENTATION_PLAN.md)推进。源码构包已接入 L3 包内维护；新候选使用独立的 `yimecore-local-product-package-v1` 契约。旧 L2 runtime-only 包仍不可安装，旧 E6-C 多架构完整性要求不变。

## 本机独立产品新入口

**2026-09-08 当前状态**：已安装 `local.12`；设置/未确认焦点切换、受影响注册宿主、升级后重启及最终 L5 日用确认均已通过，见 [L5 日志](../../docs/YIMECORE_L5_DAILY_USE_TEST_LOG.md)。[L6 只读就绪审查](../../docs/project/YIMECORE_LOCAL12_L6_READINESS_2026-09-08.md)已封存仓外候选并接入 PS5/PS7 门禁；由于 local.12 的维护控制器不同于既有实际回退版本，当前候选恢复/故障升级回退仍需单独的原生维护窗口，故 `L6_sealed=false`、`local_product_ready=false`。B2 当前源码候选为默认关闭且未安装的 local.13；DP1 独立 Rime/PIME 仍按自身计划推进。其他预留语流层未据此准入；旧过程记录保留原证据边界。

只读重算 L6 状态使用 `powershell -NoProfile -ExecutionPolicy Bypass -File tools\yimecore\run-local-product-readiness.ps1`。退出码 `2` 表示仍有诚实 pending 项，不代表脚本异常；未提供当前候选恢复证据时不会执行或建议执行维护操作。

**2026-09-04 当前状态**：当前安装已升级为 `0.1.0-local.11`，活动根为 `yimecore-e6c-f435f463bfd0-5a3f847a`，manifest SHA-256 为 `5a3f847a3136fd2198f7dc9aba22dc017ed7439d8447435e8752eb379a4a5cd8`。安装态 x64/x86 registered-host 三模式 6/6 通过；Firefox 155.0 与 Notepad++ 8.9.8 两个 PE32/I386 进程均确认加载当前安装根的 x86 DLL，并由用户确认组合提交、裸数字组字、`Shift+1` 首候选三项通过。生产/冻结注册及默认输入法保持不变；详见 [local.11 x86 验收](../../docs/YIMECORE_LOCAL11_X86_ACCEPTANCE_2026-09-04.md)。x86 本机工作流已经封存；x64 L5 日常使用和 L6 合并封存仍未关闭，`local_product_ready` 和公开发行仍为 false。下方带时刻的 local.7/local.9 “当前状态”段落均为当时的过程快照。

**17:05 原生状态**：`local.7` 升级通过，但完整卸载重装在卸载间隙发现当前用户 TIP 残留 DWORD `Enable=0` 并停止，当前产品已卸载且恢复介质完整。`local.8` 同时修复“卸载删除残留壳”和“无真实旧安装时禁止恢复旧壳”，已完成 native x64 构建及隔离验证；固定恢复入口待执行。见 [local.7 记录](../../docs/YIMECORE_LOCAL_PRODUCT_LOCAL7_2026-09-03.md)和 [local.8 记录](../../docs/YIMECORE_LOCAL_PRODUCT_LOCAL8_2026-09-03.md)。

活动 x64 已使用“音元拼音”的独立 CLSID/Profile。2026-09-04 用户批准在本机恢复 WOW64 x86 应用宿主，并与 x64 L5/L6 同步推进；新 x86 必须从当前源码以同一活动身份构建。旧 WOW64 CLSID/Profile 和原始 payload 继续只读保留，不得改名、重注册或当作当前活动产品执行。主流 x86-64 与 ARM64 试验现已恢复，使用 `run-platform-experiment.ps1` 独立入口；本机安装与 D2 门禁保持不变，实机未验收不算通过。

**08:12 原生 `.3` 历史状态**：安装后的 OneDrive 自启动值丢失、冻结 x86 profile 描述/图标改变已由定向入口恢复。该维护器随后由 `.4` 替代；`test-local3-repair.ps1` 继续保留事故的固定证据回归，见[诊断](../../docs/YIMECORE_LOCAL3_REGISTRY_PRESERVATION_2026-09-03.md)。

- `local-product.json`：唯一构包描述，保留现有 GUID/学习空间，限定 MYCOMPUTER x64。
- `test-local-product-build.ps1`：38 项路径、身份、范围、依赖、源码变更和 PS5 纯文本证据序列化保护。
- `build-local-product.ps1`：从源码和仓内数据构建，不依赖旧安装；输出到新建的 `.tmp/yimecore-local-product/<run>/`。
- `test-local-product-runtime.ps1`：由构包器调用，在仓库外隔离目录验证新包、三模式、恢复和 TSF，不做机器注册或真实 Word 验收。
- `test-installed-local-host.ps1`：只读核对当前安装根的 x64/WOW64 COM、两种注册工具状态，并以隔离 Broker 在全码、变码、简码下分别运行 x64/x86 registered-host；不改变机器注册。
- `test-local-product-maintenance.ps1`：共享维护器的正常 x64、冻结引用保留、实际进程身份、首次安装失败状态恢复及标准令牌策略回归；带旧包只读 Plan 时共 55 项，PS5.1/PS7 已验证。
- `local-runtime-launcher.cs`：同 SID/会话的标准用户启动帮助程序。使用明确保留的普通 PowerShell 主令牌，核对 PID/时间/映像/祖先/身份，并挂起验证实际子进程；只请求 `0x018b` 句柄权限。2026-09-03 07:32 原生启动验证已通过。`-NativeDesktop` 是当前 x64 Runtime 加 x64/x86 TSF 模式；历史 x64-only 包仍由 `-NativeX64Only` 维护，两者均与故障演练分离。
- `test-native-standard-user-launch.ps1` / `test-standard-user-launch-contract.ps1`：原生只读启动验证及当前 56 项隔离契约。`native-launch-fix-20260903-073233-5efe1c97` 已证明普通启动对照及 UAC 后实际普通主令牌子进程均通过，五份源码哈希一致；没有安装或停止输入法。探针无需重复。见[1346 / 错误 5 修复记录](../../docs/YIMECORE_STANDARD_USER_LAUNCH_FIX_2026-09-03.md)。
- 仓库根 `Test-YimeCore-Standard-Launch.cmd`：普通资源管理器双击入口，只调用上述探针并保留结果窗口；不自己提权，不接受内部工作进程参数，不修改安全设置。由普通 PowerShell 保持发起进程，再按需请求 UAC。不要从管理员终端或 Codex 中启动。
- `invoke-local-product-native-install.ps1`：固定新候选及原安装基线的外部验收编排，默认只读 Plan。必须普通权限启动；先请求只读启动探针 UAC，再在普通父进程中备份旧包，最后调用包内安装事务及其同账户 UAC。普通父进程保持等待，备份不能把旧 runtime 重启成管理员权限。完整执行仍须原生人工启动，不从 Codex 提权。
- 仓库根 `Install-YimeCore-Local-Dev.cmd`：本次首次晋级的一键验收入口，普通资源管理器双击；无需复制 PowerShell 命令。自动停写备份、安装和核验，不自动重启。安装后真实宿主、实际恢复/回退和重启另行验收；不要把它当作可反复执行的通用升级入口。
- `local-token-diagnostics.ps1` / `test-local-token-diagnostics.ps1`：只查询当前/关联令牌类型，保留嵌套 Win32 错误码及系统说明；不复制令牌、不改变权限、不启动进程。夹具测试不算真实提权启动通过。
- `manage-local-product.ps1`：包内入口，默认只读 Plan；安装/升级/卸载调用同一共享事务器，备份/安全恢复/验证从当前安装包解析依赖。
- `local-package-contract.ps1`：完整清单、路径和字节核对后调用包内 x64 审计，不编译、不要求仓库。
- `local-product-runtime.ps1`：包内恢复后的标准用户启动和真实进程/令牌验证；没有以长期管理员运行代替普通用户运行的回退。
- `test-local-product-package.ps1`：新包只读 Plan、入口/语法、恢复精确文件集和未列出文件拒绝测试；不冒充真实安装或恢复。
- `invoke-local6-uninstall-reinstall.ps1` / 仓库根 `Test-YimeCore-Local6-Uninstall-Reinstall.cmd`：local.6 自身卸载保留数据与完整包重装门禁。12:49 的运行保留为数据、注册和进程证据，但因漏查新用户 TIP 的 `Enable=0` 而不能作为完整 PASS；固化的 `Complete-YimeCore-Local6-Uninstall-Reinstall.cmd` 只用于该次已审查中断的恢复，不是通用入口。
- `repair-local6-active-user-tip.ps1` / 仓库根 `Repair-YimeCore-Local6-Taskbar.cmd`：只针对当前安装、SID、CLSID/Profile 和 manifest 的一次性任务栏修复；仅把活动用户 TIP 的 DWORD `Enable` 从 0 改为 1，保持语言列表、默认输入法、生产/冻结注册、数据和进程不变。必须从普通资源管理器双击，修复后仍需用户确认任务栏可见。

当前安装版本仍为 `0.1.0-local.9`；朱红色 profile 图标候选在 `.tmp/yimecore-local-product/local9-vermilion-20260903` 完成 native x64 构建、包/运行时独立性、三模式和 TSF composition 隔离验证，manifest SHA-256 为 `4a395e073bb58b432c4a35c9446eae5d277234f2e8f8b2e4d66d0ca30c07f262`。19:03 原位安装成功，活动根为 `yimecore-e6c-d099576a9d31-4a395e07-20260903190318`；19:15 正常重启后，用户又在加载 local.9 x64 DLL 的新 VS Code 进程中确认组合提交、裸数字组字和 `Shift+1` 三项通过，L4 已关闭。2026-09-04 解冻本机 WOW64 x86 后，当前源码身份的独立 Win32 S1 构建已通过；下一构包版本升为 `0.1.0-local.11`，包内同时包含 x64/x86 TSF 表面，但 Runtime/Broker 和全部工具仍为 x64。升级事务会按各包描述符选择当前身份注册工具，禁止执行 local.9 携带的旧身份 x86 文件，并在回滚 local.9 时只恢复其实际声明的 x64。长期日常使用、双架构安装态与真实 x86 宿主验收仍未关闭，`local_product_ready` 和公开发行仍为 false。日常候选升级复用包内 `Install-YimeCore-Local.cmd`；仓库根版本号专用脚本只保留固定事故恢复或验收。

维护只能从资源管理器启动的独立 Windows PowerShell 运行。备份/Restore 当前继承已验证的“新鲜归档安全恢复演练”：备份后数据变化即拒绝覆盖，不提供任意历史数据的强制覆盖。local.6 的实际普通用户启动、原位晋级、恢复和失败回退已经验收；local.8 关闭自身卸载重装缺陷，local.9 关闭真实宿主和正常重启门禁。长期日常使用确认仍待完成。晋级后不要混用旧的仓库 Trial 升级命令。

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
## 语流音变准入与隔离源码入口（2026-09-05）

`run-connected-speech-admission.ps1 -InstallRoot <明确安装根> -ExpectedManifestSha256 <固定SHA256>` 要求 PowerShell 7.5+，在新私有目录验证 24 条审定 Stage5C 别名的正向来源、四音元投影及三模式不增码，编译并运行默认不接入日用路径的新 Broker 实验分支。完整门槛包含提交学习、进程重启、禁用、错误配置拒绝和有效配置恢复；保留失败证据，保护安装元数据及历史静态载荷。它不运行 Rime、注册宿主或安装器，不读取用户文本／学习库，不修改默认输入法。

当前结果与边界见 [完成记录](../../docs/project/YIMECORE_SPEECH_ADMISSION_ISOLATED_SOURCE_2026-09-05.md)。这不是 L5 最终确认、L6 封存或新包安装通过。

## SR4-A 自包含试验包入口（2026-09-05）

`run-connected-speech-package.ps1` 要求 PowerShell 7.5+，四个必填参数为 `-AdmissionRoot`（本仓新准入证据根）、`-ExpectedAdmissionSummarySha256`（已核对的完成收据摘要）、`-InstallRoot` 和 `-ExpectedManifestSha256`（日用包保护基线）。它只接受与当前源码和工具一致、包含新增 package 合同测试的完整准入结果；旧 exercise-only 结果不能用作构包凭据。

编排生成全新 `speech-package-*` 证据根及默认关闭、不可安装的 69 文件试验包，再把固定载荷移到 Windows 用户配置根下专用 `YimeCore Isolated Fixtures\SR4` 新目录。包内工具不依赖仓库或安装路径，在独立环境和状态目录执行七阶段 Broker 验证；每次保留封存包、仓外副本及测试结果，不自动清理。它不调用安装器、Rime 或真实输入宿主，也不修改日用模块开关。环境中存在另一版时的仓外运行不等于干净机器单装验收。

`test-connected-speech-package.ps1` 是可在 Windows PowerShell 5.1／PowerShell 7 运行的 57 项 AST／合成合同，不启动产品或安装维护程序。完整结果、两个真实符号链接 SKIP 及下一步 SR4-B 边界见 [SR4-A 记录](../../docs/project/YIMECORE_SPEECH_SR4_PACKAGE_2026-09-05.md)。双产品的独立来源／维护合同入口另见 [tools/dual-product](../dual-product/README.md)。

## SR4-B1 正常产品源码验证入口（2026-09-05）

`run-connected-speech-product-source.ps1 -InstallRoot <明确安装根> -ExpectedManifestSha256 <固定SHA256>` 要求 PowerShell 7.5+，在新的仓内私有环境运行正常产品接口、设置、学习保持、候选注释等源码／合成测试，并编译正常 Broker、Runtime 与 SettingsTool。它不接通构包、执行新构建程序的完整安装流程或操作日用设置。

无能力声明的旧包保持原输入路径；新产品接口固定默认关闭、24 条 Stage5C、完整三模式及哈希绑定的审定显示证据。能力、资源和显式开关属于本版，不从 Rime/PIME、源码仓库或 SR4-A fixture 根隐式寻找运行依赖。关闭静态模块不删除学习。

入口清除真实 Rime／TSF 及旧试验 opt-in，固定无网络 Go 工具环境，记录命名测试节点和实际 SKIP，前后比较源码、锁定输入、安装元数据和历史静态载荷并精确恢复环境。测试程序子进程及隐藏原生控件不等于已安装真实宿主验收。

源码结果见 [SR4-B1 记录](../../docs/project/YIMECORE_SPEECH_SR4B_SOURCE_2026-09-05.md)；11 文件资源导出与可选构包边界见[产品契约](../../docs/project/YIMECORE_SPEECH_SR4B_PRODUCT_CONTRACT_2026-09-05.md)。B1 时点 local.12 描述和安装均未改变；B2 当前源码候选推进为 local.13，日用安装仍是 local.12，安装／维护／宿主与日用确认仍分别安排。

## SR4-B2 默认关闭的正常候选构包

2026-09-08：[符号链接负例补充记录](../../docs/project/YIMECORE_SPEECH_SR4B_SYMLINK_EVIDENCE_2026-09-08.md)。独立 `test-speech-symlink-evidence.ps1` 支持 PS5/PS7，只读源码及自有合成夹具；普通模式区分确切权限 SKIP 与已执行拒绝，`-RequireFixtures` 要求四项真实拒绝全部执行。当前两版均因 Windows 1314 保留四项 SKIP，不能视为 OS 验收闭合。完整构包 runner 已接入分项收据，本次未运行它、未重建或安装包。

`local-product.json` 为 local.13 声明默认关闭的可选 `speech` 能力。构包必须显式提供新鲜准入根、准入 summary SHA256 和 source inventory SHA256；旧入口不带这些参数会在创建输出前拒绝。无能力声明的旧 local.12 包仍保持原审计合同。

`run-connected-speech-product-package.ps1` 要求 PowerShell 7.5+、上述三个准入参数、日用安装根／manifest 固定摘要，以及 `-ProcessFixtureRoot <实际用户目录>\YimeCore Isolated Fixtures\SR4B2\speech-product-test-<新ID>`。它先验证源码仍匹配，隔离运行 PowerShell／Go 合同，构建正常 x64 Runtime 与 x64/x86 TSF 包，再在指定仓外副本运行七阶段正常 Runtime/Broker 夹具。所有进程使用显式唯一管道和新状态目录；不调用安装、真实维护、注册宿主或日用管道。

`local-product-speech-build.ps1` 只接收 build-only 导出器验证的 11 文件：9 个准入文件逐字节复制，2 个产品 envelope 新生成。正常三模式索引仍独立构建两次并与准入 core SHA256 比对。导出 mapping 和源码证明留在包外；包内 `build/build-inputs.json` 只绑定固定摘要。Python、准入工具、旧运行结果和试验状态不进入安装 payload。

`test-local-product-speech-build.ps1` 验证构包预检与源顺序，不冒充实际导出；`test-speech-maintenance-data.ps1` 验证 `speech.json` 进入实际维护数据枚举及隔离 restore 映射，不运行真实备份／恢复事务。SR4-B2 的构包和正常私有进程通过也不等于安装、Windows 重启或 Word／Notepad++ 人工验收通过。
