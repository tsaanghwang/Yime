# “计算机”共存安装测试交接

影响产品：Rime/PIME 候选安装与维护；现行 YimeCore 作为只读保护对象。
用户在 2026-09-11 指定：这边完成共存保护、候选包和说明，提交当前工作分支，由“计算机”执行安装测试，然后优化 CI。

## 2026-09-11 测试机反馈后的重交付

已合入测试分支 `32ff041c6`。原候选在准备阶段触发 PS5 的 StdRegProv COM 参数转换异常，安装器没有启动。旧目录 `test-delivery/rime-pime-coexistence-20260911` 原样保留作历史证据，停止用于本轮测试。

当前唯一交付改为带 `-stdreg` 后缀的新目录；根目录准备入口已经指向它。重新拉取当前开发分支，等包含本次重交付的 CI 成功后，从资源管理器重新准备。不得复用旧 execute-parameters、approval、boundary 或手工更改旧 PIN；已有错误记录继续保留。

开发端重新构建 x86/x64、候选 Launcher 和 Go 载荷，并重制 NSIS 包。PS5/PS7 的真实只读 StdRegProv 回归均通过，PS5 注册归属 22 项、peer 保护 9 项、源码合同 77 项及 CI 调度 12 项均通过。真实注册表回归已加入 CI 双 shell 检查。静态核对不替代完整准备、安装、双产品宿主和重启验收；这些仍待测试机执行。

## 本轮范围

执行 **YimeCore 已安装 → Rime/PIME 首装** 这一行，不卸载或升级 YimeCore 来凑单装环境。
本轮不代表 Rime/PIME 单装、反向安装顺序、升级矩阵或 ARM64 实机验收通过。
`MYCOMPUTER` 仍禁止执行该候选。历史 09-09 clean-only 安装器不适用于本轮。

新候选使用 manifest v2，明确要求现行 peer 保护。安装、注册 worker、回滚、移除及恢复入口核对 peer 的系统可见注册、Run/uninstall、安装文件、设置/学习、恢复目录和进程身份。
注册读取使用 StdRegProv；未知类型、不可读文件、间接路径、错误 COM 路径或保护对象变化都会失败。
仅排除 state 根下的 `logs`、`runtime` 和 `runtime-status.json` 这些运行输出；不排除未知设置。
保护检查不停止、修复或恢复 YimeCore，不改变默认输入法。操作期间请暂不在 YimeCore 中输入或修改设置，以免把合法的学习变化误判为维护污染。

## 获取固定候选

从本工作分支读取交付目录 `test-delivery/rime-pime-coexistence-20260911-stdreg` 和同目录的 `PIN.json`。
安装器、收据、manifest、静态载荷核对记录及来源记录均按原始字节保存。
来源编译提交：`a2d063a01dfe608de25e168fdafbc95cc8c52f93`。
安装器 SHA-256：`6301c6611edb7f1b55623be82a0f5c2c42072475fd80865eef0bf4f66a064e7b`，41,132,913 字节。
新构建包含 168 项来源载荷；NSIS 编译后已核对完整归档成员和原始内容哈希，没有执行安装器。
先用 `tools/dual-product/verify_delivery.py` 核验 `PIN.json` 中的 index SHA-256；验证结果只是交付完整性，不是实机验收。

## 执行顺序

1. 等候包含本交付的提交 CI 成功。读取 `PIN.json` 核对固定交付，不用目录中“最新”的其他 EXE，也不自行重包或修改准入。
2. 从资源管理器启动独立的、未提升的 Windows PowerShell。不要在 Codex、Windows Terminal 等可能带包身份的父进程内安装，也不要提前以管理员启动。
3. 使用下列准备命令。路径按本机仓库绝对路径填写；`--params-file` 指向准备参数 JSON，包含 `DeliveryRoot` 和 `ExpectedIndexSha256`。准备过程绑定本机名称、StdRegProv MachineGuid、发起 SID、现行 YimeCore 安装/状态路径和固定候选，只写仓库外的操作文件。

仓库中已提供 `test-delivery/rime-pime-coexistence-20260911-stdreg/prepare-parameters.json`，在仓库根目录运行时可以直接使用。也可从资源管理器双击根目录 `Prepare-Rime-PIME-Coexistence-Test.cmd`，它只准备，不安装。

```text
python tools/powershell/run_checked.py --script tools/dual-product/prepare-rime-pime-coexistence-test.ps1 --edition ps5 --params-file <准备参数JSON绝对路径>
```

4. 准备成功会显示仓库外 `execute-parameters.json` 的绝对路径。按原样运行：

```text
python tools/powershell/run_checked.py --script tools/dual-product/execute-rime-pime-coexistence-test.ps1 --edition ps5 --params-file <显示的execute-parameters.json绝对路径>
```

5. 接受候选的同 SID UAC 提升。保留全部 `peer-*-before/after/result.json`、原始 approval、boundary、恢复 ticket、journal 及运行输出。授权有效期 24 小时；过期重新准备，不编辑原文件或修改时间。
6. 先验证两版都保留：注册、当前进程和路径正确，默认输入法未变；确认 Rime/PIME 非提升 Runtime 就绪。分别手动选择两版，在记事本、Word、浏览器输入，覆盖变长、全码、简码，候选标签仍为 `⇧1` 至 `⇧9`，裸数字仍用于组字。
7. 重启并登录，验证两版自启动和实际输入。记录 PID、启动时间、映像路径、活动 profile/加载 DLL，不能仅依据旧的 runtime-status.json。
8. 安装和重启结果先回传。继续移除/恢复测试时，准备参数增加 `Mode=Remove` 或 `Resume` 和 **原始** `RecoveryTicketPath`，再使用新生成的执行参数。移除仅针对本轮 Rime/PIME；用户状态、未列文件和恢复材料按既有策略保留。

## 失败处理与回传

任何异常都保留现场和仓库外证据，停止后续测试，不删除 YimeCore、清注册、修改默认输入法、放开历史身份或绕过 hash/原生上下文检查。
进程中断后缺少 after/result 记录不等于保护通过；恢复前后需分别记录，不能把新基线替代中断前证据。
自动保护是操作前后观察，不是对恶意同 SID 写入、硬断电或用户输入期间并发变化的防护证明。

提交报告到 `perf/i7-7820x-local`，包含来源提交、候选/收据/manifest 哈希、测试阶段、机器/系统架构、每项原始证据路径及哈希、真实失败字段。
原始身份、学习内容、approval 和恢复介质留在仓库外；报告只保留必要的元数据，学习文件只记录哈希。
如某次自动化没有激活 TIP，应保留原失败并附实际激活后的观察，不能改写原始字段。

源码/合成合同通过不代表该机已经安装通过。CI 拆分属于后续独立提交，不改变此候选身份。
