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
  - 外部 `Yime-keyboard-layout` 仓库可以消费它的快照副本来生成 KLC 和打包产物，但那边的 `source_snapshots/manual_key_layout.json` 不是 canonical。

#### 2. 槽位到规范字符映射真源

- `internal_data/key_to_symbol.json`
  - 当前表达 `N01-N24` 与 `M01-M33` 到规范字符的映射。
  - 按策略文档，应将其理解为“语义槽位到 canonical 字符”的稳定层。
  - 外部 `Yime-keyboard-layout` 仓库中如果存在对应快照，也只能视为同步副本，不得反向覆盖这里。

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

- `syllable_codec/yinjie_code.json`
  - 当前是最终音节到四字符编码的产物。
  - 应从首音语义层、干音语义层和码点映射层生成。

#### 3. 布局解析与布局安装产物

- `internal_data/manual_key_layout.resolved.json`
  - 是 `manual_key_layout.json + key_to_symbol.json` 的解析产物。

- `yinyuan.klc`
  - 是键盘布局安装链的构建产物。
  - 不应反向充当键位真源。
  - 当前正式保留位置应理解为外部 `Yime-keyboard-layout/yinyuan.klc`；主仓库根目录不再要求长期保留副本。

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

补充说明：当前 Windows 键盘布局打包链已经独立到外部 `Yime-keyboard-layout` 仓库。主仓库里的 `releases/` 更应理解为过渡镜像和历史残留，而不是 IME 主线自带发布系统。

- `releases/msklc-package/`
  - 分类：已迁出主仓库。
  - 原因：当前可解释的安装样本已经保留在外部 `Yime-keyboard-layout` 仓库中，主仓库不再需要继续携带这份镜像目录。

- `releases/msklc-amd64/`
  - 分类：已迁出主仓库。
  - 原因：分架构 DLL 快照已经保留在外部 `Yime-keyboard-layout` 仓库中，主仓库不再继续保存重复副本。

- `releases/msklc-wow64/`
  - 分类：已迁出主仓库。
  - 原因：分架构 DLL 快照已经保留在外部 `Yime-keyboard-layout` 仓库中，主仓库不再继续保存重复副本。

- `releases/msklc-docs/`
  - 分类：空目录占位。
  - 原因：当前为空，暂时没有形成有效内容；该目录已在轻清理中删除。

- `releases/msklc-test/`
  - 分类：空目录占位。
  - 原因：当前为空，暂时没有形成有效内容；该目录已在轻清理中删除。

- `releases/v1.0/`
  - 分类：已移除的过渡占位目录。
  - 原因：正式键盘布局 `v1.0` 说明已经迁到外部 `Yime-keyboard-layout` 仓库，而主仓库内已不再存在对此目录的消费入口，因此这层占位本身也可以移除。

当前已完成的 `releases/` 轻清理结论是：

1. `releases/msklc-docs/` 与 `releases/msklc-test/` 两个空目录占位已删除。
2. `releases/yinyuan/` 已删除，因为它与 `releases/msklc-package/` 的代表性包文件重复，且当前运行/打包说明链没有引用它。
3. 旧的 `releases/v2.2/` 与 `releases/v2.3/` 版本说明已删除，因为它们为空或与当前主线失配。
4. 键盘布局辅助工程已经独立到外部 `Yime-keyboard-layout` 仓库，主仓库中的 `releases/v1.0/` 占位目录也已移除，正式入口统一改由外部仓库承载。
5. `releases/msklc-package/`、`releases/msklc-amd64/` 与 `releases/msklc-wow64/` 已从主仓库移除，正式样本改由外部 `Yime-keyboard-layout` 仓库承载。

#### 6A. 覆盖率报告目录（2026-05）

- `coverage/`
  - 分类：前端测试生成物。
  - 原因：当前仅承载 `lcov.info`、`coverage-final.json` 以及 `lcov-report/` HTML 报告，它们都属于测试运行后的可再生输出，而不是仓库真源。

- `htmlcov/`
  - 分类：Python 覆盖率生成物。
  - 原因：该目录是 `pytest --cov-report=html` 的标准输出目录，已经在本地存在，但不应作为版本化资产维护。

