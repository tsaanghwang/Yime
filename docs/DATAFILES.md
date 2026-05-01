# 数据文件结构说明（DATAFILES.md）

本说明介绍项目主要数据文件（JSON/CSV）结构、字段、用途及扩展方式。

## 1. 主要数据文件

- data_json_files/key_symbol_mapping.json：键位与音元符号映射
- key_to_code.json：运行时键位槽位到字符映射
- yime/reports/phoneme_dict.json：音元分类导出报告

补充说明：旧 JS 原型链使用过的 `pinyinCodeTable.json` 与 `hanziTable.json` 已随原型链一起迁出到单独的 `Yime-js-prototype` 仓库，不再属于主仓库当前主线数据资产。

## 2. 字段说明与示例

### key_symbol_mapping.json

```json
{
  "A": "ʈʂ",
  "B": "l"
}
```

- 键：键位
- 值：音元符号

### key_to_code.json

```json
{
  "N01": "ㄅ",
  "M01": "ˉ"
}
```

- 键：运行时槽位编码
- 值：对应字符

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
