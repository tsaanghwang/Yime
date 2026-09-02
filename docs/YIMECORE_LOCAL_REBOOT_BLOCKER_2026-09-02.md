# 本机正常重启复核：Trial 自启动未通过

**后续纠正（21:12 起）：本文“Run 正确”仅来自受隔离进程视图。系统实际仍指向已不存在的旧 EXE；自启动项和卸载入口现已修复，备份也已导出到系统可见目录。以下保留初次观测，不作为最新结论；见[系统视角修复记录](YIMECORE_SYSTEM_VIEW_REPAIR_2026-09-02.md)。**

复核范围：MYCOMPUTER，原生 x64，原 Windows SID。用户正常重启后开展只读核验；未执行升级、修复、自启动服务、注册操作或修改默认输入法。仅新增取证文件和记录。

## 结论

Windows 本次启动时间为北京时间 **2026-09-02 20:49:18**。最终试验包和注册正确，但登录后未观察到 Trial runtime 或 Broker 进程，本次重启验收失败。不能把重启前已经通过的宿主、备份恢复和实际回退记录改为失败，也不能据此将总体闭环勾为完成。

确切阻塞：**HKCU Run 正确指向最终包，但重启后 Trial runtime/Broker 均未运行，持久化状态和日志仍来自重启前。** 这不是 Computer Use 任务栏限制；本轮没有开展新的 Word 输入测试。

## 已通过的只读检查

- 当前 SID 与重启前一致。
- 包仍为 `C:/Program Files/YimeCore Experimental Trial/yimecore-e6c-45b389e530c0-8d48953a`；manifest SHA-256 仍为 `8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64`。
- 安装载荷静态完整性审计通过，未执行冻结架构的二进制或测试。
- `runtime-config.json` 哈希未变。
- HKCU Run 的值和 REG_SZ 类型与重启前一致；32/64 位查询一致，`repair-e6c-trial-autostart.ps1 -ValidateOnly` 通过。**本次没有复现 Run 回旧路径。** 此结果不解释上一次陈旧值的成因。
- 生产与 Trial 的机器 COM/TIP、Trial 用户 TIP 子树、语言配置和 keyboard preload 均与重启前一致。
- 默认输入法仍是微软拼音；生产 PIMELauncher 主进程/worker 正常存在。

## 未通过项及诊断边界

- 实际进程查询中 `YimeCoreTrialRuntime.exe` 和 `YimeBroker.exe` 均为 0 个。
- `runtime-status.json` 的更新时间为 `2026-09-02T12:39:03.3515692Z`（北京时间 20:39:03），早于本次启动。文件虽然写着 `running`，但不是当前活进程证据。
- `runtime.log` 最后写入也为重启前 20:39:03，没有本次启动记录。
- 本次启动后的 CodeIntegrity、AppLocker、Defender、Shell-Core 和 Application 日志均可读取，消息及 XML 搜索未发现匹配 YimeCore/YimeBroker/YimeTextService 的事件。这不能排除未记日志的启动失败，更不能据此宣称从未启动或确定为签名拦截。
- 当前 HKCU/HKLM `StartupApproved` 的 Run/Run32/StartupFolder 中未发现匹配 Yime/PIME 的项。缺失不被解释为明确禁用。

本轮没有为复核而手动启动 Trial，以免把“能手动启动”误记为“重启后自动运行”。根因尚未确定；后续应在保留本次证据的前提下定位登录启动链路及日志初始化之前的失败路径，而不是直接重写已经正确的 Run 项或重跑整个升级。

## 证据

以 `C:/dev/Yime/.tmp/yimecore-experiment/local-closure-20260902/post-reboot-20260902-204918/` 为根：

- `observed-state.json`：原始注册、runtime config、持久化状态及包身份。
- `autostart-observed.json`：只读校验真实 Run 值，`registry_mutation_requested=false`。
- `package-audit.json`：安装包静态审计。
- `reboot-summary.json`：15 项检查、3 项失败；含启动时间、实际进程、事件结果、日志尾部及关联证据哈希，`passed=false`。

复核工具为 `tools/yimecore/capture-local-reboot-verification.ps1`，要求同时检查状态时间、当前 PID、进程路径及本次启动时间，不以持久化 `running` 单独判通过。

重启前证据仍保存在[本机维护与验收记录](YIMECORE_LOCAL_CLOSURE_2026-09-02.md)。原 `closure-summary.json` 是重启前历史结论，`all_local_acceptance_completed=false` 保持不变。

签名证书正在申请，等候审批，暂缓相关事项。当前没有证据将本次自启动失败归因于签名。