当前处理原则补充：

1. `coverage/` 与 `htmlcov/` 应视为测试生成物，允许删除并重新生成。
2. 工作流可以校验这些目录中的文件是否被生成，但主仓库不应继续跟踪报告内容本身。

#### 6AA. 根目录覆盖率与缓存残留（2026-05）

- `.coverage`
  - 分类：已删除的本地覆盖率数据文件。
  - 原因：这是 coverage.py 的本地统计输出，只服务于测试统计与 HTML/XML 报告生成，不应进入版本控制。

- `__pycache__/`
  - 分类：已删除的本地 Python 字节码缓存目录。
  - 原因：目录中的 `.pyc` 文件完全由本机解释器版本与执行路径决定，属于典型临时缓存，不应版本化。

- `.pytest_cache/`
- `.tmp/`
  - 分类：本地测试/临时缓存目录。
  - 原因：它们只承载测试会话与临时运行状态，不构成设计真源，应默认忽略并允许随时清空。

#### 6B. 数据库备份副产物（2026-05）

- `yime/backup/`
  - 分类：本地数据库备份目录。
  - 原因：`yime/run_full_import.py` 与 `yime/borrow_wanxiang_frequency.py` 会在修改 `yime/pinyin_hanzi.db` 前生成保护性备份；这些文件属于本地维护副产物，不应进入版本控制。

- `yime/*.wanxiang_borrow_*.bak`
- `yime/*.pre_*`
- `yime/*.bak*`
  - 分类：本地数据库备份文件模式。
  - 原因：它们是导入、借频或人工维护阶段生成的回退文件，只服务于本地回滚，不是仓库真源。

#### 6C. 拼音数据库迁移链（2026-05）

- `docs/project/PINYIN_DATA_MIGRATION.md`
  - 分类：当前迁移说明。
  - 原因：该文档明确区分当前主线 `source_pinyin.db -> prototype tables -> runtime` rebuild 链，与独立 `.yaml -> .json` 导出链。

- `yime/legacy/`
  - 分类：旧结构归档脚本目录。
  - 原因：该目录下的脚本只服务旧 `音元拼音 / 数字标调拼音 / 词汇` 结构审计或迁移，不再属于当前主线 rebuild 面。

当前处理原则补充：

1. 主线重建优先走 `internal_data/pinyin_source_db/` 与 prototype 导入链，不再把旧中文表维护脚本当成默认入口。
2. `.yaml` 词库导出已经独立到 `internal_data/pinyin_source_db/export_yaml_lexicon_json.py`，可单独执行，不必穿过 SQLite 链。
3. `yime/legacy/` 中的脚本默认不继续扩展新功能，只保留历史兼容与审计用途。

当前处理原则补充：

1. 数据库维护脚本若需要自动备份，应统一写入 `yime/backup/` 或其他明确的本地临时位置。
2. 任何 `pinyin_hanzi` 相关 `.bak`/`pre_*` 文件都应视为本地回退副产物，不应再被提交。

#### 6C. `yime/reports/` 运行桥接文件与分析产物（2026-05）

- `yime/reports/runtime_candidates_by_code_true.json`
  - 分类：保留的运行时桥接导出。
  - 原因：当前输入法候选框与相关分析文档仍直接消费这份“仅真实音元编码键”的 JSON，它虽然可以从数据库重导出，但在当前仓库里承担实际运行输入面。

- `yime/reports/runtime_candidates_by_code.json`
- `yime/reports/runtime_candidates_placeholder_phrases.json`
- `yime/reports/phrase_code_backfill.json`
- `yime/reports/efficiency_baseline.json`
- `yime/reports/summary.txt`
  - 分类：已删除的可再生报告/分析产物。
  - 原因：这些文件只有导出脚本或分析脚本负责生成，没有运行时消费入口；它们属于数据库或报告流程的可再生输出，不应长期版本化。

当前处理原则补充：

1. `yime/reports/` 中若文件被输入法运行面直接读取，可以作为桥接导出保留。
2. 纯分析、回填、汇总类 JSON/TXT 报告应默认视为生成物，删除后按需重建，并通过 ignore 规则防止再次入库。

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

