# 数据文件结构说明（DATAFILES.md）

本说明介绍项目主要数据文件（JSON/CSV）结构、字段、用途及扩展方式。

## 1. 主要数据文件

- internal_data/key_symbol_mapping.json：键位与音元符号映射
- internal_data/ganyin_pinyin_mapping.json：PUA 音元序列到带调干音字符串映射
- internal_data/ipa_pinyin_mapping.json：带调 IPA / 音标串到数字调拼音映射
- external_data/finals_IPA_mapping.json：finals 侧外部 IPA 输入映射
- external_data/initials_IPA_mapping.json：initials 侧外部 IPA 输入映射
- `syllable/codec/key_to_code.json`：运行时键位槽位到字符映射（见 [syllable/README.md](../syllable/README.md)）
- yime/reports/phoneme_dict.json：音元分类导出报告

补充说明：旧 JS 原型链使用过的 `pinyinCodeTable.json` 与
`hanziTable.json` 已随原型链一起迁出到单独的
`Yime-js-prototype` 仓库，不再属于主仓库当前主线数据资产。

## 2. 字段说明与示例

### internal_data/key_symbol_mapping.json

```json
{
  "A": "ʈʂ",
  "B": "l"
}
```

- 键：键位
- 值：音元符号

### internal_data/ganyin_pinyin_mapping.json

- 键：项目内部使用的 PUA 音元序列
- 值：对应的带调干音字符串
- 性质：项目内生映射，不属于外部原始语料

### internal_data/ipa_pinyin_mapping.json

- 键：带调 IPA / 音标串
- 值：对应的数字调拼音
- 性质：项目内生对照映射，不属于外部原始语料

### external_data/finals_IPA_mapping.json / external_data/initials_IPA_mapping.json

- 角色：外部 IPA 输入映射
- 用途：作为 `tools/final_components.py`、`tools/final_classifier.py` 等现行链路的上游输入
- 边界：它们不是内部派生产物，不应与
  `internal_data/ipa_of_finals.json`、
  `internal_data/yinyuan_pianyin_mapping.json`
  这类内部整理结果混并

### 可下载外部频率资源

- `external_data/unihan_readings/unihan_readings.db`：
  `view_tghz2013_frequency` 提供《通用规范汉字表》8105 字 +
  BCC 单字频；`yime/refresh_runtime_yime_codes.py` 据此构建
  `char_usage_profile` 的 3500/6500/8105 分层边界，不再依赖
  `8105.dict.yaml`。
- `external_data/word_freq/`、`external_data/char_freq/`：
  BCC 合并词频目录；见
  [external_data/word_freq_README.md](../external_data/word_freq_README.md)。
  `yime/import_blcu_word_frequency.py` 按
  `char_frequency_policy.py` 写入 `phrase_frequency` /
  `char_inventory.char_frequency_abs`；
  `yime/refresh_runtime_yime_codes.py` 读取
  `merged_char_freq.txt` 构建 `char_modern_common_profile`（BCC 序位），
  并按当前字频量级为 `char_usage_profile` 动态定标 5 档
  `tier_sort_weight`，TGHZ 分层与非 TGHZ 辅助排序分别来自
  `unihan_readings.db` 与 `char_inventory`。
- 边界：它们属于可重新下载的外部公开资源，不属于仓库当前必须跟踪的 `internal_data` 真源或派生产物。

### 单字动态分档设计

- 单字需求权重真源是 BCC **字频频道**合并结果
  `external_data/char_freq/merged_char_freq.txt`，不是 `word_freq`
  频道里顺带出现的单字行；后者只保留作对照，不参与 runtime
  写库。详见
  [external_data/word_freq_README.md](../external_data/word_freq_README.md)。
- `char_inventory.char_frequency_abs` 写入的是 BCC 原始整数
  `count`；只有 BCC 未命中的长尾字才回退到 Unihan `5..1/0`
  合成序位。因为这套真实字频量级已经明显高于旧原型时期的样本基数，
  固定 `4000万/3000万/2000万/1000万/0` 骨架不再可靠。
- 当前 `char_usage_profile` 仍保留 3500 / 6500 / 8105 / 13000 /
  其余 的 5 档边界，但 `tier_sort_weight` 不再写死旧量级，而是先估算
  “真频率 + 现代常用轻量约束 + 读音先验 + 读音权重”的当前非分档上界，
  再按 `1000万` 粒度向上取整，得到动态 `tier_step`。
- 运行时排序语义因此变成：先用动态 5 档骨架稳定隔开层级，再在层内叠加 BCC 原始单字频率与轻量修正项。这样既保留 TGHZ 分层的可解释性，也避免旧骨架被新频率量级直接穿透。
- JSON 导出层会把 `sort_weight` 量化到固定小数位，
  只是为了消除 `3.7152000000000003` 这类二进制尾差显示；
  SQLite 内部排序与 runtime 决策仍按原始数值和 SQL 顺序执行。

### syllable/codec/key_to_code.json

```json
{
  "N01": "ㄅ",
  "M01": "ˉ"
}
```

- 键：运行时槽位编码
- 值：对应字符
- 位置：随 `syllable.codec` 子包一起维护的运行时映射文件

### yime/reports/phoneme_dict.json

```json
{
  "noise_phonemes": ["ㄅ", "ㄆ"],
  "musical_phonemes": ["ˉ", "ˊ"]
}
```

- 键：分类名称
- 值：当前真源全量解码后得到的音元列表
- 性质：可再生导出报告，不是运行时输入真源

## 3. 扩展方式

- 可直接添加新拼音、编码、汉字等条目
- 保持键值唯一性，避免冲突
- 详细结构见各 JSON 文件注释

---

如需具体 API 说明，请参考 [API.md](API.md)。
