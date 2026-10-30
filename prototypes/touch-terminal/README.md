# Yime 134 键双布局虚拟样机

影响范围：隔离的 ASCII 概念键盘实验，分支 `codex/ascii-physical-layout-experiment`。
候选来自真实 Go YimeCore 的实验词典，提交只进入本页文本框。

## 当前盘面与输入

- CN 来源：`design/yime-cn-134k-24u-keyboard-layout.json`；EN 来源：
  `design/yime-en-134k-24u-keyboard-layout.json`。两者均为 134 键，
  24.75 × 7.25 KLE u，位置、尺寸和 ISO 矩形并集完全相同。
- `CN EN` 同时切换输入语言与标点模式。切到英文时保留、暂停中文组合，回中文可继续。
- 英文模式下 `Layout` 在原盘面与标准英文盘面之间切换，记住选择；回中文显示 CN，
  再进入英文恢复上次选择。选择也保存在本浏览器的 localStorage。
- EN 字母下档为小写，上档为大写。新增的 23 个空白键暂时禁用；图标系统键继续仅示意。
  禁用状态是生成数据中的明确字段，与 `#d0b2e2` 颜色无关。
- 切换复用键节点及图例节点，只更新图例、动作和启用状态；不读取布局文件、不重建会话、
  不改变颜色。当前保留 CN 草案的底色；两套设计定型后再统一修改颜色。
- 主区数字 1–9 有候选时选择当前页对应项，无候选时直输；非空页缺少该序号则无操作。
  侧数字区直输 ASCII 数字和运算符，不编码、不选词、不转换标点。左右 Num Lock 独立，
  编辑态 5 无操作。该实验例外不改变正式产品的 Shift+1–9 规则。
- 虚拟 Shift 可点按一次或按住再点另一键；按下时捕获字符层。切换布局会取消未完成触点、
  清除 Shift；ANSI 兼容通道始终按 event.key 输入，不随虚拟盘面再映射。
- 75 个输入 ID 全部启用。M25/M26/M27 的编码分别是 B/M/P；R01–R03 仍复用 M22–M24。
  大小写与音元编码保持区分，Caps Lock 仅示意。
- 软件的“字面符号入口”开关默认关闭。关闭时预留 ASCII 标点入口按普通编码规则处理；
  开启时仅不带 ID 的 32 种预留标点入口直输，按当前标点模式输出，保留中文组合。
  带 ID 的编码入口不受此开关影响。六个明确的 Unicode 符号入口为 ·、—×√÷。
  连续两个字面 — 得到 ——，破折号保持原规则。按2026-10-29用户接续决定，中点键第三次显示 …（U+2026）与 ⋯（U+22EF）两个候选；连续到六次显示 …… 与 ⋯⋯，选定后才提交。网页与桌面共用规则。
  点候选或主区1/2选择，Space/Enter明确确认第一项；普通文字、导航或编辑不会代选。已有ASCII组合与字典候选在会话内保留，符号选择后恢复。最多暂存六次，第七次须先选择或取消；四/五次时选定一个完整三点组后，余下一/两次继续暂存。
  不足三次时，主区后续文字或编辑先补出剩余字面中点。退格先撤销暂存点击，取消/语言切换/会话关闭丢弃暂存，侧区literal旁路独立。

## 运行与检查

在本实验分支根目录执行：

```text
python -X utf8 tools/generate_ascii_layout.py
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:/YimeData/runtime-input-v1/pinyin_hanzi.db --output-dir .generated/ascii-keyboard-134
go -C go-backend run ./cmd/yime-keyboard-lab --root .. --port 8766
```

打开 <http://127.0.0.1:8766/>。Python 只用于离线生成；运行输入由 Go 引擎负责。
完整词典从已授权、内容锁定的独立数据库重投影，不读取其他 Git 仓库，不替代生产词库。
75 个 ID 的唯一可编辑编码投影仍是 `prototypes/touch-terminal/encoding/manual_key_layout.json`；
导入器核对 KLE 标注，不会反向覆盖投影。生成盘面与 Go 索引均核对布局摘要和词典 SHA-256。

```text
python -X utf8 tools/generate_ascii_layout.py --check
python -X utf8 prototypes/touch-terminal/validate.py
python -X utf8 -m pytest tests/yime/test_ascii_layout.py tests/tools/test_resolve_manual_key_layout.py tools/test_ascii_keyboard_overlays.py -q
go -C go-backend test ./cmd/yime-keyboard-lab ./internal/keyboardlab ./input_methods/yime/codemode ./input_methods/yime/systemlexicon
```

真实完整词典的 HTTP 验证使用 `-keyboard-lab-integration-root` 指定本 checkout 的绝对路径。
浏览器回归为 `browser-smoke.js`，必须连接当前 Go 服务。软件证据见 [本轮交接](HANDOFF.md)。

## 实屏记录

触摸屏已由用户确认到位。可分别在 CN 盘面覆盖 134 键、EN 盘面覆盖 111 个启用键，
并检查双指 Shift、快速切换后的首键、拖出取消以及连续中英文输入。
导出格式 6 记录盘面身份、英文偏好、字面入口状态、触点和切换计时。
“布局切换 → 下一帧”是浏览器处理至 requestAnimationFrame 的代理指标，
不是手指接触到屏幕发光的端到端延迟。

鼠标、CDP 模拟触摸、真人手指/触控笔分别记录。自动化导出始终标为
`hardwareAcceptance:false`，真人试用结论须依据实际设备与用户确认补充。
本轮不安装输入法、不更改系统默认输入法、不注入全局按键或读取个人学习数据。

## 历史

`design/keyboard-layout.json` 等 132/134 草案保留为历史设计；当前运行只使用上述两份已选定文件。
既有 60/129/138 键测试和旧 `.generated/ascii-keyboard*` 目录保留自己的日期与范围，
不作为当前 134 键真人触屏验收。检查不一致的原始积压状态见
[基线保存说明](CHECKPOINT_2026-10-18.md)。

## 全尺寸与桌面阶段（2026-10-19）

网页新增19.05毫米/u定尺、100毫米卷尺参考线和独立校准记录，导出格式为7。
默认屏幕宽597.73毫米是当前27英寸16:9估算，实际尺寸需按卷尺校准。
键盘保持物理键距，宽度不足时仅在盘面区域滚动。校准按显示尺寸/DPR指纹保存，换屏或缩放后重新复核。

独立桌面触摸键盘可向目标窗口发送英文、编辑键和快捷键，见[桌面说明](desktop/README.md)。
去任一侧/两侧数字编辑区及共同中缝的接口已可用；17u主区保留独立几何入口，尚待审定排布。
网页仍仅处理页内文本，安装产品不变。