#### 6D. 根目录临时导出与脚本输出（2026-05）

- `ci-summary.json`
  - 分类：已删除的 CI 汇总输出样本。
  - 原因：该文件由 `scripts/generate_ci_report.py` 直接生成，只是一次运行产物，不承担仓库真源职责。

- `pinyin_import.log`
  - 分类：已删除的导入日志文件。
  - 原因：它是导入脚本运行时写出的本地日志，不应长期版本化。

- `temp.json`
  - 分类：已删除的根目录重复 JSON 副本。
  - 原因：其内容已由 `syllable/analysis/slice/yinyuan/zaoyin_yinyuan_enhanced.json` 等现行文件承载，保留根目录副本只会制造“哪个才是当前文件”的歧义。

#### 6E. 根目录演示数据库与本机残留（2026-05）

- `character_positions.db`
  - 分类：已删除的示例字符位置数据库。
  - 原因：它只对应 `utils/position.py` 一类演示/实验用途，不参与当前输入法运行、导入或发布主线。

- `character_table.json`
  - 分类：已删除的示例字符统计输出。
  - 原因：它由 `utils/example.py` 直接生成，内容仅服务于演示示例，不应占据根目录并进入版本控制。

- `yime.db`
  - 分类：已删除的根目录辅助观测库。
  - 原因：当前数据库主线已统一到 `yime/pinyin_hanzi.db`；根目录这份 SQLite 文件只剩编辑器连接样本用途，继续保留会加重“到底哪个库在用”的混淆。

- `clear`
  - 分类：已删除的无法解释二进制残留。
  - 原因：仓库内没有消费入口，也没有可解释的构建/发布职责，更像误入库的本机残留文件。

- `Anaconda3Scriptsconda.exe`
  - 分类：已删除的空壳可执行文件残留。
  - 原因：文件本身为空且仓库内无消费入口，不具备任何可执行或文档价值。

- `custom_phoneme_dict.json`
  - 分类：已删除的根目录孤立音元字典副本。
  - 原因：仓库内没有现行消费入口；其结构又与当前 `phoneme_dict.json` / `zaoyin_yinyuan_enhanced.json` 这类现行数据文件重叠，更像历史试验副本而不是真源。

- `phoneme_dict.json`
  - 分类：已删除的根目录再生导出物。
  - 原因：仓库内没有任何运行时读取方；它只由 `syllable_codec/yinjie_decoder.py` 导出，适合下沉到 `yime/reports/phoneme_dict.json` 这类报告路径，而不应继续占据根目录主资产位置。

- `phoneme.csv`
  - 分类：已删除的根目录孤立音系对照表。
  - 原因：仓库内没有任何代码、文档或运行链读取它；内容只是单独一张声母 IPA 对照表，既不属于当前输入法运行时数据，也不属于当前生成链真源，继续留在根目录只会制造“这是现行数据文件”的误解。

- `keys_to_yunmu.json`
  - 分类：已删除的根目录重复映射副本。
  - 原因：当前实际生成位置已经固定在 `pinyin/keys_to_yunmu.json`；根目录这份文件与之内容相同，仓库内也没有任何读取方引用根目录版本，只会制造“哪个才是现行文件”的歧义。

- `ganyin_encoding.json`
  - 分类：已删除的根目录孤立干音编码快照。
  - 原因：当前仓库内真正纳入分析链的是 `syllable/analysis/slice/yinyuan/ganyin_encoding.json`；根目录这份文件没有任何消费入口，也不在现行验证链中，保留只会混淆真源位置。

- `keyboard_to_yinyuan.py`
  - 分类：已删除的根目录孤立脚本残片。
  - 原因：仓库内没有任何调用入口；文件内部还依赖未定义的 `keystroke_to_yinyuan_mapping`，更像未完成试验残片而不是当前可运行工具。

- `revert_debug.py`
  - 分类：已删除的一次性调试回滚脚本。
  - 原因：它只针对旧版 `app.py` 中已经不存在的调试字符串做文本替换；当前实现已直接回到 `show_standby()` 路径，这个脚本再保留没有任何持续价值。

