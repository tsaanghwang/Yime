# 新 ASCII 实体键盘布局：计划、实施细则与验收

## 2026-10-18：当前 134 键 CN/EN 双布局

现已转用明确选定的 CN134/EN134 文件。运行与当前检查见
[样机说明](../../prototypes/touch-terminal/README.md)和
[本轮交接](../../prototypes/touch-terminal/HANDOFF.md)。旧 138 键章节保留历史范围。
36 个 ASCII 赋值从唯一 manual 源迁移；75 个载体、规范音节和审定别名的语义不变。
新完整词典位于 `.generated/ascii-keyboard-134/data`。
触屏设备已到位，当前真人 134 键试用尚未记录通过。


## 2026-10-11：138 键上下档模型实施基线

本轮仍仅适用于 `codex/ascii-physical-layout-experiment`。以下旧版 129 键记录保留为历史，
不再是本轮实现约束；旧布局分支、已安装 YimeCore/Rime 和正式发布锁均不改动。

- 盘面采用 `prototypes/touch-terminal/design/keyboard-layout.json`，保留用户原文件；
  138 个物理键，24.75 × 7.25u，Tab/主 Backspace 为镜像双矩形 ISO 键。
- 编码投影仍以 `internal_data/manual_key_layout.json` 为唯一真源；KLE 提供几何和图例校验。
  基础 N01–N27/M01–M33 全部启用，新增独立 R04–R18 载体；R01–R03 复用 M22–M24。
  75 个独立编码载体由 52 个大小写字母和 23 个 ASCII 符号组成。
- 每键下档/上档显式定义，不套用标准 ANSI 字符配对；标准 ANSI 只验功能可达，不考核效率。
- 主键区中文编码保留原始 ASCII；单个编码符号提供首页末项的字面标点候选。
  中英文标点开关只作用于字面显示/输出，不改变编码串、音元身份或字典。
- 英文模式直输固定字符；概念 Caps Lock 不启用。左右数字/编辑模式各自独立并显示状态，
  编辑 5 无动作；数字区直输 ASCII 数字和运算符，旁路编码、选词及中文标点转换。
- 儿化只重新投影既有审定记录；不扩展词条、音变规则或改写规范读音。
- 实施顺序：唯一映射及生成器 → ANSI/后端 → 虚拟盘面 → 三模式与浏览器回归。
  触摸显示器暂缺，手指/触控笔、真实触屏多点与可达性验收延期；鼠标自动化不能代替它们。

### 当前生成与运行方式

从试验分支根目录运行，仍遵守仓库 PowerShell 预检规则：

```text
python -X utf8 tools/generate_ascii_layout.py
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:/YimeData/runtime-input-v1/pinyin_hanzi.db
python -X utf8 tools/generate_ascii_layout.py --check
python -X utf8 tools/check_layout_change_lock.py --preflight
python -X utf8 prototypes/touch-terminal/validate.py
```

完整词库在 `.generated/ascii-keyboard-138/data`，不会覆盖旧 `.generated/ascii-keyboard`。
在 `go-backend` 目录运行 `go run ./cmd/yime-keyboard-lab --root .. --port 8768`，
打开 `http://127.0.0.1:8768/`。它只修改页面文本，不是 Windows 输入法安装。
新协议 `concept-keyboard-modes-v2` 同时校验前端、物理布局、编译时布局摘要和词典 manifest，拒绝新旧混用。

### 2026-10-11 新证据

- 布局身份（75 个活动载体）：
  `5634db1c61fe211560b669a7f7a85b2b27b007a34658086b8eeddf655e4dff4d`。
- 从同一只读、内容锁定数据库重新投影 2,457,474 条规范读音，停用排除数为 0。
  既有 315 条 PSC 路径已在核心集合内；131 条审定融合儿化路径另行加入，
  每模式最终索引 2,457,604 个唯一候选/编码对。
- 儿化仍由既有语义规则派生，3 个共享载体和 15 个专用载体都来自同一手工映射源。
  131 条融合路径在三模式中均无新增异文同码桶；这个结论不代表整个基础词库没有重码。
  131 条儿缀兼容路径去重，保留原词库权重；融合旁表权重固定为 1。
