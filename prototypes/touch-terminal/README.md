# Yime 概念实体键盘实验

这是新布局的 **138 键实体盘面虚拟模型**。标准 ANSI 键盘输入和屏幕点按都通过
同一 ASCII/控制动作接口，进入真实 Go YimeCore 引擎；候选只提交到本页文本框。
不是系统输入法安装，也不使用原来的三个固定候选演示。

本轮在隔离实验中启用全部 60 个基础音元及 15 个独立儿化载体，复用既有审定儿化记录，
不扩展音变规则。服务不加载个人词库或学习数据，不替换当前正式输入法。

两套布局分支并行保留：旧布局继续位于 `codex/current-readiness-delivery-20260927`，
本样机位于 `codex/ascii-physical-layout-experiment`。本样机的标准ANSI通道只要求功能正确、能输入，
不考核输入速度、Shift次数或手感；新布局的效率和实用性设计面向概念实体键盘及其虚拟盘面。
各分支使用自身的键位源和配套生成词库，不混用，也不自动用新布局覆盖旧布局。

## 运行

在此分支仓库根目录执行（Python 仅用于离线生成）：

```text
python -X utf8 tools/generate_ascii_layout.py
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:/YimeData/runtime-input-v1/pinyin_hanzi.db --output-dir .generated/ascii-keyboard-138
go -C go-backend run ./cmd/yime-keyboard-lab --root .. --port 8765
```

生成命令读取已授权的独立内容锁定数据库并校验其 SHA-256，不读取其他 Git 仓库。
实验词典位于忽略目录 `.generated/ascii-keyboard-138/data`。若采用另一个输出目录，
生成时传 `--output-dir`，启动时传 `--data-dir` 指向其中的 `data`。
服务启动时核对布局摘要、停用集合及三份词典摘要，随后打印本机打开地址。
初次启动会编译三份索引，需要等待服务提示 ready。

打开 [本地键盘实验](http://127.0.0.1:8765/)。
直接双击 HTML 或旧的 Python 静态服务不能运行真实输入引擎。

## 怎样试用

1. 先把 Windows 系统输入法切到英文直输（避免另一输入法截获），再在实验页面选可变码、全码或简码。
   页面初始为“中文输入／英文标点”，与系统输入法的模式无关。
2. ANSI 键盘按其标准方式输入 ASCII；虚拟键盘按各键明确标注的下档/上档输出，字母也可有不同上档。
3. 候选列表和虚拟盘面的九个紫色数字/候选键均标为 **1–9**，不需要 Shift。
   此规则只适用于中文模式主键区；ANSI 小键盘数字和概念侧数字区走字面旁路。
4. Enter/Space 在有候选时确认首选；空组合时在本页插入换行/空格。
   Backspace、Escape用于退格和取消；PageUp/PageDown及页面按钮翻页。标点不充当翻页快捷键。
5. 失去窗口焦点取消未确认组合。切换码制也取消旧组合。没有全局按键注入。
6. 虚拟 Shift 支持点按一次性上档，也支持按住并点击另一键；ANSI Shift 只点亮层，输入仍按 event.key。
   无上档定义的键保持固定字符。概念 Caps Lock 不启用；Ctrl/Alt、系统键和功能键仅示意，不注入系统快捷键。
7. 「全键覆盖」「随机目标」只测键位命中，不向引擎输入。
   导出记录区分浏览器事件与真实触屏验收，不能把鼠标/自动化冒充手指测试。
8. 左右 Num Lock 各自切换数字／编辑并显示状态。数字模式直输 ASCII 数字及运算符，
   保留未确认编码、不选词、不转换中文标点；编辑模式 5 无动作，编辑只作用于本页文本。
9. 页面中英文输入和中英文标点可独立切换。转英文时未确认中文编码暂停保留，回中文后可继续。
   英文状态按盘面固定大小写直输；标点模式只改变字面输出，不改变内部编码。

### 数字、符号与候选

| 输入 | 处理规则 |
| --- | --- |
| 中文主区数字1–9 | 当前页有候选时选择对应项；没有任何候选时直接输出数字。页内有候选但该序号不存在时不做操作。 |
| 数字0、非编码ASCII符号 | 直接输出；若当前页有候选，先确认当前页首个候选，再与字符合成一次提交。无候选的未确认编码保留，不删除或偷偷上屏。 |
| 单独一个编码符号（当前23种） | 正常查询音元编码，另将字面符号放在首页实际末项；首页满时保留8个词典候选加1个符号候选，其余词典候选顺延，不丢失、不重复。无汉字候选也不自动提交该符号。 |
| 含字母或多个字符的音元编码 | 只查询正常音元候选，不把编码串误作符号候选。 |

非编码符号为感叹号、双引号、逗号、句点、冒号、分号、问号、下划线、反引号。
其余 23 种 ASCII 标点都是编码载体，上档也不能绕过编码。要连续直输标点，可切页面英文输入。
中文标点转换的实验默认表及配对引号规则见 `go-backend/cmd/yime-keyboard-lab/README.md`；
未定义的转换保留原 ASCII，并非把所有字符全角化。
这些规则由独立Go实验会话统一处理，使用版本号、稳定候选ID和事件重试缓存；不是修改正式词典或原生Rime分页。

## 唯一真源与派生物

- `internal_data/manual_key_layout.json`：唯一可编辑的音元 ID→ASCII 投影和停用策略。
- `design/keyboard-layout.json`：用户当前草案；拥有物理位置、尺寸、颜色及上下档图例。
  图例中的字符须与唯一真源一致，导入器发现冲突就失败，不反向覆盖投影。
- `data/physical-layout.json`：上述两者生成的完整盘面，禁止单独维护映射。
- 60 个基础 ID 全部启用，加 R04–R18 共 75 个独立 ASCII 载体；R01–R03 复用 M22–M24。
  M25/M26/M27 使用 `{ | }`，与同键下档 M28/M29/M30 的 `[ \\ ]` 独立。
- `layoutId` 标识 ASCII 投影和停用策略；`touchTemplateId` 标识具体虚拟盘面。
  ISO 键按两个矩形的并集显示及命中，缺角不属于可点击区域；KLE 的 y 偏移与 a 对齐按上游格式解析。

## 验证

```text
python -X utf8 tools/generate_ascii_layout.py --check
python -X utf8 prototypes/touch-terminal/validate.py
go -C go-backend test ./cmd/yime-keyboard-lab
```

真实全词库 HTTP 验证见服务的 `README.md`。浏览器回归脚本是
`browser-smoke.js`；必须连接当前 Go 服务，不得使用旧 fixture 代替。
源码自测、浏览器键盘事件、真实 ANSI 按键、手指触屏、Windows 注册宿主分别记录。
触摸显示器维修期间，只执行代码、鼠标和浏览器模拟验证；真实手指、多点触摸和触控笔验收待设备返回。

## 范围与历史

详细实施顺序见 `../../docs/project/ASCII_PHYSICAL_LAYOUT_PLAN.md`。
本分支先验证共享离线源和 YimeCore 独立实验窗口；未变更默认输入法、安装目录、
Rime/PIME 用户数据或系统级输入行为。正式交付仍需生产精选词库重投影、完整包、
CI 和各产品独立宿主验收，不可将实验词库的 manifest 冒充生产 target lock。

旧 `design/concept-129.kle.json`、`core.mjs`、60 键模板、`data/layout.json`、`data/demo.json` 及既有实屏报告
仅保留为历史原型/测试证据，当前页面和服务不读取它们。