- `unicode_pua.py`
  - 分类：已删除的临时 PUA 扫描工具。
  - 原因：仓库内没有任何代码、测试、命令脚本或文档依赖它；只剩手动 launch 配置，属于一次性排查 Windows 字体 PUA 占用的辅助工具，不应继续占据根目录。

- `unicode_pua_used.txt`
  - 分类：已删除的临时扫描报告。
  - 原因：它只是 `unicode_pua.py` 的默认输出文件，体积较大且仓库内无任何消费入口，明显属于临时查看产物。

- `diagnose_git_bash.py`
  - 分类：已删除的一次性终端诊断说明脚本。
  - 原因：文件本身只是在控制台打印排查建议，没有任何调用入口；适用场景又是一次性的 Git Bash 排障，不具备持续维护价值。

- `diagnose_git_bash_response.py`
  - 分类：已删除的一次性 Git Bash 响应诊断脚本。
  - 原因：它同样只是输出一段面向当时问题的诊断说明，仓库内无调用方，也不属于当前输入法主线或测试链。

- `split_md.py`
  - 分类：已删除的临时 Markdown 拆分工具。
  - 原因：它只为当时按 `音元系统.md` 拆分生成文档而存在；当前输入文件已不存在，仓库里也没有任何调用方，只剩一个失效的手动 launch 配置。

- `query`
  - 分类：已删除的根目录孤立残留文件。
  - 原因：文件内容只是单行临时字符串，仓库内看不到任何代码、脚本、文档或配置入口引用它，不具备持续保存价值。

- `inscode.nix`
  - 分类：已删除的旧 Inscode / Nix 环境配置残留。
  - 原因：仓库内没有任何代码、脚本或文档再引用这份 Python 3.10 环境配置；对当前 Windows + Python 3.12 主线已无实际作用。

- `.inscode`
  - 分类：已删除的旧 Inscode 启动配置残留。
  - 原因：它只指向旧的 `pinyin/pinyin_to_hanzi_enhanced.py` 运行入口，仓库内无其他消费入口，也不属于当前输入法主线。

- `pinyin_hanzi.quickquery.sql`
  - 分类：已删除的一次性数据库速查脚本。
  - 原因：文件内容只是一个极小的 SQLite 结构查询片段，仓库内没有任何调用方；更像临时查看 `yime/pinyin_hanzi.db` 时遗留的便笺。

- `nul`
  - 分类：已删除的本机保留名残留文件。
  - 原因：它不是仓库已跟踪资产，也没有任何入口或用途，只是误落在工作区根目录的本机残留。

- `-remote inscode`
  - 分类：已删除的根目录命令输出残留。
  - 原因：文件内容只是一次 `git branch -a` 风格输出的保存结果，仓库内没有任何代码、脚本、文档或配置入口引用它，不具备任何持续价值。

- `编码测试.md`
  - 分类：已删除的根目录手测记录残留。
  - 原因：内容主要是某一阶段的手测清单、手工验收步骤与轮次记录，仓库内没有任何入口引用；这类工程便笺不应继续占据根目录入口位置。

- `setup_terminal_font.cmd`
  - 分类：已删除的根目录终端字体包装脚本。
  - 原因：仓库内没有任何代码、文档、测试或启动脚本再引用它；功能本身只是调用同目录 PowerShell 脚本设置本机终端字体，不属于当前输入法主线。

- `setup_terminal_font.ps1`
  - 分类：已删除的根目录终端字体配置脚本。
  - 原因：仓库内没有任何外部入口依赖它，相关字体配置说明已由文档承载；继续保留只会增加一个与主线无关的本机环境修改脚本。

- `stop_candidate_box.cmd`
  - 分类：已删除的根目录孤立停止脚本。
  - 原因：仓库内没有任何代码、文档或启动脚本再引用它；脚本内部依赖的 `windows_candidate_box.py` 进程名在仓库中也已不存在，说明它只是旧候选框阶段遗留的包装器。

