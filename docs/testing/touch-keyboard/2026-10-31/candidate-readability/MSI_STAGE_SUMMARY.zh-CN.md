# PR87 固定包：MSI 阶段验收（含翻转与笔保持异常）

更新：2026-11-01（UTC）。本次只核对已提交结果和现有源码、更新阶段报告并提出下一小批建议；未重新执行产品/实机测试，未修代码、创建队列或合并 main。

## r2 宿主小批完成（2026-11-01）

已核对 `f7b4540b5efd3056ae816d35f461cb00791df6c9` 的 `pr87-msi-host-posture-r2`，固定7ed队列/taskSHA/package匹配。当前平放、横向翻转、2880×1800/200%、校准58范围下，Word基础绑定、Edge基础绑定、Word恢复重绑三项均按用户反馈通过；最终正文分别“你”“你”“你你”，非自动读回。手指为每组指定方式，用户未另行复述设备。详见[四机当前阶段汇总](FOUR_MACHINE_STAGE_SUMMARY.zh-CN.md)。下方旧报告中的Word/Edge未测状态保留当时归属，不再作为当前这三项待办；未测其它宿主范围不扩写。MSI笔保持/翻页继续暂停，原装笔不安排，宿主通过不代表笔问题解决。

## 后续：翻转屏小批与笔保持异常（2026-11-01）

本节为新结果审阅，优先用于当前状态；下方首轮三笔子项通过、旧建议及四机分工保留历史归属。新增手指通过项不再列为本机补测；MSI 笔保持/翻页已暂停。本文只审阅和提出对照方案，未下发任务或启动其它屏幕测试。

### 新提交与完整性

