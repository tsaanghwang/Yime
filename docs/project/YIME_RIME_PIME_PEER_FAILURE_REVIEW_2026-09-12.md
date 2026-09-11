# defaultstring 安装失败审阅与只读补证交接

影响产品：Rime/PIME 安装与回滚、受保护的 YimeCore。2026-09-12，开发端已接收测试分支 `5726308d`、`7e3e7591`，核对仓库证据索引的 9 个副本大小与 SHA-256；未在开发端重新读取测试机外部原始档案。

## 审阅结论

唯一目标事务为 `9fe7f28d-0889-4828-85b5-1f481431b43a`。其 install 无 commit/terminal，removal 只有 remove-requested、无 terminal。192 个载荷仍在；37 项注册观察中 30 项存在，缺失的是 4 项候选用户 TIP、marker-root、marker-uninstall 和 Run。候选进程为空，新增图标不能输入不能算安装成功。

YimeCore 用户 TIP 在系统注册表提供程序的前后观察中由存在变为缺失，是实际保护失败。两个注册表视图不代表两次独立删除。现有材料尚未确定写入者，也未证明 YimeCore 当前手工输入不可用。不能归因于防火墙，不能用 CI 成功覆盖本次失败。

源码对照发现：

- elevated-Register 依次执行 AssertVacant、RegisterNative、RegisterWow64、EnableTip；目前只在整个 worker 前后检查 peer。最终异常来自 `finally` 的 Complete-MaintenancePeerProtection，它可能遮住更早的异常。因此不能从最后一条错误推定 EnableTip 已成功，也不能确定首次变更发生在哪个步骤。
- 回滚异常栈落在 `Test-YimePimeTargetUserControlPanelReference` 对**值名称**的检查（ownership.ps1 第 515 行），不是读取值内容后的检查。名称包含 Rime/PIME CLSID，但未被当前精确允许列表接受；日志没有保存该名称，尚不能认定它是真正混合引用，也不能直接放宽匹配。
- 回滚在 DisableTip 阶段失败，尚未进入本轮 UnregisterWow64、UnregisterNative、RemoveMarkers；与机器注册残留一致。

## 给“计算机”AI的当前任务

拉取本交接后，仅针对本事务做只读补证。**不用等新 CI；本轮没有安装或恢复操作。** 不执行 defaultstring 安装、不生成新授权、不 Resume/Remove，不运行固定旧事务的 finalizer，不重启、不改变默认输入，不写 TIP 或手工补 journal 终态。保留已关闭的旧事务及全部原始档案。

在 Golde 同一用户、资源管理器启动的原生 PS5 中工作；所有 PowerShell 通过 `python tools/powershell/run_checked.py --script <脚本> --edition ps5 --params-file <参数 JSON>`。先利用现有原始材料，不重新运行安装来产生阶段日志。新补证写入 `%USERPROFILE%\Yime Rime-PIME Test Archives` 下独立目录，不覆盖旧文件。

1. 从现有外部索引定位本事务全部 peer before/after/result 文件，按其记录的时间、PID、阶段（缺失则明确缺失）整理对应关系。分别给出每一对 YimeCore 用户 TIP 的存在性、子键和值种类，确认 elevated-Register 开始前是否仍存在、elevated-Remove 开始前是否已缺失。不要仅依据文件名字中的随机 ID 排序。
2. 只读采集 `HKEY_USERS/<Golde SID>/Control Panel/International/User Profile` 及直接子键。通过系统 `StdRegProv` 枚举，保留返回码、键相对路径、完整值名称、种类；优先提取包含 Rime/PIME CLSID `{35F67E9D-A54D-4177-9697-8B0AB71A9E04}` 的名称，使用 JSON 保留空格和字符，不做 trim、拆分或格式归一化。必要字符串值仅限包含该 CLSID 的项。另标明该项是否包含 YimeCore CLSID。不要调用现有会提前抛错的引用检查作为唯一采集器，也不要读取全部个人设置内容。
3. 只读确认当前 YimeCore 机器 COM/Profile 与目标用户 TIP 存在性，分别标记 Registry32/Registry64 和提供程序错误；与已封存的安装前 peer 快照比较。不得以进程内 HKCU 结果替代系统提供程序，不因返回错误假定缺失。
4. 从已存执行日志、worker 输出及 PowerShell 错误记录中提取 Register 的首个异常和步骤信息（若未记录，明确“无法追溯”，不推测）。保留 UTC、PID、异常链；不重新调用 regsvr32、InstallLayoutOrTip 或注册探针来补日志。
5. 若用户方便，在保全只读证据后请用户物理选择当前 YimeCore，在空白记事本确认能否输入；不要自动切换默认输入或激活历史自研栈。未测则写未测，不阻塞其他材料回传。

提交一份精简报告与 JSON，原始敏感路径/SID 和完整证据留在 Git 外；仓库副本替换用户路径/SID，保留诊断所需的产品 GUID 与引用原文。为仓库副本和外部原件分别列 SHA-256、大小、采集时间及路径，不能混用脱敏前后哈希。提交并推送测试分支后暂停。

## 开发端后续与恢复门槛

先据准确引用名称编写回归用例，再判断应修正解析还是确属混合状态；保留对其他产品引用的拒绝保护。注册路径需逐步记录动作与前后保护观察，并同时保留原始失败和 finally 保护失败，不能只留下最后一个异常。此类改动必须进入新候选包，不能修改已封存的 defaultstring 包。

恢复必须绑定本事务及已验证的安装前快照，分别处理 YimeCore 用户 TIP 恢复和 Rime/PIME 未完成回滚，并核对默认输入与各产品运行状态。**本交接未提供可执行恢复方案，也不授权测试 AI 自行恢复。** 等上述补证明确当前状态后，开发端给出限定范围、可回退且可验证的恢复步骤；在此之前不交付下一轮安装。

原始结论见 [测试失败报告](YIME_RIME_PIME_DEFAULTSTRING_PEER_FAILURE_2026-09-12.md)；证据见 [副本索引](../testing/platform/2026-09-12-defaultstring-peer-failure/index.json)。
