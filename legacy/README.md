# Legacy Raw-YAML Chain

这个目录保存仓库根目录下、已退出当前主线的旧拼音相关归档链。

已迁入本目录的对象只用于历史审计、人工排障或对照旧生成方式，不再作为当前推荐入口，也为后续彻底删除预留独立清理边界。

这条旧链大致是：

- `hanzi_pinyin_raw.yaml`
- `remove_percent.py`
- `hanzi_pinyin.yaml`
- `split_yaml_file.py`
- `yaml_to_json.py`
- `yaml_to_json_danzi_converter.py`
- `yaml_to_json_duozi_converter.py`
- `pinyin_danzi.py`
- `pinyin_duozi.py`
- `pinyin.py`
- `pinyin_validator.py`

当前主线请改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `internal_data/pinyin_source_db/validate_source_pinyin_db.py`
- `internal_data/pinyin_source_db/export_pinyin_normalized.py`

如果只需要从仓库内 YAML 词库导出当前仍保留的 JSON 资产，请改走：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`

注意：迁入本目录后，这批脚本默认不再被 VS Code 的活动调试入口直接暴露。

## Legacy Comparison And Derived-Artifact Chain

下面这批对象也已降级为 legacy：它们主要互相消费，或生成旧比较/反转/Unicode 映射产物，不再属于当前主线 rebuild，也不参与当前最小词库链。

- `extract_pinyin_1.py`
- `extract_pinyin_2.py`
- `format_yaml_file.py`
- `merge_json.py`
- `compare_files.py`
- `pinyin_classifier.py`
- `standard_pinyin.py`
- `reverse_key_value_pairs.py`
- `unicode_hanzi_pinyin.py`
- `pinyin_hanzi.py`

以及它们的典型派生产物：

- `hanzi_to_pinyin.json`
- `pinyin.json`
- `pinyin_classified.json`
- `standard_pinyin.json`
- `standard_pinyin_reversed.json`
- `unicode_hanzi_pinyin.json`
- `unicode_pinyin_hanzi.txt`
- `mspinyin.txt`

这批对象迁档后，不应再被视为当前主线的源或必经中间产物。

另外，下列反向同音字索引 JSON 也已归档到本目录，只供旧数据库迁移脚本或历史排障使用：

- `pinyin_danzi.json`
- `pinyin_duozi.json`
