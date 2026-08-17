# Yime 数据文件格式参考

本文档描述 Yime 输入法使用的所有数据文件格式，供开发者调试和高级用户手动编辑参考。

## 共享数据文件

共享数据位于 `<install-dir>\input_methods\yime\data\`（如 `C:\Program Files (x86)\YIME\go-backend\input_methods\yime\data\`）。

### yime_pinyin_codes.tsv

拼音→编码映射表，被反查工具和词库管理器使用。

**格式**：TSV（Tab 分隔），首行为标题行。

| 列 | 名称 | 说明 | 示例 |
|----|------|------|------|
| 1 | pinyin_tone | 数字标调拼音 | `a1`、`ai2` |
| 2 | full | 等长编码（4 键） | `Hfff`、`Hsdf` |

**示例**：
```
pinyin_tone	full
a1	Hfff
a2	Hsdf
ai1	Hffu
```

该文件只保存拼音到音元编码的等长映射，不再保存派生模式。变长码和省键码由 Go 包
`input_methods/yime/codemode` 在加载时推导，不允许再作为可维护列写回该文件。

#### 首音、干音与三模式派生

等长模式下，每个音节固定由四个音元构成。第一位是实首音或虚首音；位于首音后的三位共同组成
干音，依次是呼音、主音和末音。这里的“干音”是音节结构术语，不能把它理解成一个可整体合并的
单独音元。

首音分为两类：实首音对应传统汉语语音学的非零声母，虚首音对应零声母。按本项目采用的汉语
语音学口径，零声母在《汉语拼音方案》中的书写表现包括隔音符号 `'` 以及 `y`、`w`，它们分别由
相应的虚首音进入编码。这里谈传统音节结构时使用“声母”，谈音元拼音的第一编码位置及其音元时
使用“首音”，二者不能直接替换。

变长模式固定保留首音，只合并组成干音的相邻相同音元。设呼音、主音、末音依次为三位，则四种
结构严格按下表处理：

| 等长干音 | 条件 | 变长干音 |
|---|---|---|
| `ABC` | 三个音元不同 | `ABC`，保持不变 |
| `AAC` | 只有前两个音元相同 | `AC`，合并呼音和主音 |
| `ABB` | 只有后两个音元相同 | `AB`，合并主音和末音 |
| `AAA` | 三个音元相同 | `A`，三者合并为一个音元 |

省键模式以变长模式为输入，只对变长后仍由三个同音质音元构成、且调级为高—中—低或
低—中—高的干音，省略中间的中调音元。虚首音是连续输入时的显式音节边界，在变长和省键模式中
均不删除；其中隔音符号型虚首音 `'` 尤其不能当作冗余字符省略。

**规模**：当前 1733 条数据 + 1 行标题，约 19 KB。实际数量必须与 handoff 清单的
`layout_code_inventory_count` 一致。

`yime_syllable_inventory_manifest.json` 记录原型物化表的来源修订、1733 条数字标调
音节集合的稳定 SHA-256，以及 canonical-only 清单。Go 门禁会对运行音节排序后逐行
计算同一哈希，防止没有来源候选的音节重新混入运行清单。

**特殊规则**：含 `ü` 的键会自动生成 `v` 和 `u:` 别名（如 `lü3` → `lv3`、`lu:3`）。

### yime_erhua_reverse_source.tsv

已进入三模式运行附加词典的显式融合儿化路线反查旁表。该文件由儿化混合派生器生成，只负责
恢复“基础音元如何附加卷舌/鼻化特征、形成派生儿化音元并投影到键位”的解释信息，不参与 Rime
候选生成。

**格式**：TSV，首行为固定标题行，共 12 列：

| 列 | 说明 |
|---|---|
| record_id | 显式儿化来源记录 ID |
| text | 候选文字 |
| source_kind | 授权来源类型 |
| compatibility_numeric_pinyin | 未改写规范词典的儿缀兼容数字拼音 |
| feature_rule_id | 从基础音元元组生成特征改写的规则 ID |
| attached_syllable_source | 被儿化附着的原音节 |
| source_yinyuan_ids | 发生儿化前的四位置基础音元元组 |
| derived_yinyuan_ids | 施加卷舌/鼻化特征后的派生儿化音元元组 |
| key_projection | 基础音元 + 特征 → 派生音元 ID → 物理键的投影说明 |
| full_code | 等长融合码 |
| variable_code | 变长融合码 |
| shorthand_code | 省键融合码 |

