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
  - `C:/dev/Yime-keyboard-layout` 可以消费它的快照副本来生成 KLC 和打包产物，但那边的 `source_snapshots/manual_key_layout.json` 不是 canonical。

#### 2. 槽位到规范字符映射真源

- `internal_data/key_to_symbol.json`
  - 当前表达 `N01-N24` 与 `M01-M33` 到规范字符的映射。
  - 按策略文档，应将其理解为“语义槽位到 canonical 字符”的稳定层。
  - `C:/dev/Yime-keyboard-layout` 中如果存在对应快照，也只能视为同步副本，不得反向覆盖这里。

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
  - 独立出来的键盘布局辅助仓库可以复制它做 Windows 打包试验，但复制件仍只是快照。

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
  - 当前正式保留位置应理解为 `C:/dev/Yime-keyboard-layout/yinyuan.klc`；主仓库根目录不再要求长期保留副本。

#### 4. 数据库导入与运行时消费产物

- `yime/pinyin_hanzi.db`
  - 作为数据库运行时资产，应被视为导入结果和消费结果，不应承担字符系统真源职责。
- `yime/pinyin_hanzi.db-wal`
- `yime/pinyin_hanzi.db-shm`
  - 都是数据库运行时副产物，绝不是设计真源。

#### 5. 第二批轻清理对象分类（2026-04）

以下对象已经做过一轮“只分类、不删除”的轻审查，当前建议如下。

- `yime/create_prototype_schema_additions.sql`
  - 分类：当前间接依赖。
  - 原因：该文件定义 `runtime_candidates` 视图，而当前输入法的 SQLite 回退链会直接读取这个视图，因此它不能按普通旧脚本附件处理。

- `yime/import_danzi_into_prototype_tables.py`
  - 分类：待确认旧链。
  - 原因：它属于“把单字数据导入原型数据库”的维护脚本，会配合 `create_prototype_schema_additions.sql` 和 `source_pinyin.db` 工作，但当前不是输入法前台运行主线的直接入口。

- `yime/import_duozi_into_prototype_tables.py`
  - 分类：待确认旧链。
  - 原因：它属于“把词语数据导入原型数据库”的维护脚本，角色与单字导入脚本相同，目前更像原型库维护链的一部分，而不是当前交互主线的一部分。

- `releases/`
  - 分类：可归档但暂不删除。
  - 原因：该目录更接近历史发布/打包沉积区，包含安装包、MSI 和按架构拆分的打包结果；当前没有发现运行时代码对它的直接依赖，但它仍可能承载可用安装样本与发布记录，因此现阶段先归档理解，不做删除处理。

当前处理原则：

1. 对 `当前间接依赖` 对象，现阶段不得因为“看起来像旧文件”而直接删除、搬移或改名。
2. 对 `待确认旧链` 对象，现阶段只允许继续审计、补说明或补替代链，不直接清理，直到能明确当前数据库构建链已有稳定替代入口。
3. 对 `可归档但暂不删除` 对象，现阶段只做目录级分类和用途标注，不碰包内容；等发布样本与历史沉积物拆分标准明确后再动。

`releases/` 顶层子目录当前可先按下面方式理解：

补充说明：当前 Windows 键盘布局打包链已经独立到 `C:/dev/Yime-keyboard-layout`。主仓库里的 `releases/` 更应理解为过渡镜像和历史残留，而不是 IME 主线自带发布系统。

- `releases/msklc-package/`
  - 分类：已迁出主仓库。
  - 原因：当前可解释的安装样本已经保留在 `C:/dev/Yime-keyboard-layout` 中，主仓库不再需要继续携带这份镜像目录。

- `releases/msklc-amd64/`
  - 分类：已迁出主仓库。
  - 原因：分架构 DLL 快照已经保留在 `C:/dev/Yime-keyboard-layout` 中，主仓库不再继续保存重复副本。

- `releases/msklc-wow64/`
  - 分类：已迁出主仓库。
  - 原因：分架构 DLL 快照已经保留在 `C:/dev/Yime-keyboard-layout` 中，主仓库不再继续保存重复副本。

- `releases/msklc-docs/`
  - 分类：空目录占位。
  - 原因：当前为空，暂时没有形成有效内容；该目录已在轻清理中删除。

- `releases/msklc-test/`
  - 分类：空目录占位。
  - 原因：当前为空，暂时没有形成有效内容；该目录已在轻清理中删除。

- `releases/v1.0/`
  - 分类：过渡占位目录。
  - 原因：正式键盘布局 `v1.0` 说明已经迁到 `C:/dev/Yime-keyboard-layout`，主仓库这里只保留一个入口占位，避免旧路径失联。

当前已完成的 `releases/` 轻清理结论是：

