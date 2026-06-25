<!-- markdownlint-disable-file MD013 -->

# 术语总入口（人类与 AI 请先读）

本页是 Yime 仓库里 **音元 / 片音 / 音节结构** 相关命名的 **canonical 索引**。
改 `syllable/`、写文档、用 AI 生成代码前，请先读本文，再按需进入下列专题文档。

**不要** 用通用英语语音学术语（phoneme、segment、musical note 等）随意替换本仓库已有中文概念或拼音标识符。

---

## 先读哪一份

| 读者   | 建议顺序   |
| ------ | ---------- |

| 中文维护者 | 本文 → [YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md) → [syllable/NAMING.md](../syllable/NAMING.md) |
| 英文读者 | 本文「Quick reference」→ [YINYUAN_TERMINOLOGY_EN.md](YINYUAN_TERMINOLOGY_EN.md) |
| 改编码链 / `syllable/` | 本文 → [syllable/README.md](../syllable/README.md) → [CODEPOINT_POLICY.md](CODEPOINT_POLICY.md) |
| 片音与 ASR/TTS 衔接 | [PIANYIN_TECH_BRIDGE.md](PIANYIN_TECH_BRIDGE.md) / [PIANYIN_TECH_BRIDGE_EN.md](PIANYIN_TECH_BRIDGE_EN.md) |
| 完整理论/wiki | [THEORY_INDEX.md](THEORY_INDEX.md) → `Yime.wiki/` 子模块 |

---

## 段 / 位 / 时段 / 语义槽位 — **勿混「槽」**

本仓库里 **「slot / 槽」** 出现在多处，**中文不宜一律写「槽」**。早期文档与 AI 辅助写作曾默认把英文 slot 译成「首音槽、呼音槽、四槽」，易与下面已定义的 **语义槽位（N/M）** 混淆，也与 wiki / 音元分析法惯用的 **「段」** 不对齐。**本节为定稿提醒，忙时请先回到这里。**

### 四套说法，各管一层

| 中文   | 英文   | 文档   | 指什么   | 本仓库怎么用   |
| ------ | ------ | ------ | -------- | -------------- |

| **时段** | temporal slot | [YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md) §1 | 语流中可被语音单位占据的**时间位置** | 音元 **占时段**；中文 **不用「槽」** 译 temporal slot |
| **段**（结构段） | segment (project sense) | 本文「音节结构」、`yinjie.py` 文件头 | 首音 / 干音 / 呼 / 主 / 末等 **音系切分** | 首音**段**、干音**段**；段由 **音元类别** 填充（噪音 / 乐音） |
| **位**（音元位 / 编码位） | code position | `codec/yinjie.py`、四码 `yinjie_code.json` | 固定顺序上的 **第 1–4 个音元字符** | 四**音元位**；第 1–4 位依次存放 **首音元 / 呼音元 / 主音元 / 末音元**；≠ 段本身，存的是 **已编码音元** |
| **语义槽位** | semantic slot (N/M) | [CODEPOINT_POLICY.md](CODEPOINT_POLICY.md)、[FAQ.md](FAQ.md) Q16 | `N01–N24`、`M01–M33`：**哪一个音元身份** | **仅在此层** 用「槽位」；键盘 / 真源 / 投影都围绕 N/M |

**关系（一句话）：** **段** 是结构怎么切；各段由 **音元** 填充；四码串里四个 **位** 各放一个 runtime 字符；每个字符背后对应 **语义槽位 N/M**（再投影到 PUA 等）。

```text
时段（抽象时间）
  └── 音元（占时段的单位）
        └── 填充 → 结构「段」（首音 / 呼 / 主 / 末 …）
              └── 编解码 → 四「音元位」（yinjie 四字符）
                    └── 身份 → 语义「槽位」Nxx / Mxx
```

### 推荐 / 避免

| 推荐   | 避免   |
| ------ | ------ |

