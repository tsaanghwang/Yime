# Yime 概念实体键盘实验

这是新布局的 **129 键实体盘面虚拟模型**。标准 ANSI 键盘输入和屏幕点按都通过
同一 ASCII/控制动作接口，进入真实 Go YimeCore 引擎；候选只提交到本页文本框。
不是系统输入法安装，也不使用原来的三个固定候选演示。

用户已确认本轮仅交付基础键盘实验。正式融合儿化原用的15个大写载体与新基础映射冲突，
留待下一阶段决定新键位/共键关系；本服务不加载正式语流别名、个人词库和学习数据。
它不会替换当前正式输入法。

两套布局分支并行保留：旧布局继续位于 `codex/current-readiness-delivery-20260927`，
本样机位于 `codex/ascii-physical-layout-experiment`。本样机的标准ANSI通道只要求功能正确、能输入，
不考核输入速度、Shift次数或手感；新布局的效率和实用性设计面向概念实体键盘及其虚拟盘面。
各分支使用自身的键位源和配套生成词库，不混用，也不自动用新布局覆盖旧布局。

## 运行

在此分支仓库根目录执行（Python 仅用于离线生成）：

```text
python -X utf8 tools/generate_ascii_layout.py
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:/YimeData/runtime-input-v1/pinyin_hanzi.db
go -C go-backend run ./cmd/yime-keyboard-lab --root .. --port 8765
```

生成命令读取已授权的独立内容锁定数据库并校验其 SHA-256，不读取其他 Git 仓库。
实验词典位于忽略目录 `.generated/ascii-keyboard/data`。若采用另一个输出目录，
生成时传 `--output-dir`，启动时传 `--data-dir` 指向其中的 `data`。
服务启动时核对布局摘要、停用集合及三份词典摘要，随后打印本机打开地址。
初次启动会编译三份索引，需要等待服务提示 ready。

打开 [本地键盘实验](http://127.0.0.1:8765/)。
直接双击 HTML 或旧的 Python 静态服务不能运行真实输入引擎。

## 怎样试用

1. 先切到英文输入模式，再选可变码、全码或简码，点击键区或本页文本框获取输入焦点。
2. ANSI 键盘用常规字母及 Shift+字母输入大小写；虚拟盘面的字母按钮固定输出所标字符。
3. 候选列表和虚拟盘面的九个紫色候选键均标为 **1–9**，点击直接选择，不需要 Shift。
   冻结的 KLE 草案仍保留原图例；生成的 `displayLabels` 仅调整概念样机显示，不改变动作或编码真源。
   按2026-10-09用户决定，标准 ANSI 主键区也直接按 1–9 执行同一种选择动作。
   Shift+1–9 恢复输出 `! @ # $ % ^ & * (`，不再选词；有未确认编码时保留组合并提示先选词或取消，
   不擅自确认候选。标点写入本页文本的光标/选择范围，不进入编码或发送给其他窗口。
   无对应候选时不做操作，不退回数字编码；这项变更仅用于此实验页面，未更改正式输入法。
   0 和小键盘数字仍追加编码；新音元编码不占用数字，因而数字编码通常无候选，可退格或取消。
4. Enter/Space 在有候选时确认首选；空组合时在本页插入换行/空格。
   Backspace、Escape、PageUp/PageDown 和未加 Shift 的主键区 -/= 用于退格、
   取消和翻页；小键盘减号仍是普通 ASCII。
5. 失去窗口焦点取消未确认组合。切换码制也取消旧组合。没有全局按键注入。
6. Shift/Ctrl/Alt、系统键和功能键暂以「仅示意」显示，未模拟固件修饰键状态或
   Windows 快捷键。固定大小写编码键不依赖屏幕 Shift 状态。
7. 「全键覆盖」「随机目标」只测键位命中，不向引擎输入。
   导出记录区分浏览器事件与真实触屏验收，不能把鼠标/自动化冒充手指测试。

## 唯一真源与派生物

- `internal_data/manual_key_layout.json`：唯一可编辑的音元 ID→ASCII 投影和停用策略。
- `design/concept-129.kle.json`：用户草案快照；拥有物理位置、尺寸、颜色及图例。
  图例中的字符须与唯一真源一致，导入器发现冲突就失败，不反向覆盖投影。
- `data/physical-layout.json`：上述两者生成的完整盘面，禁止单独维护映射。
- 保留 60 个语义 ID、57 个活动 ID。M28/M25、M29/M26、M30/M27 分别共用
  `[`、`N`、`]`；M25–M27 在键面划线标记停用，完整音节含它们时先过滤，再生成三模式。
- `layoutId` 标识 ASCII 投影和停用策略；`touchTemplateId` 标识具体虚拟盘面。
  KLE 的 y 偏移与 a 对齐按[上游格式](https://github.com/ijprest/keyboard-layout-editor/blob/master/serial.js)解析。

## 验证

```text
python -X utf8 tools/generate_ascii_layout.py --check
python -X utf8 prototypes/touch-terminal/validate.py
go -C go-backend test ./cmd/yime-keyboard-lab
```

真实全词库 HTTP 验证见服务的 `README.md`。浏览器回归脚本是
`browser-smoke.js`；必须连接当前 Go 服务，不得使用旧 fixture 代替。
源码自测、浏览器键盘事件、真实 ANSI 按键、手指触屏、Windows 注册宿主分别记录。

## 范围与历史

详细实施顺序见 `../../docs/project/ASCII_PHYSICAL_LAYOUT_PLAN.md`。
本分支先验证共享离线源和 YimeCore 独立实验窗口；未变更默认输入法、安装目录、
Rime/PIME 用户数据或系统级输入行为。正式交付仍需生产精选词库重投影、完整包、
CI 和各产品独立宿主验收，不可将实验词库的 manifest 冒充生产 target lock。

旧 `core.mjs`、60 键模板、`data/layout.json`、`data/demo.json` 及既有实屏报告
仅保留为历史原型/测试证据，当前页面和服务不读取它们。
