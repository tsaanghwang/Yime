# 居中省略号本地开发包（2026-10-29）

用户最终选择三次中点点击转为单码点 `⋯`（U+22EF），六次为 `⋯⋯`，允许等待第三次输出。此前“不合并”答复及临时U+2026目标已由本次决定取代。规则见[当前规则](../../../../../prototypes/touch-terminal/desktop/PUNCTUATION_RULES_2026-10-29.zh-CN.md)。

共用会话实现前两次暂存并单独显示计数，第三次才提交；网页与桌面统一，已有宿主文字不被回删。取消/失焦/关闭/语言切换丢弃暂存，退格先撤销暂存，主区其它文字/编辑先补出剩余中点。侧literal旁路独立。

[身份](package-identity.json)与[开发检查](DEVELOPMENT_RESULT.json)已固定。r2 exe SHA-256：`6ecd2bc60e9959c054ca09c153d919f6759c67bcaed4c088bb643e3bc4f0a583`。本地未提交源码构建，非CI产物；旧c35包及其物理证据保留，不能继承到新包。

当前旧包第100组顿号/破折号仍待用户结果。收到后再退出旧键盘、使用 `.generated/touch-validation-20261025-x64-16inch/Start Centered Ellipsis Keyboard.cmd` 启动新包，执行准备的101两项。没有在本轮自动替换现有键盘窗口。
