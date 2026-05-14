# 数据文件结构说明（DATAFILES.md）

本说明介绍项目主要数据文件（JSON/CSV）结构、字段、用途及扩展方式。

## 1. 主要数据文件

- internal_data/key_symbol_mapping.json：键位与音元符号映射
- internal_data/ganyin_pinyin_mapping.json：PUA 音元序列到带调干音字符串映射
- internal_data/ipa_pinyin_mapping.json：带调 IPA / 音标串到数字调拼音映射
- external_data/finals_IPA_mapping.json：finals 侧外部 IPA 输入映射
- external_data/initials_IPA_mapping.json：initials 侧外部 IPA 输入映射
- syllable/codec/key_to_code.json：运行时键位槽位到字符映射
- yime/reports/phoneme_dict.json：音元分类导出报告

补充说明：旧 JS 原型链使用过的 `pinyinCodeTable.json` 与 `hanziTable.json` 已随原型链一起迁出到单独的 `Yime-js-prototype` 仓库，不再属于主仓库当前主线数据资产。

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
- 用途：作为 `tools/final_components.py`、`tools/final_classifier.py`、`tools/orchestrator.py` 等链路的上游输入
- 边界：它们不是内部派生产物，不应与 `internal_data/ipa_of_finals.json`、`internal_data/yinyuan_pianyin_mapping.json` 这类内部整理结果混并

### 可下载外部频率资源

- `external_data/8105.dict.yaml`：可选单字频率增强输入；缺失时，`yime/refresh_runtime_yime_codes.py` 与 `yime/import_8105_char_frequency.py` 会跳过对应增强步骤。
- `external_data/xiandaihaiyuchangyongcibiao.txt`：可选单字/词频增强输入；缺失时，`yime/refresh_runtime_yime_codes.py` 与 `yime/import_xiandaihaiyu_phrase_frequency.py` 会跳过对应增强步骤。
- 边界：它们属于可重新下载的外部公开资源，不属于仓库当前必须跟踪的 `internal_data` 真源或派生产物。

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
