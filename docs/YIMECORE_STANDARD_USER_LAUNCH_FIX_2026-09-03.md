# 本机维护普通权限启动修复：Win32 1346

状态：**2026-09-03 07:32 原生只读启动验证通过，原 Win32 1346 / 5 启动阻塞在该路径已解除。**这不是新包安装、runtime/Broker、真实宿主或恢复/回退通过。下面早先诊断和命令保留为历史，探针不必重复；下一步是封装修复候选及一键原生安装验收。

## 最新：07:32 已验证实际普通权限子进程

证据：`C:\Users\tsaan\YimeCore Recovery Archives\native-launch-fix-20260903-073233-5efe1c97`。

- `ordinary-baseline.json`：同映像、同工作目录的普通启动成功；`ordinary-audit.json` 完整包审计通过。
- `summary.json` / `token-evidence.json`：UAC 工作进程仍为同一账户；实际启动子进程为 Primary、非提权、完整性 8192、会话 1、非 AppContainer。源令牌和复制后令牌均符合相同身份；请求句柄权限为 395（`0x018b`）。不是只凭退出码或关联令牌推断。
- `audit.json`：跨权限启动的审计进程完整包审计通过，manifest 为 `6bb1c10d24228c436ce6e77b4063c36bcc786fd5cabaa38a8efd690941e10e9d`。该旧包在此仅提供固定审计程序，不表示旧包已包含修复。
- 发起参考 `31316:134328655524695089`；源码集合 SHA256 `3bbebb196b9efb0808741c3fbe64a403fc829f6e956e15925c57b2f67e175695`。本轮复核五个源码文件与证据一致，五份关键 JSON 均通过独立系统文件可见性检查。
- 没有停止旧输入法、备份、安装或重启；所有相关结果标志仍为 false。

新候选将使用 `0.1.0-local.3`，原封存 `.2` 不原地修改。安装验收改为普通 Explorer 双击 `Install-YimeCore-Local-Dev.cmd`，脚本自己请求只读探针及安装 UAC；旧包备份留在普通父进程，避免旧 runtime 被管理员权限重启。候选构建及固定哈希通过后才能执行；以新候选记录为准。

## 历史：07:22 已正确进入普通发起方，创建进程返回 5

`C:\Users\tsaan\YimeCore Recovery Archives\native-launch-fix-20260903-072247-ab37cd8a` 证明：本次双击和 UAC 路径正确，发起方主令牌已核对为同 SID、会话 1、普通权限、完整性 8192、Primary。复制令牌、复制后身份检查及用户环境创建均已通过，`CreateProcessWithTokenW` 返回 **Win32 5 / 拒绝访问**。不是管理员窗口使用错误，也不是 1346 重现。没有实际子进程、安装、停机、备份或重启。

只读排查：Secondary Logon 服务在运行；候选审计 EXE 的 ACL 授予普通 Users 读取/执行、Authenticated Users 修改权限，没有 Zone.Identifier 流；07:20–07:26 的 CodeIntegrity Operational 查询成功且无匹配事件。这不能排除所有系统策略，也不能将错误归结为签名或用户操作。

