# PR87 固定包：MSI 首轮阶段验收开发端汇总

更新：2026-11-01（UTC）。本次只核对已提交结果和现有源码、更新阶段报告并提出下一小批建议；未重新执行产品/实机测试，未修代码、创建队列或合并 main。

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

## 建议下一批：仅四项，优先纯预览

这只是接续建议，不是已下发或已执行任务。仍用相同固定包、MSI 内屏和已校准设置；优先使用已验证可用的 Acer 笔。每个结果明确实际输入设备，**不自动把笔结果推广为手指通过**；不要求把四项再按设备全量倍增。

1. **工具栏退格保护及正文退格（最高优先）**：纯预览先保留已确认正文，分别在 CN 活动 ni、EN 暂停 ni 下点工具栏退格，检查正文和组合均不被错误修改；取消组合后对已确认单字符退格，确认恰好删除一次。另单独识别主体 Back Space 的组合编辑语义，避免与工具栏保护混为一项。逐段记下前后状态，不扩至宿主或全 Unicode 矩阵。
2. **三个空闲键**：纯预览空白及已有正文选区时逐一触碰 1/2/3，确认无音、无输入且正文/选区保持；随后输入 x 验证替换整个原选区。明确人工听觉/目视，不声称自动音频或正文读回。
3. **Acer 笔翻页后的旧触点失效**：笔按住候选，用可独立操作的另一输入触点翻页，再释放旧笔触，观察页确实变化且不提交旧候选、不额外输入；明确记录实际混合输入方式。若硬件拒绝同时笔/手指或不能独立翻页，记操作条件限制并停止该项，不强称 pass、不换成普通翻页、更不要求 MSI 原装笔。
4. **纯预览最小化/恢复**：记录当前语言、组合、输出；按支持的最小化/恢复路径操作，检查恢复可用、无意外提交/重复输入，并记录状态变化。此项不宣称已经验证宿主旧绑定或 Word/Edge；宿主绑定留待独立小批。

仍未关闭的范围包括：五入口移出逐项身份/组合记录、其它尚未覆盖手指/笔子项、Word/Edge 的实际明确绑定和恢复重绑。保留待测而非一次全做；不重测 Acer 笔已完成三子项来凑全通过。无安装、默认输入法、既有用户文档变更；18u 基线、旧分支、原始记录及此前桌面汇总原样保留。
