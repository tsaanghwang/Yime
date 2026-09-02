# 系统视角纠正：自启动修复与恢复介质导出

日期：2026-09-02，MYCOMPUTER 原生 x64。其它架构/机型继续冻结。

## 当前结论

已修复系统真正读取的 Trial 自启动项和卸载入口；最终包未重建、未重新安装，生产 Rime/PIME 和默认输入法未改。随后于 21:29 正常重启，18 项检查通过，已确认真正的登录自启动，[自启动阻塞解除](YIMECORE_REBOOT_AUTOSTART_ACCEPTANCE_2026-09-02.md)。**旧恢复/回退的隔离视图证据仍需在独立终端补验，不能宣布完整闭环完成。**下文保留修复过程中的手动启动记录。

## 原因与此前结论纠正

20:49 重启后，进程内 HKCU/HKU、reg.exe 的两种视图都显示新包 `8d48953a`，因此上一份报告称 Run 正确。随后通过进程外 `StdRegProv`（显式指定 `HKEY_USERS/<当前 SID>`）及 `Win32_StartupCommand`，实际看到的却是旧包 `944e300e`。系统文件查询确认这个旧路径的 runtime EXE 已不存在。机器 COM 已指向新包，但真正的用户 Run 和卸载项未同步。

这是本次不能登录启动的直接配置原因；不是新的 Word/Shift 问题，也没有签名拦截证据。此前“Run 没回旧值”的表述只适用于进程视图，不适用于系统视图；不能据此推断存在重启时重写 Run 的进程。

