# Legacy Scripts

这个目录只存放已经脱离当前主线 rebuild/runtime 路径的旧结构脚本。

当前仅保留：

- `pending_removal/`：旧 schema / 旧数据库接口的 legacy-compatible 保留面（`db_manager.py`、`windows_candidate_box.py`、`run_db_setup.py`）。

`maintenance_tests/`、`manual_db_experiments/`、`pinyin_db_prototype/` 已于 2026-06 删除；恢复请查 git 历史。

这些内容的共同特点是：

- 直接检查或修改旧 `音元拼音 / 数字标调拼音` 结构。
- 不再属于当前主线 `source_pinyin.db -> prototype tables -> runtime_candidates` 的必要环节。
- 默认不作为主线入口维护；除兼容包装仍会引用的实现外，其余都应视为归档资料。

换句话说，本目录默认视为“仓库内归档资料”，而不是当前可安装包、发布产物或主线 rebuild 流程的一部分。

当前这类 legacy-compatible 数据库 / JSON 实现已按职责拆开：

- `yime/legacy/pending_removal/`
- `yime/utils/legacy_pinyin_tables/`

其中：

- `yime/legacy/pending_removal/` 保留旧 schema / 旧数据库接口
- `yime/utils/legacy_pinyin_tables/` 保留三张拼音参考表的生成与校验链

后者当前包括：

- `split_numeric_pinyin.py`
- `rebuild_yinyuan_structure_table.py`
- `consolidate_mappings.py`
- `Initialize_pinyin_mapping.py`
- `compat_internal_data/*.json`

前者当前包括：

- `db_manager.py`

如果需要当前主线的数据重建，请不要从本目录中的脚本开始，而应改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）
