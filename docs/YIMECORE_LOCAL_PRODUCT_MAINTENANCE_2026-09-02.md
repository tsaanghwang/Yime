# L3 首批共享维护基础验收

日期：2026-09-02。结论：共享维护器的第一批安全实现与自动回归完成，**不是 L3 全部完成，也不是新产品安装 PASS**。当前安装和 L2 运行包均未替换。

## 实现

继续修改唯一事务维护器 `tools/yimecore/manage-e6c-trial-install.ps1`，没有复制一份长期分叉的产品安装器。

1. 新增正常 `NativeX64Only` 模式：只允许 MYCOMPUTER 原生 x64、保留数据和原登录数据命名空间；与故障专用 `NativeX64Rehearsal` 互斥。正常安装不能以 `NoLaunch` 绕过启动验证。提权及未来卸载命令保留本模式和原 SID。
2. 从独立 `StdRegProv` 读取机器及发起用户的冻结 x86 COM 引用。卸载规划、成功升级清理及最终立即/重启删除入口均保留引用所在旧根。提供者失败、路径不明确时拒绝删除，没有进程本地 HKCU 回退。
3. 回退前不再只看 persisted `running`。实际 PID、映像、父进程、SID、创建时间、当前启动时间及状态根必须一致；真正没有进程时才按已停止处理，身份不可见/混乱则在注册修改前拒绝。修复了 PS7 将 JSON 时间自动转成 DateTime 后丢失 UTC 语义的问题。
4. 没有旧安装根的失败路径也恢复原先的用户 TIP、Run、卸载快照及配置缺席状态，避免提前 return 漏掉这些快照。自动测试覆盖“原先没有这些项”的首次安装失败情形；不冒充完整实机重装演练。
5. 新增 `local-runtime-launcher.cs`。提权分支从同一账户的 linked token 建立标准权限子进程，先挂起并核对 SID、会话、完整性与非 AppContainer 状态，再运行；普通权限分支也核验子令牌。保留真实子进程句柄用于失败清理，不以全局进程名找清理对象。不使用 Explorer/ShellExecute、替代凭据或管理员运行回退。
6. 正常 x64 安装前校验启动帮助程序与包清单中的哈希一致；旧 E6-C 构包入口会携带该文件。仅存在新源码不代表已安装维护器更新。只读 Plan 出错也不再向 AppData 写维护错误文件。

启动实现参考微软的 [CreateProcessWithTokenW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithtokenw) 和 [TOKEN_LINKED_TOKEN](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_linked_token) 契约。所需令牌或权限不可用时应明确失败，不能悄悄继续以管理员运行。

## 当前源码身份

- 共享维护器 SHA-256：`68298e8263764abef876739f7ab445a45672514f524655f3ebeceba36c872a8e`。
- 启动帮助程序 SHA-256：`45af27f73ce47fd6a1d67628480385a70261030ccbdeed834422217bcc9eb12e`。
- `test-local-product-maintenance.ps1` 是本批新回归入口。测试替换清理/注册副作用，仅对临时夹具操作；不运行 x86/ARM64 工具，不调用实际安装/卸载。

## 验证

| 验证 | 结果与证据 |
| --- | --- |
| PS7 55 项维护契约 | `.tmp/yimecore-local-product/maintenance-1580899de4334e71b75971a9565bb85b/summary.json` PASS |
| PS5.1 同样 55 项 | `.tmp/yimecore-local-product/maintenance-88e3fc002ee741ec8de78dc13d27c460/summary.json` PASS |
| 原生令牌接口 | 两种 PowerShell 均编译 C#；只读核对当前进程真实 SID，标准/提权/错误 SID/不同会话/低或高完整性/AppContainer 策略测试通过；未执行真实提权到中等完整性启动 |
| 旧事务兼容 | 故障演练 5 项、用户 TIP 嵌套 Enable/值类型回归、安装上下文 5 项及数据上下文 3 项通过 |
| 自启动、卸载、编码 | 自启动 12 项、系统卸载 5 项及 UTF-8 元数据回归、53 处显式读取及 3 组 Unicode 编码夹具通过 |
| 旧安装契约 | `.tmp/yimecore-local-product/legacy-contract-6a429bd519ba4993b2dd5336c8a02bf2/summary.json` PASS：旧完整包配合源码维护器做只读 Plan/静态检查，未注册或卸载 |
| 系统保留 | 独立系统注册/默认设置仍与 L2 的 `20260902-231416-b6e0cf49/protection-after.json` 相同；当前仍为 runtime PID 13132、Broker PID 3536，创建时间 22:21:34 |

只读 Plan 实际发现冻结 x86 COM 仍指向：

`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-45b389e530c0-8d48953a\x86\YimeTextServiceExperiment.dll`

因此当前旧根必须保留，不能在 x64 晋级后删除或安排重启删除。Plan 同时报告 `standard_user_launcher_package_ready=false`：旧安装包缺少新帮助程序。这是尚待重新构包的工程缺口，不是当前输入法运行失败。

## 没有完成、没有宣称完成的事项

- 新本机产品的完整安装/升级/卸载入口尚未生成；L2 `runtime-bundle` 仍不能直接安装，维护器仍拒绝其非安装包契约。
- 新包契约接线、包内独立备份恢复、名称统一仍待下一批，不能因共享源码已有模式就称整个产品可维护。
- `actual_elevated_to_medium_launch_tested=false`、`live_install_or_rollback_executed=false`。实际原生提权安装、普通权限 runtime/Broker/宿主连接，以及新候选的升级失败/自身重装/重启验收留到完整 RC。
- 本批没有新 Word/物理语言栏验收，也没有新实时宿主阻塞结论。不把 Computer Use 任务栏限制重新列为产品故障。
- 生产 Rime/PIME、默认输入法、现有用户学习数据未变。x86/ARM64 等冻结目标只做静态保护，不冒充支持通过。

目前无需开发者升级或重启。

签名证书正在申请，等候审批，暂缓相关事项。