- `requirements_py312.txt`
  - 分类：已删除的重复 Python 依赖清单。
  - 原因：当前仓库保留单一 `requirements.txt` 作为 Python 依赖入口更清晰；原文件内容只是当前 Windows/Python 3.12 主线所需依赖，继续并存只会造成安装入口分裂。

- `start_candidate_box.cmd`
  - 分类：已删除的根目录孤立启动脚本。
  - 原因：仓库内没有任何代码、文档或其他脚本再引用它；脚本本质上只是再包一层 `run_input_method.py`，与当前推荐启动方式重复。

- `install_python312.bat`
  - 分类：已删除的根目录旧安装包装脚本。
  - 原因：仓库内没有任何代码、文档或启动入口再引用它；内容只是把安装文档步骤硬编码成批处理脚本，而且仍保留旧阶段启动提示，继续保留只会制造重复入口。

- `install_python312.ps1`
  - 分类：已删除的根目录旧安装包装脚本。
  - 原因：仓库内没有任何外部入口再依赖它；内容与安装文档重复，并且仍包含旧启动路径提示，不适合作为当前主线安装入口继续保留。

- `markdown-custom.css`
  - 分类：已删除的根目录 Markdown 样式残留。
  - 原因：文件内容只有极小的段落与标题样式覆盖，仓库内没有任何代码、文档或页面再引用它；继续保留只会制造一个无入口的根目录显示残留。

- `activate_yinyuan_keyboard.cmd`
  - 分类：已删除的根目录键盘激活包装脚本。
  - 原因：仓库内没有任何代码、文档或其他脚本再引用它；内容只是对当前用户注册表写入键盘布局项的本机操作包装，不属于当前仓库主线入口。

- `import_hanzi_pinyin_data.py`
  - 分类：已删除的根目录旧数据库导入脚本。
  - 原因：仓库内没有任何代码、文档或脚本再引用它；它直接写入 `yime/pinyin_hanzi.db` 的 `汉字拼音初始数据` 表，功能已被模块内的 `yime/Initialize_hanzi_pinyin.py` 初始化链取代。

- `import_frequency_data.py`
  - 分类：已删除的根目录旧字频导入脚本。
  - 原因：仓库内没有任何入口再依赖它；它通过修改 `汉字拼音初始数据` 表结构并写回频率，已经偏离当前以 `汉字频率` 表为主的模块内频率导入链，现行主线由 `yime/import_8105_char_frequency.py` 与相关频率脚本承担。

- `decompose_syllables.py`
  - 分类：已删除的根目录空文件残留。
  - 原因：文件内容为空，仓库内也没有任何代码、文档、脚本或配置引用它，属于典型的已跟踪孤儿文件。

- `start_inspect_yinjie_encoding.bat`
  - 分类：已删除的根目录手动启动包装脚本。
  - 原因：仓库内没有任何代码、文档、测试或其它脚本再引用它；功能只是包一层 `inspect_yinjie_encoding.py`，不构成独立入口价值。

- `start_yinjie_encoder.bat`
  - 分类：已删除的根目录手动启动包装脚本。
  - 原因：仓库内没有任何代码、文档、测试或其它脚本再引用它；功能只是包一层 `syllable_codec/yinjie_encoder.py`，与直接运行 Python 入口重复。

- `start_rebuild_pinyin_assets.cmd`
  - 分类：已删除的根目录手动启动包装脚本。
  - 原因：仓库内没有任何代码、文档、测试或其它脚本再引用它；功能只是包一层 `internal_data/pinyin_source_db/rebuild_pinyin_assets.py`，不应继续占据根目录入口位置。

- `inspect_yinjie_encoding.py`
  - 分类：已删除的根目录手动排查脚本。
  - 原因：仓库内没有任何代码、文档、测试或其它脚本再引用它；在对应的启动包装器删除后，它只剩单独的人工排查用途，不再构成当前仓库需要保留的根目录入口。

- `dev_check.cmd`
  - 分类：已删除的根目录开发检查包装脚本。
  - 原因：仓库内只剩一处安装文档提及它，未被代码、测试或其它脚本消费；功能也只是检查进程和锁文件状态，不足以继续占据根目录入口位置。