| 首音**段**、干音**段**、呼音**段** | 首音**槽**、呼音**槽**（像键盘插孔，且易与 Mxx 混淆） |
| 四**音元位**、**编码位**、四段**所填音元** | 四**槽**、音元**槽位层**（与 N/M **语义槽位** 撞名） |
| **语义槽位** N/M（身份层） | 把 `ascender` / 呼音 **段** 叫作某个 **M 槽** |
| 英文代码注释写 **segment / position** 并链到本文 | 一律写 slot 并反写中文「槽」 |

### 和切分标签的关系

`SyllableEncodingPipeline` 产出的是 **首音段 / 干音段** 的拼音侧**标签**（如 `zh`、`ong1`），供编码器查表——**不是** `Yinjie` 四**音元位**里的字符，也 **不是** N/M **语义槽位** 编号。三层勿混：见 [syllable/analysis/segment_split.py](../syllable/analysis/segment_split.py) 与 [syllable/codec/yinjie.py](../syllable/codec/yinjie.py) 模块说明。

### 常见误解

- ❌ 用 **「槽」** 统称：时段、结构段、四码位、N/M 身份
- ❌ **呼音槽** = 韵头 / 介音，或 **末音槽** = 韵尾（段名 ≠ 音质部件名；见上文音节结构节）
- ❌ 见代码里的 `*Slots` 类名，便在中文文档里推广 **「槽」** 作结构术语（类名历史遗留可逐步改；**中文文档以本节为准**）

---

## 核心术语速查（中文）

| 中文   | 推荐英文 / 标识   | 层次   | 一句话   |
| ------ | ----------------- | ------ | -------- |

| 时段 | temporal slot | 抽象 | 语流中可被占据的时间位置 |
| 片音 | pianyin, phonic slice | 语音切分 | 按时域切出的语音片片；见专题文档，≠ phone |
| 音元 | yinyuan | 抽象编码 | 占时段、由区别性属性划分的单位；由一类片音实现 |
| 音节 | yinjie | 结构 | 首音 + 干音 两大段 |
| 首音 | shouyin | 结构段 | **声母及与其联结的调段**（通俗：**声母 / 辅音**）；≠ 噪音类别 |
| 干音 | ganyin | 结构段 | **韵母及与其联结的调段**（通俗：**带声调的韵母**）；≠ 乐音；≠ 无调韵母 |
| 乐音 | yueyin | 片音/音元类别 | 有稳定调段的段；干音 **内部** 的呼/主/末段由乐音构成 |
| 噪音 | zaoyin | 片音/音元类别 | 首音侧；清辅音等 |
| 呼音 | huyin | 干音内结构段 | 干音的 **峰前段**（`yinjie.py`：`ascender`）；≠ 韵头 / 介音 |
| 韵音 | yunyin | 干音内结构段 | 干音的韵段；含主音 + 末音 |
| 主音 | — | 韵音内结构段 | **峰段**（`peak`）；由 **乐音类** 音元充当 |
| 末音 | — | 韵音内结构段 | **峰后段**（`descender`）；≠ 韵尾 / coda；由 **乐音类** 音元充当 |
| 四音元位 | — | 编解码 | `yinjie` 四字符顺序位；第 1–4 位依次存放首音元、呼音元、主音元、末音元；见上文「段/位/槽位」节 |
| 语义槽位 | N/M | 身份层 | `N01–N24` 噪音、`M01–M33` 乐音；**仅此层称「槽位」** |

### 音节结构 — **权威定义，禁止改层级**

**实现真源：**

- **首音 / 干音 音段定义（生成音系学）**：[`syllable/analysis/syllable.py`](../syllable/analysis/syllable.py) 模块头注释、`Syllable.shouyin` / `Ganyin`（声母或韵母 + 各自联结的调段；干音段标签如 `i1` 供编码查表）。
- **Yinjie 内部分解树（呼/韵/主/末）**：[`syllable/codec/yinjie.py`](../syllable/codec/yinjie.py) 文件头与 `Yinjie` 类。

下列树形 **不是**「示意之一」或「可简化的教学版」——改代码、写 README、用 AI 时 **不得** 压扁、对调或删掉任一层。

**两条轴（必须分开，不可混为一层）：**

| 轴   | 问什么   | 本仓库答案   |
| ---- | -------- | ------------ |

