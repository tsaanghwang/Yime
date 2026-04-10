# Zaoyin Runtime To Layout Audit

日期：2026-04-10

目的：

- 追踪 `syllable/analysis/slice/yinyuan/shouyin_codepoint.json` 中首音码元的来源链。
- 对比运行时 `zaoyin` / `首音` 码元与当前布局侧 `N01-N24` 首音槽位的对应关系。
- 说明首音链路与乐音链路的关键差异，避免把两套流程混为一谈。

## 一、来源链总表

| 阶段 | 文件 / 代码 | 作用 | 决定了什么 |
| --- | --- | --- | --- |
| 1 | `syllable/analysis/slice/yinyuan/zaoyin_yinyuan.json` | 定义首音标签与 IPA 示例的对应关系 | 最早的首音类别库存、标签名和顺序来源 |
| 2 | `syllable/analysis/slice/shouyin_encoder.py` 中 `process_shouyin()` | 读取 `zaoyin_yinyuan.json` 的 `shouyin` 键，并直接返回其键顺序 | 进入码位分配前的首音标签顺序 |
| 3 | `syllable/analysis/slice/shouyin_encoder.py` 中 `map_yinyuan_to_codepoint()` | 从 `0x100000` 开始按顺序给首音标签分配私用区字符 | `N01-N24` 对应的运行时私用区字符 |
| 4 | `syllable/analysis/slice/yinyuan/shouyin_codepoint.json` | 保存首音标签到私用区字符的最终运行时映射 | 例如 `b -> 􀀀`、`zh -> 􀀎`、`y -> 􀀗` |
| 5 | `syllable/analysis/slice/yinyuan/yinyuan_codepoint.json` 中的 `zaoyin` 段 | 保存与 `shouyin_codepoint.json` 平行的一份运行时首音映射 | 运行时总映射文件中的首音部分 |
| 6 | `internal_data/key_to_symbol.json` | 当前布局/KLC 侧使用的 `N01-N24` 符号表 | 布局侧字符是否和运行时首音字符一致 |
| 7 | `internal_data/manual_key_layout.json` / `internal_data/manual_key_layout.resolved.json` | 当前候选布局的物理键分配 | 每个 `Nxx` 被放到哪个键位和层级 |

## 二、与乐音链路的关键差别

首音链路比乐音链路短，而且没有“IPA 片音归并 -> 自定义组合字符替换”这一层。

可以直接这样理解：

1. `zaoyin_yinyuan.json` 先给出一个首音标签，例如 `b`、`zh`、`y`。
2. 同一个标签下面挂若干 IPA 示例，用于解释这个标签代表哪类发音。
3. `shouyin_encoder.py` 不再做乐音那种 `i˥ -> ɪ˥ -> ɪ́` 的二次规范化，而是直接拿这些标签名按顺序分配私用区字符。

所以首音链路里：

- `b`、`p`、`zh`、`y` 这些标签本身就是运行时分类名。
- IPA 只是说明这个标签覆盖哪些实际音值。
- 私用区字符分配直接作用于这些标签名。

## 三、关键代码锚点

| 位置 | 含义 |
| --- | --- |
| `syllable/analysis/slice/shouyin_encoder.py:12` | 首音码位起点 `START_CODEPOINT = 0x100000` |
| `syllable/analysis/slice/shouyin_encoder.py:14` | 首音源文件 `zaoyin_yinyuan.json` |
| `syllable/analysis/slice/shouyin_encoder.py:15` | 运行时首音映射输出文件 `shouyin_codepoint.json` |
| `syllable/analysis/slice/shouyin_encoder.py:40` | 按顺序分配首音私用区字符 |
| `syllable/analysis/slice/shouyin_encoder.py:86` | 处理首音源数据并提取键顺序 |
| `syllable/analysis/slice/shouyin_encoder.py:97` | 直接返回 `list(shouyin.keys())`，保留源文件键顺序 |
| `syllable/analysis/slice/shouyin_encoder.py:115` | 写入 `yinyuan_codepoint.json` 的 `zaoyin` 段 |
| `syllable/analysis/slice/shouyin_encoder.py:151` | 写入 `shouyin_codepoint.json` 的 `首音` 段 |

## 四、源标签、IPA 示例、运行时字符与当前布局位置对照