- `run_input_method_v2.py`
  - 分类：已删除的根目录旧输入法入口包装脚本。
  - 原因：当前仓库已经统一到 `python -m yime.input_method.app` 和 `python run_input_method.py` 作为唯一主线入口；原文件只负责转发到已废弃的 V2 热键实现，继续保留只会制造重复且过时的启动路径。

- `yime/input_method/app_hotkey.py`
  - 分类：已删除的模块内旧 V2 热键实现。
  - 原因：当前主线 `yime/input_method/app.py` 已覆盖仓库支持的热键唤起、待命恢复和回贴链路；该文件没有任何当前产品入口依赖，剩余价值只体现在历史兼容与专属测试上，不再值得继续维护。

#### 7. 旧 JS 原型链（2026-05）

以下对象已经整体迁出主仓库，当前正式外置位置为外部 `Yime-js-prototype` 仓库：

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

以下交互式 HTML 工具页已从主仓库根目录迁出，当前外置位置为外部 `Yime-html-tool-prototypes` 仓库：

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

补充删除：

- `tools/workflow_monitor.html`

分类：已删除的孤立前端监控原型。

原因：该页面没有任何仓库内入口引用，且自身仍停留在“模拟工作流数据”和“这里应该发送请求到后端”的原型状态；它既未接入当前工具链，也不是现行文档站或运行时页面的一部分，继续保留只会增加静态资产噪音。

#### 9. docs/ 旧静态 HTML 文档站（2026-05）

以下 `docs/` 下的旧静态 HTML 文档站页面已整体迁出主仓库，当前外置位置为外部 `Yime-docs-html-site` 仓库：

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

#### 10. 导出残留图片与临时导出参数（2026-05）

- `images/`
  - 分类：已删除的导出图片转存目录。
  - 原因：当前仓库内没有文件再引用 `images/` 下内容；其中文件名大量呈现为 `image1.png`、`image25.png`、`tonal_contour1.svg` 这类导出序号样式，更接近外部文档/网页转存图集，而不是当前项目维护中的命名式资产。

- `params.json`
  - 分类：已删除的临时导出参数文件。
  - 原因：内容是一次性的 Markdown 转 HTML 参数快照，并且只引用一个示例 `test.md`；它不属于当前主线配置，也没有仓库内调用关系。

#### 11. 孤立字体样式残留（2026-05）

- `styles/tone_font.css`
  - 分类：已删除的孤立试验样式。
  - 原因：该文件唯一用途是声明 `../fonts/custom_tone.otf`，但仓库中并不存在这份字体文件，且没有任何页面、样式或脚本再引用 `tone_font.css`；它应理解为未接入主线的旧试验残留，而不是待补齐的运行资产。

- `styles/styles.css`
  - 分类：已删除的孤立字体样式。
  - 原因：该文件只为 `body`、`h1`、`table` 和 `.custom-font` 声明 Noto Sans 字体，但当前仓库内没有任何页面、脚本、配置或文档入口再引用它；同类字体预览职责已经由 `.vscode/markdown.css` 承担，因此它属于未接入当前主线的旧残留。

#### 12. 孤立 `.bak.py` 旧脚本（2026-05）

- `syllable/analysis/slice/shouyin.bak.py`
  - 分类：已删除的旧脚本备份件。
  - 原因：当前仓库已保留 `syllable/analysis/slice/shouyin.py` 作为现行实现；`.bak.py` 版本不再被主线代码引用，仅残留在旧打包清单中。

- `yime/transform_dict_structure.bak.py`
  - 分类：已删除的旧脚本备份件。
  - 原因：当前仓库已保留 `yime/transform_dict_structure.py` 作为现行实现；`.bak.py` 版本只剩一条调试启动配置引用，不再承担维护职责。

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

当前 `syllable_codec/yinjie_encoder.py` 仍然直接消费：

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
4. `syllable_codec/yinjie_code.json`

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
  - `syllable_codec/yinjie_code.json`
   - `yinyuan.klc`
   - 数据库与导出文件

只要这个分层稳定下来，后续无论换码点区、重做布局、修复工具链还是重建数据库，都可以各改各层，不会再互相污染。