| **结构段** | 音节按位置怎么切？ | **递归二分**（见下表；不是线性链） |
| **音元类别** | 各段由哪类音元充当？ | 首音 ← **噪音**；呼/主/末 ← **乐音** |

**结构段递归分解**（每一行：父节点 → 子节点之和；与 `yinjie.py` 一致）：

| 节点   | →   | 分解   |
| ------ | --- | ------ |

| 音节 | → | (首音 + 干音) |
| 干音 | → | (呼音 + 韵音) |
| 韵音 | → | (主音 + 末音) |

首音、呼音、主音、末音在此表中为 **叶节点**，不再继续二分。

**Yinjie 三叶节点（峰位命名，真源 `yinjie.py` 字段注释）：**

| 结构段 | 峰位 | 代码字段 | 质料填充（乐音 **音段** = 音质段 + 联结调段；见 [sound_variable_analysis.md](project/syllable_analysis/sound_variable_analysis.md)） |

|--------|------|----------|------|

| 呼音 | 峰前段 | `ascender` | **结构位置名** — **≠ 韵头 / 介音**（后者只是部分类型下的音质段名）。按干音类型填充：**三质 / 后长** — 由韵头及与其联结的调段构成的音段；**前长** — 由韵腹前段及与其联结的调段构成的音段；**单质** — 由韵母前段及与其联结的调段构成的音段 |
| 主音 | 峰段 | `peak` | **结构位置名**。**三质** — 由韵腹及与其联结的调段构成的音段；**前长** — 由韵腹后段及与其联结的调段构成的音段；**后长** — 由韵腹前段及与其联结的调段构成的音段；**单质** — 由韵母中段及与其联结的调段构成的音段 |
| 末音 | 峰后段 | `descender` | **结构位置名** — **≠ 韵尾 / coda**。**三质 / 前长** — 由韵尾及与其联结的调段构成的音段；**后长** — 由韵腹后段及与其联结的调段构成的音段；**单质** — 由韵母后段及与其联结的调段构成的音段 |

规范写法：`peak` 对应中文峰位名统一记作 **峰段**；不再使用“峰值段”或“主峰段”。

**不得** 用韵头/韵尾/介音/coda 等英文名反写替换上表 **结构段** 名（呼音 / 主音 / 末音）。

**首音 (shouyin)** — 音段层定义（见 `syllable.py`）：

- **严格（生成音系学）**：声母及与其联结的声调段构成的音段
- **通俗（结构音系学 / 日常说法）**：声母 / 辅音（initial consonant）
- **对举说明**：与干音「韵母 + 联结调段」对称；**就具体首音而言**，严格定义与「声母/辅音」一致（模块原文：实际就是声母）。零声母等边界情形见 `ShouyinEncoder` 与首音码表。

**干音 (ganyin)** — 音段层定义（见 `syllable.py`）：

- **严格（生成音系学）**：韵母及与其联结的声调段构成的音段
- **通俗（结构音系学 / 日常说法）**：带声调的韵母（final with tone）

**噪音 (zaoyin)** 与 **乐音 (yueyin)** 是 **音元类别**：噪音 **填充** 首音段；乐音 **填充** 干音在 Yinjie 模型内的呼/主/末子段。类别名 **不能** 替代上述音段定义，也不与首音/干音 **同级**。

```text
音节 (yinjie)                          ← 结构：分析单位
├── 首音 (shouyin)                     ← 声母+联结调段（声母/辅音）；材料：噪音类音元 (zaoyin)
└── 干音 (ganyin)                      ← 韵母+联结调段（带调韵母）；下为 Yinjie 内部分解；≠ 乐音 (yueyin)
    ├── 呼音 (huyin)                   ← 峰前段 (ascender)；≠ 韵头/介音
    └── 韵音 (yunyin)                  ← 结构段
        ├── 主音 (peak)                ← 峰段
        └── 末音 (descender)           ← 峰后段；≠ 韵尾/coda
```

与 `syllable.py` / `yinjie.py` 一致的原句：

> **首音**：由声母和与其联结的调段构成的音段，即声母（辅音）。
> **干音**：由韵母和与其联结的调段构成的音段，即带调韵母。
> **音节分成** 首音和干音两段；干音分成呼音和韵音两段；韵音分成主音和末音两段。
> 首音由噪音充当；呼音、主音和末音由乐音充当；噪音和乐音统称音元。

