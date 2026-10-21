# 2026-10-21 晨报与跟进监控问题处理

来源：今日“每日简报”和“跟进监控”，共同指出 PR #72 五项运行时问题及 PR #75 两项验收步骤问题。处理基线 `85a5cabafac4f7d96586ee6662f17e5d66181a27`。范围只涉及桌面虚拟样机，不改变产品编码、已安装输入法、默认选择或用户数据。

| 审阅项 | 本地复现与修复 | 回归/核对 |
|---|---|---|
| [#72 英文暂停候选仍提交](https://github.com/tsaanghwang/Yime/pull/72#discussion_r4320749826) | 当前版本按候选会消费暂停组合；控制器拒绝英文选择，UI 不建立候选触点并标记“暂停” | `TestPreviewPausedCandidatesCannotCommit`、`TestPreviewPausedCandidateHasNoPointerTarget` |
| [#72 旧 0 触点提交新页](https://github.com/tsaanghwang/Yime/pull/72#discussion_r4320749860) | `0` 和其他非编码 ASCII 绕过旧检查；按实验 LayoutAlphabet 分类，仅中文可能确认候选的 input 校验版本 | `TestPreviewStaleMainNoncodingInputCannotConfirmNewPage`、`TestPreviewHeldZeroCannotCommitAfterPhysicalPageButton`；普通编码重叠、侧区 literal、显式 symbol/开启入口仍保留 |
| [#72 英文数字/Space/Enter 丢键](https://github.com/tsaanghwang/Yime/pull/72#discussion_r4320749878) | 英文重叠触点不再按候选修订号拦截，旧会话仍拒绝 | `TestPreviewEnglishOverlapAndRetiredSession`、`TestPreviewEnglishOverlappingPointerKeys`；原 `TestHostEnterPreservesShiftAndConfirmationPolicy` 改为英文旧修订允许、旧会话拒绝，同时保留中文旧候选拒绝 |
| [#72 中文空组合无空格/换行](https://github.com/tsaanghwang/Yime/pull/72#discussion_r4320749907) | 空组合按 literal 输出；非空无候选保持不提交；主区宿主 Enter 保留 Shift | `TestPreviewChineseEmptyConfirmAndUnmatchedComposition` 覆盖内存与发送替身 |
| [#72 多行光标裁切](https://github.com/tsaanghwang/Yime/pull/72#discussion_r4320749933) | 显示换行/Tab 标记，正文不改；以当前光标为中心截取，按实际字体宽度收缩到单行 | `TestPreviewMultilineDisplayKeepsCaretAndEditsVisible`、`TestPreviewDisplayFitsMeasuredSingleLine` 覆盖移动、插删、长选择与宽度 |
| [#75 P07/P08 盘面不明确](https://github.com/tsaanghwang/Yime/pull/75#discussion_r4321423565) | 明确 EN `R05K06` 的 a/A，之后才切原盘面验证偏好，结束恢复 EN | `TestPreview18uAcceptanceCaseKeys` 验证实际物理键及映射 |
| [#75 H02 导航键不存在](https://github.com/tsaanghwang/Yime/pull/75#discussion_r4321423592) | 主区改为 abc → 退格 → Shift+x → abX → 三次退格；导航/选区标阻塞，无物理键盘或全盘替代结论 | 同一 18u 物理路径回归，模板单列导航阻塞 |

五类运行时回归在修复前实际失败，编码重叠与旁路保护通过；修复后运行结果见本目录开发记录。测试中的指针调用、GDI 测量、内存会话与发送替身均是开发证据，不是手指、笔或真实应用验收。

#74 完整包及 2026-10-20 原始证据不变。当前运行时修复须用新的完整 CI 包验收；新身份交付前暂停旧包后续验收，不在旧资源目录覆盖 exe 或指南。手指、纯笔、真实宿主、自然异常恢复及 ARM64 原生结果仍待记录。没有安装、注册、系统字体或用户数据变更。
