# S3c：下一次 MyComputer 注册的交接（仅准备，未执行）

2026-11-02。用户选择“仅准备”：确认干净状态、固定入口与前置条件，**不执行注册**。
本文不是执行授权；执行前须用户另行明确批准，并在批准时核对本文列出的包身份。

## 1. 当前状态（已核实）

| 项 | 证据 |
| --- | --- |
| 18u 独立身份绝对缺席 | 恢复后独立只读扫描 0 命中（[恢复方案](S3C_RECOVERY_DELIVERY_REVIEW.zh-CN.md) §7）；固定包只读预检 `identityAbsent=true` |
| 固定包 | run 41379529964，源 `660ed0aca12049245f4492e2d8da94b959da885b`，`YimeMyComputerActivationProtected-v2-x64.zip`，manifest SHA-256 `db5fb91a55b45bceb1a412672e5e516a2b7eb34ef4d9f05de5333c8d64049a89`；EXE `30178ece…652e7c`，DLL `fe9cb490…ca3ed`（均 NotSigned 开发件） |
| 只读预检（非提升） | `status=checked`，8 项前置条件中 `nativeX64/hostMatches/hkl0804/tsf0804/identityAbsent/dllVerified/directTestAbsent` 为 true，仅 `elevated=false`；`writesStarted=false`，stderr 空 |
| 标准产品不受影响 | 恢复后在同机运行已安装 x64/x86 注册宿主回归 6/6 通过（[记录](INSTALLED_REGISTERED_HOST_X64_X86_2026-11-02.json)） |
| 原 `71a4a252` 轮次 | 保持 failed；其证据目录已移出仓库，`recovery-claim.json` 已消耗 |

## 2. 执行前置条件（全部满足才允许批准）

1. 用户在批准时明确写出上表 manifest SHA-256，且与本机解压包 `manifest.json` 实际哈希一致。
2. 本机 `--preflight`（经包内 `collect_mycomputer_preflight.py`）重新显示 `identityAbsent=true`；若有任何残留，先走恢复流程，不得用注册覆盖。
3. 以提升权限运行；线程语言与 TSF 当前语言均为 `0x0804`（当前只读预检已满足）。
4. 关闭 Word 等占用前台 TIP 的宿主；不改默认输入法，不改用户数据。
5. 新的包外证据目录；编排脚本拒绝已有目录。

## 3. 入口（供批准后使用，本文不执行）

包内编排脚本 `register` 子命令：

```text
python <package>\run_mycomputer_registration.py register
  --package <package>
  --evidence <new evidence directory>
  --manifest-sha256 db5fb91a55b45bceb1a412672e5e516a2b7eb34ef4d9f05de5333c8d64049a89
  --confirm once-mycomputer-register-and-cleanup
  --timeout-seconds 60
```

脚本只调用一次 `--register-once`，随后独立 `--verify`。成功判定要求：原生返回
`activation-unconfirmed`／exit 4、同次实际 DLL 激活 stderr marker、清理通过、独立缺席核验通过。
API 成功或 exit 0 都不是 DLL 激活证明。

## 4. 本次工具相对 `71a4a252` 的差异（影响下一次诊断）

- `--register-once` 失败时，清理前先向 stderr 写固定结构的失败记录（stage／code），
  清理失败另写一条；原先会被清理阶段覆盖的首次失败现在可追溯。
- 清理的 disable／UnregisterCategory／UnregisterProfile 以再读缺席判成功；
  其后的受门控残留清除会在同一次运行内移除 `CTF\TIP\{CLSID}` 空壳，避免再次留下残留。
- 失败且 `writesStarted=true` 时，恢复入口为 `recover` 子命令（本包已用它完成一次恢复）；
  `--inspect-recovery` 先报告 `residueShape`／`recoveryToolCapable`，不具备能力不创建声明。

## 5. 不改变

标准键位 YimeCore 与 Rime/PIME 的注册、数据与默认输入法；17u/23u 冻结；用户数据。
上次失败的根因（`ActivateProfile` 之后、消息泵期间或 `GetActiveProfile` 不匹配）仍待下一次
带诊断的运行定位；本文不预设其结论。
