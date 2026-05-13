# Legacy Raw-YAML Chain

这个目录保存 `pinyin/hanzi_pinyin/` 下已退出当前主线的旧 raw-yaml 处理链。

已迁入本目录的对象只用于历史审计、人工排障或对照旧生成方式，不再作为当前推荐入口。

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
