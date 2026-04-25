# 真源文件与生成产物清单

## 文档定位

本文档用于区分当前仓库中的：

1. 语义真源文件
2. 规范映射文件
3. 平台投影文件
4. 运行时生成产物
5. 审计与过渡辅助文件

本文档服务于下一步把生成链拆回稳定结构，避免继续把产物文件误当作真源来修改。

建议与 [码点与中间层策略](CODEPOINT_POLICY.md) 配合阅读。

与首音细分层相关的规则说明草案，见 [首音细分规则与真源 Schema 提案](SHOUYIN_SPLITTER_RULES.md)。当前代码链未启用该草案中的细分切分方案。

## 判定原则

### 真源文件

满足以下条件之一：

1. 直接表达语义结构，而不是表达某次导出结果。
2. 改动后应触发重新生成其他文件。
3. 不应该由测试过程直接回写修正。

### 生成产物文件

满足以下条件之一：

1. 可由真源文件重新构建。
2. 当前内容依赖某种码点区或平台投影选择。
3. 在重建流程中应被覆盖，而不是手工长期维护。

## 当前建议分层

### A. 语义真源层

这些文件应当被视为下一步拆回生成链的核心基础。

#### 1. 键位语义真源

- `internal_data/manual_key_layout.json`
  - 文件名里的 `manual` 是历史命名，当前语义应理解为“布局真源”，不是“manual install”或“手工编译流程”。
  - 定义物理键位与 `Nxx/Mxx` 槽位的关系。
  - 这是布局层真源，不应通过改 `yinyuan.klc` 反向修复。

#### 2. 槽位到规范字符映射真源

- `internal_data/key_to_symbol.json`
  - 当前表达 `N01-N24` 与 `M01-M33` 到规范字符的映射。
  - 按策略文档，应将其理解为“语义槽位到 canonical 字符”的稳定层。

#### 3. 理论与流程约束真源

- `docs/CODEPOINT_POLICY.md`
  - 规范语义槽位层、canonical 层和 projection 层之间的职责。
- `docs/KEYBOARD_LAYOUT_PIPELINE.md`
  - 规范键盘布局生成链应如何组织。

### B. 应尽快补齐的缺失真源层

这些文件在结构上应存在，但目前仓库里还没有稳定落地为独立真源。

#### 1. 首音语义映射真源

- 建议新增：`internal_data/shouyin_to_symbol_key.json`
  - 用来表达：`b -> N01`、`zh -> N15` 这类语义关系。
  - 这样首音语义就不再依赖具体字符文件。

#### 2. 干音语义序列真源

- 建议新增：`internal_data/ganyin_to_symbol_key_sequence.json`
  - 用来表达：`i1 -> M01 M01 M01`、`an4 -> M10 M11 M30` 这类三乐音序列。
  - 这样干音编码不会再直接绑定某个 Unicode 码点区。

这两份文件应当成为后续修复生成链时最优先补上的真源层。

### C. 平台投影层

这些文件表达的是 projection，不是最终语义真源。

#### 1. BMP PUA 投影

- `internal_data/bmp_pua_trial_projection.json`
  - 当前用于把 canonical 槽位投影到 BMP PUA。
  - 应继续保留，但应明确其职责是 projection，不是 canonical。

- `internal_data/bmp_pua_trial_projection.md`
  - 对应投影的说明文件。

### D. 当前生成产物层

这些文件都可以重建，不应被长期手工承担真源职责。

当前首音链已经切换为：

- `syllable/analysis/slice/yinyuan/zaoyin_yinyuan_enhanced.json`
  - 首音唯一真源。
  - 每条记录显式保存 `semantic_code`、`ipa`、`type`、`runtime_char`。

- `syllable/analysis/slice/yinyuan/zaoyin_yinyuan.json`
  - 兼容产物，只保留 `shouyin -> ipa` 的旧结构，供旧脚本和人工查看。

当前干音链已经切换为：

- `syllable/analysis/slice/yinyuan/yueyin_yinyuan_enhanced.json`
  - 干音唯一真源。
  - 每条记录显式保存 `semantic_code`、`layout_slot`、`aliases`、`runtime_char`。

- `syllable/analysis/slice/yinyuan/yueyin_yinyuan.json`
  - 兼容产物，只保留 `canonical yueyin -> aliases` 的旧结构。

#### 1. 运行时字符映射产物

- `syllable/analysis/slice/yinyuan/shouyin_codepoint.json`
  - 当前是首音到字符的运行时映射结果。
  - 按策略，它应从“首音语义映射真源 + 码点映射层”生成。

