# `yime/pinyin_hanzi.db` 按领域分组清单

本文按“数据职责”而不是按建表顺序整理当前 `yime/pinyin_hanzi.db` 的对象，便于理解主库里混合承载的几条链路。

说明：

- 这是逻辑分组，不代表当前工程已经物理拆库。
- 当前运行时仍把 `yime/pinyin_hanzi.db` 当作单一主库使用，主入口是 `runtime_candidates` / `runtime_candidates_materialized`。
- 以下清单以 2026-06-19 当前库内容为准。

## 0. 速查表

这张表主要给人快速定位对象职责。

这里“运行时关键路径”指：
运行时会直接读取，
或该对象缺失会
导致 `runtime_candidates` / `char_lexicon`
这类运行时主入口失效。

|对象名|类型|领域|运行时关键路径|
|---|---|---|---|
|`char_inventory`|table|规范化词库层|是|
|`char_lexicon`|view|运行时候选层|是|
|`char_modern_common_profile`|table|排序与频率增强层|否|
|`char_pinyin_map`|table|规范化词库层|是|
|`char_reading_prior`|table|排序与频率增强层|否|
|`char_usage_profile`|table|排序与频率增强层|是|
|`db_meta`|table|元数据与说明层|否|
|`key_symbol_map`|table|键位与符号布局层|否|
|`klc_layout_source`|table|键位与符号布局层|否|
|`mapping_yime_code`|table|规范化词库层|否|
|`numeric_pinyin_inventory`|table|规范化词库层|是|
|`phrase_inventory`|table|规范化词库层|是|
|`phrase_lexicon_view`|view|运行时候选层|是|
|`phrase_pinyin_map`|table|规范化词库层|是|
|`phrase_reading_preference`|table|规范化词库层|否|
|`phrase_readings`|table|原始导入层|否|
|`physical_key`|table|键位与符号布局层|否|
|`pinyin_yime_code`|table|规范化词库层|是|
|`prototype_metadata`|table|元数据与说明层|否|
|`runtime_candidates`|view|运行时候选层|是|
|`runtime_candidates_materialized`|table|运行时候选层|是|
|`runtime_tuning_parameters`|table|运行时候选层|否|
|`schema_comment`|table|元数据与说明层|否|
|`single_char_readings`|table|原始导入层|否|
|`slot_xw`|table|键位与符号布局层|否|
|`source_files`|table|原始导入层|否|
|`symbol`|table|键位与符号布局层|否|
|`vw_key_symbol_layout`|view|键位与符号布局层|否|
|`vw_klc_layout_observation`|view|键位与符号布局层|否|
|`vw_klc_layout_observation_all`|view|键位与符号布局层|否|
|`vw_symbol_crosswalk`|view|键位与符号布局层|否|
|`vw_symbol_inventory`|view|键位与符号布局层|否|
|`yinjie_slot_decomposition`|table|规范化词库层|否|

## 0.5 最小主链表

如果只关心“哪些对象一动就最容易影响输入法运行”，先看这 11 个对象即可。

- `runtime_candidates`（view）：
  运行时统一候选入口；缺失时主查询路径失效。
- `runtime_candidates_materialized`（table）：
  运行时优先使用的物化候选表；有数据时承担主查询。
- `char_lexicon`（view）：
  单字候选展开视图；单字查询与反查依赖它。
- `phrase_lexicon_view`（view）：
  词语候选展开视图；词语候选查询依赖它。
- `char_inventory`（table）：
  单字词库主表；多条单字链路根节点。
- `phrase_inventory`（table）：
  词语词库主表；多条词语链路根节点。
- `char_pinyin_map`（table）：
  单字到拼音的规范化映射。
- `phrase_pinyin_map`（table）：
  词语到拼音的规范化映射。
- `numeric_pinyin_inventory`（table）：
  数字调拼音清单；单字和词语编码链都会经过。
- `pinyin_yime_code`（table）：
  拼音到音元编码的核心映射。
- `char_usage_profile`（table）：
  运行时排序的重要权重来源。

