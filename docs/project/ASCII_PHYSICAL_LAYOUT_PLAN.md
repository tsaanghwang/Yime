# 新 ASCII 实体键盘布局：计划、实施细则与验收

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
   屏幕Shift/Ctrl/Alt/系统功能键只是明确标记的物理位置示意，尚未模拟固件或Windows快捷键。
5. 九个概念候选按钮与页面候选序号显示为1–9，单键直接选择，无需Shift。
   冻结KLE草案图例保持原样，显示层通过生成式`displayLabels`调整，不改变音元映射。
   按2026-10-09用户明确修订，标准ANSI主键区1–9也直接选词，Shift+1–9恢复输出`! @ # $ % ^ & * (`，不再选词；
   标点只在没有未确认编码时插入本页文本，否则保留组合并提示先选词或取消，不擅自提交候选。
   无对应候选时不做操作，不退回编码。0与小键盘数字仍输入编码。这是实验页面的固定行为，
   不增设数字模式切换，不修改已安装输入法。
6. 唯一可编辑的编码投影仍是 `internal_data/manual_key_layout.json`。
   KLE只拥有盘面几何和图例；图例字符与投影冲突时生成失败，不建立第二套可编辑编码表。
7. 不改拼音、四音元语义元组或规范来源。停用检查在完整元组层完成，
   然后才生成可变码、全码、简码，防止简码先丢掉停用音元导致候选泄漏。

## 2. 实施阶段

| 阶段 | 内容 | 验收条件 | 当前状态 |
| --- | --- | --- | --- |
| A | 隔离分支、冻结草案、重建唯一真源 | 60 ID完整、57活动投影唯一、3受控共享组、9固定候选动作 | 已完成 |
| B | 离线投影与三模式规则 | 语义摘要不变；生成Go音质/音级元数据；1733活动音节逐项对照语义派生 | 已完成 |
| C | 标准ANSI功能兼容通道 | 真实引擎查询/翻页/稳定ID选词/页面提交；大小写区分，1–9选词、Shift+1–9标点；不考核效率 | 自动化通过，真人按键仅核对功能正确性 |
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
- 原型离线19个Python测试、28个JS测试通过（包含保留的历史协议测试）。
  布局/语义锁/Rime离线导出/目标锁联合26个Python测试通过。
- 扩展 `tests/yime`：98通过、4个需要额外来源数据的测试跳过。
  `tests/input_model` 加候选交接/目标锁定向检查另有56项通过。
  `tests/input_model` 与 `tools/lexicon/tests` 联合检查在5个生产发布/evaluation正向断言处停止，
  此前73项通过；失败原因是新布局派生物尚未匹配旧生产target lock。
  保留这个发布阻断，不把基础实验描述成全仓库CI或生产验收通过。
- Go lab、codemode、yimecore、systemlexicon测试通过；本机外部符号链接测试因无创建权限跳过，
  不将该跳过项记为通过。
- Playwright在真实浏览器验证：129键几何、57活动键ASCII、ANSI及虚拟键三模式选词、
  主键区1–9直接选择、Shift数字输出九个标点且保留未确认组合、0保留编码、翻页、大小写、取消/失焦、全键覆盖及记录导出。
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