[结果提交 6d0e5aadc4460bcb18066954040ac67197875fa4](https://github.com/tsaanghwang/Yime/commit/6d0e5aadc4460bcb18066954040ac67197875fa4)仅新增[一份 JSON](https://github.com/tsaanghwang/Yime/blob/6d0e5aadc4460bcb18066954040ac67197875fa4/results/msi-x64/pr87-msi-x64-r1/819182e0c9895660a809167f7a95b2a030378baa489ac391d50ed18123158ae6.json)，UTF-8 含末尾换行 8488 字节，SHA-256 `819182e0c9895660a809167f7a95b2a030378baa489ac391d50ed18123158ae6` 与文件名一致。任务 ID、机器、c27 queueCommit、taskSHA256 `fc2158b212a941987ab0c2ae89018f12d73bc8d7066fdcb0fe18be09d9066f34`、四检查项及 package 对象与固定任务和前次报告一致。仍是 run `41178044364` / amd64 artifact `13034145597` / source `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`，既有校准参数 58 未换；不是新包。

### 新增通过与尚未解决项

| 观察 | 采用的限定结论 |
| --- | --- |
| 笔记本约 75°、平放及翻转后姿态 | 用户报告布局完整、手指命中对应正常；读回当前主屏 orientationCode=2、2880×1800、DPI192（200%），支持当时横向翻转状态。未改显示设置；不是所有姿态/角度的穷尽测试 |
| 空组合最小化恢复 | a/空组合/EN 保持、再点一次 a 的预期序列获得用户整体确认；用户没有独立逐字抄录最终 aa，不升级为自动正文读回 |
| 非空组合最小化恢复 | CN 未提交组合取消，已确认正文保持，没有额外提交/重复；不重做这项 |
| CN 活动及 EN 暂停时工具栏退格 | 用户报告正文、组合保持，无候选提交；准确组合字符串未逐一抄录，不虚构精确内容 |
| 三个空闲键 | 全选后逐个触碰，无动作/音，正文与选区保持；本轮通过，不重复安排 |
| Acer 笔按住候选再协同翻页 | 预期保持期间用户感到近乎接触即提交，稳定保持前提未满足；本次 pen-small-batch=fail **仅限此保持场景**，旧三子项反馈通过不被抹去。旧触点翻页仍未验证，继续暂停，不强行重做 |

手指整项 not-run 仍表示覆盖未完而非完全未测。Word/Edge 本轮未测，不继承 ASUS 或桌面结果，不自动追加。后续回复沿用平放翻转和手指操作语境，未每条再次确认姿态；惯用手对照也未获实际手别记录。原装 MSI 笔是用户自行尝试后报告类似现象，不取消“原装笔不再安排”的决定。手指等效操作正常、其它屏幕“几乎没有”是观察线索，不是已控制版本/姿态/设备条件的因果对照。

### 事件摘要支持什么，不支持什么

报告称诊断使用同一 EXE SHA-256 `b1210ca2c34f1a349ca12c65128a48e419ba74b4dee2b86848b916cc5c90a830`，仅本地预览 input-trace，pen-recontact 默认 0。完整快照仍只在 MSI：`C:/YimeTaskExchange/msi-x64/tasks/pr87-msi-x64-r1/pen-diagnostics/snapshot-early-commit-1793507761957.jsonl`，报告大小 241216 字节、SHA-256 `210f1c457aa9e174e9478034f1d437378a8c503b99ace319da9c5887534a4ccf`。**提交中只有摘要和该哈希，没有完整 trace 文件；云端不能据此声称重算了原始日志哈希、检查了所有事件或证明摘要没有遗漏。**

| 摘要序号 | elapsedMS / 状态 |
| --- | --- |
| 121，DOWN 前 | 144101.4701；WM_POINTERDOWN 0x0246、pointerType=3；组合长度2、正文长度0 |
| 125，DOWN 后 | 正文仍为0 |
| 133，UP 前 | 144130.9042；WM_POINTERUP 0x0247；正文仍为0 |
| 135/136，关联触摸帧及处理后 | flags=0x54、id796；随后组合长度0、正文长度1 |
| 140，下次笔 DOWN | 144341.7759 |

摘要时间复算：DOWN→UP 为 **29.4341ms**；UP→下次 DOWN 为 **210.8717ms**。这支持应用观察到 UP 关联处理后增加一个字符，不支持“首个 DOWN 就直接提交”的代码结论，也没有证明重复提交。接收 UP 不等同证明笔尖真实离屏；无法凭摘要区分微小动作、硬件、驱动、事件时序或其它原因。后一次 DOWN 也不能单凭时间间隔认定造成第二次提交。过往未校准启动异常先于本批，不归因给当前笔现象。

固定包源 [preview_windows.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/preview_windows.go) 的 previewDown 保存候选手势；previewUp 先删除该指针手势（重复 UP 无动作），检查移出及状态版本后才调用 selectCandidate。[platform_windows.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/platform_windows.go) 将预览 up 路由到 previewUp；[input_trace_windows.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/input_trace_windows.go)记录应用消息及长度，不记录真实笔尖物理状态。以上三个文件包源 blob 与本次所读开发树一致；这是源码语义核对，不是新测试或对所有异常路径的正确性证明。有效候选内部正常释放提交一次本身是预期行为；异常是用户试图保持却提前结束的体验，根因仍未定。

**开发结论：先保留可复现条件与差异，不改全局延迟、去抖或重接触参数，不把硬件假设登记为已确认缺陷。** 即便将来确认设备/驱动限制，也须另评合法事件处理是否恰好一次，不能由外部归因推导软件所有路径无误。

### 下一步建议：两屏同笔小对照，先保持再翻页

仅提出最小方案，待用户明确安排；MSI 不续跑保持/翻页，不扩大到完整触控/宿主矩阵。使用**同一支 Acer PE270XT 随附笔**，大屏 MyComputer + Acer PE270XT 与 ASUS 内屏各做以下两步，并分别记录屏幕、姿态、实际手别及前后正文/组合。不能把其它笔或 ASUS 历史结果替代此次对照。

前提：两屏都用固定 source `12a9930ce4e84b5c7de35fb2816c201b1e72e8af` 的匹配原生架构包（amd64 artifact `13034145597` / ARM64 artifact `13033634731`），而非要求 EXE 哈希跨架构相同；各屏只用自己的已确认校准，禁止复制 MSI 参数58。MyComputer OS/CPU/原生架构、匹配包和本屏校准尚未核实，不能先假定 amd64、现有任务配置或已有第四机队列。若前提不足，停在核对，不启动产品。ASUS 既有原生及本屏校准证据可引用，不为此重复一轮验证。

1. **稳定按住候选**：纯预览正文为空、组合 ni；笔按候选并有意保持约1秒后在原候选内释放，操作期间不翻页。**预期：保持期间正文仍空、组合仍在；主动释放后只提交一个候选并清组合，无重复。** 记录实际操作和是否提前变化，不声称人工估时是精密接触测量。若保持前提前提交，立即结束此屏小批，保留失败前后状态，不进入翻页、不反复尝试凑 pass。
2. **仅在第1步成立后做混合翻页**：重新准备空正文/ni，笔稳定按候选，另一手指翻页，再释放旧笔触。**预期：页面确实变化，释放旧笔触不提交旧候选、不新增正文，仍为未提交组合。** 明确标作笔+手指混合；若设备不支持同时操作或无法构造，记条件限制，不换成普通翻页冒充完成。

每屏只做这组匹配条件样本，不据一次成功/失败估发生率或下硬件诊断。先读原始摘要并按上述预期人工观察；本方案不自动开启新日志、改驱动/显示/诊断参数或上传任何原始轨迹。若需要进一步日志证据，再明确最小采集范围。MSI 已通过的姿态、手指恢复、退格保护及空闲键不重测；已确认正文退格和 Word/Edge 当前不并入对照。原始 JSON、初次快照 physicalAcceptance=false/awaiting-human 及旧记录保留。

## 来源与包身份

- 结果分支 `task-results/msi-x64`，提交 [547a794a8694a233b1c4733bdae3bcd37a1004af](https://github.com/tsaanghwang/Yime/commit/547a794a8694a233b1c4733bdae3bcd37a1004af) 仅新增[一份结果 JSON](https://github.com/tsaanghwang/Yime/blob/547a794a8694a233b1c4733bdae3bcd37a1004af/results/msi-x64/pr87-msi-x64-r1/d378408118853200b3d2bc74800e7c4068fec1b525159232bc3543ea752536e6.json)。UTF-8 原文含结尾换行共 5326 字节，SHA-256 `d378408118853200b3d2bc74800e7c4068fec1b525159232bc3543ea752536e6` 与文件名一致。
- `taskID=pr87-msi-x64-r1`、`machine=msi-x64`、主机 `WIN-JTKUT7KBVN7`；[固定队列 c27d01b43e0eb337461f5c93184042282e081ae0](https://github.com/tsaanghwang/Yime/blob/c27d01b43e0eb337461f5c93184042282e081ae0/tasks/queue/msi-x64/pr87-msi-x64-r1.json) 的 ID、机器、四项检查及次序、整个 package 对象均匹配。按运行器去首尾空白算法复算任务 SHA-256 为 `fc2158b212a941987ab0c2ae89018f12d73bc8d7066fdcb0fe18be09d9066f34`，与结果一致。
- 固定 PR87 amd64 包：CI run `41178044364`、artifact `13034145597`、sourceCommit `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`。ZIP SHA-256 `e790c0fe0e245456e54163f348c969af93b3ac0ed91dda95e53e00655da4e34f`，98830082 字节；manifest/EXE 哈希、源身份和 31 个负载数均与[原固定包记录](ci-evidence/records/package-identities.json)一致。这是固定测试包，不是 main 合并后重建包，也不继承旧包真人结论。
- 汇总基于开发主线 `f605d1acf9f9a20986c3ec3d6490da3e2d5c15ac`、流程汇总分支 `2f8df714e50e1f424a73afc3d75209cca7ea1a4c`；保留[桌面鼠标汇总](DESKTOP_MOUSE_SUMMARY.zh-CN.md)及其仅鼠标范围，不向该桌面追加手指/笔任务。

## 分层结果：不是完全未测，也不是全体验收通过

| 层次/检查项 | 阶段结论 | 证据边界 |
| --- | --- | --- |
| 自动开发/静态包核对 | JSON 记录本机固定包及 31 负载核验、包自检与 `--touch-ui` 自检退出 0；touch-screen-v2 共 102 位置（84 主体、18 控制），18u×5.7u，三模式返回“你”，hostInputSent=false | 这些是本地自动开发证据，不是真人输入或宿主通过。本次仅读取提交中的报告，未独立访问本机包或未上传的详细日志；用户另报告 PE/source 核验，不扩写为云端重验 |
| screen-calibration：pass | MSI 内置 16 英寸屏，2880×1800、200%；100mm 参考尺最初实测 58mm，使用支持参数重新启动后复测 100mm；主体外缘约 340mm，对照设计 342.90mm，约 -0.85% | pass 指完成本屏真人校准及记录实测，不声称精确几何相等或手指/笔验收通过；不因此改动 18u 基线 |
| finger-small-batch：not-run，部分真人覆盖 | n→ni，首选提交恰好一个“你”并清空组合，无报告重漏；手指按住候选、另一手指翻页后释放旧触点，有成功翻页且无新增输入的反馈 | “五个选词入口移出后没有第二个你”的反馈没有逐一入口身份和最终组合，不能记完整移出覆盖。整体 not-run 是覆盖未完成，不是没有真人证据 |
| pen-small-batch：not-run，三个子项反馈通过 | **Acer PE270XT 随附笔**：输入抬笔无重漏；候选按住不提交、释放提交一次并清组合；再输入 ni，候选按住移出抬笔后原一个“你”和 ni 组合保留 | 用户正常操作未见误提交/重复；仅认可这三次操作，不推出一般可靠性、全部笔类型或宿主通过 |
| word-edge-binding：not-run | 本轮未进行 Word/Edge 宿主验收 | 不继承桌面鼠标或旧包宿主结果 |

`humanEvidence=true`；顶层 `physicalAcceptance=false`、`status=awaiting-human` 和手指/笔整项 not-run 保持原样。领取时 `verification.executableStarted=false` 不否定 observation 中后续已运行的自检及真人操作；`receivedAt` 不是所有人工观察发生时间。原始手工记录与自检详细报告仅以本地路径在 JSON 中引用，提交未附其文件，本次不宣称独立核阅这些原件。

**MSI 原装笔已按用户要求移出后续安排。** 疑似没电或笔有问题的原因未确认，不记故障定论，不要求修复/换电后重测，不继承 Acer 笔结果。操作不稳误触、屏幕反弹或未觉察二次接触，仅为用户疑虑：尚无发生频率、可复现事件序列或根因；不立产品缺陷、不改去抖/事件逻辑。大屏及 ASUS 对比只是背景，不是受控对照结论。

## 开发侧审查与剩余事项

固定包源已有以下受控回归，与真人记录分开：

- [touch_toolbar18_windows_test.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/touch_toolbar18_windows_test.go)：`TestTouchToolbarBackspaceRejectsCompositionAndOldGestures` 覆盖活动/暂停组合保护、旧手势与重复抬起；`TestTouchToolbarBackspaceEditsCompleteRunesAndSelection` 覆盖已确认正文编辑；`TestTouchToolbarSpareKeysAreInertInAllInputContexts` 覆盖空闲键不改正文/选区/组合、不发音。
- [touch_header_windows_test.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/touch_header_windows_test.go) 的 `TestTouchHeaderPagerEdgesKeepGestureCancellation` 等覆盖受控双指针翻页后旧候选不提交；不把该用例或手指反馈当作 Acer 笔已经通过。
- [taskbar_windows_test.go](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/taskbar_windows_test.go) 的最小化恢复/取消、`TestMinimizeInvalidatesHostTicket` 覆盖旧绑定票据失效；不能代替 MSI 实际恢复或 Word/Edge 重新绑定。

本次静态核对上述测试源码及原开发记录，未重跑；工具栏和任务栏测试文件的包源 blob 与当前开发树一致。现有证据没有新增已证实缺陷；后续先补有限的行为证据，遇到可复现异常再按输入设备、操作顺序、前后正文/组合/选区归因，不按反弹假设先修代码。

## 后续分工更新（2026-11-01）

用户随后确认[四机专项分工](FOUR_MACHINE_TEST_ROLES.zh-CN.md)：MyComputer + Acer PE270XT 主责手指/笔共性交互，MSI 主责笔记本及翻转屏适配。下列四项保留为当时的建议，**不是 MSI 必须完成的已下发批次**；后续共性退格/空闲键/笔旧触点优先由大屏规划，MSI 仅围绕明确的本机适配问题安排必要子项。历史未覆盖状态不改写，也不要求 MSI 补完完整手指/笔矩阵；不自动中止用户已进行的本地操作。

## 建议下一批：仅四项，优先纯预览

这只是接续建议，不是已下发或已执行任务。仍用相同固定包、MSI 内屏和已校准设置；优先使用已验证可用的 Acer 笔。每个结果明确实际输入设备，**不自动把笔结果推广为手指通过**；不要求把四项再按设备全量倍增。

1. **工具栏退格保护及正文退格（最高优先）**：纯预览先保留已确认正文，分别在 CN 活动 ni、EN 暂停 ni 下点工具栏退格，检查正文和组合均不被错误修改；取消组合后对已确认单字符退格，确认恰好删除一次。另单独识别主体 Back Space 的组合编辑语义，避免与工具栏保护混为一项。逐段记下前后状态，不扩至宿主或全 Unicode 矩阵。
2. **三个空闲键**：纯预览空白及已有正文选区时逐一触碰 1/2/3，确认无音、无输入且正文/选区保持；随后输入 x 验证替换整个原选区。明确人工听觉/目视，不声称自动音频或正文读回。
3. **Acer 笔翻页后的旧触点失效**：笔按住候选，用可独立操作的另一输入触点翻页，再释放旧笔触，观察页确实变化且不提交旧候选、不额外输入；明确记录实际混合输入方式。若硬件拒绝同时笔/手指或不能独立翻页，记操作条件限制并停止该项，不强称 pass、不换成普通翻页、更不要求 MSI 原装笔。
4. **纯预览最小化/恢复**：记录当前语言、组合、输出；按支持的最小化/恢复路径操作，检查恢复可用、无意外提交/重复输入，并记录状态变化。此项不宣称已经验证宿主旧绑定或 Word/Edge；宿主绑定留待独立小批。

仍未关闭的范围包括：五入口移出逐项身份/组合记录、其它尚未覆盖手指/笔子项、Word/Edge 的实际明确绑定和恢复重绑。保留待测而非一次全做；不重测 Acer 笔已完成三子项来凑全通过。无安装、默认输入法、既有用户文档变更；18u 基线、旧分支、原始记录及此前桌面汇总原样保留。
