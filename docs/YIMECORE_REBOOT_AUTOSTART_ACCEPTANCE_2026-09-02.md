# 本机重启自启动验收通过

范围：MYCOMPUTER，原生 x64。本轮只读取系统状态并保存证据，没有安装、修复注册表、启动/停止 Trial 服务或更改默认输入法。其它架构/机型继续冻结。

## 结论

2026-09-02 **21:29:36（北京时间）**正常重启后，Trial runtime 于 **21:30:06** 自动启动，PID **27424**；其子 Broker PID **27460** 同时出现。Shell-Core 9707/9708 登录启动事件对应同一 runtime PID、当前用户 SID 和 `YimeCoreTrialRuntime.exe -no-toolbar` 命令，父进程为 Explorer PID 14432。

18 项重启检查全部通过。上次系统 Run 指向已不存在旧包的问题，本次未复现，**自启动阻塞解除**。这不是手动启动后的“通过”，也不是依赖旧 `runtime-status.json` 推断。

## 同步核验

- 系统 `StdRegProv/HKEY_USERS/<当前 SID>` 读取的 Run 指向最终包 `yimecore-e6c-45b389e530c0-8d48953a`，REG_SZ 类型正确；进程视图与系统视图一致。
- manifest SHA-256 仍为 `8d48953ac0b5017b725272ee6300d0b988e99a0d25b9e035216f6c90b774fb64`。安装包静态审计通过，runtime/Broker 的当前路径与包一致。
- 当前状态文件来自本次启动，PID 与真实进程匹配；启动时间晚于上次修复及最后一次手动恢复。
- 机器生产/试验 COM/TIP 与原快照一致；另外通过系统 provider 读取确认生产 x64/x86 COM 路径、试验 x64 COM、用户 Enable=1 和卸载入口。用户 TIP、语言配置及 keyboard preload 的进程视图比较也无变化，不将其扩大成先前实际回退的系统级证明。
- 系统可见的 Trial 卸载信息仍正确，独立只读校验通过。
- 默认输入法仍为微软拼音。打开宿主仍需实际选择 Trial，不为验收更改默认输入法。
- `C:/Users/tsaan/YimeCore Recovery Archives` 下三份恢复档案的 manifest 在重启后仍由系统文件查询确认可见。此前完整文件哈希和导出证据继续保留。
- 本次启动后读取的 CodeIntegrity、AppLocker、Defender、Application 日志没有匹配 Trial 的事件；Shell-Core 中有上述两条成功启动事件。此结论限于本次读取范围。

## 取证工具修正

最初采集时，`Get-FileHash` 的默认共享方式与正在运行的原生 runtime 日志写入句柄冲突，导致取证脚本中止；服务未停止，也不是输入法错误。现按允许并发写入的只读方式复制打开时的日志长度，再哈希不可变的证据副本。

新增回归验证：写入句柄始终保持打开时可采集；后续日志追加不改变证据副本；拒绝覆盖已有副本。PowerShell 7 与 Windows PowerShell 5.1 均通过。没有为取证暂停自动启动的服务。

## 证据位置

以 `C:/dev/Yime/.tmp/yimecore-experiment/local-closure-20260902/post-reboot-20260902-212936/` 为根：

- `reboot-summary.json`：18 项通过、实际进程、启动事件 XML、日志副本哈希及证据关联；`runtime_started_by_verifier=false`、`registry_mutated_by_verifier=false`、`installer_executed=false`。
- `observed-state.json`：注册、系统 provider 读取结果、runtime config/status、包身份。
- `autostart-observed.json`：系统视角只读 Run 校验。
- `package-audit.json`：已安装包静态审计。
- `runtime-log-snapshot.txt`：不中断服务取得的日志前缀副本。
- `system-uninstall-observed.json`：未请求修复的卸载信息验证。
- `archive-visibility-after-reboot.json`：AppData 外恢复档案的系统可见性及 manifest 哈希。

## 剩余事项

无需为自启动再次升级或重启。本报告之后，22:21 已在独立 Windows PowerShell 中完成停写备份、实际恢复和失败升级回退，详见[原生闭环验收](YIMECORE_NATIVE_LOCAL_CLOSURE_ACCEPTANCE_2026-09-02.md)。本机恢复/回退缺口已补齐；首次独立发布审批仍单独保留，不能由本报告代替。

签名证书正在申请，等候审批，暂缓相关事项。