- 新词典 SHA-256：
  全码 `a965ce8c87132facc54919ce4a1c54e8f9a681f3b83c8b7480db5f9983abfa55`；
  可变码 `a535e9464e4840f1f4e3203d34300091ba39bdae9be1384567e9872df0f5d358`；
  简码 `459f0837214cd1c6b2da068dda0327ed62eae2f6e327a2289ed2e8ba76ce0c7a`。
  完整构建与碰撞审计分别见上述 data 目录的 `ascii_keyboard_manifest.json` 和上级 `overlay_audit.json`。
  基底生成器的原始摘要已单独保留为 `base_yime_lexicon_manifest.json`，不再以最终词典身份留在 data 目录。
  两次全量构建的最终三份字典 SHA-256 完全一致；manifest 的构建时间可以不同。
- 全量词库 HTTP 回归通过，覆盖三模式真实候选查询、选择提交及全部 23 个编码符号的字面候选路径。
- 隔离真实 librime 1.17.0 三模式 × 儿化旁表启停通过：每模式使用实际词库导出的
  265 条完整竞争桶夹具；131 条融合路径启用可提交、停用消失、131 条儿缀路径仍保留。
  六个临时 schema 另执行 450 次大小写/符号载体探针。未操作已安装 Rime 用户目录。
- 1737 个规范音节和 135 个独立派生的儿化收缩对照通过；原型校验含 20 项 Python、
  36 项 JavaScript 测试（包括保留的历史协议测试）。
- `tests/yime` 加手工布局解析器共 105 通过、4 跳过；旁表合并/基底身份隔离单测 4 通过。
  Go 的 lab、codemode、yimecore、systemlexicon 四个包通过。
  checked-in 儿化别名文件仅刷新 393 个布局编码字段，其余语义、词条、来源与原时间不变。
- Playwright 实际浏览器联测通过：英文/英文标点下 ANSI 与虚拟键均可输出全部 95 个可打印 ASCII；
  75 个 ID 的上下档入口、三模式选词、侧数字区旁路、独立模式切换、双 Num Lock、
  ISO 缺角拒绝命中与拖出取消、138 键覆盖及格式 5 记录导出均通过。
  模拟双指按住 Shift 后先松 Shift、再松字母键仍按按下时的上档处理；390px 窄屏无整页横向溢出。
  `errors=[]`、`external=[]`、`hardwareAcceptance=false`；模拟触摸不算真实触屏验收。
  截图 `output/playwright/concept-138-desktop.png`、`concept-138-narrow.png` 已目视检查。

真实 Rime 回归从 `go-backend` 执行：

```text
go test ./input_methods/yime -run TestASCIIConceptErhuaThreeModesAndRollback -count=1 -v -args -ascii-concept-rime
go test ./cmd/yime-keyboard-lab -run TestCanonicalCorpusHTTP -v -args -keyboard-lab-integration-root C:/Users/tsaan/.codex/worktrees/ascii-keyboard-model/Yime
```

正式 target lock 保持原样，普通发布门禁仍应拒绝把新布局当成旧的已批准交付。
本轮实际复查得到预期的 approved Windows target 摘要不匹配；语义 preflight 则通过。
广域 `go test ./input_methods/yime/connectedspeech` 仍失败：历史离线审核器固化了旧布局的
数字载体、Shift 符号禁用与 N12/N26、N25/N27 共享约束，部分测试读取旧生产 ASCII 表。
这些非儿化语流工具并未接入本次样机，未通过改写规范读音、更新生产锁或删除断言来掩盖失败。
如要让试验分支覆盖全部旧生产语流功能，需要另行迁移这些审核器及其夹具，并逐模块验证。
不能把本轮定向测试描述成全仓库 CI、正式包或已安装 Windows 宿主验收通过。
标准 ANSI 真人复核、真实触屏/触控笔、多点触控手感和实体键盘固件仍是独立后续验收。

## 历史：2026-10-09 的 129 键阶段（不作为当前约束）

日期：2026-10-09。分支：`codex/ascii-physical-layout-experiment`。
基线：主线 `26578669`。影响范围：共享离线键位源，以及独立 YimeCore 键盘实验窗口。
原主目录的未提交修改与已安装产品保持不动。

