# 当前开发与测试交接

更新：2026-09-20。影响产品：YimeCore、Rime/PIME。本文件是唯一当前交接入口；历史报告、旧执行单和本地临时目录不产生新的测试任务。

## 当前结论

本轮分支 `codex/current-readiness-release-delivery` 从当前 `main` 的 `0ab8631266736775bf1386f456d4a1d53e8e2eb3`（PR #62 合并后）创建，只核验 2026-09-19 current-readiness 的包身份、来源和交付条件。

**当前未满足 Release asset 交付条件；测试端无任务。** 原完整包及 admission 原始证据所在目录已不存在，在限定的本地清单搜索和 GitHub Release/相关 CI 附件中未找到同一个完整包。已从安装时保留的维护副本只读取回两份清单，SHA-256 与历史报告完全一致；这补全了 225 个载荷文件的清单，但不能恢复原完整包、构建日志或 ZIP SHA-256。详见[本轮核验报告](../../docs/testing/simple-maintenance/2026-09-20/current-readiness-release/REVIEW.md)及[交付准备状态](../../docs/testing/simple-maintenance/2026-09-20/current-readiness-release/RELEASE-PLAN.json)。

## 包身份与来源

| 项目 | 核验结果 |
| --- | --- |
| current-readiness 完整包 Release/asset URL | **无**；未创建 Release 或上传完整包 |
| 完整包 ZIP 字节数 / SHA-256 | **未知**；原报告未记录，原包未找回 |
| YimeCore 清单 | 65 文件；`67cbdf516ae8e4348f47ffa5bc7d94d1468d200c320b66b4a1d73ce649facf8d` |
| Rime/PIME 清单 | 160 文件；`2996982b88c70b251124847fd6fa37ada185a6c173de1139cbb32afda8324d38` |
| 原报告关联源码 | `53b409d7713ad47e0ae1039e060462012614d7b2`；[源码 CI](https://github.com/tsaanghwang/Yime/actions/runs/35411599859) 12/12 作业成功 |
| 本轮 main 基线 | `0ab8631266736775bf1386f456d4a1d53e8e2eb3`；[主线 CI](https://github.com/tsaanghwang/Yime/actions/runs/35418522827) 12/12 作业成功 |
| 原包实际来源提交 | 尚未由完整构建 provenance 证实；上述两个提交之间仅两份验收报告不同，不能据此推定当时构建工作区干净 |

两份清单是各产品的 `product-package.json` 哈希，**不是 ZIP 哈希**。源码检出和 `yime-native-*` CI 附件均不是完整双产品包。旧 [PR #57 测试预发布](https://github.com/tsaanghwang/Yime/releases/tag/test-simple-pr57-c5216861) 身份保持不变，不能替代 current-readiness 包。

## 验证边界

- 2026-09-19 在 MYCOMPUTER 的历史开发机验收见 [DEVELOPMENT.md](../../docs/testing/simple-maintenance/2026-09-19/current-readiness/DEVELOPMENT.md) 和 [post-reboot.json](../../docs/testing/simple-maintenance/2026-09-19/current-readiness/post-reboot.json)。它记录 x64 Word、x86 Notepad++ 两产品重启前后输入；原始报告字节保持不变。
- YimeCore 首次注册 `0x800700B7` 失败，随后同路径包重试成功；本轮保留实际失败与成功日志，并在核验报告校正原文的失败日志编号笔误。首次失败不计为成功。
- 本轮只做源码/CI/清单/现有安装载荷的静态读取及合成回归。没有安装、卸载、注册、重启产品进程、输入验收、修改默认输入法或用户数据；不将静态结果认作新的实机输入通过。
- 原包检查、原包 `Test-Product`、admission 两项原始文件复核和完整包重现仍未完成。ARM64 实机、正式签名、正式公开发行状态均不变。

## 开发端下一步与测试端状态

开发端需找回原完整包和构建/admission 证据，或在明确的新构建身份下重新制包，再完成所有适用包验证。满足条件后，才在本文件记录真实 GitHub Release asset URL、字节数、ZIP SHA-256、已核实来源提交和相应 CI。不能从已安装载荷反向拼包并称为 9 月 19 日原包，也不能沿用历史实机验收作为新构建的验收。

**`perf/i7-7820x-local` 测试端当前无需同步、下载、安装、卸载、重启或重测。** 包交付不自动发起测试；以后只有本文件新增明确任务才开始接收。大包通过明确 GitHub artifact/Release asset 交付，报告通过 Git 分支交回，不使用共享临时目录。

已完成的历史阶段保留：[2026-09-14 测试端验收](../../docs/testing/simple-maintenance/2026-09-14/source-candidate-test/REVIEW.md)、[2026-09-15 主线同步](../../docs/testing/simple-maintenance/2026-09-15/main-sync/REVIEW.md)、[验证范围汇总](VALIDATION.md)。这些记录均不要求重复执行。
