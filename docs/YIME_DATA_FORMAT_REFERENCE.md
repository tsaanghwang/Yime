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

**规模**：1624 条数据 + 1 行标题，约 32 KB。

**特殊规则**：含 `ü` 的键会自动生成 `v` 和 `u:` 别名（如 `lü3` → `lv3`、`lu:3`）。

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

**规模**：约 1729 条，约 33 KB。

### yime_pua_pinyin.json

候选注释使用的 PUA 音元序列→数字标调拼音映射。Go 后端加载后会反转为“数字标调拼音→PUA 音元序列”，仅用于候选注释显示。

```json
{
  "PUA 音元序列": ["a1"]
}
```

该文件不参与 Rime 按键解析和词库编码；Rime 内部仍使用 `yime_pinyin_codes.tsv` 中的 ASCII 编码。`fonts/YinYuan-Regular.ttf` 提供 PUA 字形，由安装包注册到 Windows 字体目录。

### yime_variable.dict.yaml / yime_full.dict.yaml / yime_shorthand.dict.yaml

Rime 系统词库，每种编码方案一个文件。三者是由唯一导入的
`yime_full.dict.yaml` 生成的内部运行产物，不是三份独立数据源；请勿手工修改。

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

**规模**：每种方案约 468,166 条，约 9.5-10 MB。

同目录的 `yime_lexicon_manifest.json` 记录唯一导入文件的 SHA-256、
转换和布局版本、词条数，以及三套生成词典的 SHA-256。发布或安装前应以该清单
检查三套文件是否来自同一次生成。

**注意**：1.9% 的词条有多个编码（多音字），最多 11 个编码（欸）。

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
| redeploy_revision | 最近一次要求重新部署的修订号；没有时省略 |

兼容旧格式中的 `scope` 和 `requires_redeploy`；读取时会把旧标记映射到对应修订号。写入由 `.yime-runtime-change.lock` 跨进程串行化，锁文件只在更新期间短暂存在。无法解析的旧标记会备份为 `yime_runtime_change.json.corrupt` 后重建，便于诊断而不阻断后续通知。

### yime_variable.custom.yaml / yime_full.custom.yaml / yime_shorthand.custom.yaml

Rime 方案自定义配置，由设置工具和候选数设置写入。

**格式**：Rime custom.yaml 格式。

```yaml
patch:
  "menu/page_size": 7
```

**注意**：`menu/page_size` 键可能被引号包围（`"menu/page_size"`）也可能不被引号包围，读写时必须同时支持两种形式。

## 日志文件

| 文件 | 路径 | 说明 |
|------|------|------|
| go_backend.log | `%APPDATA%\PIME\Rime\go_backend.log` | Go 后端主日志 |
| rime_deployer.log | `%APPDATA%\PIME\Rime\rime_deployer.log` | Rime 部署日志 |

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
├── go_backend.log                 # 后端日志
└── pime_yime_tool_hub.json        # 工具箱 manifest（自动生成）
```
