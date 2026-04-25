# Yueyin Runtime To Layout Audit

日期：2026-04-10

目的：

- 追踪 `syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json` 中干音乐音码元的来源链。
- 对比运行时 `yueyin` 码元与当前布局侧 `M01-M33` 乐音槽位的对应关系。

## 一、来源链总表

| 阶段 | 文件 / 代码 | 作用 | 决定了什么 |
| --- | --- | --- | --- |
| 1 | `syllable/analysis/slice/yinyuan/pitched_yinyuan_of_mid_high_median_model.json` | 定义乐音类音元清单，使用 `˥/˦/˩` 风格 | 最早的乐音类别库存与顺序来源 |
| 2 | `syllable/analysis/slice/yinyuan/variables_of_attributes.json` | 定义音质归并和音高归并规则 | 哪些 IPA 片音会并到同一个乐音码元 |
| 3 | `syllable/analysis/slice/yueyin_yinyuan.py` | 用归并规则把片音转成乐音码元名 | `i˥ -> ɪ˥`、`ɤ˨ -> o˩` 这类归并逻辑 |
| 4 | `syllable/analysis/slice/convert_pitch_style.py` | 把 `˥/˦/˩` 转成 `́/̄/̀` 风格 | `ɪ˥ -> ɪ́`、`o˩ -> ò` 这类自定义组合字符替换 |
| 5 | `syllable/analysis/slice/yinyuan/yueyin_yinyuan_enhanced.json` | 干音唯一真源，显式保存 `semantic_code`、`layout_slot`、`aliases`、`runtime_char` | 乐音语义码、布局槽位与运行时字符的一一对应 |
| 6 | `syllable/analysis/slice/yinyuan/ganyin_to_pianyin_sequence.json` | 干音到三段片音序列的输入表 | 每个干音由哪些“呼音/主音/末音”组成 |
| 7 | `syllable/analysis/slice/ganyin_encoder.py` | 读取增强版真源中的显式 `runtime_char`，并替换三段乐音码元为运行时字符 | `M01-M33` 对应的运行时字符，以及 fixed-length 结果 |
| 8 | `syllable/analysis/slice/yinyuan/yinyuan_codepoint.json` 中的 `yueyin` 段 | 运行时乐音码元到私用区字符的最终映射 | 例如 `ɪ́ -> 􀀠`、`ḿ -> 􀀸` |
| 9 | `syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json` | 每个干音的三字符固定长编码 | 例如 `i1 -> 􀀠􀀠􀀠`、`er1 -> 􀀵􀀵􀀵` |
| 10 | `internal_data/key_to_symbol.json` | 当前布局/KLC 侧使用的 `M01-M33` 符号表 | 布局侧是否和运行时字符一致 |
| 11 | `internal_data/manual_key_layout.json` | 当前候选布局的物理键分配 | 每个 `Mxx` 被放到哪个键位和层级 |

## 二、关键代码锚点

| 位置 | 含义 |
| --- | --- |
| `syllable/analysis/slice/ganyin_encoder.py:13` | 干音唯一真源文件 `yueyin_yinyuan_enhanced.json` |
| `syllable/analysis/slice/ganyin_encoder.py:14` | 兼容乐音清单文件 `yueyin_yinyuan.json` |
| `syllable/analysis/slice/ganyin_encoder.py:32` | 读取增强版真源中的 `entries` |
| `syllable/analysis/slice/ganyin_encoder.py:69` | 构建 canonical yueyin 与 aliases 的显式运行时字符映射 |
| `syllable/analysis/slice/ganyin_encoder.py:181` | 用显式 `yueyin` 映射把乐音码元名替换成运行时字符 |
| `syllable/analysis/slice/ganyin_encoder.py:192` | 把三段结果拼成 fixed-length 编码 |
| `syllable/analysis/slice/yueyin_yinyuan.py:97` | 片音到乐音码元的 mid-high 归并逻辑 |
| `syllable/analysis/slice/yueyin_yinyuan.py:159` | 把 `˥/˦/˩` 风格转换成 `́/̄/̀` 风格 |
| `syllable/analysis/slice/convert_pitch_style.py:49` | 保留输入键顺序，写出 `yueyin_yinyuan.json` |

## 三、IPA 片音到自定义组合字符的关键替换层

这一层是理解整套符号系统的关键。它并不是“直接把 `i˥` 编成私用区字符”，而是先经过两次抽象：

1. 把具体 IPA 片音归并到乐音类音元。
例如：`i˥` 和 `ɪ˥` 并到 `ɪ˥`，`ɤ˥` 并到 `o˥`，`ʅ˥` 和 `ɿ˥` 并到 `󰉺˥`。