| 槽位 | 首音标签 | IPA 示例 | 运行时字符 | 当前布局位置 |
| --- | --- | --- | --- | --- |
| N01 | `b` | `p` | `􀀀` | `base:h` |
| N02 | `p` | `pʰ` | `􀀁` | `base:y` |
| N03 | `f` | `f`, `ɸ` | `􀀂` | `base:p` |
| N04 | `m` | `m` | `􀀃` | `base:[` |
| N05 | `d` | `t` | `􀀄` | `base:g` |
| N06 | `t` | `tʰ` | `􀀅` | `base:b` |
| N07 | `l` | `l`, `ɾ` | `􀀆` | `base:a` |
| N08 | `n` | `n`, `n̠` | `􀀇` | `base:z` |
| N09 | `g` | `k` | `􀀈` | `base:8` |
| N10 | `k` | `kʰ` | `􀀉` | `base:9` |
| N11 | `h` | `x`, `χ`, `h` | `􀀊` | `base:0` |
| N12 | `z` | `ʦ` | `􀀋` | `base:5` |
| N13 | `c` | `ʦʰ` | `􀀌` | `base:6` |
| N14 | `s` | `s` | `􀀍` | `base:7` |
| N15 | `zh` | `ʈʂ`, `ꭧ` | `􀀎` | `base:4` |
| N16 | `ch` | `ʈʂʰ`, `ʦʰ` | `􀀏` | `base:3` |
| N17 | `sh` | `ʂ` | `􀀐` | `base:2` |
| N18 | `r` | `ɻ`, `ʐ`, `ɹ`, `z` | `􀀑` | `base:1` |
| N19 | `j` | `ʨ` | `􀀒` | `base:w` |
| N20 | `q` | `ʨʰ` | `􀀓` | `base:q` |
| N21 | `x` | `ɕ` | `􀀔` | `base:]` |
| N22 | `'` | `ʔ`, ``, `ɣ`, `ŋ` | `􀀕` | 未放入当前布局 |
| N23 | `w` | `w`, `ʋ` | `􀀖` | 未放入当前布局 |
| N24 | `y` | `j`, `ɥ` | `􀀗` | 未放入当前布局 |

## 五、如何读取首音模板字段

在读取 `internal_data/shouyin_group_template.json` 里新增的布局字段时，可以按下面理解：

| 字段名 | 含义 | 例子 |
| --- | --- | --- |
| `runtime_semantic_label` | 该小组在运行时链路里对应的语义类别说明 | `唇音与相关唇部首音`、`翘舌组` |
| `current_layout_position` | 单个 `Nxx` 当前落在哪个层和物理键 | `base:h`、`base:4`、`base:]` |
| `physical_reading_order_symbol_keys` | 该小组按当前实际阅读顺序排列的 `Nxx` 列表 | `['N18', 'N17', 'N16', 'N15']` |
| `physical_reading_order_source_names` | 上一字段对应的运行时首音标签顺序 | `['r', 'sh', 'ch', 'zh']` |
| `physical_reading_order_positions` | 上一字段对应的物理键位顺序 | `['base:1', 'base:2', 'base:3', 'base:4']` |
| `unplaced_symbol_keys` | 仍在运行时库存和模板里、但当前布局未落位的槽位 | `['N22']`、`['N23']` |

阅读原则：

1. `members` 保留的是模板定义顺序，也就是该组的概念分组顺序，不一定等于当前键盘上的实际阅读顺序。
2. `physical_reading_order_*` 反映的是当前键盘上从左到右、从上到下的实际阅读顺序。
3. `source_name` 就是运行时首音标签名，也是 `shouyin_codepoint.json` 的直接键名，不需要像乐音那样再经过一次 IPA 归并或自定义组合字符替换。
4. `ipa_examples` 只负责解释 `source_name` 覆盖哪些实际音值，不参与再次规范化。
5. 如果某个 `Nxx` 出现在 `unplaced_symbol_keys` 里，不代表运行时没有这个字符，只表示当前键盘还没有给它分配物理键位。

## 六、严格不一致项

### 6.1 字符级不一致

结论：无。

运行时 `shouyin_codepoint.json` / `yinyuan_codepoint.json` 的 `zaoyin` 段，与布局侧 `internal_data/key_to_symbol.json` 的 `N01-N24` 当前是一一一致的。

### 6.2 布局级不一致

1. 当前布局只实际放置了 `N01-N21`。

`N22`、`N23`、`N24` 这三个运行时首音字符当前仍然存在，但没有进入当前候选布局的物理键位分配。

1. `internal_data/shouyin_group_template.json` 仍把 `N22/N23/N24` 作为模板成员保留。

这不是编码错误，但说明：

- 运行时首音库存是 24 个。
- 当前候选布局实际只启用了前 21 个槽位。
- 零首音 / 半元音占位是否重新纳入布局，仍然是一个单独的设计决策。

## 七、审计结论

1. 首音链路没有乐音链路里的“IPA 归并后再替换成自定义组合字符”步骤；它直接以首音标签为运行时分类名来分配私用区字符。

2. 当前运行时首音字符集与布局侧 `N01-N24` 字符表完全一致，没有字符级错位。

3. 当前真正需要注意的不是字符映射，而是布局覆盖范围：`N22/N23/N24` 仍然存在于运行时和模板中，但尚未进入当前候选布局。
