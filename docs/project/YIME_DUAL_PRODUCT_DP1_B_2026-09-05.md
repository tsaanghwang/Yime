# DP1-B：Rime/PIME 静止状态维护准入保护

日期：2026-09-05。依据 [双产品开发计划](YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md)。本批接续 [DP1-A](YIME_DUAL_PRODUCT_DP1_2026-09-05.md)，不改变其原始结果和历史收据。

## 结论与新增限制

本批完成的是**源码层静止状态维护准入保护及隔离分支回归**，不是完整 DP1，也不是实际安装/升级/卸载、DP2 实机共存或发布验收。Rime/PIME 与 YimeCore 的单装、同时安装、独立维护方向不变。

维护前先验证明确选定安装根的产品标记、规范路径、无 reparse 跳转及当前 Windows SID，再核对确切发布映像路径、PID、启动时间和进程 SID。发现该产品仍有运行进程，或相关映像名称的路径不可读，立即拒绝并提示先保存、关闭本产品；**不会强杀进程，也不会调用共享退出事件**。正常新安装的空/不存在目录及带有效产品标记的自定义根仍可进入后续流程。

这一限制是有意保守的：目前不能一键自动停止正在运行的 Rime/PIME。仅关闭输入宿主未必关闭后台 Launcher；若后台仍运行，应先正常退出或在未运行本版的会话重试，不应通过强制终止来绕过门禁。无法证明身份的旧版/不完整根须单独修复，不会被自动删除。当前静止检查也不是阻止进程之后重新启动的维护锁。

实际 Launcher 源码 `PIMELauncher/src/main.rs` 的 `/quit` 使用共享 `PIMELauncher2_QuitEvent`，不是可绑定某个安装根进程的管道维护 RPC。其现有 watchdog 收到事件后会杀死子进程；本批没有把它称为已经证明能刷新学习状态的优雅退出。

## 实现范围

- 新增 `tools/dual-product/rime-pime-ownership.ps1`（仅定义函数）及 `invoke-rime-pime-maintenance.ps1`（独立 NSIS 入口）。包装入口动作是 `ValidateInstall`、`ValidateExisting`、`Stop`；其中 `Stop` 当前只是静止状态准入检查。失败退出 41；没有任何真实进程停止实现。
- `dev-stop-pime.ps1`、`dev-install.ps1`、`dev-uninstall.ps1` 复用同一归属 helper；必需 helper 缺失时拒绝，不回落到全局按名称停止。保留 `dev-stop` DLL 锁退出码 2、`KeepInstallRoot` 与 `-AllowLocked` 原位升级路径。
- 开发卸载只维护明确指定的 `InstallRoot`（未传参时为当前 YIME 默认根），不额外搜索或依赖 legacy registry/default PIME 目录，也不无条件删除 legacy PIME 安装/卸载标记。另一个无关 PIME 目录不能阻止有效自定义 YIME 根的本次选择。原注册清理的完整根/SID 所有权矩阵仍待后续，不能据此宣称任意多个 PIME 分支都已可独立维护。
- NSIS 安装器和卸载器分别内嵌 helper 字节，无需已安装另一产品或仓库；旧版升级的运行状态检查放在用户确认之后、第一项清理之前。保留原 DLL 暂存/重启替换逻辑。此次未编译或运行完整 NSIS 安装器，其完整事务仍待专门验证。
- 运行映像清单对照 `go-backend/build.bat` 实际发布目的地：Launcher、12 个 Go 工具/服务及可选 `input_methods\yime` 下 `rime_deployer.exe` / `rime_dict_manager.exe`，共 15 条精确路径。仅按 basename 判断的分支只用于“路径不可读，无法证明静止”时拒绝，不用于终止。

## 隔离验证与收据

