# 首音细分规则与真源 Schema 提案

## 文档目的

本文档定义一层位于《汉语拼音方案》正字法之后的“首音细分层”。

这层规则的用途不是重写拼音方案，而是把拼音书写中被合并、省略或折叠的起首差异，整理成对编码链更稳定的首音语义类别。

当前优先处理三组现象：

1. `y -> j / ɥ`
2. `' -> 纯零起首 / ŋ 类起首`
3. `r -> r_ɹ / r`

## 设计原则

1. splitter 层优先产出“实际辅音类别”，而不是仅产出抽象拼音声母字母。
2. 运行时编码阶段允许先把细分标签映射回当前 canonical 首音条目，避免一次性打断现有编码链。
3. 对于拼音正字法没有稳定显式信号的现象，不强行自动猜测；优先走显式 override。

## 真源 Schema 提案

建议首音真源在现有字段基础上，增加下列可选字段：

```json
{
  "entries": {
    "y": {
      "display_label": "y",
      "ipa": ["j", "ɥ"],
      "type": "unstable_pitch_yinyuan",
      "semantic_code": "UPY_Y",
      "runtime_char": "",
      "layout_slot": "N24",
      "splitter_aliases": ["y_j", "y_rounded"]
    },
    "'": {
      "display_label": "'",
      "ipa": ["ʔ", "", "ɣ", "ŋ"],
      "type": "mixed_yinyuan",
      "semantic_code": "UPY_'",
      "runtime_char": "",
      "layout_slot": "N12",
      "splitter_aliases": ["zero_plain", "zero_ng"]
    },
    "r_ɹ": {
      "display_label": "r_ɹ",
      "ipa": ["ɹ", "z"],
      "type": "unstable_pitch_yinyuan",
      "semantic_code": "UPY_R_ɹ",
      "runtime_char": "",
      "layout_slot": "N16",
      "splitter_aliases": ["R_ɹ_flat_variant"]
    }
  }
}
```

### 字段说明

1. `display_label`
   - 面向人工阅读的显示标签。
   - 不要求在运行时唯一。

2. `splitter_aliases`
   - splitter 输出的细分首音标签列表。
   - 这些标签在运行时可先映射回当前 canonical 条目。
   - 未来若扩槽，可以再从 alias 升格为独立 entry。

## splitter 判别规则表

| 规则组 | 输入模式 | splitter 输出 | 当前运行时 canonical 映射 | 说明 |
| --- | --- | --- | --- | --- |
| `y -> j` | `ya/ye/yao/you/yan/yin/yang/ying/yong` 等 `y` 引导且不属 `yu` 系 | `y_j` | `y` | 表示更接近硬腭近音 `j` 的起首 |
| `y -> ɥ` | `yu/yue/yuan/yun` | `y_rounded` | `y` | 表示更接近圆唇硬腭近音 `ɥ` 的起首 |
| 零起首普通类 | 元音起首、`ê/m/n` 特殊音节 | `zero_plain` | `'` | 汇总 `ʔ`、空起首、`ɣ` 等零起首情况 |
| 零起首鼻音类 | `ng/ng1/ng2/ng3/ng4/ng5` | `zero_ng` | `'` | 单列 `ŋ` 类起首，便于编码和语音说明 |
| `r -> r_ɹ` | 由显式 override 规则表命中 | `r_ɹ` | `r_ɹ` | 单列 `ɹ/z` 类实际起首，避免后续槽位字符错位 |

## 自动规则与 override 规则

### 自动规则

当前可稳定自动判别的只有两类：

1. `y_j` / `y_rounded`
2. `zero_plain` / `zero_ng`

### override 规则

`r_ɹ` 目前不根据拼音字面自动推断，而是走显式 override。

原因如下：

1. 《汉语拼音方案》不会稳定标出这种变体。
2. 单靠拼音字面无法可靠判断某个音节是否应落入该变体槽。
3. 这类事实更适合由词表、方音说明或工程例外表显式指定。

建议 override 表使用如下形态：

```json
{
  "ri1": "r_ɹ",
  "ri2": "r_ɹ"
}
```

## 与当前运行时链的关系

当前阶段，splitter 输出细分标签后，运行时仍允许先回落到 canonical 首音键：

1. `y_j -> y`
2. `y_rounded -> y`
3. `zero_plain -> '`
4. `zero_ng -> '`
5. `R_ɹ_flat_variant -> r_ɹ`

这样做的好处是：

1. 细分规则可以先在切分层生效。
2. 当前 `shouyin_codepoint.json` 和 `yinyuan_codepoint.json` 中，`r_ɹ` 已是显式槽位，不再回落到 `r`。
3. 后续若决定扩为 27 槽，可直接把 alias 升格为独立 entry。

## 后续演进建议

1. 若决定为 `y_j / y_rounded / zero_plain / zero_ng` 再继续分配独立槽位，应先把 alias 升格为独立真源条目。
2. 升格后再更新 `layout_slot`、`runtime_char`、`key_to_code.json` 和统一校验器。
3. 在此之前，保持“splitter 细分、runtime 回落”的兼容模式最稳。
