# Yime 项目现状与验证边界

更新：2026-11-03（Asia/Shanghai）。本轮已 fetch 并核对主线 `64a785a7ede5fb2a53e2560b873075950160668b`，另读取固定候选/结果分支及 GitHub PR 状态。影响范围：YimeCore、Rime/PIME、18u 实验布局与输入链、共同离线数据工程。本页汇总已有记录，本轮未运行产品、安装或补做验收。

审阅修订补充了 MSI test.7 的固定安装结果 `86049049`，以及 22:50:29 完成、固定回传于 `ff7349be` 的单次自有宿主脱敏结果。重启核验仍按独立会话报告另列，不归入上述任一结果；其余主线、候选及 PR 状态仍沿用本轮原快照。

## 当前结论

Yime 保持 **YimeCore 主开发、Rime/PIME 独立稳定维护**。两套产品各自拥有运行组件、注册身份、安装目录和用户数据。18u/CN134 是隔离的概念键盘布局及输入链开发方向；它不替换标准布局，也不把两套产品改成共享运行时。

当前工作已从 9 月的双产品简版交付，推进到 **18u 便携原型、独立 TSF 接入、安装版触控前端和 ARM64 完整输入链候选开发与验证**。主线、验证分支、候选包和设备结果进度不同，不能归并为“全部合入、全部验收通过”。项目仍处于开发与受控测试阶段，正式可信签名发行尚未完成。

## 主线与候选来源

下表是本轮核对时的固定快照。分支后续移动时，应读取新提交及其证据；链接固定到本次实际读取的提交。