`tools/dual-product/test-rime-maintenance.ps1` 使用新建 `.tmp/dual-product/dp1-rime-maint-*`；在创建前拒绝 reparse 祖先。只载入 helper 定义与通过 PowerShell AST 提取的三个卸载函数，不执行开发安装/卸载入口或 NSIS。进程、SID 查询与删除操作全部是合成记录/mock；假 EXE 是不可执行文本。输出仅为合成测试结果、源码哈希和状态，不包含用户文字或学习数据。

| 收据 | 结果 |
| --- | --- |
| `.tmp/dual-product/dp1-rime-maint-red-20260905-a1/result.json` | 初始负例：6 项中 5 项失败，保留原结果 |
| `.tmp/dual-product/dp1-rime-maint-prewire-20260905-a1/result.json` | helper 接入前：18 项中 5 项失败，保留原结果 |
| `.tmp/dual-product/dp1-rime-maint-quiescent-ps5-20260905-a3/result.json` | 最终 PS 5.1：30 项，0 失败 |
| `.tmp/dual-product/dp1-rime-maint-quiescent-ps7-20260905-a3/result.json` | 最终 PS 7：30 项，0 失败 |
| `.tmp/dual-product/dp1-20260905-b1/baseline.json` | 当前源码基线：26 个哈希输入，23 个纯内存/源守卫检查，0 失败/跳过，3 项 pending |

PS 5.1 首次启动被本机默认执行策略拒绝，未运行测试；后续仅该测试进程使用 `-ExecutionPolicy Bypass`，未修改系统/用户执行策略。首次指定的非捆绑 Python 被系统拒绝启动，随后使用已配置捆绑 Python 完成基线验证。

关键负例包括：错误产品标记、未知/宽泛/非规范根、Core 根、错误 SID、同名前缀但不同根、PID/映像变化、所有权查询失败、15 个工具各自单独运行、相关映像路径不可读、缺必需 helper、helper 返回 3 拒绝、返回 2 保留原位流程，以及实际卸载函数在 foreign 根上删除调用次数为零。有效自定义根旁有 foreign 默认/registry legacy 根不成为依赖。reparse 为路径/元数据防护与源码检查，**没有声称创建了实际 OS 符号链接**。

当前 baseline 读取实际函数里的 guard 与顺序，删除 guard、重引入全局停止、移除必需 helper 拒绝分支都会使测试失败。旧 `LEGACY-03` 不再仅因为历史调用名称出现而误报“无 marker”。历史 DP1-A 收据未改。

SHA-256：

- PS5 最终结果：`bb3832764aa7e9ab7f3717f0ae3df1c990df23b61e66a237ae71495d8946a0f8`
- PS7 最终结果：`0d484ec0b7e423fc1fcd2cc07831eac4c6231035b46f3a90900aea681eba46f3`
- 当前 DP1-B baseline：`21e74aa43a3d5ad600f500f24022d508805de20f5a70deff50266ad7c47d0dc3`
- 未修改 DP1-A baseline：`6d05ae9fe1241b0e7933f420eae914979b5b82eb92bd3578c7267fac1b4da86b`

## 尚未关闭的门禁

1. `DP1-PIME-DIRECTED-EXIT-04`：根/SID/进程绑定的定向退出协议、确认与状态刷新，以及维护期间阻止重启的协调机制。不能把静止时无进程等同自动退出完成。
2. `DP1-PIME-REGISTRY-05`：旧/当前注册值对所选根的完整所有权、跨用户清理、启动 SID 经提权/NSIS 的传递验证。本批 helper 验证执行用户/目标进程 SID，不证明提权前启动用户身份链已闭合。
3. `DP1-PIME-TRANSACTION-06`：完整安装/升级/卸载/回滚和 DLL 锁事务夹具；另行授权后的两版实际单装/共存/重启、x86-64/ARM64 可用目标验收。

本轮没有执行任何真实 Stop-Process/taskkill、安装/卸载、生产 Rime/PIME/冻结二进制、注册写入或默认输入法变更；没有读取生产用户数据。`dp1_full_implementation_passed=false`、`dp2_physical_acceptance_passed=false`。开发方向批准不替代发布、默认切换、最终日用确认或其他尚未通过门禁。