当前为 89 行记录；实际行数及文件 SHA-256 必须与 `yime_erhua_mixed_manifest.json` 一致。旁表
缺失时普通反查保持可用，但不显示融合儿化解释。不得据此旁表从词尾“儿”类推未审定词条。

### pinyin_normalized.json

数字标调拼音→Unicode 标调拼音映射，被反查工具使用。

**格式**：JSON 对象，键为数字标调拼音，值为 Unicode 标调拼音。

```json
{
  "a1": "ā",
  "a2": "á",
  "a3": "ǎ",
  "a4": "à",
  "a5": "a",
  "ai1": "āi"
}
```

**声调规则**：1-4 对应四声标记，5 为轻声（无标记）。

**规模**：当前 canonical 审计库存 1737 条，约 33 KB。运行时物化且有布局编码的音节
为 1733 条；`guai2`、`kuai1`、`ra4`、`tin4` 只保留在 canonical 审计层，不进入
候选、反查或练习题库。其中 `kuai1` 在当前统一来源库中没有单字、词语、接纳或拒绝记录。

### yime_pua_pinyin.json

候选注释使用的 PUA 音元序列→数字标调拼音映射。Go 后端加载后会反转为“数字标调拼音→PUA 音元序列”，仅用于候选注释显示。

```json
{
  "PUA 音元序列": ["a1"]
}
```

该文件不参与 Rime 按键解析和词库编码；Rime 内部仍使用 `yime_pinyin_codes.tsv` 中的 ASCII 编码。`fonts/YinYuan-Regular.ttf` 提供 PUA 字形，由安装包注册到 Windows 字体目录。

### yime_full / yime_variable / yime_shorthand.dict.yaml

Windows 三模式运行词库。三者由原型交付的整理后核心等长词典一次性派生，文本、读音和权重完全
同源，只有编码投影不同。安装包同时携带三套 dict 和对应 schema。

**格式**：Rime dict.yaml 格式。`---` 到 `...` 之间为头部元数据，`...` 之后为词条数据。

```
# Rime dictionary
---
name: yime_variable
version: "<normalized-source-hash-prefix>"
sort: by_weight
...
词条	编码	权重
幅	qu	240230122
逼	qu	240110193
```

| 列 | 说明 | 示例 |
|----|------|------|
| 词条 | 汉字或词组 | `幅`、`中国` |
| 编码 | Yime 编码 | `qu`、`7dgo` |
| 权重 | 整数，越大越优先 | `240230122` |

**规模**：每种模式当前1,167,057条；实际数量以
`yime_lexicon_manifest.json` 的 `entry_count` 为准，不应在导入脚本之外手工调整。

同目录的 `yime_core_source_manifest.json` 记录原型修订、来源/筛选 SHA-256 和 BCC、
RIME-LMDG、结构保底的独立证据计数；`yime_lexicon_manifest.json` 记录派生规则版本、词条数及
三模式输出 SHA-256；`yime_runtime_profile.json` 记录默认方案、运行词典和用户候选层。

**注意**：同一文本可以有多个编码（多音字）。相关数量和占比必须从当前
证据清单和生成词典重新统计，不得沿用其他数据版本的历史指标。

## 用户数据文件

用户数据位于 `%APPDATA%\PIME\Rime\`。

### yime_user_phrases.txt

用户词库源文件，被词库管理器编辑。

**格式**：TSV，`#` 开头为注释，空行忽略，LF 换行。

```
# PIME Yime user phrases
# format: phrase<TAB>numeric-tone-pinyin<TAB>weight
# example: 中国	zhong1 guo2	1000000
中国	zhong1 guo2	1000000
北京	bei3 jing1
```

| 列 | 必填 | 说明 | 示例 |
|----|------|------|------|
| 词条 | 是 | 汉字或词组 | `中国` |
| 数字标调拼音 | 是 | 空格分隔的多字拼音 | `zhong1 guo2` |
| 权重 | 否 | 整数，默认 1000000 | `1000000` |

**约束**：
- 词条不能含 Tab、CR、LF
- 权重必须是整数
- 同词条重复写入会覆盖（upsert）

**生成产物**：应用后生成 `custom_phrase_variable.txt`、`custom_phrase_full.txt`、`custom_phrase_shorthand.txt`，其中拼音列替换为对应方案的 Yime 编码。

### yime_blocklist.txt

用户屏蔽词表，被屏蔽词管理器编辑。

**格式**：纯文本，每行一个屏蔽词，`#` 开头为注释，空行忽略，CRLF 换行。

```
# PIME Yime user blocklist
# format: one blocked phrase per line
# example: 某个不想看到的词
呢
的
```