- `syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json`
  - 当前是干音到固定长度三字符序列的运行时产物。
  - 按策略，它应从“干音语义序列真源 + 码点映射层”生成。

- `syllable/analysis/slice/yinyuan/yinyuan_codepoint.json`
  - 当前是运行时总字符映射汇总文件。
  - 应视为聚合产物，而不是单独真源。

#### 2. 音节编码产物

- `yinjie_code.json`
  - 当前是最终音节到四字符编码的产物。
  - 应从首音语义层、干音语义层和码点映射层生成。

#### 3. 布局解析与布局安装产物

- `internal_data/manual_key_layout.resolved.json`
  - 是 `manual_key_layout.json + key_to_symbol.json` 的解析产物。

- `yinyuan.klc`
  - 是键盘布局安装链的构建产物。
  - 不应反向充当键位真源。

#### 4. 数据库导入与运行时消费产物

- `yime/pinyin_hanzi.db`
  - 作为数据库运行时资产，应被视为导入结果和消费结果，不应承担字符系统真源职责。
- `yime/pinyin_hanzi.db-wal`
- `yime/pinyin_hanzi.db-shm`
  - 都是数据库运行时副产物，绝不是设计真源。

### E. 审计与过渡辅助文件

这些文件很有价值，但它们的职责是“帮助审计现状”，不是“定义未来结构”。

- `internal_data/yinjie_runtime_key_symbol_mapping.json`
  - 用来审计当前 runtime 字符与槽位关系。
  - 非真源。

- `internal_data/layout_runtime_consistency_report.json`
  - 一致性检查输出。
  - 非真源。

- `internal_data/zaoyin_runtime_layout_audit.md`
  - 首音运行时链路审计文档。
  - 非真源。

- `internal_data/yueyin_runtime_layout_audit.md`
  - 乐音运行时链路审计文档。
  - 非真源。

## 当前结构的主要问题

### 1. 语义层缺失独立文件

当前首音和干音的语义关系仍然大量隐含在“字符结果文件”里，而不是明确落在 `N/M` 槽位映射文件中。

这导致：

1. 一旦换码点区，语义层也会跟着漂移。
2. 测试失败时，容易直接去改字符结果。
3. 生成链难以稳定拆分。

### 2. 运行时字符文件被过度当作真源

当前 `yinjie_encoder.py` 仍然直接消费：

- `syllable/analysis/slice/yinyuan/shouyin_codepoint.json`
- `syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json`

这意味着字符层文件事实上仍在扮演真源角色，与策略文档要求不一致。

### 3. 数据库文件容易被误改为修复入口

当测试或运行链不通时，如果没有明确“数据库只是消费端产物”，就很容易出现“为提高测试通过率直接改库”的错误做法。

## 下一步拆链建议

建议按以下顺序进行。

### 第一步：补齐语义真源层

新增：

1. `internal_data/shouyin_to_symbol_key.json`
2. `internal_data/ganyin_to_symbol_key_sequence.json`

目标：先把“首音/干音语义”与“Unicode 字符”彻底拆开。

### 第二步：让运行时字符文件退回生成产物角色

调整生成链，使以下文件由语义层自动生成：

1. `syllable/analysis/slice/yinyuan/shouyin_codepoint.json`
2. `syllable/analysis/slice/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json`
3. `syllable/analysis/slice/yinyuan/yinyuan_codepoint.json`
4. `yinjie_code.json`

### 第三步：明确 canonical 与 projection 的分工

建议：

1. `internal_data/key_to_symbol.json` 继续承担 canonical 映射职责。
2. `internal_data/bmp_pua_trial_projection.json` 继续承担 BMP projection 职责。
3. `yinyuan.klc` 由布局真源 + 选定 projection/canonical 模式生成。

### 第四步：把数据库完全降级为消费端产物

目标：

1. 数据库不再被视为修复字符系统的入口。
2. 需要修字符系统时，回到语义层和码点层修，再重建数据库导入结果。

## 最终目标结构

理想结构如下：

1. 语义层
   - `manual_key_layout.json`
   - `shouyin_to_symbol_key.json`
   - `ganyin_to_symbol_key_sequence.json`

2. 规范码点层
   - `key_to_symbol.json`

3. 平台投影层
   - `bmp_pua_trial_projection.json`

4. 生成产物层
   - `shouyin_codepoint.json`
   - `ganyin_to_fixed_length_yinyuan_sequence.json`
   - `yinyuan_codepoint.json`
   - `yinjie_code.json`
   - `yinyuan.klc`
   - 数据库与导出文件

只要这个分层稳定下来，后续无论换码点区、重做布局、修复工具链还是重建数据库，都可以各改各层，不会再互相污染。
