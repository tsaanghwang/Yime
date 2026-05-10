# Archived Migration Helpers

这个目录保存原 `yime/migrations` 下的历史维护脚本与 SQL。

它们已从 `yime/` 包目录迁到仓库根目录下，并明确标记为待删除归档，目的是在彻底删除前再保留一段时间，避免继续给当前包结构造成误导。

它们不属于当前主线 rebuild/runtime 路径，仅为以下用途保留：

- 旧 SQLite / MySQL 迁移排查
- 历史数据修复与核对
- 人工迁移参考

当前主线请改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`

本目录中的脚本默认视为手工运维工具，不应被新代码继续依赖。
