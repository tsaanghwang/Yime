# 本机独立产品：原生安装验收窗口

当前：2026-09-03 07:32 原生普通主令牌启动探针已经通过，见[启动修复记录](YIMECORE_STANDARD_USER_LAUNCH_FIX_2026-09-03.md)。原 `.2` 候选仍封存，不再安装。新 `.3` 候选纳入修复，并使用普通 Explorer 双击 `Install-YimeCore-Local-Dev.cmd` 的原生验收入口；构建结果与固定哈希另列新候选记录。新包仍未安装，不能把探针 PASS 当成安装验收 PASS。

下列内容均为早先 `.2` 窗口的历史记录。尤其“管理员终端”和旧 `-LaunchProbeOnly` 命令不再是当前操作指令。新版从普通用户开始，脚本保留发起进程、自行请求两次同账户 UAC，备份在普通父进程执行；不改 UAC、不借用 Explorer 令牌、不让 runtime 常驻管理员权限。

## 2026-09-03 06:47 原生失败与当时的诊断步骤（历史）

用户执行的证据在 `C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-064718-04f03961`。`failure.json` 的阶段为 `standard-user-launch-preflight`；失败发生在 `DuplicateTokenEx`，报错 `Duplicate linked primary token`。旧记录只存了 PowerShell 外层异常，**未保留 NativeErrorCode，不能据此断言是权限不足或模拟级别不足**。

复查确认：该次归档没有 `preinstall-backup`，新目标目录未创建，旧 manifest 仍为下述 `8d48953a…`；旧 Runtime PID 14016、Broker PID 23756 的实际映像仍指向旧安装。关联令牌的 SID、会话、非提权及中完整性检查通过，不代表它能够被复制为可启动的主令牌。这是原生维护启动问题，不是 Word/任务栏自动化限制，也不是输入引擎实现语言问题。

当前只做诊断，不重启、不重复完整安装、不直接改封存候选。保持相同账户的资源管理器启动的 **Windows PowerShell（管理员）**，关闭 Word 和输入法管理工具后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\invoke-local-product-native-install.ps1" -LaunchProbeOnly
```

此入口查询当前/关联令牌类型和模拟级别，使用候选原封不动的启动帮助程序重复只读审计探针，记录完整异常链、Windows 错误码和系统错误说明。它只创建新的诊断证据目录；**即使探针成功，也在停写、备份、安装之前返回**。不会借用 Explorer 的令牌、变更权限、修改生产注册或让输入法长期以管理员运行。当前候选的 `-Execute` 已被验收编排明确暂停；只有查明问题并验证修复后才能恢复。

提供终端的 `BLOCKED: ... Win32=...` 或 `PASS: read-only ...` 行及证据目录即可。新诊断和验收脚本不属于封存候选：各自哈希写入 `preflight.json`，没有伪造候选清单。诊断 PASS 不等于安装、普通权限运行、恢复/回退、真实宿主或重启验收 PASS。

回归：PS5.1/PS7 均通过只读令牌诊断 29 项、安装编排保护 28 项；错误码 5/1346/1314/0 是异常序列化夹具，**不是本次真实失败的错误码**。真实提权启动仍需上述原生诊断。

本次新增测试证据在 `.tmp/yimecore-local-product/`：PS5 为 `token-diagnostics-contract-16bd88cc48a9429ca3fd9bbbee34c3e6`、`native-install-contract-eb62a7a7cd0041d79594bf6faefe054a`；PS7 为 `token-diagnostics-contract-1d8a4c32f92d4809b7859f3d4f739794`、`native-install-contract-4cdba0136a8f44d4bfc16a585be14367`。默认 Plan 已重新验证，并明确返回 `native_install_paused=true`；封存候选全清单检查通过。

## 固定输入

候选目录：`C:\dev\Yime\.tmp\yimecore-local-product\20260903-000638-13644db3\package`。

候选 manifest SHA256：`6bb1c10d24228c436ce6e77b4063c36bcc786fd5cabaa38a8efd690941e10e9d`。

预期旧 Trial manifest SHA256：`8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64`。

仅接受当前开发者 SID `S-1-5-21-2783006668-770716121-2150155084-1001` 和 MYCOMPUTER 原生 x64。若已安装其它版本、候选被改动或目标已存在，拒绝重复迁移并要求重新规划。

`tools/yimecore/invoke-local-product-native-install.ps1` 是本轮验收编排，不是第二个产品安装器：它调用冻结候选的包内安装及维护入口，并把自己的内容哈希记录在证据中。候选文件、manifest 和已封存源码没有因新增验收脚本而重打包。

## 原计划操作（暂停，勿重试）

以下保留为原验收顺序，不是当前指令。修复后重新审查候选与哈希，才恢复完整安装：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\invoke-local-product-native-install.ps1" -Execute
```

不是 Codex/打包应用里的终端；不要切换到另一个管理员账户。管理员权限用于检查旧的提权 runtime、维护和取证，不作为新 runtime 的日常运行权限。脚本不自动重启。没有 `-Execute` 时仅输出只读计划，不访问当前用户运行数据，也不创建归档。

顺序：

1. 检查上下文、账户、候选哈希、旧包哈希、占用工具和实际旧 runtime/Broker。
2. 在停写之前，以相同 SID 的标准令牌实际启动包内只读审计探针。不存在仅验证“有 linked token”就开始停机的问题；创建进程失败时旧 runtime 不被停止。
3. 通过包内兼容适配做一次新鲜停写备份，验证归档中的状态/完整旧包文件集和系统可见性。
4. 调用候选的 `Install-YimeCore-Local.cmd`。安装器负责完整 staging、同 SID 注册、冻结引用保留和安装失败事务回滚。
5. 核对已安装 manifest、runtime/Broker 真实身份和普通用户令牌，调用安装包自己的 Verify，验证三模式与整句用例。
6. 用独立 StdRegProv 系统视图比较生产/冻结注册、用户 TIP、默认输入法及无关自启动项；核对新 COM、Run、卸载命令和账户/状态路径。对比学习/词库/设置文件，并检查冻结 x86 引用的旧安装根字节未变。

归档与证据位于 `C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-<时间>-<随机值>`，其中 `preinstall-backup` 包含状态和完整旧安装包。失败会记录准确阶段和异常到 `failure.json`、`summary.json`，保留归档；不会自动重复安装或在安装后检查失败时强制覆盖数据。

完成后提供最后的 PASS 行；失败则提供完整错误和证据目录，暂不重启。不应再运行旧 `Upgrade-YimeCore-Trial.cmd`。

## 已完成的准备验证

- 固定候选 71 项文件/23 PE 审计和包内 Plan 再次通过。
- 当前 Codex 调用上下文明确被现有原生保护拒绝，没有绕过保护或执行真实安装。
- 验收脚本 23 项回归在 PS5.1/PS7 均通过，覆盖生产/冻结/默认设置变化、错误 COM/Run 类型和路径、缺失/重复 Run、卸载 SID/状态/模式等拒绝分支，以及备份/标准用户预检的执行顺序。
- 证据：`.tmp/yimecore-local-product/native-install-contract-ba5a352975004f0ca0a4b51d83153ffc`（PS5）、`native-install-contract-232693945bda465b8e5ed014648842d5`（PS7）。这些都是夹具测试，不是实际安装通过。

即使此脚本 PASS，也只关闭本次原位安装、权限和数据/注册保持检查；实际备份恢复、失败回退、自身重装、Word/其它真实宿主和重启登录仍分开验收。`local_product_ready` 和 `public_release_ready` 继续为 false。

签名证书正在申请，等候审批，暂缓相关事项。冻结架构和其他机型不变。
