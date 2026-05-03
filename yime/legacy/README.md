# Legacy Scripts

这个目录只存放已经脱离当前主线 rebuild/runtime 路径的旧结构脚本。

当前已归档到这里的文件：

- `cleanup_test_rows.py`
- `db_checks.py`
- `db_inspect.py`
- `db_inspect_verbose.py`
- `db_table_list.py`
- `export_mappings_csv.py`
- `migrate_pinyin_table.py`

这些脚本的共同特点是：

- 直接检查或修改旧 `音元拼音 / 数字标调拼音 / 词汇` 结构。
- 不再属于当前主线 `source_pinyin.db -> prototype tables -> runtime_candidates` 的必要环节。
- 继续保留仅为了历史审计、旧库排查或人工迁移参考。

当前没有归档、但仍应视为 legacy-compatible 的文件：

- `db_manager.py`
- `hanzi_db_manager.py`
- `import_numeric_pinyin.py`
- `Import_yinyuan_pinyin.py`
- `consolidate_mappings.py`
- `run_full_import.py`

它们之所以暂时保留在主目录，是因为仍有旧文档、旧测试或旧入口引用，不适合在这一轮直接移动。

如果需要当前主线的数据重建，请不要从本目录中的脚本开始，而应改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`

如果只需要从 `.yaml` 导出 JSON，请改走：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`