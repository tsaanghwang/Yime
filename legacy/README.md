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

另外，原 `pinyin/plugins/` 下的实验性插件包也已迁入 `legacy/pinyin_plugins/`：

- `pinyin_plugins/__init__.py`
- `pinyin_plugins/default_rules.py`
- `pinyin_plugins/example_plugin.py`

这套插件接口没有接入当前 `pinyin/yunmu_to_keys.py` 主链，且内部 API 已与现状分叉，因此仅保留作历史对照，不再视为活动扩展点。

另外，原 `pinyin/` 主目录下的两份 `yunmu_to_keys` 手工副本也已迁入 `legacy/pinyin_snapshots/`：

- `pinyin_snapshots/yunmu_to_keys copy.py`
- `pinyin_snapshots/yunmu_to_keys copy 2.py`

它们都是对 `pinyin/yunmu_to_keys.py` 的历史分叉快照，没有活跃入口，也不应继续留在当前活动实现旁边制造误导。

另外，原 `pinyin/` 主目录下孤立的 `yinjie` 生成链也已迁入 `legacy/pinyin_generated/`：

- `pinyin_generated/generate_yinjie.py`
- `pinyin_generated/yinjie.json`

这条链只有脚本自写自读式输出，没有当前运行、测试、导入或发布主线消费者，更接近历史试验产物而不是现行真源。

另外，原 `pinyin/` 主目录下几份没有代码层消费者的数据快照也应视为归档对象，已迁入 `legacy/pinyin_data_snapshots/`：

- `pinyin_data_snapshots/initial.json`
- `pinyin_data_snapshots/neutral_tone_syllable.json`
- `pinyin_data_snapshots/shengdiao.json`
- `pinyin_data_snapshots/shengmu.csv`
- `pinyin_data_snapshots/shengmu_enhanced.json`
- `pinyin_data_snapshots/unconverted_lines.json`
- `pinyin_data_snapshots/yunmu.json`
- `pinyin_data_snapshots/yunmu_enhanced.json`

它们与当前 `pinyin` 包的活跃 API 没有直接代码消费关系，继续留在包根目录只会放大“这里仍是拼音主数据仓”的误解。

另外，原 `pinyin/` 主目录下两个边缘工具也已迁入 legacy：

- `pinyin_generated/keys_to_yunmu.py`
- `pinyin_generated/keys_to_yunmu.json`
- `pinyin_analysis/compare_pinyin_lists.py`

其中 `keys_to_yunmu` 只是从 `yunmu_to_keys.json` 派生反向映射的孤立导出链，没有主线消费者；`compare_pinyin_lists.py` 则直接依赖已不存在的 `pinyin/pinyin_to_hanzi.json`，属于失效的历史分析脚本。

另外，原 `pinyin/` 包剩余的 `yunmu` helper 实现也已整体迁入 `legacy/pinyin_package/`：

- `pinyin_package/__init__.py`
- `pinyin_package/constants.py`
- `pinyin_package/conversion_stats.json`
- `pinyin_package/rule_plugin.py`
- `pinyin_package/yunmu_to_keys.py`
- `pinyin_package/yunmu_to_keys.json`
- `pinyin_package/test/`

它们不再被当前运行时、数据 rebuild 链或打包面使用；保留仅为历史对照和局部算法考古。
