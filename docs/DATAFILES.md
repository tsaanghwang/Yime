# 数据文件结构说明（DATAFILES.md）

本说明介绍项目主要数据文件（JSON/CSV）结构、字段、用途及扩展方式。

## 1. 主要数据文件

- data_json_files/pinyinCodeTable.json：拼音到编码映射表
- data_json_files/hanziTable.json：编码到汉字映射表
- data_json_files/key_symbol_mapping.json：键位与音元符号映射
- phoneme_dict.json：音元分类字典

## 2. 字段说明与示例

### pinyinCodeTable.json
```json
{
  "zhang1": "A123",
  "li3": "B456"
}
```
- 键：带调拼音
- 值：音元编码

### hanziTable.json
```json
{
  "A123": ["张", "章"],
  "B456": ["李"]
}
```
- 键：音元编码
- 值：汉字数组

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