调用链来自 WindowsApps 下的打包应用。其清单同时声明旧版全局 virtualization disabled 和 Windows 11 的特定排除列表，后者没有包含 Yime 用户项。现场的私有/系统视图差异与微软记录的 MSIX 隔离规则吻合：Windows 11 使用新的特定排除声明，读取时可合并私有与真实 HKCU，进程内一致不代表 Explorer 可见。[微软：Flexible virtualization](https://learn.microsoft.com/en-us/windows/msix/desktop/flexible-virtualization)

注意：现场命令子进程的 `GetCurrentPackageFullName` 返回 `APPMODEL_ERROR_NO_PACKAGE`，仍出现上述视图差异。因此不能仅检查子进程的 package identity；维护入口保守检查打包应用祖先进程。未修改调用应用的清单、权限或 Windows 防护设置。

## 已落地的修复

- 自启动修复/校验通过系统 `StdRegProv` 访问当前 SID 的 Run。保留进程视图作对照，provider 错误直接失败，不降级为进程内“通过”。真实系统值从 `944e300e` 改为 `8d48953a`，再次独立校验通过。
- 仅修复当前用户 Trial 卸载信息的 4 个差异值：InstallLocation、UninstallString、QuietUninstallString、EstimatedSize；原值和原始类型已保存，修复函数具备失败回滚。COM、TIP、生产项、默认输入法未写入。
- E7 现在要求独立系统注册表证据；旧版仅进程视图的证据不能通过。
- 源码中的安装/卸载入口拒绝打包应用来源，且在提权/安装写入之前拒绝。备份、恢复、回退演练同样要求从 Explorer 启动的独立 Windows PowerShell。此保护位于工作区源码，尚未重新打包进入已安装的旧维护脚本；这次不为此重复安装。
- 重启验收增加本次 PID 对应的 Shell-Core 9708 登录启动事件校验，并支持最近维护时间边界，避免手动恢复被写成自启动通过。

实际服务恢复是 `-no-toolbar` 手动启动，不属于登录启动证据。停写校验后再次恢复，最后取证的 runtime/Broker PID 为 2464/3524；运行路径仍是 `C:/Program Files/YimeCore Experimental Trial/yimecore-e6c-45b389e530c0-8d48953a`。

## 数据和恢复介质

还发现 AppData 内新建的三份旧恢复档案只在隔离视图中可见，系统文件查询看不到。因此此前把它们称作“独立恢复介质”不够准确。原档案没有丢失，也没有删除。

已将其完整复制到 AppData 和 Git 工作区之外：

- `C:/Users/tsaan/YimeCore Recovery Archives/local-closure-20260902`：168 个文件。
- `C:/Users/tsaan/YimeCore Recovery Archives/local-closure-second-20260902`：150 个文件。
- `C:/Users/tsaan/YimeCore Recovery Archives/local-closure-final-20260902`：150 个文件。

468 个文件逐一比较路径、长度及 SHA-256，复制前后源档案不变；各备份原 manifest 中的 149 项状态/包文件也重新通过哈希校验。三份目标的 manifest、学习 journal、旧包 manifest/runtime 均经系统文件查询确认可见。目录内原 manifest 的历史来源路径保留原样，迁移对应关系另见导出证据，不伪造旧快照元数据。

短暂停止 Trial 写入后，当前两份学习 journal 及用户词库、屏蔽词表、专业词库配置共 5 个文件，与最终备份的哈希相同。随后恢复服务。正常备份入口已改用 `%USERPROFILE%/YimeCore Recovery Archives`；设置窗口的直接复制仍不属于已认证的停写恢复入口。

需要降级的旧结论：隔离上下文中的“实际恢复”及回退演练的用户 TIP/Run/卸载字段，不能证明真实系统视图完成同样的变更。原始记录保留；Word/记事本实际输入、机器 COM 切换、离线副本恢复等各自成立的证据不被删除。后续需在独立终端重新做停写恢复与失败升级回退，并用系统视角取证。

## 回归与证据

- 自启动契约 12 项：包括“私有视图正确但系统陈旧”、真实修复、不落地写入、provider 拒绝；先看到旧代码错误通过，再修复。PowerShell 7 / Windows PowerShell 5.1 均通过。
- 卸载元数据事务 5 项：成功、写失败恢复、读回不一致恢复、无需变更、缺值；PS7/5.1 通过。
- 安装器上下文 5 项、数据维护上下文 3 项；拒绝真实当前隔离上下文时未安装、未建备份目录。
- E7 自启动证据 10 项通过；这只是定向门禁回归，不等于 E7 全部通过。
- 安装包静态审计及当前服务/COM/系统自启动一致性通过，未执行冻结架构的测试。

证据根为 `C:/dev/Yime/.tmp/yimecore-experiment/local-closure-20260902/post-reboot-20260902-204918/`：

- `autostart-system-before.json`：改进后的只读校验明确失败，含旧系统值与新进程值。
- `autostart-system-repair.json`、`autostart-system-final.json`：实际修复及后续只读校验。
- `uninstall-view-comparison.json`、`system-uninstall-before.json`、`system-uninstall-repair.json`、`system-uninstall-final.json`：卸载入口修复前后证据。
- `manual-start.json`、`manual-restart-after-data-check.json`：明确标记手动服务恢复，不作为登录证据。
- `final-system-state.json`：服务、生产/试验 COM、系统可见 Run/卸载/Enable。
- `data-after-system-repair.json`：停写后 5 个文件哈希一致。
- `archive-system-visibility.json`、`archives-export.json`：旧隔离档案不可见及新导出档案完整性/系统可见性。

最新安装态审计：`.tmp/yimecore-experiment/e6d-independence/system-registry-repair-complete-20260902/summary.json`。
E7 定向回归：`.tmp/yimecore-experiment/e7-readiness/autostart-regression-0a3543cc819b4ca0adff5da43c192482/summary.json`。

## 下一步

正常重启后的系统 Run、真实服务进程、包身份及 Shell-Core 启动事件已核验通过。下一步安排独立 Windows PowerShell 下的恢复/回退补验；不在当前隔离上下文重复安装。

签名证书正在申请，等候审批，暂缓相关事项。
