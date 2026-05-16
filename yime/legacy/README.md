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
- `Initialize_pinyin_mapping.py`
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
- `test_index_constraint.py`
这些脚本的共同特点是：

- 直接检查或修改旧 `音元拼音 / 数字标调拼音` 结构。
- 一部分文件还是带阶段命名的试验性测试变体，用于当时逐步试错 `db_manager.py` 的旧表结构与连接方式。
- 另一部分则是直接连到 `yime/pinyin_hanzi.db` 的只读探针、一次性约束检查脚本或第三方库用法样例，并不属于当前应维护的自动化测试面。
- 还包括一条更早的 `pinyin.db` 原型链：用 `create_table.py` 建库、`import_initial.py` 导入 `shengmu.csv`、再由 `update_table.py` 把上层 `initial_ipa.json` 写回旧 `initial` 表；对应的旧实验数据库也一并归档为 `pinyin.db`。
- 不再属于当前主线 `source_pinyin.db -> prototype tables -> runtime_candidates` 的必要环节。
- 当前默认不作为主线入口维护；但其中被主目录兼容包装层直接依赖的模块会继续随包分发，避免安装环境中的兼容入口失效；其余内容仍应视为归档资料，而不是当前主线 rebuild 路径。
- 继续保留仅为了历史审计、旧库排查或人工迁移参考。

换句话说，本目录默认视为“仓库内归档资料”，而不是当前可安装包、发布产物或主线 rebuild 流程的一部分。

当前这类 legacy-compatible 数据库 / JSON 实现已按职责拆开：

- `yime/legacy/pending_removal/`
- `yime/utils/legacy_pinyin_tables/`

其中：

- `yime/legacy/pending_removal/` 保留旧 schema / 旧数据库接口
- `yime/utils/legacy_pinyin_tables/` 保留三张拼音参考表的生成与校验链

其中一组旧中文辅助视图（`多音字视图`、`拼音映射视图`、`汉字拼音映射视图`、`汉字标准拼音视图`、`汉字音元拼音视图`）已不再保留为兼容面，因为当前主线和保留的 legacy 入口都不再读取它们。

旧 `汉字音元拼音映射` / `汉字数字标调拼音映射` 两张关联表、旧 `词汇` 表，以及旧 `汉字` / `汉字频率` 表也已退场；当前保留的兼容面仅剩旧拼音参考表与其迁移辅助脚本。

后者当前包括：

- `split_numeric_pinyin.py`
- `rebuild_yinyuan_structure_table.py`
- `consolidate_mappings.py`
- `run_full_import.py`
- `Initialize_pinyin_mapping.py`
- `compat_internal_data/*.json`

前者当前包括：

- `db_manager.py`

现在这些 legacy 入口的真实实现已经分别落在 `yime/legacy/pending_removal/` 与 `yime/utils/legacy_pinyin_tables/`，不再继续保留 `yime/` 主目录下的同名兼容包装文件。

如果需要当前主线的数据重建，请不要从本目录中的脚本开始，而应改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`

如果只需要从 `.yaml` 导出 JSON，请改走：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`
