# Legacy Scripts

这个目录只存放已经脱离当前主线 rebuild/runtime 路径的旧结构脚本。

当前已归档到这里的文件：

- `cleanup_test_rows.py`
- `consolidate_mappings.py`
- `db_checks.py`
- `db_inspect.py`
- `db_inspect_verbose.py`
- `db_table_list.py`
- `export_mappings_csv.py`
- `migrate_pinyin_table.py`
- `create_table.py`
- `import_initial.py`
- `pinyin.db`
- `update_table.py`
- `shengmu.csv`
- `run_full_import.py`
- `jsonpath_example.py`
- `safe_test_unique.py`
- `safe_test_unique_ignore.py`
- `test_db_manager.py`
- `test_db_manager_working.py`
- `test_db_manager_simple.py`
- `test_db_manager_refactored.py`
- `test_db_manager_real.py`
- `test_db_manager_final.py`
- `test_db_manager_final_v2.py`
- `test_duplicate_groups.py`
- `test_hanzi_db_manager.py`
- `test_hanzi_pinyin_data.py`
- `test_index_constraint.py`
- `test_pinyin_db_manager.py`

这些脚本的共同特点是：

- 直接检查或修改旧 `音元拼音 / 数字标调拼音 / 词汇` 结构。
- 一部分文件还是带阶段命名的试验性测试变体，用于当时逐步试错 `db_manager.py` 的旧表结构与连接方式。
- 另一部分则是直接连到 `yime/pinyin_hanzi.db` 的只读探针、一次性约束检查脚本或第三方库用法样例，并不属于当前应维护的自动化测试面。
- 还包括一条更早的 `pinyin.db` 原型链：用 `create_table.py` 建库、`import_initial.py` 导入 `shengmu.csv`、再由 `update_table.py` 把上层 `initial_ipa.json` 写回旧 `initial` 表；对应的旧实验数据库也一并归档为 `pinyin.db`。
- 不再属于当前主线 `source_pinyin.db -> prototype tables -> runtime_candidates` 的必要环节。
- 当前也已从项目的构建/分发路径中排除：`MANIFEST.in` 会 `prune yime/legacy`，`pyproject.toml` 也不再将 `yime.legacy*` 纳入包发现；原先暂放在仓库根目录的 legacy 迁移目录也已在清理轮次中移除。
- 继续保留仅为了历史审计、旧库排查或人工迁移参考。

换句话说，本目录默认视为“仓库内归档资料”，而不是当前可安装包、发布产物或主线 rebuild 流程的一部分。

当前没有归档、但仍应视为 legacy-compatible 的文件：

- `db_manager.py`
- `hanzi_db_manager.py`
- `import_numeric_pinyin.py`
- `Import_yinyuan_pinyin.py`

它们之所以暂时保留在主目录，是因为仍有旧文档、旧测试或旧入口引用，不适合在这一轮直接移动。

其中 `consolidate_mappings.py` 与 `run_full_import.py` 的主体实现现已归档到本目录；主目录同名文件只保留极薄的兼容包装入口，避免旧命令路径立即失效。

如果需要当前主线的数据重建，请不要从本目录中的脚本开始，而应改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`

如果只需要从 `.yaml` 导出 JSON，请改走：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`
