# 拼音数据迁移说明

本文档只说明当前主线的数据重建入口、独立 `.yaml` 导出入口，以及哪些旧脚本已经降级为 legacy-compatible。

## 1. 当前主线 rebuild 链

当前推荐的数据主线是：

1. 外部上游文本导入到 `source_pinyin.db`
2. 从 `source_pinyin.db` 重建 prototype tables
3. 用 canonical 码面刷新 runtime 资产

对应入口：

- [build_source_pinyin_db.py](/c:/dev/Yime/internal_data/pinyin_source_db/build_source_pinyin_db.py)
- [validate_source_pinyin_db.py](/c:/dev/Yime/internal_data/pinyin_source_db/validate_source_pinyin_db.py)
- [import_danzi_into_prototype_tables.py](/c:/dev/Yime/yime/import_danzi_into_prototype_tables.py)
- [import_duozi_into_prototype_tables.py](/c:/dev/Yime/yime/import_duozi_into_prototype_tables.py)
- [refresh_runtime_yime_codes.py](/c:/dev/Yime/yime/refresh_runtime_yime_codes.py)

这条链的关键点是：

- runtime 主线已经改为 `pinyin_tone -> yime_code`，不再依赖旧 `音元拼音.全拼 UNIQUE`。
- 单字和词语 prototype 导入不再从旧 `汉字 / 数字标调拼音 / 词汇` 表借字段或主键。
- `numeric_pinyin_patch.csv` 与 `canonical_yime_patch.csv` 只作为受控兜底层，不再把旧表当主线真源。

推荐执行顺序：

```bash
c:/dev/Yime/.venv/Scripts/python.exe internal_data/pinyin_source_db/build_source_pinyin_db.py
c:/dev/Yime/.venv/Scripts/python.exe internal_data/pinyin_source_db/validate_source_pinyin_db.py
c:/dev/Yime/.venv/Scripts/python.exe yime/import_danzi_into_prototype_tables.py
c:/dev/Yime/.venv/Scripts/python.exe yime/import_duozi_into_prototype_tables.py
c:/dev/Yime/.venv/Scripts/python.exe yime/refresh_runtime_yime_codes.py --apply
```

## 2. 独立 `.yaml` 导出链

如果你的目标只是从仓库内 `.yaml` 词库导出：

- `danzi_pinyin.json`
- `duozi_pinyin.json`

那么不需要经过 SQLite rebuild 链。

独立入口：

- [export_yaml_lexicon_json.py](/c:/dev/Yime/internal_data/pinyin_source_db/export_yaml_lexicon_json.py)

执行方式：

```bash
c:/dev/Yime/.venv/Scripts/python.exe internal_data/pinyin_source_db/export_yaml_lexicon_json.py
```

这条链只做：

- `hanzi_pinyin_danzi.yaml -> danzi_pinyin.json`
- `hanzi_pinyin_duozi.yaml -> duozi_pinyin.json`

它和 `source_pinyin.db`、prototype tables、runtime refresh 是分离的。

## 3. 当前 legacy-compatible 区域

下面这些对象仍然保留在仓库里，但不属于当前主线 rebuild：

- `yime/db_manager.py`
- `yime/hanzi_db_manager.py`
- `yime/import_numeric_pinyin.py`
- `yime/Import_yinyuan_pinyin.py`
- `yime/consolidate_mappings.py`
- `yime/run_full_import.py`

保留原因：

- 仍被旧文档、旧测试或旧入口引用。
- 仍可用于历史库审计、兼容导入或旧结构排障。

但它们不再定义当前主线的“正确 rebuild 方式”。

## 4. 已归档的旧脚本

已经移入 [yime/legacy/README.md](/c:/dev/Yime/yime/legacy/README.md) 所在目录的脚本，都是只服务旧结构、且当前主线没有引用的工具。

这一步的目的是把主目录中的误用面降下来，避免把旧表检查脚本误认为当前 rebuild 入口。