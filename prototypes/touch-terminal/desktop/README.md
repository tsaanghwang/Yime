# Windows 桌面触摸键盘：第一阶段

这是独立、无需安装输入法的桌面实验程序。它读取现有 CN/EN134 盘面，
以不激活窗口承接触摸，向当前目标输入框发送英文文本、编辑键和快捷键。
网页样机继续承担中文引擎、布局与触点实验；桌面程序本阶段尚未接中文组合。

## 当前可用

- 全盘24.75u，每u为常见全尺寸键盘的19.05毫米中心距，整盘471.4875毫米。
  这是键距，键帽边缘保留间隙。默认597.73毫米屏幕有效宽度来自当前27英寸16:9估算。
- 100毫米参考线与卷尺校准；不根据Windows缩放百分比推定真实尺寸，也不随窗口变窄缩键。
- 英文小写/大写、标点，单次或双指Shift，Ctrl/Alt组合，退格、回车、空格、Tab、F1–F12。
- 左右数字/编辑区独立切换，方向、Home/End、PgUp/PgDn、Insert/Delete；编辑态5无操作。
- 目标窗口及焦点在按下到释放之间变化时取消本次输入。移出键面再返回仍取消。
  ISO缺角不作为可命中区域。修饰键按需成批发送，窗口关闭不遗留系统按键状态。
- Ctrl+Alt+K呼出/隐藏；窗口顶部可移动。Caps、系统键、Pause和CN EN暂未接入并作示意。

## 本机试用

源码根目录执行：

```text
python -X utf8 tools/build_touch_keyboard_desktop.py
```

打开生成目录 `.generated/touch-keyboard-desktop/`，双击 `Start Keyboard.cmd`。
在记事本等应用中先点好文本光标，再触摸键盘。程序不更改当前默认输入法或已安装产品。
英文字符通过Unicode键盘事件提交，编辑与快捷键通过虚拟键事件提交；必须分别观察真实应用接受情况。
受Windows输入完整性级别约束，不能据此声称所有应用或管理员窗口兼容。

**先量100毫米线段。** Ruler −1%/+1%调整的是像素到毫米的换算，u仍为19.05毫米。
需要精确换算可重启时给出此前参考线的实际长度，例如：

```text
YimeTouchKeyboard.exe --root . --screen-width-mm 597.73 --ruler-observed-mm 98.5
```

校准目前在当前进程有效，重启后需使用相应参数。换屏、旋转或缩放后重新复核。
另一台16英寸机器应填写其有效显示宽度，不能沿用27英寸估算。

## 便携形态接口

```text
--numeric-zones both|left|right|none
--remove-gutters
--profile <JSON>
```

同一可执行文件可隐藏任一侧或两侧数字/编辑区，并移除左右区缝与中间共同的0.25u空带。
生成目录内的四个CMD分别提供全盘、仅主区、保留左区、保留右区入口。
所有接口只改变物理几何，不修改按键身份、ASCII编码或字典。

| 配置 | 宽度u | 按19.05毫米/u的宽度 |
|---|---:|---:|
| 当前完整134键 | 24.75 | 471.49毫米 |
| 去三条共同中缝、保留两侧 | 24 | 457.20毫米 |
| 去中缝、仅保留一侧 | 21 | 400.05毫米 |
| 去中缝、不保留两侧 | 18 | 342.90毫米 |
| 便携目标主区 | 17 | 323.85毫米 |

当前原主区去缝后仍为18u。用户提供的 `design/yime-cn-134k-23u-keyboard-layout.json` 另生成了可用的17u主区（323.85毫米）和23u全盘（438.15毫米）配置；生成器按完整键面和区域匹配稳定键身份，不按发生变化的KLE行号硬配。

启动包中的 `Start 17u Main Area.cmd` 或 `Start 23u Keyboard.cmd` 可试用。普通键最小1u，仅N26、N27移到下一行两端，其余音元保持原行与左右顺序。英文视图沿用原键身份的映射；未新增音元编码或臆造英文映射。

**详细操作见[中文使用帮助](USER_GUIDE.zh-CN.md)**，程序顶部也有Help按钮。原盘面视图和英文视图当前均只输出英文；灰色“中文未接入”不是可用的中文开关。截图或启动时可用 `--key-view original` 预览原盘面。

2026-10-19 用户报告当前27英寸屏未按缩放按钮时100毫米标尺与实体尺一致。保留默认换算，不把这一次量尺结果推广为其他屏幕校准或触摸接受。

## 验证入口与范围

```text
go -C go-backend test ./internal/touchkeyboard ./cmd/yime-touch-keyboard ./cmd/yime-keyboard-lab
YimeTouchKeyboard.exe --root . --self-test
```

self-test只创建本进程的临时原生EDIT目标，检查真实SendInput和前台焦点，不操作现有文档。
它不是记事本/Word实测，也不是手指、触控笔或ARM原生硬件验收。后台自动启动自检时，Windows可能不允许临时测试窗口取得前台，此时程序退出且不发送输入；正常试用应由你先在目标应用点好光标。
ARM64包只交叉构建，待相应真实机器到位后再做原生验证。

Windows接口依据：[不激活窗口](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)、
[WM_TOUCH](https://learn.microsoft.com/en-us/windows/win32/wintouch/wm-touchdown)、
[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)。
