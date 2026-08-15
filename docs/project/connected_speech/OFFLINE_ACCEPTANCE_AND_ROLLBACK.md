# 离线试算、回归基线与回退

## 基线清单

阶段 0 每次运行前后都必须计算下列已跟踪文件的 SHA-256：

```text
go-backend/input_methods/yime/data/yime_pinyin_codes.tsv
go-backend/input_methods/yime/data/yime_syllable_decomposition.tsv
go-backend/input_methods/yime/data/yime_yinyuan_layout.json
go-backend/input_methods/yime/data/yime_full.dict.yaml
go-backend/input_methods/yime/data/yime_variable.dict.yaml
go-backend/input_methods/yime/data/yime_shorthand.dict.yaml
go-backend/input_methods/yime/data/yime_full.schema.yaml
go-backend/input_methods/yime/data/yime_variable.schema.yaml
go-backend/input_methods/yime/data/yime_shorthand.schema.yaml
go-backend/input_methods/yime/data/yime_lexicon_manifest.json
go-backend/input_methods/yime/data/yime_runtime_profile.json
```

任一文件在离线试算后变化即为失败。阶段 0 不允许“生成后再恢复”来掩盖写入行为。

## 模块开关

清单使用以下逻辑开关，默认全部为 `false`：

```text
connected_speech.enabled
connected_speech.tone_sandhi
connected_speech.neutral_tone_surface
connected_speech.erhua_suffix_compatibility
connected_speech.erhua_fused
connected_speech.particle_allomorphy
connected_speech.assimilation
connected_speech.dissimilation
```

阶段 0 只允许在临时试算清单中切换开关。即使总开关为真，`research_only`、`deferred`、`rejected`
记录也必须保持禁用。模块开关不能改变记录的审定状态。

## 输出目录和报告

```text
.tmp/connected-speech-audit/
  manifest.json
  summary.json
  source_coverage.tsv
  rewrite_review.tsv
  three_mode_coverage.tsv
  code_length.tsv
  collisions.tsv
  ranking_impact.tsv
  rejected_records.tsv
  baseline_hashes_before.json
  baseline_hashes_after.json
```

`manifest.json` 至少记录 schema、ruleset、布局、模式转换和工具版本，以及全部输入和输出哈希。
时间戳不得参与确定性内容哈希；需要时间时单独写入非比较字段。

## 报告门禁

1. `record_id`、来源观察 ID 和规则 ID 均唯一；
2. 每个音节四个位置，首音为 `Nxx`，其余为 `Mxx`；
3. 每条改写的 `from_id` 与规范元组一致，`to_id` 已在稳定音元目录登记；
4. 三模式集合一一对应，模式转换来自同一语义四音元；
5. 等长模式必须保持每音节四码；在首音（包括虚首音）不省略的前提下，变长和省键模式必须从
   音变后的四音元重新投影，每音节满足 `2 ≤ len ≤ 4`，并报告码长增加、减少或不变；码长方向不
   作为拒绝条件，但任何变化都必须能由同一四音元记录和同一模式算法确定性重建；
6. `research_only`、`deferred`、`rejected` 的运行输出为零；
7. 候选文字策略不是 `preserve` 时必须有显式来源观察和人工判决；
8. 所有碰撞均列出规范候选、别名候选、旧排序和试算排序；
9. 第一批允许新增碰撞报告，不允许改变规范首选；
10. 前后基线哈希相同。

## 回归基线

- 正例：审定的“一、不”逐位置变调、既有轻声 `5`、儿缀 `er5` 兼容身份；
- 反例：`第一`、独立 `ér`、文字未写“儿”的口语 `r`、未审定虚词轻读；
- 边界例：`ao/iao` 末音按 `u` 分析、舌尖前后元音后的“啊”、来源相互冲突；
- 禁用例：所有模块关闭时报告中别名数量为零，规范哈希与基线一致；
- 布局例：默认布局和一个替代布局的语义音元改写相同，只有键位投影不同；
- 用户例：阶段 0 不访问用户数据；后续阶段才验证学习、备份、屏蔽词和用户词库。

## 回退演练

阶段 0 的回退是删除整个 `.tmp/connected-speech-audit/` 后重新运行规范测试。由于阶段 0 禁止写入
规范数据和用户数据，不需要数据迁移。

后续运行阶段必须继续满足：

1. 每个模块可以独立关闭；
2. 删除可再生别名产物；
3. 从同一规范真源重建三模式词典；
4. 比较并恢复规范构建哈希；
5. 保留用户规范拼音、学习记录和屏蔽词；
6. 真实 Rime 和 x86/x64 宿主验证通过后才重新启用。

发现失败时首先关闭具体模块，不回滚规范词典、码表、布局或 PIME 宿主。
