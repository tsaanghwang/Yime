# Legacy Raw-YAML Chain

这个目录保存仓库根目录下、已退出当前主线的旧拼音相关归档链。

已迁入本目录的对象只用于历史审计、人工排障或对照旧生成方式，不再作为当前推荐入口，也为后续彻底删除预留独立清理边界。

## Reading Guide

阅读本目录时，可以先按三类理解：

- 带有“当前主线请改走”说明的段落：表示这里只保留历史链，真实入口已经迁到现行目录。
- `legacy/*_tools/`、`legacy/*_scripts/`、`legacy/diagnostic_scripts/`：表示仍可手动运行、但只用于旧链路排障或兼容包装的历史脚本。
- `legacy/*_snapshots/`、`legacy/*_generated/`、`legacy/comparison_chain/` 这类目录：表示历史快照、派生产物或旧数据链，不应再视为当前真源。

这条旧链现已整体下沉到 `legacy/raw_yaml_chain/`，大致包括：

- `raw_yaml_chain/hanzi_pinyin_raw.yaml`
- `raw_yaml_chain/remove_percent.py`
- `raw_yaml_chain/hanzi_pinyin.yaml`
- `raw_yaml_chain/split_yaml_file.py`
- `raw_yaml_chain/yaml_to_json.py`
- `raw_yaml_chain/yaml_to_json_danzi_converter.py`
- `raw_yaml_chain/yaml_to_json_duozi_converter.py`
- `raw_yaml_chain/pinyin_danzi.py`
- `raw_yaml_chain/pinyin_duozi.py`
- `raw_yaml_chain/pinyin.py`
- `raw_yaml_chain/pinyin_validator.py`

当前主线请改走：

- `internal_data/pinyin_source_db/build_source_pinyin_db.py`
- `internal_data/pinyin_source_db/validate_source_pinyin_db.py`
- `internal_data/pinyin_source_db/export_pinyin_normalized.py`

如果只需要从仓库内 YAML 词库导出当前仍保留的 JSON 资产，请改走：

- `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`

注意：迁入本目录后，这批脚本默认不再被 VS Code 的活动调试入口直接暴露。

## Legacy Comparison And Derived-Artifact Chain

下面这批对象也已降级为 legacy，并已整体下沉到 `legacy/comparison_chain/`：它们主要互相消费，或生成旧比较/反转/Unicode 映射产物，不再属于当前主线 rebuild，也不参与当前最小词库链。

- `comparison_chain/extract_pinyin_1.py`
- `comparison_chain/extract_pinyin_2.py`
- `comparison_chain/format_yaml_file.py`
- `comparison_chain/merge_json.py`
- `comparison_chain/compare_files.py`
- `comparison_chain/pinyin_classifier.py`
- `comparison_chain/standard_pinyin.py`
- `comparison_chain/reverse_key_value_pairs.py`
- `comparison_chain/unicode_hanzi_pinyin.py`
- `comparison_chain/pinyin_hanzi.py`

以及它们的典型派生产物：

- `comparison_chain/hanzi_to_pinyin.json`
- `comparison_chain/pinyin.json`
- `comparison_chain/pinyin_classified.json`
- `comparison_chain/standard_pinyin.json`
- `comparison_chain/standard_pinyin_reversed.json`
- `comparison_chain/unicode_hanzi_pinyin.json`
- `comparison_chain/unicode_pinyin_hanzi.txt`
- `comparison_chain/mspinyin.txt`

这批对象迁档后，不应再被视为当前主线的源或必经中间产物。

另外，下列反向同音字索引 JSON 也已归档到 `legacy/comparison_chain/`，只供旧数据库迁移脚本或历史排障使用：

- `comparison_chain/pinyin_danzi.json`
- `comparison_chain/pinyin_duozi.json`

另外，原 `pinyin/plugins/` 下的实验性插件包也已迁入 `legacy/pinyin_plugins/`：

- `pinyin_plugins/__init__.py`
- `pinyin_plugins/default_rules.py`
- `pinyin_plugins/example_plugin.py`

这套插件接口没有接入当前 `pinyin/yunmu_to_keys.py` 主链，且内部 API 已与现状分叉，因此仅保留作历史对照，不再视为活动扩展点。

## Legacy Pinyin-Side Artifacts

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

这一组对象目前仍保留为完整旧包，而不是继续拆成更多子目录，因为它内部还自带 `test/`，并且 [docs/DEVELOPMENT.md](c:/dev/Yime/docs/DEVELOPMENT.md) 仍把它当作“维护已归档旧 helper”时的局部参考面。就当前职责来看，它更像一个自洽的历史包快照，而不是一堆应继续下沉拆散的杂项文件。

## Legacy Syllable-Side Artifacts

另外，原 `syllable/` 根目录下几份未接入当前主线的原型模块和目录快照也已迁入 legacy：

