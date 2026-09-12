# 给“计算机”AI：本次失败事务的限定恢复

影响产品：Rime/PIME 候选回滚与 YimeCore 用户 TIP 恢复。用户已要求制作恢复工具。本交接取代此前“等待制作”；仅适用于事务 `9fe7f28d-0889-4828-85b5-1f481431b43a`，不执行旧安装器，不安装新产品。

## 交付和验证边界

恢复入口、适配器、TIP 修复和原载荷复制器均在 `tools/dual-product`；策略在 `test-delivery/defaultstring-recovery-20260912`，随当前开发分支交付，不需等另一个包。策略 SHA-256：

```text
8bfc966d137d1954430ac6699e9e260f8c7c5ea841f8f4a985c0de2b08efc274
```

策略固定 93 个代码/模式文件，代码摘要仅统一 CRLF/LF，保留 BOM；旧授权、票据、安装前快照、原包仍按原始字节摘要验证。执行期间保留代码读取租约。新恢复代码不会替换封存包中的文件。

开发端已通过 PS5 静态检查、25 项现有维护事务测试、TIP 范围与冲突拒绝测试、适配器模块调用测试、复制器拒绝测试，并从原构建输出实际复制校验 189 个清单成员。没有在开发机执行真实恢复、UAC 或产品注册写入；这些不是已通过的物理验收。

## 执行顺序

先拉取包含本页的开发分支，等待该提交 CI 成功。由 Golde 从资源管理器打开**非管理员原生 Windows PowerShell 5**，进入测试仓库。AI 若处于打包应用上下文，应提供下列命令给用户在该原生窗口执行，不绕过祖先进程检查。不要关闭防火墙、修改默认输入或重启。

第一步仅准备：验证旧票据，建立本次新的限时恢复授权，把原安装目录内清单载荷复制到独立目录，不修改原载荷。

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-defaultstring-recovery.ps1 --edition ps5 --params-file test-delivery/defaultstring-recovery-20260912/prepare-parameters.json
```

保存打印的 `Recovery parameters:` 目录，以下 `<恢复目录>` 必须替换成该绝对路径。**不要执行生成的 execute-parameters.json，不启动旧 EXE。** 专用入口读取该文件只是为了验证授权绑定。

第二步只验证，不调用 UAC、不写产品：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<恢复目录>\recovery-validate.json"
```

必须退出 0 并打印 `VALIDATED`。失败立即停止并提交原错误，不创建另一份授权重试，不修改摘要或放宽保护。若验证成功，可以在同一原生窗口继续第三步，无需先回传等待批准：

```text
python tools/powershell/run_checked.py --script tools/dual-product/recover-defaultstring-transaction.ps1 --edition ps5 --params-file "<恢复目录>\recovery-apply.json"
```

第三步重复所有验证，使用同 SID UAC 完成候选 Remove 路径，再用系统提供程序恢复原 YimeCore 用户 TIP 的固定子树和 DWORD Enable=1。只处理本次事务的已验证载荷/注册；peer 的其他快照字段和独立 Control Panel 引用必须保持一致。工具拒绝覆盖冲突 TIP，也不以全量语言列表重写修复。

任何一步失败都停止，保留生成目录、诊断、原包和原 journal，不自动再跑 Apply。若回滚完成但 TIP 修复失败，Rime journal 可以已为 rolled-back，而整体恢复仍失败；不得将其报告为全部成功。代码不会通过删除刚创建的 TIP 来掩盖部分写入，需要按新证据处理。

## 回传与下一步

成功必须同时有退出 0、`RECOVERED` 和新 `peer-repair-*/result.json`。该结果要求原 peer 快照完整一致、候选注册缺失、默认输入未变；仍不代表宿主输入或重启验收通过。

回传各命令 UTC、退出码、控制台、原事务终态、当前载荷/注册状态和 peer-repair 前后快照及 result；外部原件保持不动，以 SHA-256/大小索引，仓库只提交检查后的脱敏副本。不要上传授权和私有路径/SID。失败则附 diagnostics 中新增的 worker-original-Remove/defaultstring-recovery 错误和逐步 peer 观察。

整体恢复成功后，可请用户物理选择当前 YimeCore，在空白记事本确认输入；不要更改默认输入。测试后回传并暂停，重启登录与下一候选安装另行安排。本工具解决当前现场，Register 导致 TIP 消失的具体底层触发仍待隔离定位，旧 defaultstring 包继续停用。
