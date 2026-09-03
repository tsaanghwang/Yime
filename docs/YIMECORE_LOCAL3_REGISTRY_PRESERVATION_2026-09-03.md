# local.3 原生安装后的注册保护缺陷与三项恢复

后续状态：三项现场恢复完成后，local.4 又修复了升级备份、冻结 Profile 的 x64 `repoint` 选择及冻结根验收，并已安装通过纠正后的原生验收。见 [local.4 原生升级记录](YIMECORE_LOCAL_PRODUCT_LOCAL4_2026-09-03.md)。本文保留 local.3 事故事实。

状态：新包已经安装，原生安装命令返回成功，但安装后保护项检查正确拦截，不能报整体安装验收 PASS。2026-09-03 08:12，三项定向注册恢复已执行并通过，证据为 `%USERPROFILE%\YimeCore Recovery Archives\local3-registration-repair-20260903-081229-9138eafd`；独立 `StdRegProv` 复核也已通过。恢复没有停止输入法、重装、覆盖用户数据或重启。修复源码已验证并进入 `.4` 描述，尚未重新封装/安装。

原证据：`C:\Users\tsaan\YimeCore Recovery Archives\local-product-install-20260903-075343-65e06cb5`。`summary.json` 为 `install_command_succeeded=true`、`stage=compare-data-and-system-registry`、`passed=false`，保留原件不改写。

## 精确变化

| 原生系统注册表位置/值 | 安装前 | 安装后 |
| --- | --- | --- |
| HKU/原用户 SID/Software/Microsoft/Windows/CurrentVersion/Run，`OneDrive`，REG_SZ | `"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background` | 值被删除 |
| HKLM/SOFTWARE/WOW6432Node/Microsoft/CTF/TIP/试验 CLSID/LanguageProfile/0x00000804/原 profile，`Description`，REG_SZ | Yime 自研栈试验版 | Yime 独立开发版 |
| 同一冻结 profile，`IconFile`，REG_SZ | 旧根 `yimecore-e6c-45b389e530c0-8d48953a\profile-icon.ico` | 新根 `yimecore-e6c-75485fda5d79-6964099f\profile-icon.ico` |

试验 CLSID：`{41EC6C9B-E8D2-4E1E-9E7C-5CA3DAF0F66B}`；profile：`{607895A8-9504-4A2E-9BB1-2C159E3A1757}`。

生产 Rime/PIME COM/TIP、冻结 x86 COM 路径、用户 TIP、默认输入法及其余保护项未变。Yime 自己的 Run 值正确指向新包；丢失的是无关的 OneDrive 自启动，不是 Yime 自启动。这不是排序/序列化误报，不应删除或放松保护断言。

## 原因和源码修复

1. 原安装器对共享 Run 父键调用 `New-Item -Force`，导致整个键被重建。单值回滚帮助函数也有同一问题。微软明确说明该参数对已有注册表键会清空原属性和值，与文件夹行为不同：[New-Item 文档](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-5.1#example-9-use-the--force-parameter-to-overwrite-existing-files)。本轮在唯一、可删除的测试注册表键复现了此行为，没有碰真实 Run/TIP。
2. x64 注册工具调用 TSF `UnregisterProfile`/`RegisterProfile`；本次真实前后证据说明 WOW64 的同一语言 profile 描述和图标也被更新。COM 保持 x64 写入并不等于所有 profile 元数据只影响 x64。没有执行/构建 x86 程序，也不能把该变化当成 x86 适配通过。微软的 [RegisterProfile 文档](https://learn.microsoft.com/en-us/windows/win32/api/msctf/nf-msctf-itfinputprocessorprofilemgr-registerprofile)定义描述和图标参数；本机跨视图副作用依据现场证据，不声称该文档承诺了架构隔离。

源码 `manage-e6c-trial-install.ps1` 已改：Run 父键只在缺失时创建，已有值不受影响；单值回滚也不重建父键。正常 native-x64 的注册/反注册入口在操作前快照、finally 恢复并读回核对**固定试验 CLSID 的冻结 WOW64 TIP 子树**，保留缺失状态、所有值类型/子键；不执行冻结程序。旧多架构模式不调用这项恢复。注册失败仍失败，冻结恢复失败也不能报成功。

外部首次安装脚本已暂停 `-Execute`，错误报告现在列出确切变化的保护分组。源修复不能冒称已安装包修复；当前包内 Install/Upgrade/Uninstall 维护器仍有缺陷，**暂不要使用这些操作，也不要重复旧 Trial 升级入口**。

## 本次人工步骤：仅恢复原值

资源管理器普通双击 `C:\dev\Yime\Repair-YimeCore-Local-Registration.cmd`，不要右键以管理员身份运行。脚本自行请求一次同账户 UAC。不需要关闭输入法，不停 runtime/Broker，不重新安装，不写学习数据、不恢复整个用户数据目录，不自动重启。

入口先核对已安装 `6964099f…` manifest、原生上下文、SID、原归档哈希和完整系统保护快照。只允许：补回缺失的 OneDrive 字符串，将已知新值的 Description/IconFile 改回原值。若已是原值则不写；若是第三种新值、类型变化或其它保护项有变化，拒绝覆盖。每次写入前再次核对当前原始值；不创建/删除注册键，不整树恢复。失败保留已完成的精确值写入记录，不用批量回滚覆盖并发变化。

原前后文件固定哈希：

- `system-before.json`：`4ff1f84f29b442f006ae6a76c849d4ea1636b18ca20de56f695624ba3c03c67e`。
- `system-after.json`：`0464c9f62b8293baf20f1cbd67a2c163c7409debd78ae9473b0f5ecb061271d0`。

结果写入新的 `%USERPROFILE%\YimeCore Recovery Archives\local3-registration-repair-<时间>-<随机值>`。原失败归档保持不变。提供 PASS/错误行及目录，暂不重启。恢复通过后，仍须生成并验收含源码修复的新维护包，再做实际恢复/回退和宿主闭环。

## 已核验状态和回归

- 新安装包完整性通过，manifest `6964099f48e0b6f534b763728d4a1806e4d4edfb1e7d7053b42c6d78d9fee74a`。
- 原生记录中的三模式、12 项整句验证通过。新 runtime PID 26844、Broker PID 34928 的实际映像和当前启动身份复查通过，均为同 SID、会话 1、非提权、中完整性 8192、Primary。
- 原生停写备份的状态及旧完整安装包逐文件哈希通过，旧冻结引用根逐字节未变。当前学习、词库、设置记录与安装前备份哈希一致。
- 诊断及恢复计划：`C:\dev\Yime\.tmp\yimecore-local-product\20260903-local3-postinstall-review\summary.json`、`repair-plan.json`。这些是只读核验，不是实际恢复证据。
- PS5.1/PS7：17 项注册保护回归（含真实临时注册键复现，以及冻结注册成功/失败/不存在/恢复失败夹具）；16 项三值恢复回归（用本次真实前后证据，包含第三种新值拒绝、幂等及其它保护项变化拒绝）。50 项原维护契约、45 项外部安装编排、56 项启动契约、用户 TIP 嵌套类型回滚测试通过。
- ARM64/x86/其它机型仍冻结；没有执行其注册或宿主测试。签名证书正在申请，等候审批，暂缓相关事项。

当前三项现场恢复已通过，但原 `.3` 安装验收记录保持 `passed=false`；`repair_executed=true`、`protected_registry_restored=true`、`installed_maintenance_source_fixed=false`、`local_product_ready=false`。不要将已运行的新核心误报成未安装，也不要将正常核心运行或定向恢复误报成维护安全闭环完成。
