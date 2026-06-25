# 普通用户帮助

这组文档面向普通试用者，整理当前外挂输入法原型最常用的启动、操作、词库维护和排错说明。

如果你是第一次使用，先看这一页；需要更细步骤时，再进入下面几个专题页。

## 当前定位

- 这是一个 Windows 桌面输入法原型，不是系统级 TSF / IMM32 输入法。
- 它已经可以在外部窗口里组合输入、显示候选、选词和回贴。
- 推荐先在记事本、VS Code 普通文本区等简单环境试用。

## 推荐阅读顺序

1. [快速开始](quick-start.md)
2. [菜单与用户词库](menu-and-lexicon.md)
3. [故障排查](troubleshooting.md)

## 最短说明

- 推荐启动：`python -m yime.input_method.app`
- 等价启动：`python run_input_method.py`
- 首选候选可用 `Space`、`Enter` 或鼠标左键直接选择。
- 第 2~5 候选可依次用 `` ` ``、`-`、`=`、`\`，也可用鼠标左键直接选择。
- 任意候选都可先用方向键移动高亮，再按 `Space` / `Enter` 确认；也可直接鼠标左键点击。
- 当每页候选数设为 6~9 时，第 6~9 候选没有单独快捷键，建议用鼠标左键或方向键定位后再按 `Space` / `Enter`。
- `Home` / `PgUp` / `PgDn` / `End` 用于翻页。
- `ESC` 退出当前组合，`Ctrl+Q` 关闭窗口。
- 待命状态下，可点“音”图标或按当前唤起热键恢复。

## 常见问题入口

- 提示“将使用手动输入模式”：先看 [故障排查](troubleshooting.md)
- 要维护用户词库：先看 [菜单与用户词库](menu-and-lexicon.md)
- 想知道当前是不是正式系统输入法：先看本文“当前定位”

## 相关文档

- [安装指南](../install/INSTALLATION_GUIDE.md)
- [使用说明](../USAGE.md)
- [常见问题](../FAQ.md)
- [实现边界](../project/INPUT_METHOD_SOLUTION.md)
- [反查与用户词库详细说明](../REVERSE_LOOKUP_AND_USER_LEXICON.md)
- [词语调序规则说明](../LOCAL_PHRASE_PRIORITY_RULES.md)