**常见误解（务必避免）：**

- ❌ 呼音 = **韵头 / 介音**（呼音是 Yinjie **峰前段**；三质/后长上由「韵头 + 联结调段」**音段** 填充，前长/单质上由「韵腹前段 / 韵母前段 + 联结调段」**音段** 填充 — 均 **≠** 把结构段直呼为韵头）
- ❌ 末音 = **韵尾 / coda**（末音是 **峰后段**；三质/前长上由「韵尾 + 联结调段」**音段** 填充，后长/单质上由「韵腹后段 / 韵母后段 + 联结调段」**音段** 填充 — 均 **≠** 把结构段直呼为韵尾）
- ❌ 首音 = **噪音类别**（首音是 **音段**；噪音是填充首音的 **音元类别**）
- ❌ 干音 = 乐音
- ❌ 干音 = **无调韵母**（干音 **含** 与韵母联结的调段）
- ❌ 音节 = 首音 + 乐音（删掉或合并 **干音** 中间层）
- ❌ 把干音与乐音画成 **同级** 兄弟节点
- ❌ `ganyin` 与 `yueyin` 可以互换命名类或模块
- ❌ 把 `GanyinEncoder` 理解成「只编码乐音」——它编码的是 **干音结构**，内部使用乐音类 **音元**（如 `YueyinYinyuan`）作为材料
- ❌ 把 `YueyinMapper`、`YueyinYinyuan`、`YueyinPianyin` 当成同一层对象（前者是归并/转换流程，后两者分别是音元对象、片音对象）
- ❌ 用通用英语 onset / rime / nucleus / coda **替换并重组** 上树，再反写回中文术语
- ❌ 在 README、注释或对外说明里「为了方便」写 **干音即无调韵母** 或 **干音即韵母即乐音**

**AI 篡改本结构的典型模式（本项目历史教训）：**

1. **压扁层级** — 对外文档写成「首音 + 韵母/乐音」，省略 `ganyin` / `yunyin`。
2. **概念偷换** — 见 `YueyinYinyuan`、`YueyinPianyin` 等名含 yueyin，便断言「干音就是乐音」。
3. **平行类树** — 新建第二套 `Yinjie` / 音节模型，层级与上树不一致。
4. **英文名自造** — `MusicalSegment`、`RimeTone` 等替代 `ganyin` / `yueyin` 拼音标识，加剧与真源脱节。

网上部分二手介绍若混用「干音/乐音/韵母」，**以本树与 `yinjie.py` 为准**；不确定时 **扩写本文**，不要在外部博客式表述里重新定义。

---

## Quick reference (English)

| Term   | Identifier   | Layer   |
| ------ | ------------ | ------- |

| pianyin | phonic slice | concrete temporal slice |
| yinyuan | yinyuan | abstract slot-filling unit |
| yinjie | syllable (Yinjie) | onset + rime-body structure in this project |
| shouyin | shouyin segment | **initial + tone linked to initial** (colloquially: initial / consonant); **not** zaoyin category |
| ganyin | ganyin segment | **final + tone linked to final** (colloquially: toned final); **not** yueyin |
| yueyin | pitched musical segment | class/category; fills huyin / peak / descender inside ganyin |
| huyin | pre-peak segment | `ascender`; **not** medial / onset glide |
| peak (主音) | peak segment | `peak` |
| descender (末音) | post-peak segment | `descender`; **not** rime coda |

Do **not** rename project concepts to generic English (`MusicalSegment`, `RimeTone`, etc.) without reading [syllable/NAMING.md](../syllable/NAMING.md).

### 给英文背景 / 英文用户向 AI 的特别提醒