2. 再把 `˥/˦/˩` 风格改写成项目自定义的组合字符风格 `́/̄/̀`。
例如：`ɪ˥ -> ɪ́`，`o˩ -> ò`，`m˦ -> m̄`。

| IPA 片音示例 | 归并后乐音类音元 | 自定义组合字符 | 规则来源 |
| --- | --- | --- | --- |
| `i˥`, `ɪ˥` | `ɪ˥` | `ɪ́` | `quality_variables.ɪ` + `pitch_marks.˥` |
| `i˦`, `ɪ˦` | `ɪ˦` | `ɪ̄` | `quality_variables.ɪ` + `pitch_marks.˦` |
| `i˧`, `i˨`, `i˩`, `ɪ˨`, `ɪ˩` | `ɪ˩` | `ɪ̀` | `quality_variables.ɪ` + `mid_high_median_model.L -> ˩` |
| `u˥`, `ᴜ˥` | `ᴜ˥` | `ᴜ́` | `quality_variables.ᴜ` + `pitch_marks.˥` |
| `ʏ˥`, `y˥` | `ʏ˥` | `ʏ́` | `quality_variables.ʏ` + `pitch_marks.˥` |
| `a˥`, `æ˥`, `ɑ˥`, `ᴀ˥` | `ᴀ˥` | `ᴀ́` | `quality_variables.ᴀ` + `pitch_marks.˥` |
| `o˥`, `ɤ˥`, `𐞑˥` | `o˥` | `ó` | `quality_variables.o` + `pitch_marks.˥` |
| `e˥`, `ə˥`, `ᵊ˥`, `ᴇ˥` | `ᴇ˥` | `ᴇ́` | `quality_variables.ᴇ` + `pitch_marks.˥` |
| `ʅ˥`, `ɿ˥` | `󰉺˥` | `󰉺́` | `quality_variables.󰉺` + `pitch_marks.˥` |
| `ɚ˥` | `󰊈˥` | `󰊈́` | `quality_variables.󰊈` + `pitch_marks.˥` |
| `m˥` | `m˥` | `ḿ` | `quality_variables.m` + `pitch_marks.˥` |
| `n˦` | `n˦` | `n̄` | `quality_variables.n` + `pitch_marks.˦` |
| `ŋ˧`, `ŋ˨`, `ŋ˩` | `ŋ˩` | `ŋ̀` | `quality_variables.ŋ` + `mid_high_median_model.L -> ˩` |

对 AI 或语音学读者来说，可以把这一步理解为：

- 输入端是实际 IPA 片音。
- 中间层是项目定义的“乐音类音元”规范化形式。
- 输出端是项目内部通用的自定义组合字符名。
- 私用区字符分配发生在这一步之后，而不是这一步之内。

## 四、运行时 `yueyin` 到当前布局槽位对照

在读取 `internal_data/musical_group_template.json` 里新增的布局字段时，可以按下面理解：

| 字段名 | 含义 | 例子 |
| --- | --- | --- |
| `current_layout_position` | 单个 `Mxx` 当前落在哪个层和物理键 | `base:j`、`shift:n`、`altgr:l` |
| `physical_reading_order_pattern` | 该组成员按当前键盘上实际阅读顺序得到的调位模式 | `高-中-低`、`低-中-高`、`高-低-中` |
| `physical_reading_order_symbol_keys` | 按当前实际阅读顺序排列的 `Mxx` 列表 | `["M06", "M05", "M04"]` |
| `physical_reading_order_tone_roles` | 上一字段对应的调位顺序 | `["low_level", "mid_level", "high_level"]` |
| `physical_reading_order_positions` | 上一字段对应的物理键位顺序 | `["base:x", "base:c", "base:v"]` |

阅读原则：

1. `members` 保留的是该组的定义顺序，也就是高调、中调、低调。
2. `physical_reading_order_*` 反映的是当前键盘上从左到右、从上到下的实际阅读顺序。
3. 如果两者不同，不表示编码错了，只表示当前布局为了手感或分层做了重排。