经验上：

- 改动这 11 个对象前，应先视为“可能直接影响运行时行为”。
- 清理历史表、观察视图、元数据表时，不要和这 11 个对象混在同一批变更里。

## 1. 运行时候选层

这层最接近输入法实际查词路径。

### 表（运行时候选层）

- `runtime_candidates_materialized`：运行时候选物化表，供运行时快速按码查候选。
- `runtime_tuning_parameters`：运行时排序/刷新参数。

### 视图（运行时候选层）

- `runtime_candidates`：运行时候选统一视图；运行时主查询入口。
- `char_lexicon`：单字候选展开视图，供运行时与反查读取。
- `phrase_lexicon_view`：词语候选展开视图。

## 2. 原始导入层

这层保留从上游文本导入后的原始或近原始读音记录，属于构建链输入面。

### 表（原始导入层）

- `source_files`：导入来源文件登记。
- `single_char_readings`：单字原始读音记录。
- `phrase_readings`：词语原始读音记录。

## 3. 规范化词库层

这层是当前主线词库模型，把原始导入整理成可稳定 join 的规范化结构。

### 单字相关表（规范化词库层）

- `char_inventory`：单字主表。
- `char_pinyin_map`：单字到数字调拼音的映射表。
- `numeric_pinyin_inventory`：数字调拼音清单。
- `pinyin_yime_code`：拼音到音元编码的映射。
- `mapping_yime_code`：兼容性映射面，保留 `mapping_id -> yime_code`。
- `yinjie_slot_decomposition`：音节到各槽位拆解后的物化表。

### 词语相关表（规范化词库层）

- `phrase_inventory`：词语主表。
- `phrase_pinyin_map`：词语到拼音的映射表。
- `phrase_reading_preference`：词语首选读音记录。

## 4. 排序与频率增强层

这层不直接定义“有哪些词”，而是为运行时排序补充权重、层级和先验。

### 表（排序与频率增强层）

- `char_usage_profile`：单字使用档位与层级排序权重。
- `char_modern_common_profile`：现代常用字增强信息。
- `char_reading_prior`：单字读音先验权重。

## 5. 键位与符号布局层

这层服务键盘布局、音元符号映射和观察视图，不是词库主干，但仍放在同一个库里。

### 表（键位与符号布局层）

- `physical_key`：物理键定义。
- `symbol`：音元符号与私用区字符定义。
- `key_symbol_map`：键位到符号的映射。
- `klc_layout_source`：KLC 布局原始导入表。
- `slot_xw`：槽位相关映射表。

### 视图（键位与符号布局层）

- `vw_key_symbol_layout`：键位与符号布局展开视图。
- `vw_symbol_inventory`：符号映射盘点视图。
- `vw_symbol_crosswalk`：符号跨表示图。
- `vw_klc_layout_observation_all`：KLC 全量观察视图。
- `vw_klc_layout_observation`：KLC 标准键位观察视图。

## 6. 元数据与说明层

这层不承载业务词条，而是承载 schema 注释、原型版本和维护信息。

### 表（元数据与说明层）

- `db_meta`：数据库级元数据。
- `prototype_metadata`：原型/导入链元数据。
- `schema_comment`：中文 schema 注释表。

## 7. 当前理解建议

如果只是为了读懂 `pinyin_hanzi.db`，建议先按下面顺序看：

1. `runtime_candidates` / `runtime_candidates_materialized`
2. `char_lexicon`、`phrase_lexicon_view`
3. `char_inventory`、`phrase_inventory`
4. `char_pinyin_map`、`phrase_pinyin_map`、`numeric_pinyin_inventory`、`pinyin_yime_code`
5. `char_usage_profile`、`char_modern_common_profile`、`char_reading_prior`
6. `single_char_readings`、`phrase_readings`
7. `physical_key`、`symbol`、`key_symbol_map`、`klc_layout_source`

这样看，能先抓住运行时主链，再回头看构建来源和布局观察层，不容易把“运行时表”和“原始导入表”混在一起。
