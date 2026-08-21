# 当前实现总览

> **2026-07 主线切换：** `.generated/lexicon_source_bundle/source_lexicon.sqlite3`
> 是字词来源、读音、来源证据、分类频次以及后续音元编码输入的唯一生产真源。
> 旧 `.generated/source_pinyin.db` 不再是默认入口，也不得作为运行库重建的回退来源。

本文是当前分支的工程状态入口。它只描述已经落到代码、数据和锁检查中的主线；理论设想、旧试验和
外部 Windows 前端的实现细节不在这里冒充现状。

阅读 `syllable/analysis/`、片音对象、音元对象或 Yinyuan ID 前，先看
[片音分析与音元表示：工程阅读概要](PIANYIN_ANALYSIS_OVERVIEW.md)。固定四元编码位置不是等长语音
时间窗，当前分析对象也不是程序从波形中切出的平顶音段。

## 一句话状态

当前项目已经基本形成“字典驱动的音元编码生成器”：给定格式合格、带明确声调的拼音字典，工具链
可以提取规范音节，对已登记规则覆盖的音节生成四个 Yinyuan ID，再生成三模式编码、布局投影和运行时
词库。遇到没有来源或没有登记规则的新形式时，流程应失败并报告，不允许临时猜码。

## 当前端到端数据链

```text
Unihan 单字读音 / phrase-pinyin-data 词语读音 / 经审查补丁
  -> 字典拼音第一轮合规审查（共用策略、保留来源上下文）
       -> 合规实例：准入
       -> 有旁证的来源错误：按字头校正
       -> 方案允许的省写：还原为编码入口形式
       -> 已知非规范拼式：保留字形和审计证据，只阻止该读音进入解码
  -> source_lexicon.sqlite3（统一生产真源）
  -> 规范数字标调音节清单（当前 1732 项）
  -> SyllableEncodingPipeline
  -> 首音段 + 干音段
  -> ShouyinEncoder + GanyinEncoder
  -> 4 个 Yinyuan ID
  -> 等长 / 变长 / 省键三模式编码
  -> manual_key_layout.json 的唯一键位投影
  -> SQLite 运行时候选、Rime/KLC/Windows 消费产物
```

三模式严格按同一条派生链生成：等长模式保留每音节四个音元；第一位是实首音或虚首音，后三位是组成干音的呼音、主音和末音。变长模式固定保留首音，只合并组成干音的相邻相同音元：三者不同时保持不变，只有前两者相同时合并前两者，只有后两者相同时合并后两者，三者相同时合并为一个音元。省键模式以变长结果为输入，只对仍由三个同音质音元构成、且调级为高—中—低或低—中—高的干音省略中间的中调音元。虚首音承担连续输入的音节边界，不再作为省键项删除。该顺序与 Windows Yime 的 `codemode` 实现一致。

1732个现行音节均有 Unihan、词语来源或经审查补丁依据，并全部能通过正式编码器。逐项来源、规则和
四个 Yinyuan ID 见 `internal_data/yime_syllable_encoding_provenance.tsv`。

## 当前真源

| 层 | 真源 | 职责 |
|---|---|---|
| 来源合规 | `dictionary_pinyin_compliance_policy.json` | 外部字典进入解码前的声韵准入、字头校正、已知排除和儿化省写还原策略 |
| 字词、读音、频次、九级汉字分级与来源证据 | `.generated/lexicon_source_bundle/source_lexicon.sqlite3` | 唯一生产真源；统一门禁后的编码输入边界及 `character_tiers` 分级表 |
| 上游单字输入 | Unihan / `internal_data/hanzi_pinyin/pinyin.txt` | 重建统一库的来源证据，不由下游直接消费 |
| 上游词语输入 | pypinyin、万象及其原始分类文件 | 重建统一库的来源证据，不由下游直接消费 |
| 上游频次输入 | BCC 各原始分域字频/词频频道 | 原始 count 写入统一库；merged 二手文件不接入生产链 |
| 拼音补充 | `internal_data/pinyin_source_db/pinyin_normalized_patch.json` | 明确审查的来源或标调补充；不能写音元码 |
| 缺失音节审查 | `internal_data/pinyin_source_db/syllable_admission_reviews.json` | 让有真实来源、结构合法且经批准的音节跨过旧清单循环门禁；可限定多字来源，不能写编码 |
| 拼写规则说明 | `internal_data/syllable_encoding_rule_catalog.json` | 解释来源、规范化和兼容规则；禁止保存编码映射 |
| 首音稳定登记 | `syllable/yinyuan/zaoyin_yinyuan_enhanced.json` | N01–N27 的标签、语义码、Yinyuan ID 与运行时字符；不是条件音值规则起点 |
| 乐音稳定登记 | `syllable/yinyuan/yueyin_yinyuan_enhanced.json` | M01–M33 的标签、别名、Yinyuan ID 与运行时字符；不是条件音值规则起点 |
| 条件音值来源与规则契约 | `syllable/pianyin/conditional_sound_value_model.json` | 指向片音实现值、音质/音高归并、规范三段分解及稳定登记表；当前 `research_only` 且不接运行时 |
| 音节分解 | `syllable/analysis/syllable_encoding_pipeline.py`、`syllable_splitter.py` | 标准拼音到首音段/干音段 |
| 音节编码 | `ShouyinEncoder`、`GanyinEncoder`、`YinjieEncoder` | 正式生成四音元编码 |
| 键盘布局 | `internal_data/manual_key_layout.json` | 唯一 Yinyuan-ID-to-key 投影 |
| 运行时词库 | `yime/pinyin_hanzi.db` | SQLite 候选主路径；属于可重建消费端数据 |