| 乐音组 | 槽位 | 运行时 `yueyin` 名 | 运行时字符 | 当前布局位置 |
| --- | --- | --- | --- | --- |
| /i/ | M01 | `ɪ́` | `􀀠` | `base:u` |
| /i/ | M02 | `ɪ̄` | `􀀡` | `base:i` |
| /i/ | M03 | `ɪ̀` | `􀀢` | `base:o` |
| /u/ | M04 | `ᴜ́` | `􀀣` | `base:v` |
| /u/ | M05 | `ᴜ̄` | `􀀤` | `base:c` |
| /u/ | M06 | `ᴜ̀` | `􀀥` | `base:x` |
| /ü/ | M07 | `ʏ́` | `􀀦` | `base:n` |
| /ü/ | M08 | `ʏ̄` | `􀀧` | `base:m` |
| /ü/ | M09 | `ʏ̀` | `􀀨` | `base:,` |
| /a/ | M10 | `ᴀ́` | `􀀩` | `base:f` |
| /a/ | M11 | `ᴀ̄` | `􀀪` | `base:d` |
| /a/ | M12 | `ᴀ̀` | `􀀫` | `base:s` |
| /o/并入/e(ɤ)/ | M13 | `ó` | `􀀬` | `base:j` |
| /o/并入/e(ɤ)/ | M14 | `ō` | `􀀭` | `base:k` |
| /o/并入/e(ɤ)/ | M15 | `ò` | `􀀮` | `base:l` |
| /ê/ | M16 | `ᴇ́` | `􀀯` | `base:t` |
| /ê/ | M17 | `ᴇ̄` | `􀀰` | `base:r` |
| /ê/ | M18 | `ᴇ̀` | `􀀱` | `base:e` |
| /-i/ | M19 | `󰉺́` | `􀀲` | `shift:j` |
| /-i/ | M20 | `󰉺̄` | `􀀳` | `shift:k` |
| /-i/ | M21 | `󰉺̀` | `􀀴` | `shift:l` |
| /er/ | M22 | `󰊈́` | `􀀵` | `altgr:p` |
| /er/ | M23 | `󰊈̄` | `􀀶` | `altgr:[` |
| /er/ | M24 | `󰊈̀` | `􀀷` | `altgr:]` |
| /m/ | M25 | `ḿ` | `􀀸` | `altgr:j` |
| /m/ | M26 | `m̄` | `􀀹` | `altgr:k` |
| /m/ | M27 | `m̀` | `􀀺` | `altgr:l` |
| /n/ | M28 | `ń` | `􀀻` | `base:;` |
| /n/ | M29 | `n̄` | `􀀼` | `shift:n` |
| /n/ | M30 | `ǹ` | `􀀽` | `base:'` |
| /ng/ | M31 | `ŋ́` | `􀀾` | `base:.` |
| /ng/ | M32 | `ŋ̄` | `􀀿` | `shift:m` |
| /ng/ | M33 | `ŋ̀` | `􀁀` | `base:/` |

## 五、严格不一致项

### 5.1 字符级不一致

结论：无。

运行时 `yinyuan_codepoint.json` 的 `yueyin` 段，与布局侧 `internal_data/key_to_symbol.json` 的 `M01-M33` 当前是一一一致的。也就是说：

- 运行时 `M01-M33` 对应的私用区字符。
- 当前布局/KLC 侧 `M01-M33` 使用的私用区字符。

这两者目前没有字符级错位。

### 5.2 语义级不一致

1. 当前布局中的若干组，在物理键从左到右的阅读顺序上，并不总是 `高-中-低`。

典型例子：

- `/u/` 组当前是 `x c v = M06 M05 M04`，从左到右是 `低-中-高`。
- `/a/` 组当前是 `s d f = M12 M11 M10`，从左到右是 `低-中-高`。
- `/ê/` 组当前是 `e r t = M18 M17 M16`，从左到右是 `低-中-高`。

这不是字符映射错误，但它和“模板按高-中-低固定顺序理解”的读法不一致，后续复查时容易误判。

1. `/n/` 与 `/ng/` 两组当前在布局层面被拆到 `base + shift`，不是同层连续三连。

具体为：

- `/n/`: `M28=base:;`, `M29=shift:n`, `M30=base:'`
- `/ng/`: `M31=base:.`, `M32=shift:m`, `M33=base:/`

这同样不是运行时与字符表的错误，但它和“组内三成员集中放置”的直觉不一致。

## 六、审计结论

1. `ganyin_to_fixed_length_yinyuan_sequence.json` 中的干音乐音运行时字符，现已由 `ganyin_encoder.py` 直接读取 `yueyin_yinyuan_enhanced.json` 中显式声明的 `runtime_char` 得到，不再依赖键顺序或 `0x100020 + i`。

2. 当前布局侧 `M01-M33` 使用的字符，与运行时 `yueyin` 字符集完全一致；没有字符级错位。

3. `internal_data/musical_group_template.json` 现已与运行时术语对齐，已补充：

- 运行时语义标签。
- `normalized_yueyin_base`。
- 每个 `Mxx` 的 `runtime_yueyin_name`。

1. 当前还需要关注的不是“字符表错了”，而是“物理布局阅读顺序”是否会让人误判：

- 若要长期维护，建议在布局文档里明确哪些组是按 `高-中-低` 摆放，哪些是按 `低-中-高` 摆放。