1. `releases/msklc-docs/` 与 `releases/msklc-test/` 两个空目录占位已删除。
2. `releases/yinyuan/` 已删除，因为它与 `releases/msklc-package/` 的代表性包文件重复，且当前运行/打包说明链没有引用它。
3. 旧的 `releases/v2.2/` 与 `releases/v2.3/` 版本说明已删除，因为它们为空或与当前主线失配。
4. 键盘布局辅助工程已经独立到 `C:/dev/Yime-keyboard-layout`，主仓库中的 `releases/v1.0/` 现已降级为占位入口。
5. `releases/msklc-package/`、`releases/msklc-amd64/` 与 `releases/msklc-wow64/` 已从主仓库移除，正式样本改由 `C:/dev/Yime-keyboard-layout` 承载。

#### 6. 根目录旧原型数据库链（2026-04）

以下对象已经确认为旧原型/练习链，且已从主仓库移除：

- `pinyin_hanzi.db`
  - 分类：已删除的根级练习库。
  - 原因：当前运行时与数据库维护主线都已统一到 `yime/pinyin_hanzi.db`，这个根目录 SQLite 文件体量很小、表结构也明显更旧，更接近早期练习或原型残留，而不是现行输入法资产。

- `create_tables_from_manager.py`
  - 分类：已删除的根级旧建表脚本。
  - 原因：它只操作根目录 `pinyin_hanzi.db`，不参与当前 `yime/` 模块内的数据库运行/导入链，已被模块内数据库脚本体系替代。

- `run_db_setup.py`
  - 分类：已删除的根级旧初始化脚本。
  - 原因：它默认操作根目录 `pinyin_hanzi.db`，与 `yime/run_db_setup.py` 这条模块内链重复，保留它只会继续制造“根目录库 vs 模块目录库”的混淆。

当前处理原则补充：

1. 数据库相关脚本若仍以仓库根目录 `pinyin_hanzi.db` 为默认目标，应优先视为旧原型链候选，而不是当前主线入口。
2. 当前输入法运行、导入、诊断与测试的数据库主线统一以 `yime/pinyin_hanzi.db` 为准。

#### 7. 旧 JS 原型链（2026-05）

以下对象已经整体迁出主仓库，当前正式外置位置为 `C:/dev/Yime-js-prototype`：

- `package.json`
- `package-lock.json`
- `babel.config.cjs`
- `jest.config.js`
- `main.js`
- `input-method.js`
- `input-method-prototype.html`
- `hanziModule.js`
- `hanziTable.json`
- `pinyinModule.js`
- `pinyinCodeModule.js`
- `pinyinCodeTable.json`
- `src/`

分类：已迁出的旧 JS / React 原型链。

原因：这条链仍有内部自洽的 Node CLI 与 React 原型结构，但已经不属于当前 Windows IME 主线；继续保留在主仓库根目录只会混淆“旧前端演示链”和 `yime/` 下的现行 Python 输入法实现。

#### 8. 根目录 HTML 工具页与一次性报告页（2026-05）

以下交互式 HTML 工具页已从主仓库根目录迁出，当前外置位置为 `C:/dev/Yime-html-tool-prototypes`：

- `blank-editor.html`
- `undo_editor.html`
- `version_control_editor.html`
- `character_palette.html`
- `character_validator.html`
- `find_and_replace.html`
- `pinyin_editor.html`
- `pinyin_editor.js`
- `continuous-input.html`
- `continuous-input-test.html`

分类：已外置留档的旧 HTML 工具原型。

原因：这些页面虽然不再属于当前输入法主线，也没有仓库内调用关系，但仍保留了相对完整的前端交互逻辑，适合脱离主仓库后作为历史工具原型单独留档。

以下根目录 HTML 文件已直接删除：

- `index.html`
- `comments_preview.html`
- `conversion_dashboard.html`
- `filename_change_demo.html`
- `finals_classifier_validation.html`
- `finals_comparison.html`
- `git_push_guide.html`
- `phoneme_comparison.html`
- `pianyin_analyzer_report.html`
- `pinyin_counter_validation.html`
- `stats_display.html`
- `ü_character_comparison.html`

分类：已删除的一次性报告页、说明页与异常产物。

原因：这批页面同样没有主线引用，其中多数只是一次性展示或说明页面；而根目录 `index.html` 体积异常、文件头也并非正常 HTML，更接近误提交的导出/二进制产物，不适合继续保留在主仓库。

#### 9. docs/ 旧静态 HTML 文档站（2026-05）

以下 `docs/` 下的旧静态 HTML 文档站页面已整体迁出主仓库，当前外置位置为 `C:/dev/Yime-docs-html-site`：

- `docs/index.html`
- `docs/overview.html`
- `docs/quickstart.html`
- `docs/architecture.html`
- `docs/api.html`
- `docs/configuration.html`
- `docs/development.html`
- `docs/manual.html`

分类：已外置留档的旧静态 HTML 文档站。

原因：这组页面只在 HTML 站内部互相链接，不参与当前输入法运行，也不是当前文档维护主线；主仓库现行文档入口已经以 `docs/README.md` 及各 Markdown 文档为准，继续同时保留两套文档面只会制造维护歧义。

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