**用户已确认本轮边界：先完成基础键盘实验，融合儿化载体另行设计；暂不替换正式输入法。**
以下C/D是本轮交付，E的首轮结果只作候选证据，F不在本轮执行。

## 0. 两套布局并行保留

2026-10-09用户明确：标准键盘输入新布局的效率不作考核，只要求能正确输入。
因此保留两条布局路线，不要求新布局兼顾标准键盘的输入效率：

- **旧布局 / 标准键盘路线**：现有分支 `codex/current-readiness-delivery-20260927`，
  工作树 `C:\dev\Yime`。原键位源和已有未提交工作保持不动；这不是新冻结的发布版本。
- **新布局 / 概念实体键盘与虚拟盘面路线**：分支 `codex/ascii-physical-layout-experiment`，
  工作树 `C:\Users\tsaan\.codex\worktrees\ascii-keyboard-model\Yime`。
  新布局的标准ANSI输入仅是功能兼容和验证通道，不考核速度、Shift次数或手感，
  不为改善标准键盘效率而反向修改概念布局。

每条分支仍以各自版本的 `internal_data/manual_key_layout.json` 为唯一编码投影真源，
各自生成和验证词库、布局身份及证据，禁止把旧词库与新映射混用。
不自动合并覆盖旧布局；通用修复可单独移植并分别回归。两套布局与YimeCore/Rime两产品是不同维度。
当前主要实用性工作转向概念键盘的触屏操作、键位可达性，以及普通数字/符号输入功能补齐；
标准ANSI只保留正确性、功能可达性检查，不开展效率比较或优化。

## 1. 设计约束

1. 使用用户的 `keyboard-layout.json` 草案，共129个实体键位。
   快照保存于 `prototypes/touch-terminal/design/concept-129.kle.json`。
   原文件与快照 SHA-256 均为
   `9a0c113a4fe517541925a05abd85423c867671b9063897f9584f9976e8a85278`。
2. 保留全部60个规范音元ID，活动57个；M25、M26、M27保留语义和位置，但当前不输出编码或候选。
   M28/M25、M29/M26、M30/M27分别共用 `[`、`N`、`]`。
3. 活动投影为52个大小写字母和5个标点：单引号、左右方括号、反斜杠、斜杠。
   N12仍是单引号；N25=`y`、N26=`Q`、N27=`R`，不沿用旧共享关系。
4. 标准ANSI键盘通过普通字母和Shift+字母输入；概念键盘用独立按钮固定输出大小写字符。
   屏幕Shift提供一次性符号上档；独立字母键不改变映射。Ctrl/Alt/系统功能键仍只是位置示意，不发送Windows快捷键。
5. 九个概念数字/候选按钮与页面候选序号显示为1–9，无需Shift。
   冻结KLE草案图例保持原样，显示层通过生成式`displayLabels`调整，不改变音元映射。
   按2026-10-09最新修订，数字1–9在当前页有候选时选择对应项，候选列表为空时直接输出数字；
   页内有候选但序号不存在时不做操作。ANSI及虚拟键盘（含小键盘）统一按数字字符处理。
   0及所有未编码ASCII符号直接输出，包括上下档；`-`、`=`不再翻页，改用PageUp/PageDown或页面翻页按钮。
   用户明确选择：直接字符到来时先确认当前页首选，再与字符合并提交；无候选时只输出字符，保留未匹配编码。
   单独输入五个编码符号`' [ ] \ /`时，把符号自身加入首页实际末项；首页满则8个词典候选加符号，
   其余候选顺延，不能丢失/重复。多个字符或含字母的编码串不增加此符号候选。
   这些是隔离实验适配，不修改规范词库、已安装输入法或原生Rime分页。
6. 唯一可编辑的编码投影仍是 `internal_data/manual_key_layout.json`。
   KLE只拥有盘面几何和图例；图例字符与投影冲突时生成失败，不建立第二套可编辑编码表。
7. 不改拼音、四音元语义元组或规范来源。停用检查在完整元组层完成，
   然后才生成可变码、全码、简码，防止简码先丢掉停用音元导致候选泄漏。

## 2. 实施阶段