- `syllable_prototypes/syllable_mapper.py`
- `syllable_prototypes/syllable_factory.py`
- `syllable_prototypes/three_models.py`
- `syllable_prototypes/syllable_analyzer_strategy.py`
- `syllable_prototypes/analysis/initial_final_with_tone/initial_final_with_tone_analyzer.py`
- `syllable_prototypes/analysis/slice_analyzer.py`

这些文件主要服务于早期“声母韵母声调 <-> slice”原型抽象，当前运行时、`yinjie` 编码链、测试和打包面都不再消费；继续留在活动包根目录只会制造它们仍属现行 API 的误解。

这一组对象目前仍适合整体保留在 `legacy/syllable_prototypes/` 下，而不是继续拆成更多零散快照目录，因为它们和 `analysis/initial_final_with_tone/` 一起构成了一套相对完整的早期原型尝试。当前更合适的整理方式是只消掉没有信息增量的单文件子目录，例如把只剩一个 `slice_analyzer.py` 的 `analysis/slice/` 扁平化，而不是把整个原型包拆碎。

另外，原 `syllable/analysis/initial_final_with_tone/` 目录下剩余的整条旧分析链也已整体迁入 `legacy/syllable_prototypes/analysis/initial_final_with_tone/`：

- `analysis/initial_final_with_tone/analysis_executor.py`
- `analysis/initial_final_with_tone/initial_final.py`
- `analysis/initial_final_with_tone/initial_final_with_tone.py`
- `analysis/initial_final_with_tone/potential_syllable.py`
- `analysis/initial_final_with_tone/all_possible_syllables.json`
- `analysis/initial_final_with_tone/initial_final.json`
- `analysis/initial_final_with_tone/initial_final_with_tone.json`
- `analysis/initial_final_with_tone/potential_syllables.json`
- `analysis/initial_final_with_tone/yinjie.json`
- `analysis/initial_final_with_tone/temp.py`

这条链只消费当前数字调拼音表并在目录内自生成 `initial/final/possible syllables` 派生产物，没有任何活动代码、测试或运行时入口再依赖它；保留仅为历史分析方法对照。

另外，原 `syllable/analysis/slice/` 中几份只负责生成现行 `syllable/yinyuan` JSON 资产、但并不属于运行时实现面的脚本已迁到 `tools/syllable_analysis/`：

- `ganyin_enhanced.py`
- `ganyin_slicer.py`
- `ganyin_to_pianyin_sequence.py`
- `ganyin_to_yinyuan_sequence.py`

它们现在仍可用于重建 `ganyin_enhanced.json`、`ganyin_to_pianyin_sequence.json`、`ganyin_to_yinyuan_sequence.json` 等产物，但不再占据 `syllable.analysis.slice` 这个旧实现目录。

其中，`tools/syllable_analysis/ganyin_to_pianyin_sequence.py` 现在只保留为旧命名入口的兼容包装；当前实际实现已经收敛到 `tools/syllable_analysis/ganyin_slicer.py`。

同时，原 `syllable/analysis/slice/reverse_key_value_pairs.py` 也已并入 `legacy/syllable_analysis_tools/`。当前活动重建链已经使用 `yime/reverse_key_value_pairs.py`，因此这份旧 helper 只保留作历史工具链对照，不再需要继续挂在独立的 `slice` 目录下。

这轮又补做了最后一批边界清理：

- 原 `syllable/analysis/slice/shouyin_analyzer.py` 已迁到 `tools/syllable_analysis/shouyin_analyzer.py`，因为它负责生成和更新 `syllable/yinyuan/pianyin_initial.json`，属于资产生成脚本而不是运行时实现。
- 原 `tools/syllable_analysis/run_syllable_analyzer.py` 已迁入 `legacy/syllable_analysis_tools/analyzer_cli_wrapper.py`，因为它只是绕回当前 analyzer CLI 的旧包装入口，且没有活动消费者。
- 原 `tools/syllable_analysis/extract_musical_element.py` 已迁入 `legacy/syllable_analysis_tools/extract_yueyin_yinyuan_wrapper.py`，因为它与 `tools/syllable_analysis/extract_yueyin_yinyuan.py` 为重复实现，只保留旧入口兼容语义。

此外，`scripts/` 下几份早期 syllable 手工验证脚本也已迁入 `legacy/syllable_analysis_scripts/`：

- `dynamic_finals_workflow_probe.py`
- `dynamic_finals_summary_probe.py`
- `dynamic_finals_category_probe.py`
- `ganyin_final_logic_probe.py`
- `ganyin_categorization_probe.py`
- `shejian_processing_probe.py`

这几份脚本没有活动消费者，主要承担一次性检查、打印式验证或早期行为演示；其中 `dynamic_finals_*_probe.py` 这一组集中对应动态韵母分类/流程验证，`ganyin_*_probe.py` 对应干音分类与定义逻辑检查，`shejian_processing_probe.py` 则对应舌尖音处理检查。它们对应的分类/编码/一致性检查现在已由 `tests/syllable_analysis/` 和 `tools/syllable_analysis/` 中的现行工具覆盖，因此不再需要继续保留在顶层 `scripts/` 目录。

