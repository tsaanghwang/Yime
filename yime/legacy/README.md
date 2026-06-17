# Legacy Scripts

这个目录只存放已经脱离当前主线 rebuild/runtime 路径的旧结构脚本。

当前仅保留：

- `pending_removal/windows_candidate_box.py`：已退役的 Windows Tk 候选框测试壳（仍被 `yime/windows_candidate_box.py` shim 引用）。

`db_manager.py`、`run_db_setup.py`、`yime/utils/legacy_pinyin_tables/` 三表生成链已于 2026-06 删除；恢复请查 git 历史。

音节结构/解码兼容实现已迁到 `yime/utils/syllable_compat/`，根目录 `yime/syllable_structure.py` 与 `yime/syllable_decoder.py` 仍为公开 shim。

如果需要当前主线的数据重建，请改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `yime/import_danzi_into_prototype_tables.py`
- `yime/import_duozi_into_prototype_tables.py`
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）
