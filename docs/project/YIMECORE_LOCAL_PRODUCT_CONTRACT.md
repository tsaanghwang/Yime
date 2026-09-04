# 本机独立产品契约与功能保留清单

更新：2026-09-04。规范入口是 `tools/yimecore/local-product.json`；源码描述和当前安装均为 `0.1.0-local.11`。活动范围是 MYCOMPUTER 原生 x64 Runtime/Broker 及本机 x64、WOW64 x86 TSF 表面。local.3/local.4 等记录保留为历史证据。

## 身份和兼容边界

2026-09-03 的 `local.9` 已通过重启后 x64 宿主三项人工确认。2026-09-04 用户批准解冻本机 WOW64 x86 应用宿主；`local.11` 双架构包随后完成干净源码构包、真实安装和 x64/x86 三模式 registered-host，并在 Firefox/Notepad++ 32 位进程中确认加载当前 x86 DLL 及三项输入行为。x86 分支已通过，但 x64 L5 日常使用及 L6 合并封存仍待完成。

活动产品使用独立 CLSID/Profile，显示名为“音元拼音”。旧 CLSID/Profile 只归历史封存试验；旧 x86 文件不得因本机 x86 解冻而执行或改称当前产品。

新构包的 x64 与 Win32 TSF 均使用 `YIME_LOCAL_PRODUCT=ON`，从唯一描述生成显示名与 CLSID/Profile 头文件；未启用此开关的旧 Trial 构建保持旧名称和旧 GUID。维护器从经清单验证的描述读取显示名，并注册当前身份的 x64/x86 COM 表面。语言栏菜单和按键契约不变。

| 身份 | 保持的值 | 当前消费者与后续接线位置 |
| --- | --- | --- |
| 活动 x64/x86 COM CLSID | `{E40FA752-BB96-461D-A51D-F40EB437EC65}` | `local-product.json` 生成当前身份；维护器按包声明写入 x64 与 WOW64 COM 视图 |
| 活动输入法 Profile | `{126F54C6-E9B1-4E22-8652-03224CBD49F9}`；语言 `0804` | 两种进程位数共享“音元拼音”输入法条目 |
| 冻结旧身份 | CLSID `{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}`；Profile `{607895A8-9504-4A2E-9BB1-2C159E3A1757}` | 历史构建与 WOW64 静态注册；迁移前后均须逐值保持，不执行冻结二进制 |
| 安装/状态目录 | `YimeCore Experimental Trial` | runtime 的 `resolveOptions`、`ExperimentSettings`、安装器、工具启动参数；目录内 Trial 不表示依赖 Rime |
| Run/卸载产品键 | `YimeCoreExperimentalTrial` | `manage-e6c-trial-install.ps1`、autostart/system-uninstall 修复器 |
| 日常管道 | `\\.\pipe\YimeBroker.YimeCoreTrial.v1` | runtime 和 TSF Broker endpoint；隔离测试使用另一个唯一管道 |
| 学习 source ID | `yimecore-e6c-three-mode-trial-v1` | runtime、Broker durable store、备份/恢复探针；不因改名重置学习 |
| 数据格式 | model v1–v4、journal v1–v2 兼容读取 | 现有 Go 恢复实现；本次不新增格式迁移 |

`test-local-product-build.ps1` 直接核对 TSF GUID 与 runtime 兼容常量；拒绝身份改变、范围越界和不规范路径。当前生产 GUID、生产文件、默认输入法不属于可写目标。旧身份 x86 注册引用根继续保护；只有从当前源码和身份新构建并由描述符声明活动的 x86 工具可以进入事务。

## 不悄悄删减的功能