另外，几份更早的独立诊断/重命名试验脚本也已迁入 `legacy/diagnostic_scripts/`：

- `theory_markdown_punctuation_probe.py`
- `noise_yinyuan_base_class_probe.py`
- `noise_yinyuan_rename_probe.py`
- `mysql_root_connectivity_probe.py`

其中 `theory_markdown_punctuation_probe.py` 依赖的 `理论文件/` 目录已不复存在；`noise_yinyuan_base_class_probe.py` 与 `noise_yinyuan_rename_probe.py` 只保留作 `NoiseYinyuan` / `UncertainPitchYinyuan` 历史重命名关系的一次性断言；`mysql_root_connectivity_probe.py` 则是依赖本地环境变量和数据库实例的临时连通性诊断脚本。它们都没有活动消费者，也不构成当前仓库的可复用工具链。

另外，原 `syllable/analysis/slice/temp.py` 这类未命名的临时实验脚本也已按用途收进 `legacy/diagnostic_scripts/`：

- `tone_mark_sort_probe.py`

这类脚本主要用于一次性验证声调符号排序、Unicode 组合字符行为等局部问题；保留它们的价值在于历史排障记录，而不是作为某条长期维护的分析链入口。

此外，原 `scripts/generate_ci_report.py` 也已迁入 `legacy/ci_scripts/`。

- `generate_ci_report.py`

这份脚本只会读取本地 `python-coverage.json` 并写出一次性的 `ci-summary.json` 汇总样本；当前 GitHub Actions 与发布链均未再调用它，因此不再需要继续占据顶层 `scripts/` 目录。

另外，原 `syllable/yinyuan/` 下又分离出一批已经脱离当前运行/生成链的旧快照与副本，统一迁入 `legacy/syllable_yinyuan_snapshots/`：

- `initial_pianyin.json`
- `merged_musical_yinyuan.json`
- `merged_yueyin_by_tone.json`
- `musical_pianyin_attributes.json`
- `noise_yinyuan.json`
- `noise_yinyuan_encoding.json`
- `noise_yinyuan_simplified.json`
- `pitch_quality_synchronous_yinyuan.json`
- `shouyin.json`
- `shouyin_yinyuan.json`
- `standard_pinyin.json`
- `variables_of_pitch_and_quality.json`
- `yinjie_code.json`
- `ganyin_theoretical.json`
- `ganyin_encoding.json`

当前 `yinyuan` 目录的现行真源应优先看 `syllable/yinyuan/` 下仍被运行时和重建链读取的资产；本目录这批对象只保留作历史分析快照、兼容副本或早期派生产物对照。仓库内已经没有任何精确到这些旧路径的活动消费者，因此把它们留在活动目录里只会继续抬高“哪些文件真的参与当前链路”的辨识成本。

同时，以下仍会从现行真源生成、但不应继续占据 `syllable/yinyuan/` 活动目录的兼容/辅助输出，已统一迁到 `internal_data/yinyuan_derived/`：

- `zaoyin_yinyuan.json`
- `yueyin_yinyuan.json`
- `ganyin_enhanced.json`
- `ganyin_to_pianyin_sequence.json`
- `ganyin_to_yinyuan_sequence.json`
- `ganyin_to_variable_length_yinyuan_sequence.json`
- `ganyin_to_yinyuan_seq_marks.json`
- `ganyin_to_yinyuan_seq_notes.json`

这批对象的当前替代面就是 `internal_data/yinyuan_derived/` 本身：它们并非运行时真源，也不参与当前输入法主链读取；保留它们的目的主要是旧脚本兼容、人工查看和辅助分析，因此更适合放在派生输出目录，而不是继续与 `yinyuan` 真源和运行时产物混放。

另外，原 `syllable/` 根目录下几份没有活动代码读取的旧 JSON 快照也已迁入 `legacy/syllable_root_snapshots/`：

- `syllable_root_snapshots/ganyin.json`
- `syllable_root_snapshots/ganzhi.json`
- `syllable_root_snapshots/ganzhi_yunmu.json`
- `syllable_root_snapshots/initial_map.json`
- `syllable_root_snapshots/jiediao.json`
- `syllable_root_snapshots/shouyin.json`
- `syllable_root_snapshots/shouyin_map.json`
- `syllable_root_snapshots/shouyin_shengmu.json`
- `syllable_root_snapshots/syllabic_quality.json`

当前对应的活动读取面已经切回 `syllable/yinyuan/` 与相关现行分析模块；这批文件更接近旧分析链或理论快照，而不是当前 `syllable/yinyuan/` 运行资产。其中 `ganyin.json` 的唯一活动读取方也已切回 `syllable/yinyuan/ganyin.json`，因此它们不再需要继续占据 `syllable/` 包根目录。
