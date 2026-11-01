# PR87 固定包：桌面鼠标结果开发端汇总

更新：2026-11-01（UTC）。本次只读取已回传 JSON、核对来源与范围并更新文档；没有重新运行产品、宿主或回归测试，没有修改产品代码。

## 来源与一致性核对

- 结果提交：[176c4a25979e7de05d3210ec8ad2b9e632ad1bdf](https://github.com/tsaanghwang/Yime/commit/176c4a25979e7de05d3210ec8ad2b9e632ad1bdf)。该提交仅新增下述一份 JSON，没有截图或其他文件。
- [不可变结果 JSON](https://github.com/tsaanghwang/Yime/blob/176c4a25979e7de05d3210ec8ad2b9e632ad1bdf/results/desktop-x64/pr87-desktop-x64-r1/8cf5bd6d8f82996c08db9b811004ac3dc2ee8031cbcba7520ad1ecf25e4c69e5.json)：UTF-8 原文 4116 字节，包含结尾换行的 SHA-256 为 `8cf5bd6d8f82996c08db9b811004ac3dc2ee8031cbcba7520ad1ecf25e4c69e5`，与文件名一致。原文不改写、不复制覆盖结果分支。
- 任务：`pr87-desktop-x64-r1`，机器 `desktop-x64` / 实际主机名 `计算机`。结果与固定 [queueCommit c27d01b43e0eb337461f5c93184042282e081ae0 中的任务](https://github.com/tsaanghwang/Yime/blob/c27d01b43e0eb337461f5c93184042282e081ae0/tasks/queue/desktop-x64/pr87-desktop-x64-r1.json) 的任务 ID、机器、三个检查项及次序、整个 package 对象一致。按运行器去首尾空白的原算法计算任务 SHA-256 为 `e3b1b24661e523b5b9201acc65500fa875f5155b50f15e21bbbea32a265f263c`，与结果相符。
- 固定 PR87 amd64 包：CI run `41178044364`、artifact `13034145597`、sourceCommit `12a9930ce4e84b5c7de35fb2816c201b1e72e8af`。ZIP/manifest/EXE 的身份与任务、[原固定包交付记录](ci-evidence/records/package-identities.json)一致；31 个负载的静态校验结果属于领取时记录。本次不冒充重新访问本机包进行独立校验。
- 汇总时开发主线仍为 `f605d1acf9f9a20986c3ec3d6490da3e2d5c15ac`，任务流程分支为 `c27d01b43e0eb337461f5c93184042282e081ae0`。任务源、包源和结果提交保持各自身份，不相互替换。

## 本机范围与结论

**“计算机”不是触摸屏，本轮只验收桌面鼠标。手指与触控笔不属于本机范围，不列为本机待测项，也不以它们承接单鼠标无法构造的场景。** 三个检查项的 inputMethod 均为 mouse。

| 检查项 | JSON 原状态 | 本轮可以接受的结论 | 证据和限制 |
| --- | --- | --- | --- |
| toolbar-edit-guards | pass | 纯预览鼠标范围通过：CN 活动 ni / EN 暂停 ni 的工具栏退格保护、取消、已确认 a 的删除、主体 Back Space 将 ni 退到 n 再清空；空闲 1–3 无声并保持正文/选区，随后 x 替换整个选区，实际最终为 x | 人工反馈；不是自动文本/音频读回。不扩展到宿主编辑保护或更广 Unicode 编辑 |
| minimize-rebind | pass | 纯预览及新建空白 Word 文档1范围通过：最小化/恢复正常，旧绑定失效；明确重新绑定后单击 a，实际正文恰好 a，无重复、漏字或错误提示 | 人工鼠标反馈；未声称自动读取 Word 正文。后续再次最小化，不能据此认定当前绑定仍有效 |
| candidate-states | not-run（部分覆盖） | 已观察按住凹下、移出恢复、移回松开无提交、普通翻页往返无提交；仍不把整项记为通过 | 自动鼠标截图观察仅支持其描述的移出松开无提交；其余明确归于用户反馈。按住候选期间另行翻页需要独立并发操作，单鼠标单指针无法构造，本轮旧按压失效未验证。这是操作条件限制，不是发现产品失败 |

`humanEvidence=true` 表示本报告包含人工观察。顶层 `status=awaiting-human`、`physicalAcceptance=false` 及 `verification.executableStarted=false` 保留运行器的初次领取/静态验证语义，不是本轮全部未测的结论，也不应改写成全产品通过。JSON 的 observation 明确记录本批实际启动固定包并完成上述受限测试。`receivedAt` 是领取时间，不用作本轮人工测试的发生时间。

本轮没有测试 Edge；旧鼠标预览、旧 Word/Edge 最小批次继续归属各自历史记录，不改写为本轮观察。此次 JSON 不含原始截图或本地反馈文件，本汇总只核对提交中实际存在的内容，不宣称独立查看了那些未上传证据。

## 开发侧剩余事项与边界

1. **候选旧按压失效的覆盖结论需要分层收口，而不是要求本机改用手指或笔。** 当前固定包源中已有对应受控回归：
   - [TestTouchHeaderPagerEdgesKeepGestureCancellation](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/touch_header_windows_test.go)：候选指针 100 保持按下，另一指针 101 翻页后，再释放 100，断言不提交旧候选。
   - [TestTouchRaisedPagersRenderStateAndKeepEdgeGestures](https://github.com/tsaanghwang/Yime/blob/12a9930ce4e84b5c7de35fb2816c201b1e72e8af/go-backend/cmd/yime-touch-keyboard/touch_control_keycap_windows_test.go)：同样覆盖独立指针翻页、重复抬起以及旧候选不提交。
   本次静态核对确认上述文件在包源与当前开发树的 Git blob 一致。它们是受控多指针开发用例，不能替代本机单鼠标真人结果；本次没有重跑，也不把旧 CI 总通过改称此轮实机覆盖。后续开发验收若需关闭整项，应单独核对对应回归执行证据及接受标准，或明确记录本机人工条件不适用，保持原 JSON 的 not-run 不变；不能仅凭此缺口要求修改产品逻辑。
2. **本轮没有新增已证实的产品缺陷。** 两个限定范围 pass 可纳入当前桌面鼠标矩阵，不重测以凑全覆盖。宿主编辑保护、更广 Unicode 编辑、Edge 新一轮测试未包含在这次结论中；它们是范围排除项，不自动转成新开发任务或本机待办。如未来确需扩大范围，应另定任务和证据要求。
3. **其它机器与包分别处理。** 此份桌面 JSON 不给 ASUS ARM64 或 MSI 结论，也不把其它设备的触屏职责转给“计算机”。其它机器应以各自明确提交的实际结果另行汇总；本次没有因它们未出现在该 JSON 而判定失败或重新安排测试。

本次开发端动作到文档归档和范围核对为止：不新建测试队列、不修改原任务 ID/内容、不执行测试、不修产品代码、不合并 main。