| 阶段 | 内容 | 验收条件 | 当前状态 |
| --- | --- | --- | --- |
| A | 隔离分支、冻结草案、重建唯一真源 | 60 ID完整、57活动投影唯一、3受控共享组、9个数字/候选键位 | 已完成 |
| B | 离线投影与三模式规则 | 语义摘要不变；生成Go音质/音级元数据；1733活动音节逐项对照语义派生 | 已完成 |
| C | 标准ANSI功能兼容通道 | 真实引擎查询/翻页/稳定ID选词/页面提交；大小写区分，1–9按候选状态选词或直输、非编码符号直输、编码符号首页末项；不考核效率 | 自动化通过，真人按键仅核对功能正确性 |
| D | 概念实体键盘虚拟模型 | 129键位置与尺寸一致，共键停用可见；点按与ANSI走同一路径 | 已完成，待用户真人触屏体验 |
| E | 正式生产精选词库重放 | 从锁定语义源重做source/capacity/model/selection，生成新证据 | 首轮候选生成通过；未晋升生产 |
| F | 安装包与Windows宿主 | 儿化载体决定→完整派生回归→源码提交→CI→完整包→真实宿主 | 按用户决定不在本轮执行 |

这是逐阶段交付，不把C/D的成功描述成F成功。普通安装构建仍受生产target lock约束。

## 3. 真源与运行链

```text
规范拼音 → 正式四音元ID元组 → 完整元组停用过滤
         → manual_key_layout.json 唯一ASCII投影 → 三模式实验词典

KLE物理几何 + 同一个manual投影 → physical-layout.json
ANSI事件 / 虚拟物理键动作 → ASCII或控制动作 → 独立Go服务
                         → 真实YimeCore候选 → 稳定候选ID选择 → 本页文本
```

