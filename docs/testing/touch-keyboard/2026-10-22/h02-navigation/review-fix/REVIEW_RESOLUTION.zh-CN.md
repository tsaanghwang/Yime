# PR #77：消息泵内取消修复

2026-10-22，回应[审阅项 r4346286083](https://github.com/tsaanghwang/Yime/pull/77#discussion_r4346286083)。确认问题：`previewUp` 已将触点移出 map，但宿主消息泵可以在执行前收到 `WM_CANCELMODE` 或意外 `WM_CAPTURECHANGED`；旧版只有会话/目标票据检查，取消动作不会改变这两个身份，可能继续执行旧 Home 或重新开启选区。`hostSink` 的第二次消息泵也有同类窗口。

修复为 UI 取消世代：每次 `cancel()` 增加世代，触点在登记时固定当前世代，UP 消息泵后再次核对；发送闭包另固定当前世代并在最终消息泵后核对。旧触点或旧输出不会执行/发送，保持既有失败停止机制。不修改布局、键身份、颜色或产品运行时。

新增 `TestNavigationCancellationDuringHostMessagePumps`：自有隐藏窗口使用真实窗口过程，向线程消息队列投递两类取消消息，在 UP 泵覆盖 Home 与选区开关，在发送泵覆盖 Home，共六个场景；发送端为替身，没有 OS 宿主输入。测试锁定线程并恢复窗口过程。

使用进程局部 Go `-overlay` 替换回修复前 `84ac0d24` 的三个桌面 UI 源文件，保留新测试，六个场景全部复现失败，见 [pump-before.log](pump-before.log)。当前代码的桌面/几何完整测试通过，见 [pump-after.log](pump-after.log)。该 overlay 仅用于桌面测试的反例验证，没有全局 GOFLAGS 或产品覆盖。

初版 `df70abc6` 的 CI run 39749274057、ZIP 与包记录保留为历史，不再作为真人验收对象；修复提交 `ceed533f` 的新 CI 包已核验，见[固定交付](CI_DELIVERY.zh-CN.md)。真人手指、笔、真实应用及 ARM64 原生结果仍待记录。