`key_to_symbol.json`、BMP PUA 投影等文件负责字符承载和平台投影，不得反过来定义拼音分解。数据库、
`yinjie_code.json`、resolved layout、crosswalk、KLC 和审计 TSV 都是派生或审计产物，不应手工作为
单项修复入口。

统一来源库把轻声作为完整词音的表层属性保存：`neutral_tone_positions` 记录位置，
`neutral_tone_status` 区分确认轻声与未定无调，`pronunciation_scope` 防止孤立词境证据生成单字候选。
本调、词汇性轻声和临时语流弱化不得压成一张“每个音节都有第五声”的闭合表。有一至四声家族的
来源轻声由正式编码器常规派生；没有本调家族的来源轻声必须进入
`neutral_tone_encoding_exceptions.json` 明确审查，再由同一编码器处理。例外表只登记来源和适用范围，
不保存 Yinyuan ID、码元或键位。运行时完整多音节输入若命中已准入的轻声音节、但缺少对应的轻声
单字候选，可以把同字音族一至四声的已有单字读音临时投影到该轻声位置参与动态组合。该投影只产生
有数量上限的本次候选，不写回单字读音、来源库或音节码表；单音节输入、未准入的五声形式和没有
同声韵本调依据的特殊轻声均不得触发。

这里的“表层属性”只表示完整词音中出现了轻声这一身份，不表示数据库已经保存其具体表层调值。
当前 `tone=5` 及三个中调乐音（音元）序列是稳定工程标识和兼容编码，不是第五个固定声调的声学声明，
也不要求为每条轻声回填阴平、阳平、上声或去声中的深层本调。后期若要按语流中的实际轻声输入，必须
在词语或构式层增加有来源、可撤销的表层输入别名；不得用该别名改写规范读音、基础音节码或轻声身份。

单字分级同样只在统一来源库生成：`kTGH` 正式三级、`kXHC1983` 扩展、从
`kHanyuPinyin ∪ kMandarin` 按BCC补到累计14000、剩余 `kHanyuPinyin`、
剩余 `kMandarin`、项目门禁且已有正式音元编码字符、未编码Unihan字符，共九级。
运行库只复制 `character_tiers` 中已有编码的成员和序位，不再维护平行五档算法。

## 这版键盘布局重构

当前布局状态为 `canonical_yinyuan_vk_layout_v1`，已经写入唯一布局真源并由布局锁闭合。

### 总体分配

- 47个 Base 可分配键中：22个放常用乐音，25个承载首音；N12/N26、N25/N27 受控共键，反引号承载 N25/N27。
- 其余11个乐音放在 Shift 层。
- 所有60个 Yinyuan ID 只使用 Base 或 Shift；保留的 AltGr 槽位全部为空。
- `Shift+1` 至 `Shift+9` 是候选选择操作，不承载 Yinyuan ID。
- 已删除早期“把数字和标点机械搬到其他键位”的输入兜底；数字和标点由宿主/候选功能处理。

### Base 乐音记忆结构

```text
左手：W E R = o 低中高    右手：U I O = u 高中低
      S D F = a 低中高          J K L = i 高中低
      X C V = e 低中高          M , . = ü 高中低

A/Z = n 高/低            ; / = ng 高/低
```

### 首音和特殊首音