布局摘要包含停用策略，防止复用旧布局身份；盘面另有touchTemplateId。
KLE的行偏移和12位置图例按[官方serializer](https://github.com/ijprest/keyboard-layout-editor/blob/master/serial.js)
解析。旋转或其他不支持的形状立即报错，不静默改变草案。

离线Python不成为输入运行时。Go服务只绑定127.0.0.1，校验同源、令牌、请求长度、
会话版本、事件重试、候选当前页及词典SHA-256。没有旧词典、安装目录、用户学习库或另一产品回退。

## 4. 可重复执行命令

从此分支根目录：

```text
python -X utf8 tools/generate_ascii_layout.py
python -X utf8 prototypes/touch-terminal/generate_data.py
python -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:/YimeData/runtime-input-v1/pinyin_hanzi.db
python -X utf8 tools/generate_ascii_layout.py --check
python -X utf8 tools/check_layout_change_lock.py --preflight
python -X utf8 prototypes/touch-terminal/validate.py
go -C go-backend test ./cmd/yime-keyboard-lab ./input_methods/yime/codemode ./input_methods/yime/yimecore ./input_methods/yime/systemlexicon
go -C go-backend run ./cmd/yime-keyboard-lab --root .. --port 8767
```

全部实验产物写入 `.generated/ascii-keyboard`；不修改独立内容锁定源。
全量HTTP验收在go-backend目录执行：

```text
go test ./cmd/yime-keyboard-lab -run TestCanonicalCorpusHTTP -v -args -keyboard-lab-integration-root C:/Users/tsaan/.codex/worktrees/ascii-keyboard-model/Yime
```

PowerShell工作仍必须通过仓库 `tools/powershell/run_checked.py` 入口。

## 5. 已取得的证据

- 129键无矩形重叠，边界25.75×7.25 KLE单位。原音元语义摘要未变。
- 规范1737音节中，1733活动音节三模式逐项通过；4个含停用音元的音节
  `hm5/m1/m2/m4` 被拒绝投影，而不是从语义源删除。
- 独立数据库5,491,941,376字节，SHA-256
  `694a5c984c3784dd2a07f49db454e69d01e08b24ce7de14b45ac10b70e315379`，
  与既有批准输入证据一致。
- 实验读取2,457,474条读音，排除7条，导出2,457,467条；每模式索引去重后2,457,466条。
  三字典摘要保存在 `.generated/ascii-keyboard/data/ascii_keyboard_manifest.json`。
  该manifest明确 `production_handoff_promoted=false`。
- 可变/简码 `ni→你`、`hau→好`；全码 `niii→你`、`haau→好`，
  由规范音元链派生并在真实HTTP服务验证，不是手写演示候选。
- 原型离线22个Python测试、30个JS测试通过（包含保留的历史协议测试）。
  布局/语义锁/Rime离线导出/目标锁联合26个Python测试通过。
- 扩展 `tests/yime`：98通过、4个需要额外来源数据的测试跳过。
  `tests/input_model` 加候选交接/目标锁定向检查另有56项通过。
  `tests/input_model` 与 `tools/lexicon/tests` 联合检查在5个生产发布/evaluation正向断言处停止，
  此前73项通过；失败原因是新布局派生物尚未匹配旧生产target lock。
  保留这个发布阻断，不把基础实验描述成全仓库CI或生产验收通过。
- Go lab、codemode、yimecore、systemlexicon测试通过；本机外部符号链接测试因无创建权限跳过，
  不将该跳过项记为通过。
- 本轮完整词库HTTP回归覆盖三模式五种编码符号的首页末项、次页选择、符号提交及首选加标点；
  实验前后端以`candidate-or-literal-v1`核对规则版本，拒绝新页面连接旧规则服务。
- Playwright在真实浏览器验证：129键几何、57活动键ASCII、ANSI及虚拟键三模式选词、
  数字选词/直输、符号确认首选后直输、五个符号候选首页末项、独立翻页、大小写、取消/失焦、全键覆盖及记录导出。
  390px窄视口无页面溢出，键区横滚；项目私有字体加载成功；无外部请求或JS错误。
- 截图保存在 `output/playwright/ascii-keyboard-desktop.png` 与
  `output/playwright/ascii-keyboard-narrow.png`。这些是自动化证据，不是新的真人触屏报告。

## 6. 正式交付的剩余门槛

发现15个既有融合儿化专用大写载体与新基础映射冲突：
`F D S R E W Y T Q V C X P A Z`。不能通过忽略碰撞检查、暗中共享或删除儿化规则解决。
用户选择把这15个载体的新键位/共键方案留到下一阶段；当前实验服务只加载规范基础词库，
不加载正式语流别名、个人词库和学习数据，不代表正式输入法的全部功能。
逐项冲突、停用音节审计及后续“啊”共享关系迁移要求见
[离线派生审计](ASCII_PHYSICAL_LAYOUT_DERIVED_AUDIT.md)。

当前完整实验源集合不是已批准的1,166,753条生产精选集合。原选择TSV只有摘要，
独立数据库的selection表为空，不能从旧ASCII词典反推读音恢复。
必须重放既定选词流程，先核对源语义产物身份，再记录新布局过滤与选择差异。
不能为了让CI或安装通过而只改旧target lock摘要。

本轮已经按原固定策略完成一次精选候选重建：1,166,746条映射，仍有1,151,404个文本，
46,095个单字覆盖完整，四项候选门禁通过。相对旧数量少7条，不据此声称已完成正式晋升。
其selection摘要为 `8a684e6eddded9352f0ed97d8a8e6f5df2d8dbd8b269850ac8ae021b67976e76`，
全码候选词典摘要为 `edd8191adf44e9303d897bf3a5911257a7b932796d3c9b1f9d546a494aa63bba`。
规范accepted entries等五项来源产物与旧证据逐字节一致；拒收报告因当前绝对来源路径不同而变化，
没有把整套来源产物标记为与历史完全相同。
独立第二轮来源重建的六项产物与首轮一致，输入模型已完成；容量计算按本轮收口要求停止并保留部分输出。
尚未完成第二轮精选构建，不声称完整双构建复现。完整命令、来源身份及各阶段边界见
[离线证据报告](../testing/ASCII_LAYOUT_OFFLINE_EVIDENCE_2026-10-09.md)。

完成正式生成、审核新manifest、通过CI并交付完整包之后，分别验证YimeCore和Rime/PIME。
真实ANSI键盘、手指触屏、Windows注册宿主是独立验收面；新布局ANSI只验功能，不考核效率。
旧60键触屏记录不得套用到129键。
不变更默认输入法，不把隔离页面结果当成原生TSF结果，不在未交付新包时启动安装。
