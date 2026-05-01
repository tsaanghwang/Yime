# 数据文件结构说明（DATAFILES.md）

本说明介绍项目主要数据文件（JSON/CSV）结构、字段、用途及扩展方式。

## 1. 主要数据文件

- data_json_files/key_symbol_mapping.json：键位与音元符号映射
- phoneme_dict.json：音元分类字典

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

### phoneme_dict.json

```json
{
  "A": "噪音",
  "B": "乐音"
}
```

- 键：音元编码
- 值：音元类型

## 3. 扩展方式

- 可直接添加新拼音、编码、汉字等条目
- 保持键值唯一性，避免冲突
- 详细结构见各 JSON 文件注释

---

如需具体 API 说明，请参考 [API.md](API.md)。
