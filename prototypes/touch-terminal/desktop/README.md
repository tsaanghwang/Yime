# Windows 桌面触摸键盘：18u 开发基线

2026-10-20：以 **18u 主区**为样机基准，P1/P2 随 #71 合并，P3 已完成本地中文受控预览。新包的 `Start Keyboard.cmd` 与 `Start Main Area.cmd` 均打开 18u，原全盘用 `Start Full Keyboard.cmd`；旧包入口不追溯改写。17u / 23u 派生配置冻结为候选。按[18u 开发计划](DEVELOPMENT_PLAN_18U.md)推进，手指/触控笔验收准备暂缓。

这是独立、无需安装输入法的桌面实验程序。它读取现有 CN/EN134 盘面，
以不激活窗口承接触摸，向当前目标输入框发送英文文本、编辑键和快捷键。
显式 `--preview` 入口则使用共用中文引擎，组合和候选确认只写入本窗口文本区。中文跨应用提交待 P4，完整中文便携包待 P5。

## P3 中文受控预览（源码开发入口）

完整实验词典已按原型 README 生成时，在仓库根目录执行：

```text
go -C go-backend run ./cmd/yime-touch-keyboard --root .. --numeric-zones none --remove-gutters --preview --data-dir ../.generated/ascii-keyboard-134/data
```

初次加载会校验完整词典哈希并生成临时索引，退出即清理。缺少资源或身份不符时失败，不查找已安装输入法。现有英文便携包没有这些词典和预览字体资源，不能把上述源码入口视为 P5 交付。

预览支持三编码模式、CN EN、候选点击/分页、原始组合显示和本地文本编辑。CN EN 同时切换标点；中文始终显示 CN，英文时 Layout 可切换 CN/EN 键帽，偏好在本次运行内保留。字形/ID 按钮切换基础音元字形显示，私有字体不安装到系统。更多步骤与编辑范围见[中文使用帮助](USER_GUIDE.zh-CN.md)。

预览不会向其他应用输入，输出只在内存中，关闭即丢弃；不能与 `--self-test` 或 `--check-data` 混用。移出候选/按键再返回仍取消；候选版本变化后的旧触点和重复抬手均不提交。

可重复运行完整语料检查（不是手指/笔验收）：

```text
go -C go-backend test ./cmd/yime-touch-keyboard -run TestPreviewCompleteCorpus -count=1 -v -args -desktop-preview-integration-root C:/dev/Yime
```

路径需换成实际检出目录。可选 `-desktop-preview-evidence-dir <新目录>` 导出受控候选截图和 JSON，不覆盖历史证据。

## 默认英文跨应用入口

- 默认主区18u、100键、342.90毫米；可选全盘24.75u、134键、471.4875毫米。每u为19.05毫米中心距。
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
新包默认及仅主区CMD共用 `profiles/main-only.json`；另提供原全盘、保留左区、保留右区及冻结候选入口。直接运行 exe 的命令行默认仍为原全盘，需主区时显式传 `--numeric-zones none --remove-gutters` 或主区 profile。
所有接口只改变物理几何，不修改按键身份、ASCII编码或字典。

| 配置 | 宽度u | 按19.05毫米/u的宽度 |
|---|---:|---:|
| 当前完整134键 | 24.75 | 471.49毫米 |
| 去三条共同中缝、保留两侧 | 24 | 457.20毫米 |
| 去中缝、仅保留一侧 | 21 | 400.05毫米 |
| 去中缝、不保留两侧 | 18 | 342.90毫米 |
| 便携目标主区 | 17 | 323.85毫米 |

当前原主区去缝后仍为18u。用户提供的 `design/yime-cn-134k-23u-keyboard-layout.json` 另生成了可用的17u主区（323.85毫米）和23u全盘（438.15毫米）配置；生成器按完整键面和区域匹配稳定键身份，不按发生变化的KLE行号硬配。

冻结候选的启动入口 `Start 17u Main Area.cmd` 和 `Start 23u Keyboard.cmd` 保留，不作为本轮开发或验收基准。普通键最小1u，仅N26、N27移到下一行两端，其余音元保持原行与左右顺序。英文视图沿用原键身份的映射；未新增音元编码或臆造英文映射。

**详细操作见[中文使用帮助](USER_GUIDE.zh-CN.md)**，程序顶部也有Help按钮。原盘面视图和英文视图当前均只输出英文；灰色“中文未接入”不是可用的中文开关。截图或启动时可用 `--key-view original` 预览原盘面。

2026-10-19 用户报告当前27英寸屏未按缩放按钮时100毫米标尺与实体尺一致。保留默认换算，不把这一次量尺结果推广为其他屏幕校准或触摸接受。

## 验证入口与范围

```text
go -C go-backend test ./internal/touchkeyboard ./cmd/yime-touch-keyboard ./cmd/yime-keyboard-lab ./internal/keyboardlab
YimeTouchKeyboard.exe --root . --self-test
```

self-test只创建本进程的临时原生EDIT目标，检查真实SendInput和前台焦点，不操作现有文档。
它不是记事本/Word实测，也不是手指、触控笔或ARM原生硬件验收。后台自动启动自检时，Windows可能不允许临时测试窗口取得前台，此时程序退出且不发送输入；正常试用应由你先在目标应用点好光标。
ARM64包只交叉构建，待相应真实机器到位后再做原生验证。

## 中文会话开发检查

P2 新增桌面进程内数据检查入口，复用网页的 `internal/keyboardlab`。检查要求显式指定独立实验词典目录，核对投影与三份词典哈希、构建临时索引，并分别打开、清空、关闭三模式会话；退出时释放会话和索引。不打开键盘窗口，不向应用发送输入，也不表示桌面中文界面已经接通。

在仓库根目录、完整实验词典已按原型 README 生成后运行：

```text
go -C go-backend run ./cmd/yime-touch-keyboard --root .. --numeric-zones none --remove-gutters --check-data --data-dir ../.generated/ascii-keyboard-134/data --data-report ../.generated/touch-keyboard-data-check.json
```

包内 exe 也支持同样的检查选项；GUI 子系统下应给 `--data-report` 指定报告文件。当前英文包不附带完整中文词典，不能仅凭该包执行成功的数据检查。无清单、错误投影、哈希不匹配或不完整词典均失败，不回退到已安装产品。`--data-dir` 必须与 `--check-data` 或 `--preview` 显式组合，不会暗中开启中文跨应用输入。

Windows接口依据：[不激活窗口](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)、
[WM_TOUCH](https://learn.microsoft.com/en-us/windows/win32/wintouch/wm-touchdown)、
[SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput)。