代码发现并修正一项与该错误高度相关的遗漏：原复制句柄掩码为 `0x000b`，只含 query/duplicate/assign-primary；[Chromium 的同类实现](https://chromium.googlesource.com/chromium/src/+/refs/tags/140.0.7339.50/base/win/elevation_util.cc) 还请求 `TOKEN_ADJUST_DEFAULT` 与 `TOKEN_ADJUST_SESSIONID`。现使用明确限定的 `0x018b`，不申请 ALL_ACCESS/MAXIMUM_ALLOWED、不启用额外系统特权、不取 Explorer 令牌、不改变同 SID/会话/完整性/Primary 要求。只参考其令牌句柄权限组合，不采用该文件的 Explorer 来源或特权启用逻辑。**这是源码修正，必须有新的原生 PASS 才能确认本机错误 5 已解除；具体缺哪一项权利尚未做逐项原生对照。**

同一双击入口现先在普通原生发起进程中直接启动同一固定审计 EXE、同一工作目录并验证完整包，保存 `ordinary-audit.json` / `ordinary-baseline.json`；再 UAC 验证跨权限启动。失败证据新增执行阶段、请求权限掩码、复制前后和实际子进程令牌。提权分支的子进程令牌在挂起时从实际句柄取得，不再在程序可能已退出后重开 PID。源代码/候选哈希锁定及退出清理规则不变。

PS5.1/PS7 启动契约 **56 项通过**，维护契约 55 项通过，原生安装编排 28 项通过，上下文保护 8 项通过。证据在 `.tmp/yimecore-local-product/`：`standard-primary-contract-5b4c6644dfc24e4ca01d0ea8c18d9f05`、`standard-primary-contract-c256f5f5e0db430cab962ca41ccd3ee5`；`maintenance-442dc3f63d4d42c4bb706f6efd16290f`、`maintenance-dcc0249e9d744e6ab98e5a801703cf9e`；`native-install-contract-e2e5dcad301b4b9d8b1b15fe53d01d7a`。旧候选和当前安装仍未更改。

## 确切原因

原生证据：`C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-065942-0db93597`。

`preflight.json` 显示：管理员调用方为 Primary；关联令牌为 `TokenType=2`（Impersonation）、`ImpersonationLevel=1`（SecurityIdentification），同 SID、同会话、非提权、中完整性。`failure.json` 记录 `DuplicateTokenEx` 返回 **1346**。旧帮助程序只判断账户、完整性和提权状态，误把满足身份条件的关联令牌当成可用于启动的主令牌。

SecurityIdentification 允许检查身份，但不允许以该身份执行模拟操作；创建用户进程需要满足相应权限的主令牌。[Microsoft 模拟级别说明](https://learn.microsoft.com/en-us/windows/win32/secauthz/impersonation-levels)、[CreateProcessWithTokenW 契约](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithtokenw)。本机失败类型和错误码来自上面的真实原生记录，不是仅根据文档推断。

这不是安装目录损坏、输入引擎语言问题或任务栏自动化问题。原预检在停写前失败，未进入备份/安装事务。

## 修复边界

- 从资源管理器启动的**普通 Windows PowerShell**发起维护，UAC 只提权工作进程。原普通进程等待工作进程结束，以 `PID:创建时间 FILETIME` 显式传递并保持启动来源。
- 共享 C# 启动器不再查询关联令牌来启动进程。它只打开该明确发起进程的主令牌，核对原生 PowerShell 映像、包身份、存活及创建时间、SID、会话、中完整性、非提权和 Primary 类型。
- 当前维护方与被引用发起方均须通过原生上下文检查；`NO_PACKAGE` 子进程不能绕过打包祖先检查。没有借用 Explorer 令牌、按进程名搜索可借用令牌、启用额外权限、改凭证、管理员常驻或放宽完整性要求。
- 只请求主令牌启动所需的明确句柄权限组合 `0x018b`；原先仅三项权限的断言被上面的错误 5 修正记录取代。新进程先挂起，实际令牌校验成功后才恢复执行；失败只终止自己创建的进程并释放句柄。
- 共享正常 x64 安装器显式跨 UAC 传递发起进程，普通进程保持等待。备份/恢复启动入口接入同一发起方祖先检查。旧多架构契约和冻结载荷不重建、不运行。

源码修改涉及 `local-runtime-launcher.cs`、`development-scope.ps1`、`manage-e6c-trial-install.ps1`、`local-product-runtime.ps1`；封存候选 `6bb1c10d…` 未被原地修改。旧安装和生产注册保持原样。

## 历史探针步骤（07:32 已通过，无需重复）

推荐直接打开**资源管理器**，进入 `C:\dev\Yime`，普通双击 `Test-YimeCore-Standard-Launch.cmd`。不要右键选“以管理员身份运行”，也不要从当前管理员终端或 Codex 中运行它。入口只调用下述只读探针，保留结果窗口，不增加提权绕过。无需关闭 Word；此探针不使用输入宿主。

手动终端方式仍可用，但必须是新开的非管理员 Windows PowerShell，而不是管理员窗口中再开一个子 PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\dev\Yime\tools\yimecore\test-native-standard-user-launch.ps1"
```

允许随后出现的同账户 UAC 请求，并保持原窗口打开直到结束。脚本先固定自身/帮助程序源码哈希，UAC 工作进程复核相同源码快照，核对发起进程的实际主令牌，然后通过修复后的启动器启动冻结候选中哈希固定的 x64 **只读审计程序**。证据包含真实审计进程的普通权限主令牌、完整包审计结果和异常链。它不会停旧输入法、改生产/试验版注册、创建备份、安装或重启。

重复的 `Start this probe from ordinary Windows PowerShell, NOT administrator` 是入口发现实际管理员令牌后的主动拒绝，尚未运行探针；不是 1346 再次发生。2026-09-03 只读现场核对：Explorer PID 14384 和旧 runtime PID 14016 均为普通权限/完整性 8192，PowerShell PID 31056 为提权/完整性 12288；系统视图 `EnableLUA=1`，所检查的 PowerShell 开始菜单快捷方式没有 Run-as-admin 标记。不能仅凭这些检查推断用户点了哪个按钮；没有改 UAC、快捷方式或兼容设置。

结果归档：`%USERPROFILE%\YimeCore Recovery Archives\native-launch-fix-<时间>-<随机值>`。提供终端 PASS/BLOCKED 行及证据目录即可。不要重试旧 `-LaunchProbeOnly`（它使用仍未修改的旧候选，会重复原错误）或完整 `-Execute`。

原生探针 PASS 后再封装修复候选、更新安装验收固定哈希和普通发起/UAC 接线，之后才恢复完整安装。不能把“源代码通过回归”或本探针 PASS 说成已经安装、恢复/回退或真实宿主通过。

## 已完成验证

- PS5.1/PS7：41 项主令牌启动契约，包括身份吻合但模拟令牌仍拒绝、PID/时间参数、跨 UAC 来源、祖先拒绝、挂起校验顺序、最小令牌权限、只读探针边界。
- 双击入口新增后 PS5.1/PS7 均为 45 项通过；证据 `.tmp/yimecore-local-product/standard-primary-contract-0cb48ae0a0c24a98b30ca35615744b75`、`standard-primary-contract-de40c81f5bd2434d8d5ce45b00408680`。实际 CMD 调用在 Codex 上下文仍被原生祖先保护拒绝并保留非零退出码，没有请求 UAC；不把这次拒绝算作真正原生启动通过。
- PS5.1/PS7：55 项原有本机维护契约，包括冻结引用保留、注册/回滚夹具、旧包只读 Plan。
- 原生安装编排保护 28 项通过，旧候选完整安装仍暂停。
- 打包应用及原生数据维护上下文保护 8 项通过；本机范围回归 66 项通过，冻结架构不执行。
- 未从 Codex 请求 UAC、提取可启动令牌或启动逃逸进程。当前工具上下文仅执行自身令牌只读检查和隔离夹具；真正原生启动仍需要上述用户启动的探针。

证据根 `.tmp/yimecore-local-product/`：`standard-primary-contract-462b3a57e4804e1db4eea6a7ad61fb1c`（PS5）、`standard-primary-contract-e19f7e5362934e4c92a7c8740271b957`（PS7）、`maintenance-96deeb88014846e6893b9df1022f9437`（PS5）、`maintenance-79a8c725514744f89297b9d826e89fbd`（PS7）、`native-install-contract-e14d06062cd94b669b5237fc1d019f52`。范围证据 `.tmp/yimecore-experiment/e7-readiness/scope-regression-2e133dfb449246c8b6fb919ac0dc1113`。

`local_product_ready=false`，`public_release_ready=false`。签名证书正在申请，等候审批，暂缓相关事项。
