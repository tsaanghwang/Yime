# H02 触屏辅助导航开发记录

2026-10-22。受影响范围：独立桌面键盘实验；产品 YimeCore / Rime/PIME 运行时均未改动。基线是 PR #76 的 main 合并提交 `3cae8c6b6f8a0af25285cfd8116cb7a19e9c43bd`，工作分支 `codex/touch-keyboard-h02-navigation`。

下文记录首次本地开发验证时的快照。后续已提交/推送 `df70abc6` 并创建 PR #77；固定 CI 包及核验结果另见 [CI 交付记录](CI_DELIVERY.zh-CN.md)，不改写下文本地包当时的 dirty 身份。

## 检查结论与实现

现有 18u 主区 100 键没有 Left/Home/End，但 `preview.apply(local)`、`emitEdit`、目标世代/事件去重及 Windows 虚拟键发送已经支持导航与 Shift 选区。现有预览编辑器具备 Unicode 码点、选区替换/删除、全文 Home/End。故只补桌面辅助控件，不修改键盘 JSON、编码源、键身份、几何、颜色、profile 或产品协议。

五个控件放在现有 y=240–290 输出栏右侧，主区起点 y=300、18u/342.90 mm 不变。绘制和命中共用矩形。按下记录会话版本与目标票据，原区域抬起才执行；移出返回、重复 UP、旧版本、旧目标、重叠触点和发送失败有保护。

“选区”是辅助导航专用开关，每次导航只发送一个独立 Shift+导航事件，不维持系统修饰键；字符/退格等其他操作关闭它。活动及暂停的中文组合禁止导航；没有隐式确认。预览 Home/End 仍为全文首尾，宿主原生 Home/End 的语义由应用决定。辅助栏只在中文预览/默认宿主入口出现，冻结旧英文入口未扩展。

## 本轮验证

| 检查 | 结果与证据边界 |
|---|---|
| Go 桌面、几何、共用会话、实验及产品 codemode | 343 个 test/subtest pass 事件，无失败；[结构化结果](go-tests.json)。lab 命令包无测试文件；符号链接权限测试、可选完整语料 HTTP/preview 测试跳过，不能算通过 |
| 新增导航回归 | 7 个顶层测试及参数子项：顺序选择/缩小/替换/删除、模拟 WM_TOUCH 与笔兼容鼠标路径、移出/取消/重复 UP、组合/暂停/旧状态/重叠、目标门禁与唯一事件、失败停止、命中和几何边界 |
| `python -X utf8 prototypes/touch-terminal/validate.py` | 27 Python + 44 JavaScript 通过；生成数据和语法通过 |
| `generate_ascii_layout.py --check`、`generate_touch_keyboard_profiles.py --check` | 通过；实验投影、134 键及冻结 17u/23u profile 原样保留 |
| 新 x64 完整便携包 | [包检查](package-check.json)通过：仓库外中文/空格路径、空 cwd、每模式 2,457,604 索引记录及“你”内存确认、默认 18u/100 键与显式全盘、缺失/篡改资源/外部路径拒绝、私有字体离屏渲染 |
| 视觉检查 | [渲染图](portable-preview.png)中辅助按钮完整显示、输出栏与盘面无重叠；主区未移动/缩放。仅离屏渲染，不代表触点可用性验收 |
| ARM64 | 新完整包交叉构建通过；无原生执行结论 |

首次沙箱内 Go 检查因沙箱 TEMP 中索引重命名 `Access is denied` 失败；仅把该检查进程的 TEMP/TMP 定向仓库内专用临时目录后原测试通过。网页总检首次受沙箱临时文件/回环网络限制；按同一原命令在沙箱外通过。包检查首次资源与内存部分运行后，在沙箱内加载 GDI 进程私有字体失败；同一包在沙箱外完成全部检查和离屏渲染。未弱化检查或修改系统环境变量，未安装字体。

未运行向 OS 发送输入的 `--self-test`/`--host-self-test`；导航发送测试使用替身。没有本次自有 EDIT、记事本/Word、真人手指/触控笔或 ARM64 原生通过结论。SendInput 不能原子绑定 HWND 的既有限制仍在。

## 包与后续验收

[本地包身份](package-identity.json)固定 x64/ARM64 路径、exe/manifest/资源哈希以及桌面源码文件哈希，`sourceChanges:true` 明确表示基线加未提交开发修改。没有创建新 CI run/artifact 或交付 ZIP。后续提交、CI 构建和外部交付应另建身份，不用本地路径充当 GitHub 交付，也不覆盖 #74/#76 历史包。

按[新版验收指南](../../../../../prototypes/touch-terminal/desktop/ACCEPTANCE_18U.zh-CN.md)与[新结果模板](RESULT_TEMPLATE.zh-CN.md)，在本次新包分别记录手指、纯笔及每个真实应用。新增 P11 和 H02-N1–N5 覆盖导航/选区；辅助物理键盘、鼠标、全盘/侧区或笔加手指结果不能计入相应纯覆盖。所有真人项均待记录。

未安装或修改已安装/默认输入法、注册、系统字体或用户数据；旧包、旧证据、产品字典和冻结候选保持原样。
