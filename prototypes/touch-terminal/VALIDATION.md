# 本地验证记录

日期：2026-09-22。基础提交：`0ab86312`；目标分支：`codex/touch-terminal-prototype`。影响范围：共享源数据的独立浏览器原型；未运行安装器、注册宿主、系统输入模拟或已安装产品维护。

环境：Windows 11 build 26200，Python 3.14，Node v24.15.0，Playwright CLI 0.1.21 驱动本机 Chrome。服务仅监听 `127.0.0.1:8765`。

| 检查 | 结果 | 可重复入口 |
| --- | --- | --- |
| 生成数据与来源摘要 | 通过；60 ID / 58 投影，三个规范样例 | `python -X utf8 prototypes/touch-terminal/generate_data.py --check` |
| Python 数据与静态服务边界 | 7 项通过 | `validate.py` |
| JS 协议/状态与几何模型 | 18 项通过 | `validate.py` |
| 页面与浏览器脚本语法 | 通过 | `validate.py` |
| 浏览器交互 | 7 组通过，无页面 JS 异常，无外部网络请求 | `browser-smoke.js`（运行方式见 README） |
| 现有布局语义锁 | 通过 | `python -X utf8 tools/check_layout_change_lock.py` |
| 现有仓库数据边界 | 通过 | `python -X utf8 tools/lexicon/check_repository_data_boundary.py` |

浏览器检查逐一点击全部 60 键，验证每次抬起只输入一次；共享物理投影仍保留不同音元 ID。逐键输入规范样例后测试退格/恢复候选、Shift+2选择、Enter确认及空退格保留已确认文本；候选出现时裸数字继续组合。13 项候选正确分页为 9+4，点选不自动确认，焦点返回键盘后快捷键有效。

另检查拖出再返回原键不输入、单键 Space 激活、合成失焦事件清空未确认组合、固定 20 目标鼠标点按及 JSON 下载。浏览器模拟触摸验证 N26 一次 tap、CDP `touchCancel` 和 390px 窗口横向滑动取消输入；1440px 与 390px 截图均已查看，窄窗口没有整页横向溢出。小视口是桌面浏览器仿真，不是新硬件目标或原生触屏执行。

本机截图和导出位于忽略目录 `output/playwright/touch-terminal-desktop.png`、`touch-terminal-narrow.png`、`touch-terminal-session.json`。这些是辅助软件证据，正式接续入口始终是本分支中的源码、生成摘要、验证脚本及本文，不以临时共享目录交付。

自动脚本的 20 次鼠标目标全部命中仅说明坐标与处理链可用，**不能作为人体误触率**。未测：真实触屏与手掌干扰、contact/release-to-photon 延迟、连续输入效率、真实 Go/Broker 解码、宿主写入、x64/x86/ARM64 原生兼容性。误触分布和延迟阈值仍是 HARDWARE.md 中明确标注的假设/目标。

CI 的原型工作流重复 `validate.py`，没有浏览器或硬件验收；具体提交状态以 GitHub 对应分支运行记录为准。本轮无需输入法安装包，也不要求测试机执行历史安装步骤。