| 范围 | 固定提交 / 状态 | 已证实的进展与限制 |
|---|---|---|
| 主线 `main` | `64a785a7`；PR #94 已合入 main | 包含 18u 原型、ARM64 标准 YimeCore 工程、PR #88 原生异步门、#89 H02 清单、#90 短路径夹具、#92/#93 CI 清理与证据保留、#94 失败诊断改进 |
| 18u 安装验证分支 | [`11c7a774`](https://github.com/tsaanghwang/Yime/tree/11c7a774b0507d55cc97be117ee952ddc544778d)，`validation/18u-simple-installer-20261102` | [#95](https://github.com/tsaanghwang/Yime/pull/95)、[#96](https://github.com/tsaanghwang/Yime/pull/96) 已合入此验证分支，**不是 main**；含安装输入序列及完整旧状态升级隔离回归 |
| 验证分支后续审阅 | [#97](https://github.com/tsaanghwang/Yime/pull/97)，head `50db7ccc`，open | 修复夹具预期路径的作用域绑定并增加负例；目标仍是上述验证分支。它是测试有效性修复，不是已确认的真实安装路径错误 |
| MSI test.7 触控前端候选 | 分支 `codex/msi-18u-test-preparation-20261103`，交付记录 `cf70cae6`；包源码 `33b7113c` | [固定交付与安装前清单](https://github.com/tsaanghwang/Yime/blob/cf70cae6/docs/testing/18u/2026-11-03/msi-preparation/TEST7-DELIVERY.zh-CN.md)记录专用、原型及通用 CI 通过；后续[安装结果 `86049049`](https://github.com/tsaanghwang/Yime/blob/86049049ca6f336cbdd70ca3d64e8a2b5511223b/installed-results/msi-x64/installed18u-test7-msi-install-r1/live-entry-r1/result.json)记录旧版卸载、新版安装及静态核验完成，该固定结果当时尚未重启。重启会话报告和单次自有宿主结果分别见下表；普通应用及指笔验收未完成。MSI 指微星机器，不是 `.msi` 文件 |
| MSI test.7 自有宿主回传 | `codex/msi-test7-ownhost-report-20261103`；结果 `ff7349be`，交接整合 `c07c9545` | [固定脱敏审阅报告](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/REVIEW.zh-CN.md)及[更新后交付说明](https://github.com/tsaanghwang/Yime/blob/c07c9545227ed0a333ca44eed060df098cb8259a/docs/testing/18u/2026-11-03/msi-preparation/TEST7-DELIVERY.zh-CN.md)已回传；本轮核对时 `task-results/msi-x64` 仍为安装结果 `86049049`，新宿主结果来自这条独立分支，不表示 main 已合入 |
| ARM64 完整输入候选 | [`956350e4`](https://github.com/tsaanghwang/Yime/blob/956350e4/docs/testing/arm64/2026-11-03/full-input/README.md)，`codex/arm64-complete-input-20261103` | 标准 YimeCore 新包来源为主线 `64a785a7`，安装和注册宿主已有报告；另有 Rime/PIME ARM64、18u 前端及普通用户启动修复。后者尚不能写成 main 已包含或最终包已验收 |

## 已有交付与实机证据

| 对象 / 设备 | 已记录结果 | 尚不能推出的结论 |
|---|---|---|
| 标准双产品 x64 / WOW64 | 9 月简版安装、卸载、重装及所报告应用输入已完成；9 月 29 日注册修复交付由[工作区核对](project/WORKSPACE_RECONCILIATION_2026-10-18.md)索引 | 不把历史包的维护/输入结果自动赋予后续包 |
| MYCOMPUTER 标准 YimeCore：注册宿主矩阵 | 11 月 2 日 `0.1.0-local.14-pr88`（源 `fdd075cd`）构建安装；x64/x86 × 三模式检查先经历观察器失败（未运行用例），再有前台激活失败的 1/6、5/6 两轮及单格复测 1/1，最终一次完整矩阵 **6/6 通过**。见[原始矩阵与尝试记录](project/18u-self-developed-integration/INSTALLED_REGISTERED_HOST_X64_X86_PR88_BUILD_2026-11-02.json)及[恢复方案 §9](project/18u-self-developed-integration/S3C_RECOVERY_DELIVERY_REVIEW.zh-CN.md) | 原失败与复测记录保留，不记为首轮通过；仅证明该开发机、该包的注册宿主结果，不是所有普通应用或 18u 物理验收 |
| MYCOMPUTER 标准 YimeCore：用户反馈 | 用户确认 `local.14-pr88` 新版本正常并保留日用，见[当前安装交接](../installer/simple/HANDOFF.md) | 用户日用确认单列，不扩展注册宿主矩阵的验收范围 |
| HUASHUONOTEBOOK 标准 YimeCore ARM64 R2 | 10 月 26 日完整包交付、安装、原生 Notepad 受控 UI 检查及两项用户物理键盘反馈；注册宿主首轮 **8/9**，失败单格两次复测通过，见[原始报告](testing/arm64/2026-10-26/PACKAGE-AND-INSTALL-TEST.md) | 不能改写首轮为 9/9；首失败根因未定，真实应用三模式、重启及稳定性未由本报告封版 |
| 同机标准 ARM64 新包 | 11 月 3 日主线 `64a785a7` 包安装返回 0、69 个载荷匹配，ARM64/x64 仿真/x86 仿真 × 三模式注册宿主 **9/9**；[分支报告](https://github.com/tsaanghwang/Yime/blob/956350e4/docs/testing/arm64/2026-11-03/full-input/README.md)同时记录常驻运行时以 High 完整性启动的问题 | 用例使用独立普通用户 Broker，不能证明常驻 Runtime 权限正确；分支修复与最终重制包、普通权限启动及真实应用复验仍需各自记录 |
| “计算机”独立 18u test.6 | 包源码 `5367accdb6f18bb298f2282df67d4cc6d342aa5e`；[结果分支 `b1b47aaa`](https://github.com/tsaanghwang/Yime/blob/b1b47aaa1f07dde0a7996e97ebf09d2bafa75a65/installed-results/desktop-x64/installed18u-test6-desktop-x64-r1/result.json)记录安装、一次正常重启、单次 installed-host commit/读回通过 | 保留首次 UAC 失败与明确授权的手动接续；`physicalAcceptance=false`、`overallProductAcceptance=false`。未测 Word/Edge、性能或指笔；本机鼠标条件不应转成指笔待测 |
| ASUS 独立 18u test.6 readiness | [`85b0d079` 只读结果](https://github.com/tsaanghwang/Yime/blob/85b0d079/installed-results/asus-arm64/installed18u-arm64-readiness-r1/result.json)：原生 ARM64 与既有标准版确认；该任务因未提供原生 ARM64 test.6 包而 blocked，安装/宿主未执行 | 标准 ARM64 包、PR87 便携包及后来 ARM64 候选均不能冒充此任务通过 |
| 微星 test.7 完整前端：固定安装结果 | 源码 `33b7113c8b76d6c95447856c2d5cca374b542507`，[artifact 13221664045](https://github.com/tsaanghwang/Yime/actions/runs/41617296801/artifacts/13221664045)；产品 ZIP SHA-256 `a9ee98aefc93bd3b579dcbd388bc7de34a8a2fcb5839666598d660b4e9d39e8a`。[结果 `86049049`](https://github.com/tsaanghwang/Yime/blob/86049049ca6f336cbdd70ca3d64e8a2b5511223b/installed-results/msi-x64/installed18u-test7-msi-install-r1/live-entry-r1/result.json)记录旧版卸载、确认缺席、新版安装及静态核验各执行一次，卸载/安装均返回 0；45 个安装文件匹配，COM 路径匹配、Profile 注册存在 | 固定结果明确 `rebootPerformed=false`、`inputAcceptancePerformed=false`，不证明实际 TIP 激活、DLL 加载或输入。六个 PE 为 `NotSigned`，未建立发布者信任；外层 artifact ZIP 与内层产品 ZIP 哈希不同 |
| 微星 test.7：后续重启核验报告 | 来源为 2026-11-03 后续会话中转述的本地核验：22:36:31 重启后，45 个安装文件及 COM/Profile 注册核验通过，标准版与 Rime/PIME 的程序文件和机器级 COM/TIP 注册保持不变；报告给出的本地记录为 `.generated/installed18u-test7-msi-postreboot-r1/result.json` | 本轮未读取该本地 JSON，也未取得它的固定提交/哈希；本地路径不是公开核验链接。该会话报告不归入 `86049049` 或 `ff7349be`，本身不证明实际激活或输入；后续单次自有宿主结果另列 |
| 微星 test.7：一次 CN/variable 自有宿主 | 22:50:29 完成；[脱敏结果 `ff7349be`](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/result.sanitized.json)记录同交互/安装用户、非管理员令牌、固定包及 45 个安装文件核验通过。一次 Windows 注册 profile 激活、已安装 DLL 实际加载、`applied` 提交及非空匹配读回；无 SendInput、无自动重试，Runtime 返回 0，宿主/Broker 正常退出 | 仅这一模式、这一自有宿主、一次提交；不覆盖 Word/Edge、翻转、手指、笔、其他模式、延迟锁、失败写入、重放、日用稳定性或独立启动验收。固定链接只能核验已发布摘要及索引，原始证据全部留在 MSI 本机 |

MSI 宿主结果保留 `runtimeInstalledProfilePresenceVerified=false`，对应 Runtime 原字段 `installedProfilePresenceVerified=false`；不能因 native 的 `registered=true`、`windows-activated-profile` 和实际 DLL 加载而改为 true。静态持久注册核对单独成立。脱敏摘要记录前后受保护路径/注册、独立安装目录/注册快照及默认输入法相关注册比较未变；启动项仅观察进程内注册视图，没有 StdRegProv 独立核验。[证据索引](https://github.com/tsaanghwang/Yime/blob/ff7349be6b7ccad35b318477a0f7e0008e0efa52/docs/testing/18u/2026-11-03/msi-ownhost-test7/evidence-index.json)中的原始文件均为 `uploaded=false`，哈希只作本机证据保全引用；依赖脚本哈希是审阅时观察值，不表示执行时已自动锁定。本轮读取了固定脱敏摘要及索引，未读取或复核 MSI 原始日志，也未重新执行检查。

test.6 桌面结果中的 `installedProfilePresenceVerified=false` 原样保留；持久注册由独立安装后检查支持。结果还保留 `userDataPreserved=null`、`standardRuntimeStateChanged=true`，因此只能报告既有内容未发现重置，不能声称重启后所有状态或用户数据逐字节不变。原始证据留本地，脱敏结果引用的文件由[证据索引](https://github.com/tsaanghwang/Yime/blob/b1b47aaa1f07dde0a7996e97ebf09d2bafa75a65/installed-results/desktop-x64/installed18u-test6-desktop-x64-r1/evidence-index.json)定位。

## 18u 布局与输入链

- 标准布局真源仍为 `internal_data/manual_key_layout.json`；实验布局为 `prototypes/touch-terminal/encoding/manual_key_layout.json`，产物和包身份独立。18u 为主开发几何，17u/23u 保留为冻结候选。
- 便携原型已完成中文三模式、组合/候选、绑定与取消、导航编辑和完整包阶段；当前 touch-screen-v2 为 **84 主体键＋18 控制键**。旧 98 键触屏视图和 100 键完整视图的步骤只适用于各自固定包。见[原型交接](../prototypes/touch-terminal/desktop/HANDOFF.md)与[PR87 固定交付](testing/touch-keyboard/2026-10-31/candidate-readability/HANDOFF.zh-CN.md)。
- 自研 TSF 接入从会话协议、自有宿主、异步保护推进到独立 TIP；主线已有失败诊断和严格证据校验。旧本机注册残留已按固定包恢复并独立确认缺席，不能因历史报告再次启动恢复。[PR #94](https://github.com/tsaanghwang/Yime/pull/94)保留坏 stderr 行附近的有效失败轨迹，未将旧分支的整套恢复设计直接替换进主线。
- test.7 候选新增完整触控前端；“完整”仅指候选包所含前端范围，不代表功能或触控操作已全面验收。该候选经激活 TIP 的实际 `DoEditSession` 提交，其普通应用进程间接入仍待安装后验证。当前声明范围为原生 x64、同用户/会话/权限级别的可写 TSF context；未支持的快捷键不能据便携原型能力推定可用。
- 已有物理反馈必须保留机器、包与输入方法：[桌面 PR87 结果](https://github.com/tsaanghwang/Yime/blob/b1b47aaa1f07dde0a7996e97ebf09d2bafa75a65/results/desktop-x64/pr87-desktop-x64-r1/8cf5bd6d8f82996c08db9b811004ac3dc2ee8031cbcba7520ad1ecf25e4c69e5.json)的工具栏保护/最小化重绑在所述鼠标范围通过，`candidate-states` 整体仍为 `not-run`；[ASUS 持笔补测](https://github.com/tsaanghwang/Yime/blob/85b0d079/results/asus-arm64/pr87-asus-pen-hold-r2/19cc37627dba722a656f226ddaa4beeaaaae1a4333f7bcb160f801ba4728b81c.json)只有单次纯笔保持、单次笔＋手指换页样本。两者都不代表整机物理验收、稳定频率或 test.7 的结果。

## 性能、数据与发行

9 月 19 日[开发机 E3 报告](testing/simple-maintenance/2026-09-19/current-readiness/DEVELOPMENT.md#e3-performance)记录评分序列缓存后的三模式通过；9 月 9 日 [i7-7820X 历史失败](project/YIMECORE_I7_7820X_NATIVE_BENCHMARK_RESULT_2026-09-09.md)保留。不同报告的耗时、比率、样本和机器不能混用；普通 CI、包检查和安装成功不证明新候选的输入延迟或跨平台性能达标。本轮没有性能测量。

规范拼音、音节编码、音元语义和布局投影继续分层；语流变化按有来源、可撤销的词/短语别名准入。共同数据变更分别验证真实 Rime 三模式与独立 YimeCore，不能用一个产品代替另一个的正确性。大型外部词源仍由内容锁归档提供，不读取其他 Git 工作树。

目前可引用的是开发/测试包及各自验证记录。最终可信签名、完整目标包的普通权限运行、真实应用与设备验收、生产用户数据策略仍需收敛。ARM64 已有实机，不能再写成“无设备冻结”；标准 YimeCore ARM64、Rime/PIME ARM64 候选和 18u ARM64 候选须分别判断。

## 下一步与记录规则

1. 完成 #97 的验证分支审阅，明确后续合入对象；不将 #95/#96 的验证分支合并写成 main 合并。
2. MSI test.7 已有固定安装静态核验和一次 CN/variable 自有宿主激活、加载、提交/读回结果；不自动重复成功用例。重启会话报告仍待独立固定来源，启动验收未完成；后续按获准任务分别记录普通应用中的激活/读回及各输入方法。test.6 和本次单宿主结果均不扩展为这些场景通过。
3. 对 ARM64 普通用户启动修复重制候选并复验，分别标明主线运行载荷与新安装器来源；Rime/PIME 和 18u 草稿制包证据单列。
4. 根据新源码/包实际变化安排性能、稳定性及签名发行工作，保留首次失败、跳过和未测项。

具体优先级见[路线图](YIME_DEVELOPMENT_ROADMAP.md)。标准产品操作入口为[安装交接](../installer/simple/HANDOFF.md)，18u 便携入口为[原型交接](../prototypes/touch-terminal/desktop/HANDOFF.md)，安装版候选按上表固定分支交接。文档快照不是新的安装、恢复、重启或派测指令；带日期的原始证据保持原样。
