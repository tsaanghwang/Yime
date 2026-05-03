# 单字拼音补丁文件使用说明

本文档只说明两个受控补丁文件的分工：

- `numeric_pinyin_patch.csv`
- `canonical_yime_patch.csv`

它们都用于补齐上游 `../pinyin-data/pinyin.txt` 与仓库内音节编码资产之间的缺口，但补的层不同，不应混用。

## 1. 先判断缺口在哪一层

重建或校验后，先运行：

```bash
c:/dev/Yime/.venv/Scripts/python.exe yime/refresh_runtime_yime_codes.py
```

按输出判定：

- 如果样例是 `<missing pinyin_tone>`，说明缺的是 `single_char_readings -> numeric_pinyin_inventory` 这一层，应补 `numeric_pinyin_patch.csv`。
- 如果样例是 `<missing in code map>`，说明数字调拼音已经进库，但 `syllable_codec/yinjie_code.json` 没有对应 canonical 码，应补 `canonical_yime_patch.csv`。
- 如果两者都不是，而是 `单字受旧表唯一约束阻塞行`，这不是补丁文件要解决的问题，而是旧 `音元拼音.全拼 UNIQUE` 结构残留问题。

## 2. 什么时候补 `numeric_pinyin_patch.csv`

补这个文件的条件是：

- 上游单字源没有某条 `pinyin_tone`，导致它根本进不了 `single_char_readings`。
- 导入脚本跑完后，`numeric_pinyin_inventory` 缺这条 `pinyin_tone + mapping_id`。
- `refresh_runtime_yime_codes.py` 报的是 `<missing pinyin_tone>`。

这个文件表达的是“数字调拼音事实缺失”，字段是：

- `pinyin_tone`
- `initial`
- `final`
- `tone_number`
- `mapping_id`
- `legacy_numeric_pinyin_id`

它由 [import_danzi_into_prototype_tables.py](../../yime/import_danzi_into_prototype_tables.py) 消费，用来补齐 `numeric_pinyin_inventory`。

简单说：

- 缺的是“这条数字调拼音事实本身”时，补 `numeric_pinyin_patch.csv`。
- 先补这一层，再谈后面的 canonical 码。

## 3. 什么时候补 `canonical_yime_patch.csv`

补这个文件的条件是：

- 该 `pinyin_tone` 已经存在于 `numeric_pinyin_inventory`。
- 但 `load_canonical_code_map()` 从 `syllable_codec/yinjie_code.json` 里拿不到对应码。
- `refresh_runtime_yime_codes.py` 报的是 `<missing in code map>`。

这个文件表达的是“canonical 音节码缺失”，字段是：

- `pinyin_tone`
- `mapping_id`
- `yime_code`

它由 [canonical_yime_mapping.py](../../yime/canonical_yime_mapping.py) 消费，用来补齐 canonical 码面，并同步到 `pinyin_yime_code`；`mapping_yime_code` 只作为兼容映射面保留。

简单说：

- 数字调拼音已经有了，只是没有 canonical 编码时，补 `canonical_yime_patch.csv`，主线最终会反映到 `pinyin_yime_code`。
- 不要把纯编码问题写进 `numeric_pinyin_patch.csv`。

## 4. 一个最短决策顺序

1. 跑一次 `yime/refresh_runtime_yime_codes.py`。
2. 看到 `<missing pinyin_tone>`：先补 `numeric_pinyin_patch.csv`。
3. 重新导入单字，再跑一次校验。
4. 如果错误变成 `<missing in code map>`：再补 `canonical_yime_patch.csv`。
5. 最后再跑一次 `yime/refresh_runtime_yime_codes.py --apply` 同步数据库。

## 5. 不要这样用

- 不要用 `canonical_yime_patch.csv` 去补一个根本不存在于 `numeric_pinyin_inventory` 的拼音。
- 不要把旧表唯一约束冲突写进任一补丁文件。
- 不要把这两个补丁文件当成长期替代上游真源；它们只是当前仓库内可复现的受控兜底层。

## 6. 当前维护原则

- 能修上游 `pinyin-data` 或主线 `yinjie_code.json` 时，优先修真源。
- 真源暂时不能改、但仓库必须可重建时，才补这里的 CSV。
- 每次补完后，都要重新运行 `yime/refresh_runtime_yime_codes.py` 验证缺口是否按预期从上一层推进到下一层，或直接归零。
