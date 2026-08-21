# 数字标调拼音补丁使用规则

本目录只保留 `numeric_pinyin_patch.csv` 一种补丁。它只补充上游缺失的
“数字标调拼音事实”，不能直接指定音元编码、Yinyuan ID 或键位。

## 允许补的层

仅当上游单字源缺少某条 `pinyin_tone`，导致它无法进入
`numeric_pinyin_inventory`，并且刷新程序报告 `<missing pinyin_tone>` 时，才可补
`numeric_pinyin_patch.csv`。

字段为：

- `pinyin_tone`
- `initial`
- `final`
- `tone_number`
- `mapping_id`
- `legacy_numeric_pinyin_id`

补丁由
[import_danzi_into_prototype_tables.py](../../yime/import_danzi_into_prototype_tables.py)
消费。补完后必须重新导入并验证。

## 禁止从编码中间层补丁直入

`canonical_yime_patch.csv` 已退役并禁止恢复。遇到 `<missing in code map>` 时，
不得手写“拼音 → 四音元码”兜底；必须回到正式链查明缺口：

```text
数字标调拼音
  -> SyllableEncodingPipeline / YinjieEncoder
  -> 首音段 + 第2至第4音元
  -> 4 个 Yinyuan ID
  -> runtime / canonical symbol
```

需要修复的是这条链上的真源或编码规则，并重新生成
`syllable/codec/yinjie_code.json`。布局修改不能改动这条语义链。

## 最短判断顺序

1. 运行 `yime/refresh_runtime_yime_codes.py`。
2. 如果是 `<missing pinyin_tone>`，核实上游后补 `numeric_pinyin_patch.csv`。
3. 重新导入单字并再次验证。
4. 如果是 `<missing in code map>`，停止补丁操作，修复正式音节编码链。
5. 最后运行 `yime/refresh_runtime_yime_codes.py --apply` 同步数据库。

布局改动另受 [布局改动锁](../../docs/LAYOUT_CHANGE_LOCK.md) 约束，必须运行：

```bash
python tools/run_locked_layout_pipeline.py
```