- 21个实首音全部在 Base；数字排保留 `x/q/j/s/c/z/zh/ch/sh/r` 的组块。
- `N12` 零首音使用 `'`。
- `N23` 使用 `Y`，`N24` 使用 `=`。
- `N04 m`、`N05 d`、`N07 l` 分别使用 `-`、`]`、`\`。
- `N06 t` 使用 `T`；`N01 b`、`N08 n`、`N09 g`、`N11 h` 使用同字母键，`N10 k` 使用 `Q`。

设计理由见 `internal_data/musical_layout_skeleton.md` 与
`internal_data/shouyin_layout_skeleton.md`；实现事实必须以 `manual_key_layout.json` 为准。

## 三张音节审计表

运行 `tools/export_syllable_decomposition.py` 会同时生成：

1. `yime_syllable_decomposition.tsv`：1732项正式分解、Yinyuan ID 和布局码。
2. `yime_syllable_encoding_provenance.tsv`：每项编码的来源和规则依据。
3. `yime_syllable_omissions.tsv`：实际来源在进入正式音节清单前被过滤，或进入清单后编码失败的记录。

遗漏表不再把预定义韵母补齐为五声，也不登记未被来源实例化的 `v`、`ue`、`uong` 等技术或
合并形式。缺少来源实例的组合不属于“遗漏”；将来出现新的经审查读音时，由实例驱动链自动纳入。

## 修改入口

### 修改拼音来源或音节规则

1. 从单字/词语原始来源开始，并先运行 `tools/audit_dictionary_pinyin.py`。
2. 判断问题属于通用拼写规则、带字头上下文的来源校正，还是只保留证据的已知排除；不得把单字
   勘误扩张成全局音节别名。
3. 修改合规策略、正式规范化、切分或编码真源，并在规则目录登记依据。
4. 重建来源库、编码和三张审计表。
5. 单独审查语义变化并执行布局锁；不得从 `yinjie_code.json` 中间补入。

### 修改键盘布局

1. 只改 `internal_data/manual_key_layout.json`。
2. 运行 `python tools/run_locked_layout_pipeline.py`。
3. 检查 resolved layout、crosswalk、KLC 和运行时一致性。
4. 不得在布局修改中改变拼音到 Yinyuan ID 的语义链。

### 常用验证

```powershell
.\venv312\Scripts\python.exe tools\export_syllable_decomposition.py
.\venv312\Scripts\python.exe tools\check_layout_change_lock.py
```

## 当前边界

- 这套链能自动处理已登记规则覆盖的字典音节，不承诺对任意新拼音形式自动发明分解规则。
- 词频、默认读音、多音排序和候选质量仍依赖输入字典与频率数据。
- Python 原型是语义、生成和审计主仓库；Windows 输入法、Rime 或 KLC 是消费者，必须从这里的正式
  语义和布局产物同步，不能在消费者仓库另建一套拼音到键位映射。

## 大规模字词来源语料包

`tools/build_lexicon_source_bundle.py` 把 Unihan 单字拼音、pypinyin 词语拼音、万象字词拼音与 BCC
字词频次汇入 `.generated/lexicon_source_bundle/`。所有读音先经过共用的第一轮合规审查和当前可解码
音节门禁；BCC 原始计数与万象权重分列保存，未匹配词条和读音冲突分别报告。具体口径和产物见
[字词拼音与频次统一语料包](LEXICON_SOURCE_BUNDLE.md)。该语料包仍必须从正式音节编码链进入下游，
不得直接保存或猜测 Yinyuan ID。

## 输入候选整理与动态组合覆盖层

`yime/input_model/` 在统一来源库之上提供独立的候选决策覆盖层。它只读
`source_lexicon.sqlite3`，把机器建议、人工批准、拒绝和暂缓决策写入单独的
`.generated/input_candidate_model/input_model.sqlite3`。候选目录覆盖合规读音、BCC 频次和拒绝记录中的
全部不同字串；BCC 频次只决定审查顺序，不限制整理范围。动态组合器只使用已经批准的组件及来源库
中已有的合规读音；不会逐字猜读音，也不会直接修改运行时词库。

两字未编码字串采用内建动态可达性证据：当左右两个单字分别已有来源门禁合格注音时，只记录该字串
可由两个单字连续输入，不自动改变类别、策略或待审状态。可达性不等同于非词，也不能单独成为退出
静态待编码系列的依据。

`tools/build_recursive_composition_model.py` 把这一证据扩展到全部多字未编码候选。模型按长度从长到
短扫描，先尽量使用来源门禁合格、可由正式链编码的多字串；未覆盖余段默认封装成二字动态块，必要
时用三字或四字块避免暴露顶层孤字。单字只在残余块内部验证输入根基，缺失时作为例外报告，不参与
顶层切分竞争。模型保存首选分层路径、多字覆盖量、动态残余、递归树、结构多解、组件读音多解和
缺失单字根基。组件不要求先经人工分类；组合出的拼音只是输入序列，不成为目标长串的来源词音，也
不改变候选去留。

`tools/plan_static_lexicon_capacity.py` 从已编码字串反向建立静态词库容量模型。它按完整读音递归检查
更短组件，把单字和没有更短同读音路径的字串列为静态硬底座，再以 BCC 频次和组件复用价值形成可调
容量前沿。输出只是带证据的迁移候选；运行词库删减仍须通过真实输入回放、候选排名、歧义和延迟
验证。

正序/逆序筛选结果可以另存人名、商号、品名、货币计量、其他专名、固定词、确定性无效材料或未定
等后段语义分类。分类本身不决定编码；独立批处理重新核验组件读音、递归结构及货币数字形态后，才
把可恢复动态材料移出静态待编码系列，把固定词保留待审，把明确无效材料归入 R0 修复/隔离，并将
证据写入候选覆盖层。低频、古旧、构式部件或暂时不可达均不能单独触发 R0。

来源合规策略另登记两种严格受限的码点处理：一对一 Unicode 规范分解的 CJK 兼容码点只继承目标
统一字已有的 Unihan 读音，不保存或猜测拼音；暂无可信普通话读音来源且不可规范归并的码点暂未
编码，任何包含它们的来源字串均写入 `unencoded_pending_strings`。候选模型将其标为
`unknown + needs_review + deferred`，保留给专家或未来可信来源复核，不把来源不足等同于无效、
永久拒绝或最终不予编码。

主体结构、分类轴、整合政策和后续模型接入口见
[汉语输入候选整理与动态组合系统](INPUT_CANDIDATE_MODEL.md)；当前规模、整理进度、优先级和分阶段
目标见[候选语料库整理路线图](CANDIDATE_CORPUS_ROADMAP.md)。

## 分层输入架构迁移

候选整理的主线正在从逐条词汇判决迁移为“基础解码、动态组合、用户学习、语义排序”四层。运行时已
建立动态候选提供者和语义排序器接口；用户库除词条及选择频率外，开始保存本地上下文转移，用相同
接口模拟未来远程语义重排。首个内置动态提供者负责受约束的轻声回退：当完整轻声词条或轻声单字
缺失时，用同声韵的既有本调单字构造临时候选，但不扩张正式读音。模拟层没有数据或不可用时，候选
顺序回到确定性本地排序。

运行时现同时启用一般单字动态组合，完整输入窗口为二至七音节。组合先限制每音节单字槽位，再做
固定束宽搜索，最后跨提供者按字串去重并限制同首字簇和总候选数，不物化完整笛卡尔积。用户把一个
或多个已验证候选加入待上屏区并提交后，若提交文本与选择轨迹逐字一致、每字都有明确数字标调拼音
且总长为二至七字，整句自动写入本地用户词库；手工改写或证据不闭合的提交不学习。用户词条和同码
显式选择频次排在公共静态 `sort_weight` 之前，但频次仍以 `lookup_code + text` 隔离，不能串扰其他
编码。各层职责、
当前实现边界和迁移顺序见[分层输入架构迁移](LAYERED_INPUT_ARCHITECTURE.md)。52,290 至
202,290、全量 pypinyin、A/B 和 B-lite 等容量档继续作为历史对照；Windows Yime 当前默认发布层
已经固定为两级筛选后的 `yime_core_trial`：

- 1,152,157个不同字串、1,167,057条不重复的已编码运行映射；
- 46,095个已编码单字全部进入运行链，其中14,000字为核心、32,095字为低频外围；
- 安装包只携带核心词典、schema、manifest 和运行 profile；
- 旧 2,456,797 条等长/变长/省键大词库退出安装运行链，保留为离线真源、筛选池和回归资源；
- 固定回放 2,440/2,449 冷启动首选，99.6325%，95% Wilson 下界 99.3030%；
- 540,000 次加速学习漂移全部验收项通过；
- 纯净用户态人工压力测试 5/5 可构造，3/3 一次纠正后成为首选并在重启后保持。

未预装的完整词条不再自动归入“待注音/待编码”：只要组成它的字符和读音已通过正式门禁，就走动态
组合和用户学习。只有字符或实际读音本身缺少可信来源或正式音元编码时，才属于编码缺口。
