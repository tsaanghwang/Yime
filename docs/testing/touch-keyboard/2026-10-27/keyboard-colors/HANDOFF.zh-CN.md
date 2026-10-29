# 深灰白字配色试用

2026-10-27。用户报告语言键修复版太亮、看不清楚，并提供微星电脑上Windows自带触摸键盘的两张截图。已从原PNG取样，见[参考色](REFERENCE_COLORS.json)；截图含轻微颜色变化，采用代表值做不透明主题，不声称复现系统透明、壁纸混色或屏幕实际亮度。

| 用途 | RGB |
|---|---|
| 背景 | #212020 |
| 普通键面、候选 | #3B3A3A |
| 功能键、工具栏 | #313131 |
| 字符 | #FFFFFF |
| 按下/修饰开启、当前模式 | #50634F |
| 输出区 | #292929 |

原盘面颜色和语义数据未编辑。`--theme dark`只改变绘制；`--theme original`及省略参数保留原配色。深色模式统一灰色，不再通过原色组区分音元；禁用、字符、动作、语言和Layout行为继续由原数据决定。语言或Layout切换不改变主题。现有18u/100键、58.8校准参数、字体与命中位置保持；没有修改Windows主题、亮度、安装输入法或用户数据。

新独立本地包：`.generated/touch-dark-palette-20261027-amd64`，x64，`sourceChanges:true`，源码基线9adc3cdd9634e0258b58c9a8945b3497fc8777ad；不是CI交付。exe SHA-256：`e59bac7e4bc6c6e697324808136a6f84709df52a64595588d97779dcf58e1fa7`。完整[包身份](package-identity.json)记录源码及载荷哈希。相对语言键版，载荷变化仅exe、指南与包含指南哈希的resources.json；其余26个载荷（含布局、profile、私有字体、三模式隔离词典）一致。

相关Go回归、完整包移出仓库/空工作目录三模式和资源拒绝检查已通过，见[包检查](package-check.json)。[渲染检查](RENDER_CHECK.json)确认新包原配色与上一包在相同参数下逐像素一致，两主题尺寸同为2830×1442，错误主题被拒绝。开发者查看了[深色渲染图](new-dark.png)，不是物理触摸结果。白字对普通键面的计算对比度约11.34:1，对高亮面约6.48:1；不能据此替代该屏幕的可读性试用。

先关闭旧预览（关闭会丢弃预览内存文字），再双击[深色预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Dark Preview.cmd>)。需要对照时关闭当前预览再开[同包原配色预览](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Original Colors Preview.cmd>)。宿主入口另备[深色键盘](</C:/dev/Yime/.generated/touch-validation-20261025-x64-16inch/Start Dark Keyboard.cmd>)，当前先做预览可读性试用，不因入口存在而增加宿主通过项。

真人待确认：背景/键面亮度、白色字符、键面边界、Shift单次高亮是否清楚。在EN预览依次点Shift、a、a，核对高亮与Aa；若太亮/太暗或字符不清，记录具体区域再调整。

P10原有250项手指反馈保留原包身份，见[当前测试进度](../../2026-10-26/p01-p10/RESULT.zh-CN.md)。这次换色不自动把它们提升为新包通过；剩余CN150项与两支笔各400项继续待记录。下一组尚未准备，先接续本次可读性反馈。
