# 本机独立开发版 0.1.0-local.3：原生启动修复候选

> 历史记录：local.3 后来已安装并于 2026-09-03 升级为 local.4。本文“尚未安装”的描述只代表当时状态；当前状态见 [local.4 原生升级记录](YIMECORE_LOCAL_PRODUCT_LOCAL4_2026-09-03.md)。

**后续状态已更新：07:54 新包已安装，但 Run/冻结 profile 保护检查发现三项真实变化，整体验收未通过。停止使用下述首次安装命令及当前包内升级/卸载入口。当前操作见[注册保护缺陷与三项恢复](YIMECORE_LOCAL3_REGISTRY_PRESERVATION_2026-09-03.md)。下文为构包时的封存记录。**

当前结果：原生普通主令牌只读启动通过；修复已封装，完整 x64 源码构包、隔离验证和交付核对通过。**尚未实际安装新包；新包的真实宿主、数据恢复、失败升级回退、自身卸载重装及最终登录启动仍待验收。** `local_product_ready=false`、`public_release_ready=false`。

## 下一步：一次原生安装验收

关闭 Word 和输入法设置/管理工具，打开 Windows 资源管理器，进入 `C:\dev\Yime`，普通双击 `Install-YimeCore-Local-Dev.cmd`。不要选择“以管理员身份运行”，不要从 Codex/打包应用终端运行。保持结果窗口打开；两次同账户 UAC 分别用于只读启动检查和安装事务。无需复制 PowerShell 命令，不自动重启。

流程：同账户普通父进程 → 只读 UAC 启动检查 → 普通父进程停写备份旧包 → 包内安装器自行同账户 UAC → 普通 runtime/Broker、三模式、数据及系统注册核验。旧包备份不得放到提权工作进程内，否则旧兼容启动器会将旧 runtime 重启成管理员权限。

此根目录 CMD 是本次从固定旧 Trial 晋级的验收入口，不是可反复执行的通用升级器。初始配置、旧包哈希或目标占用有变化即停止重新规划；不自动重试覆盖。安装成功后使用已安装包的 `Maintain-YimeCore-Local.cmd`，不要混用旧 `Upgrade-YimeCore-Trial.cmd`。

完成后提供 PASS/BLOCKED 行及证据目录，暂不重启。证据在 `%USERPROFILE%\YimeCore Recovery Archives\local-product-install-<时间>-<随机值>`；其中 `preinstall-backup` 包含完整旧包和用户状态。安装事务自身负责安装失败回滚；安装后检查失败只保留证据，不强制覆盖已变化的数据。新包实际恢复/回退与宿主验收另行安排。

## 固定候选与来源

构建根：`C:\dev\Yime\.tmp\yimecore-local-product\20260903-local3-standard-primary`，安装包为其 `package` 子目录。

| 项目 | SHA256 |
| --- | --- |
| 候选 manifest | `6964099f48e0b6f534b763728d4a1806e4d4edfb1e7d7053b42c6d78d9fee74a` |
| 来源 manifest，662 个文件 | `7e89a59cb891e2d2c2d83011e7468178fd08cc829728a596e9a9c6a66aa087f1` |
| 完整来源 ZIP | `693f2f59d62101e0523309567557d72dd624cc8a05d4de2b6dc843d6654090fb` |
| TSF DLL | `80cc32ea112cab8e87b51f629893a6c91f7952da91ffdf371287703bacf1bbf0` |
| Runtime EXE | `52e6de312cddea26e4c6d7fab3247cf541eab7ad7a54e81bf3e236d02442afb2` |
| 普通主令牌启动器 | `36ccdd6cb08e05819ab994bd8fcfe032c4654d379bd612b69e0812c48650f12c` |
| 包内共享安装器 | `e21718a6890c25a09511eb9724a1ed1737c12b8a415e9c1ca798457e76fd32a9` |
| 外部首次晋级验收脚本 | `7f387a3a87dbf27b2b20b65eb01299c31492485bec0c45ea57d1924c5115ce34` |
| 根目录一键 CMD | `9f7812605d1d9c45caa10d85a4d48cf6e721b0492d0c7764864cd2ea5ad2c8b9` |

Package ID：`yimecore-local-0.1.0-local.3-7e89a59cb891`；71 个载荷文件，23 个 x64 PE。Runtime 与上一个 `.2` 候选哈希相同是预期结果：这次主要修复维护启动链，不伪称引擎已改变。原安装基线为 `8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64`，不等于这个新候选的 runtime。

来源完整核验：662 个 ZIP 条目逐个比对长度和哈希，当前构包来源只有一处允许的构建后差异——**不属于安装载荷的外部验收脚本**，把候选 manifest 占位哈希替换为最终值。`verify-handoff.ps1` 核对该差异仅为这一行，包内文件及封存 ZIP 未修改。实际原生执行再把外部脚本/诊断依赖的哈希集合跨 UAC 固定，保存到自身证据，不冒称它与封存占位文本相同。

## 本轮已验证

- 用户原生证据 `native-launch-fix-20260903-073233-5efe1c97`：普通同映像对照及 UAC 后实际普通 Primary 子进程均成功，五份源码哈希一致；五份关键 JSON 系统可见。只解除这个启动路径阻塞。
- Windows PowerShell 5.1 完整构建通过；Go core/Broker/runtime/audit 测试、C++ 契约及独立性审计通过。
- 全码/变码/简码每份索引 1,166,753 条，各构建两次哈希相同；12 个整句用例、三模式 Broker、隔离恢复 generation 12 / records 11 通过。
- 仓库外唯一管道、全新模型下的直接 x64 TSF/语言栏/候选/标点提交、64 组英文 Shift 透传、Broker 故障重启及测试运行时停止通过。不是机器注册或真实 Word/任务栏点击验收。
- PS5.1/PS7：56 项启动契约、55 项维护契约（含旧包只读 Plan）、45 项外部安装编排契约、35 项包内维护契约通过。另有 38 项构包、29 项令牌诊断、8 项上下文、66 项范围回归通过。
- 最终 Plan 在 PS5.1/PS7 均通过；目标为 `C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-75485fda5d79-6964099f`，当前不存在。只启用 x64 注册；冻结 x86 引用仍明确要求保留完整旧根。
- 真实根目录 CMD 在确认的 Codex 打包上下文被 guard 拒绝，保留退出码 1，没有 UAC/备份/安装。这是保护测试，不是真实原生安装 PASS。
- `handoff-verification.json`：独立系统注册视图与构建前一致，旧完整包审计通过，旧 runtime PID 14016、Broker PID 23756 仍为同用户普通 Primary；没有改变当前输入法或默认项。

主要证据：构建根下 `summary.json`、`independence-audit.json`、`runtime-verification/summary.json`、`package-verification/summary.json`、`package-verification-ps7/summary.json`、`native-install-plan.json`、`handoff-verification.json`、`installed-baseline-audit.json`。

范围仍只有 MYCOMPUTER 原生 x64。生产 Rime/PIME 保留，冻结 ARM64/x86/旧 x64/其它机台；未恢复模拟测试、联网同步或新增音变规则。签名证书正在申请，等候审批，暂缓相关事项。
