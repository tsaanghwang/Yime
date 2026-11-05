# 独立 18u installed-host 修复验收交接

2026-11-03；本轮已完成，不要求重新安装或重复成功用例。

## 结论与接续状态

MYCOMPUTER Windows x64 已安装的独立 18u test.2 DLL/Broker，配合修复后的开发检查宿主，重启后真实注册激活、提交与读回用例通过。用户于 08:13:57 从前台终端执行一次性脚本，08:14:11 完成，08:14:12 脚本退出 0。只检查原始记录后形成此结论，没有再次运行。

| 层次 | 证据与结论 |
| --- | --- |
| 安装成功 | 当前仍为 test.2；test.3 曾在文件占用阶段停止，不可标为已安装 |
| 重启及注册可见 | 启动时间 07:26:43 +08:00；只读 status 显示 COM/TIP 注册、1 个 profile、5 个 category |
| TSF 激活 | r2 原始结果 registered=true、activationIdentity=windows-activated-profile、actualDLLLoaded=true |
| 编辑与读回 | outcome=applied、readbackMatches=true、readbackEmpty=false、otherContextEmpty=true；host/Broker 均退出 0 |

`sendInput=false`，`installedPayloadUnchanged=true`。没有重装、修改注册、替换旧标准版、改变默认输入法或迁移用户数据。本轮仅覆盖 commit 用例，不宣称其他故障用例、Word/Edge、物理手指/笔或 test.4 整包通过。

## 身份与修复

- 分支：`codex/18u-installed-input-events-20261103`；修复提交：`6915f8b9fc1d0978c578f06363e65244b5fe7cd5`；[PR #95](https://github.com/tsaanghwang/Yime/pull/95)。
- 安装根：`C:\Program Files\YimeCore 18u Touch`；版本：`0.1.0-18u-test.2`；安装源：`bb7cc136c284a5d5ee3a764749119b0b423da482`。
- CLSID：`{6DFACE1F-562E-4773-A9D6-D5753A314711}`；profile：`{1BD904AC-3194-4419-B70A-5574100F18B3}`；语言：`0804`。
- 安装 descriptor SHA-256：`89928fe4c4496462d9198e4be9be28b72ddb9816594b6eab7986fac766844adf`。
- 开发检查宿主 SHA-256：`8ceeb29cd2de6cdfc8c0f90ff4c6ab088e73184cb93cb3fd22d39c9d1b0d2267`。DLL/Broker 路径与哈希见 [inputs.json](raw/r2/inputs.json)。

旧宿主把两个字符的 canonical code 放进单次 input，违反真实引擎每事件一个字符的约定，导致 engine input E_ABORT。修复宿主逐字符输入、核验逐步 revision，首错停止；原 DLL/Broker 和词典没有修改。原包内旧检查宿主仍在，不应重复旧命令或将新宿主成功写成旧包检查器原样通过。

固定包：[test.2 Release](https://github.com/tsaanghwang/Yime/releases/tag/test-18u-installed-bb7cc13)；[固定交付说明](https://github.com/tsaanghwang/Yime/blob/9a707df43a4c04583d957c437ed486169bf0547c/delivery/18u-installed-bb7cc13/README.zh-CN.md)。

[修复提交专用 CI](https://github.com/tsaanghwang/Yime/actions/runs/41548776549) 已通过；[test.4 构建 artifact](https://github.com/tsaanghwang/Yime/actions/runs/41548776549/artifacts/13189942070) 是新构包输出，尚未安装。本机修复宿主成功不能替代该新包的交付与安装验收。

## 已执行入口与证据

以下命令仅用于记录本次已完成操作，**不要再次执行**：

```powershell
& 'C:\Users\tsaan\AppData\Local\Programs\Python\Python314\python.exe' -X utf8 'C:\dev\Yime-evidence\18u-input-fix-20261103\manual_once.py'
```

这是开发宿主复核入口，不是固定 Release 整包入口。执行时须为本机交互前台，安装与宿主身份/哈希匹配；宿主自身保留前台、注册身份、实际 DLL 和编辑完成门槛，没有绕过。一次性标记与证据目录禁止覆盖。

原始目录：`C:\dev\Yime-evidence\18u-input-fix-20261103`。本次结果在 `native-fixed-host-r2`；本地报告为 `RESULT.zh-CN.md`，完整本地索引为 `r2-verified-evidence-inventory.json`。本目录 [raw/r2/result.json](raw/r2/result.json) 与 [host stdout](raw/r2/host-stdout.jsonl) 是原文件逐字节副本；同时保留输入身份、进程、Broker 输出、stderr 和启动记录。副本哈希见 [SHA256SUMS.txt](SHA256SUMS.txt)，raw 禁止文本换行转换。

成功须 result.status=evidence-consistent，且上表激活、编辑、读回字段及双进程退出 0 全部成立。仅退出码、READY、connected、安装成功或注册存在均不足以单独判定成功。

## 保留的失败与停止规则

原 test.2 的 connected 后 engine input E_ABORT 位于 `C:\Users\tsaan\Yime18u-host-test2-r1`，审计副本在 `C:\dev\Yime-evidence\installed18u-entry-audit-20261103`。

修复宿主 r1 于 07:51 因 `own foreground not granted; no bypass` 停止，未到输入阶段；保留 [r1 原始记录](raw/r1/result.json)。随后获准的前台启动器返回 PID，但未进入验证脚本，原因未确立；[启动观察](raw/foreground-r2-launch-observation.json) 与原启动记录保留。用户后来的前台手动执行才产生 r2 成功证据，不能覆盖或改写前两项异常。

任何后续获准的新测试若出现哈希/身份不符、前台失败、连接或 HRESULT 异常、超时、非零退出、缺失/额外输出、读回不符或载荷变化，保留原始文件并停止；不自动修复、重试、重装或变更默认输入法。

接续工作先读取本交接及 PR 差异。当前成功用例无需重测；如果继续新包交付或实际应用/物理输入验收，须使用明确的新包身份、范围和新证据目录，分别记录，不能把本轮结论扩大。