> **To AI assistants whose priors are English phonetics, IPA glossaries, or generic NLP syllable APIs:**
> We know you “already know” **onset, rime, nucleus, coda, phoneme, tone, and medial**. **They are not licensed substitutes for 首音、干音、呼音、主音、末音、音元、片音 in this repository.**
> Earlier English-first “helpful rewrites” (flattening 干音 into “toned rime”, equating 干音 with 乐音 because of `Yueyin*`, calling 呼音 *medial* or 末音 *coda*) **already polluted docs and code once.**
> **Do not translate-then-write-back.** Keep pinyin identifiers, read [`yinjie.py`](../syllable/codec/yinjie.py) and this page, `grep` before you rename anything you find “unfamiliar”.
> If you cannot map a term cleanly to English, **that is a feature, not a bug** — expand this doc instead of inventing `MusicalSegment`.

中文维护者旁白：专门「气」一下那些不读本页、上来就用 onset/rime/coda 重组音节树、再把英文反写进注释的模型——**你们那套课本默认值，在本仓库里是 bug 来源，不是 shortcut。**

---

## 专题文档（命名、含义、翻译）

下列文档 **分工明确**，本页不重复其正文：

1. **[YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md)** — 时段、片音、音元的定义、中英对照、与传统音位学的区别；**含音节结构术语与常见误解**
2. **[YINYUAN_TERMINOLOGY_EN.md](YINYUAN_TERMINOLOGY_EN.md)** — 英文版术语说明
3. **[PIANYIN_TECH_BRIDGE.md](PIANYIN_TECH_BRIDGE.md)** — 片音与语音识别/合成技术单位的衔接
4. **[PIANYIN_TECH_BRIDGE_EN.md](PIANYIN_TECH_BRIDGE_EN.md)** — 英文版片音技术桥接
5. **[syllable/NAMING.md](../syllable/NAMING.md)** — **代码与文件名** 的唯一类名/模块约定（给 AI 与维护者）
6. **[syllable/README.md](../syllable/README.md)** — 编解码包目录与 CLI

理论正文与析音法细节以 **`Yime.wiki` 子模块** 为权威；见 [THEORY_INDEX.md](THEORY_INDEX.md)。

---

## 给 AI 与贡献者的硬性提醒

在生成或修改本仓库代码/文档时：

1. **先读本页 + [syllable/NAMING.md](../syllable/NAMING.md)**，再 `grep` 是否已有同名类或模块。
2. **禁止** 新建第二份 `pianyin.py`、第二个 `PitchedPianyin` 等同义类（见 NAMING 文档中的「禁止」表）。
3. **禁止** 将 `ganyin`（干音结构）与 `yueyin`（乐音类别）混为同一概念或类名。
4. **禁止** 改写 [`syllable/codec/yinjie.py`](../syllable/codec/yinjie.py) 所定义的音节层级（例如压成「首音 + 乐音」、删除干音/韵音中间层、或新建平行 `Yinjie` 结构）。
5. 无法用英文忠实翻译的概念，**保留拼音标识**（`yinyuan`、`pianyin`、`ganyin`），
   不要强行换成 `MusicalYinyuan` 之类自造英文名除非 NAMING 表已登记。
6. 运行时码表键使用 **带调 numeric 拼音**（如 `zhong1`），不要用英文单词键替代。
7. 不确定时 **扩写 [TERMINOLOGY_INDEX.md](TERMINOLOGY_INDEX.md) 音节结构节**，
   不要在外部博客式表述里重新定义术语（易形成错误传播，且曾被 AI 二次放大）。
8. **禁止** 在中文文档里用 **「槽」** 指结构段或四码位；结构用 **段**，四码用 **位**，N/M 用 **语义槽位**（见本文「段/位/时段/语义槽位」节）。

贡献流程亦见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

---

## 与实现约束的关系

术语正确后，仍须遵守：

- [CODEPOINT_POLICY.md](CODEPOINT_POLICY.md) — **语义槽位** N/M 与 projection（「槽位」仅指此层）
- [SOURCE_AND_ARTIFACTS.md](SOURCE_AND_ARTIFACTS.md) — 真源 vs 生成物

---

**维护说明**：新增「音元/片音/音节结构」相关公开术语时，应：

1. 先更新 [YINYUAN_TERMINOLOGY.md](YINYUAN_TERMINOLOGY.md)（及 EN 版）；
2. 再更新 [syllable/NAMING.md](../syllable/NAMING.md)；
3. 最后在本页速查表补一行。
