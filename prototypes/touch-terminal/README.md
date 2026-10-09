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
3. 候选列表和虚拟盘面的九个紫色数字/候选键均标为 **1–9**，不需要 Shift。
   冻结的 KLE 草案仍保留原图例；生成的 `displayLabels` 仅调整概念样机显示，不改变动作或编码真源。
   按2026-10-09用户修订，ANSI与虚拟键盘共用下表规则，小键盘数字也按数字字符处理。
4. Enter/Space 在有候选时确认首选；空组合时在本页插入换行/空格。
   Backspace、Escape用于退格和取消；PageUp/PageDown及页面按钮翻页。上下档的 `- _ = +` 都输出符号，不再翻页。
5. 失去窗口焦点取消未确认组合。切换码制也取消旧组合。没有全局按键注入。
6. 虚拟Shift为一次性符号上档，点Shift后再点数字/符号键可输出其上档字符；
   固定大小写音元键不变更映射。Ctrl/Alt、系统键和功能键仍为「仅示意」，不发送Windows快捷键。
7. 「全键覆盖」「随机目标」只测键位命中，不向引擎输入。
   导出记录区分浏览器事件与真实触屏验收，不能把鼠标/自动化冒充手指测试。

### 数字、符号与候选

| 输入 | 处理规则 |
| --- | --- |
| 数字1–9 | 当前页有候选时选择对应项；没有任何候选时直接输出数字。页内有候选但该序号不存在时不做操作。 |
| 数字0、非编码ASCII符号 | 直接输出；若当前页有候选，先确认当前页首个候选，再与字符合成一次提交。无候选的未确认编码保留，不删除或偷偷上屏。 |
| 单独一个编码符号 `' [ ] \ /` | 正常查询音元编码，另将符号自身放在首页实际末项；首页满时保留8个词典候选加1个符号候选，其余词典候选顺延，不丢失、不重复。 |
| 含字母或多个字符的音元编码 | 只查询正常音元候选，不把编码串误作符号候选。 |

非编码符号包括上下档，例如 `- _ = + ; : , < . >`、反引号/波浪号、`! @ # $ % ^ & * ( )`、
双引号、花括号、竖线和问号。五个编码符号的上档字符也是直接符号。
这些规则由独立Go实验会话统一处理，使用版本号、稳定候选ID和事件重试缓存；不是修改正式词典或原生Rime分页。

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