**约束**：
- 词条不能含 Tab、CR、LF
- 长度不超过 64 个 Unicode 字符
- 重复词条自动去重

### yime_settings_state.json

设置状态文件，记录用户偏好。

**格式**：JSON，2 空格缩进，尾部换行。

```json
{
  "reverse_lookup_display_mode": "key_sequence",
  "candidate_layout": "vertical"
}
```

| 字段 | 有效值 | 默认值 | 说明 |
|------|--------|--------|------|
| reverse_lookup_display_mode | `hidden`、`standard_pinyin`、`yime_pinyin`、`key_sequence` | `key_sequence` | 候选窗反查注释显示模式 |
| candidate_layout | `vertical`、`horizontal` | `vertical` | 候选排列方向 |

### yime_runtime_change.json

独立工具通知活动输入会话刷新设置、词库缓存或 Rime 部署状态的广播标记。它不是单消费者队列，每个 IME 会话独立记录已处理的修订号。

```json
{
  "revision": 1700000000000000000,
  "settings_revision": 1700000000000000000,
  "lexicon_revision": 1699999999999999999,
  "redeploy_revision": 1700000000000000000
}
```

| 字段 | 说明 |
|------|------|
| revision | 最近一次任意变更的单调修订号 |
| settings_revision | 最近一次设置变更修订号；没有时省略 |
| lexicon_revision | 最近一次词库变更修订号；没有时省略 |
| redeploy_revision | 最近一次外部构建完成、要求活动会话安全重建的修订号；没有时省略 |

兼容旧格式中的 `scope` 和 `requires_redeploy`；读取时会把旧标记映射到对应修订号。`scope: redeploy` 表示纯维护部署，不增加设置或词库修订号。写入由 `.yime-runtime-change.lock` 跨进程串行化，锁文件只在更新期间短暂存在。无法解析的旧标记会备份为 `yime_runtime_change.json.corrupt` 后重建，便于诊断而不阻断后续通知。

### yime_variable.custom.yaml / yime_full.custom.yaml / yime_shorthand.custom.yaml

Rime 方案自定义配置，由设置工具和候选数设置写入。

**格式**：Rime custom.yaml 格式。

```yaml
patch:
  "menu/page_size": 7
```

### YIME 用户数据备份

设置工具把备份写入 Windows“文档\YIME 备份”下的时间戳目录。每个快照包含：

- `yime-backup.json`：格式版本、用途、创建时间，以及每个文件的相对路径、大小和 SHA-256。
- `data\`：设置、用户词库、屏蔽词表、Rime `sync` 快照及其他可移植用户数据。

备份排除可重新生成的 `build`、运行时通知临时文件，以及输入法运行时锁定且不能一致复制的 `*.userdb` LevelDB 目录。恢复前必须验证清单和全部文件摘要，并另建 `pre-restore-safety` 安全快照；恢复后由 `rime_deployer` 更新运行数据。

**注意**：`menu/page_size` 键可能被引号包围（`"menu/page_size"`）也可能不被引号包围，读写时必须同时支持两种形式。

## 日志文件

| 文件 | 路径 | 说明 |
|------|------|------|
| `go_backend.log` | `%LOCALAPPDATA%\PIME\Logs\go_backend.log` | Go 后端当前主日志 |
| `go_backend.log.1` 至 `.5` | `%LOCALAPPDATA%\PIME\Logs\` | 达到 10 MiB 后轮转的历史日志，最多保留 5 份 |

外部 `rime_deployer.exe` 的标准输出和错误输出由调用方捕获并写入
`go_backend.log` 或显示在工具错误摘要中；当前程序不约定
`%APPDATA%\PIME\Rime\rime_deployer.log` 这一独立日志文件。

## 目录结构

```
%APPDATA%\PIME\Rime\
├── yime_user_phrases.txt          # 用户词库
├── yime_blocklist.txt             # 屏蔽词表
├── yime_settings_state.json       # 设置状态
├── yime_variable.custom.yaml      # 变长方案自定义
├── yime_full.custom.yaml          # 等长方案自定义
├── yime_shorthand.custom.yaml     # 省键方案自定义
├── custom_phrase_variable.txt     # 用户词库生成（变长）
├── custom_phrase_full.txt         # 用户词库生成（等长）
├── custom_phrase_shorthand.txt    # 用户词库生成（省键）
├── build/                         # Rime 编译缓存
└── pime_yime_tool_hub.json        # 工具箱 manifest（自动生成）
```

Go 后端日志不在这棵用户数据目录中，而在
`%LOCALAPPDATA%\PIME\Logs\`。