| 能力 | 本批保留载荷/验证 | 晋级时的限制 |
| --- | --- | --- |
| 全码、变码、简码与整句组合 | 三个新建 `.yidx`；Broker、TSF、整句回归工具 | 词典是静态构包数据，读取 YAML 不等于运行 Rime |
| 裸数字输入、Shift+1…9 选词、⇧ 标签 | 原有 TSF 按键/候选契约，直接 TSF 回归 | 不引入数字选词开关，不改候选所有权 |
| 中英模式、英文 Shift、语言栏菜单、标点 | 原有 TSF 实现与回归 | 直接隔离测试不是物理任务栏验收；改显示/安装后仍需新 RC 的真实宿主复核 |
| 自学习、恢复、索引事务 | 原有 Broker/core；包内预编译 RecoveryProbe | 探针只运行于带标记的临时克隆；包内安全恢复仍需新候选原生维护验收 |
| 用户词库、学习管理、黑名单、专业词库 | LexiconManager、LearningManager、BlocklistManager、ProfessionalLexicon、catalog | 保留原试验状态目录；不写生产 Rime 用户目录 |
| 系统词库审查、高频新词扫描 | SystemLexiconAudit、PromotionScan | 不把工具界面内容当成正式新包实机验收 |
| 布局、反查、训练、候选设置 | LayoutDesigner、ReverseLookup、Trainer、SettingsTool；字体/训练素材 | 从明确仓内来源复制，记录哈希；不读取兄弟仓库 |
| 工具中心、词库中心、诊断和帮助 | ToolCenter、LexiconCenter、Diagnostics、4 个原有帮助页面及本机产品指南 | 保留内部 Trial 文件名及部分历史帮助说明；自有 Win32 UI 只允许工具使用，核心仍禁止 UI 依赖 |
| 安装、升级、卸载、完整备份与安全恢复 | 包内 Install/Maintain CMD、共享事务器、恢复/验证/标准用户启动依赖 | Restore 是新鲜归档安全恢复演练，数据改变即拒绝覆盖；任意历史灾难恢复与真实新包安装不能由夹具通过代替 |
| 同步和新增音变规则 | 不增加、不扩展 | 联网自动同步及额外离线同步功能后续排期；备份不等于同步 |

## 构包契约

新入口为 `tools/yimecore/build-local-product.ps1`。从空目录构建，既不接受旧 BasePackageRoot，也不从 AppData 的 `runtime-config.json` 隐式寻找旧安装。

新候选契约为 `yimecore-local-product-package-v1`，`installable=true`；`local.11` 清单包含 74 个运行、TSF、数据及维护文件。这里的 installable 仅指可安装包类型；`local_product_ready=false`，直至真实安装、普通权限、回退和 x64/x86 宿主使用验收完成。旧 `yimecore-local-runtime-bundle-v1` 继续要求 `installable=false`，不接受维护入口，也不可被安装器接收。

- descriptor 的 Go/native/assets/maintenance_assets 列表驱动构包；审计器独立固定必需集合并拒绝额外载荷，测试确认集合一致，不能通过删减清单同时漏掉工具。
- `bin/`、维护器和 `x64/` PE 必须为 AMD64；只有 `x86/` 下三个 TSF PE 必须为 I386。新候选拒绝 ARM64 目录；旧 E6-C 的多架构必需文件要求保持，不借修改新契约削弱历史审计。
- 清单拒绝未知契约、缺文件、漏列文件、重复路径、越界/ADS/非规范路径、间接路径、哈希和架构错误。静态 PE 导入及所有 Go 命令依赖都排除 Rime/PIME。
- 保存 commit、dirty 状态、643 项首批源码/数据内容记录（以后数量随源码变化）、完整源码 ZIP、二进制 Git diff、Go/MSVC/CMake 版本和参数。包里保存来源清单；完整源码 ZIP 在构建证据目录，不作为运行依赖。
- 新索引从仓内字典构建两次并逐字节哈希比较。源码在构包后逐文件复查，新增/删除文件也使本次构建失败。
- 不声称所有 PE、ZIP 和证据 JSON 都逐字节可复现：时间戳、绝对构建路径和运行证据独立列明。未提交修复不会被仅记录 HEAD 隐去。
- 首批自动验证在仓库外的唯一临时目录、唯一管道和全新模型运行；不注册候选 DLL，不启动 registered-host 测试，不要求打开 Word，不改默认输入法。运行前后独立 StdRegProv/HKU 系统视图比较生产/试验 COM/TIP、用户 TIP、Run、卸载和默认语言设置。

当前可执行的开发命令（不是安装命令）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\test-local-product-build.ps1"
pwsh -NoProfile -File "C:\dev\Yime\tools\yimecore\build-local-product.ps1"
```

L2 运行包完整构包已在 PowerShell 7 验证；新候选增加 Windows PowerShell 5.1 完整构包及 PS5/PS7 入口回归。证据序列化规范化为纯文本，避免 PS5 展开 Get-Content 的 Provider 对象图。CMD 使用子进程限定的 Windows 原生模块目录，避免继承 PS7 的不兼容模块搜索路径。构包需要 Go、MSVC/CMake；包内只读 Plan 和隔离运行不需要它们。真实安装/恢复/标准用户启动仍待 L4，不能用只读 Plan 代替。

普通维护须由资源管理器启动的独立 Windows PowerShell 执行；不会从 Codex 自动逃逸上下文。备份保存在用户目录的 `YimeCore Recovery Archives`，恢复前校验精确文件集、路径、哈希以及完整学习/词库/设置清单；原件保留。新旧两个维护流程共享同一事务器，不复制长期分叉的安装器。

签名证书正在申请，等候审批，暂缓相关事项。
