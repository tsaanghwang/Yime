# Legacy Scripts

这个目录只存放已经脱离当前主线 rebuild/runtime 路径的旧结构脚本。

当前顶层只保留几组按职责拆开的 legacy 子目录：

- `maintenance_tests/`：仍会被人工执行的旧结构维护/观测测试。
- `manual_db_experiments/`：仍会直连主 `pinyin_hanzi.db` 做手动排查的旧实验入口。
- `pinyin_db_prototype/`：更早的 `pinyin.db` 原型链；保留建库、导入 `shengmu.csv`、回写 `initial_ipa.json` 以及对应实验数据库。
- `pending_removal/`：旧 schema / 旧数据库接口的 legacy-compatible 保留面。

这些内容的共同特点是：

- 直接检查或修改旧 `音元拼音 / 数字标调拼音` 结构。
- 不再属于当前主线 `source_pinyin.db -> prototype tables -> runtime_candidates` 的必要环节。
- 默认不作为主线入口维护；除兼容包装仍会引用的实现外，其余都应视为归档资料。
- 继续保留仅为了历史审计、旧库排查或人工迁移参考。

换句话说，本目录默认视为“仓库内归档资料”，而不是当前可安装包、发布产物或主线 rebuild 流程的一部分。

当前这类 legacy-compatible 数据库 / JSON 实现已按职责拆开：

- `yime/legacy/pending_removal/`
- `yime/utils/legacy_pinyin_tables/`

其中：

- `yime/legacy/pending_removal/` 保留旧 schema / 旧数据库接口
- `yime/utils/legacy_pinyin_tables/` 保留三张拼音参考表的生成与校验链

其中一组旧中文辅助视图，以及旧 `汉字音元拼音映射` / `汉字数字标调拼音映射` / `词语搜索*` / `通用单字搜索*` / `专用单字` / `字符` / `字符扩展` / `字词` / `字词关联` / `生僻单字` / `词语` / `通用单字` / `词汇` / `汉字` / `汉字频率` 等表都已退场；当前保留的兼容面仅剩旧拼音参考表与其迁移辅助脚本。

后者当前包括：

- `split_numeric_pinyin.py`
- `rebuild_yinyuan_structure_table.py`
- `consolidate_mappings.py`
- `Initialize_pinyin_mapping.py`
- `compat_internal_data/*.json`

前者当前包括：

- `db_manager.py`

现在这些 legacy 入口的真实实现已经分别落在 `yime/legacy/pending_removal/` 与 `yime/utils/legacy_pinyin_tables/`，不再继续保留 `yime/` 主目录下的同名兼容包装文件。

如果需要当前主线的数据重建，请不要从本目录中的脚本开始，而应改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）
