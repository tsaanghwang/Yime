# 词语调序规则说明

本文只说明当前这版“局部词语优先”规则如何工作，不讨论更长期的词库清理、连续输入演进或更大范围的排序重构。

## 当前目标

这套规则只解决一个很具体的问题：

- 在高碰撞单字码下，单靠单字频率时，首屏常被大量单字占满
- 用户明明已经打满第一个音节，更希望尽快看到常用词语候选

所以当前实现不是全局改写排序，而是在一小段局部路径上，对部分词语候选做额外提升。

## 什么时候触发

当前规则只在下面这个场景触发：

- 已完整输入 1 个音节，也就是 4 码
- 当前走的是词语前缀扩展，而不是完整多音节词精确命中
- 命中的桶在局部规则文件里有配置

换句话说，它主要影响“刚打完第一个音节时，候选框里先看到哪些词”。

它当前不负责：

- 用户词库调频
- 完整多音节词语精确命中后的排序
- 单字本身的基础排序
- 更长连续输入路径下的整体候选策略

## 规则来源

当前规则不是手工逐条硬编码，而是基于高碰撞桶自动生成：

- 高碰撞桶来源：`yime/reports/runtime_tuning_scan.json`
- 规则文件：`internal_data/local_phrase_priority_rules.json`
- 样本文件：`internal_data/local_phrase_priority_samples.json`
- 生成脚本：`tools/generate_local_phrase_priority_baseline.py`

当前默认覆盖前 20 个高碰撞单音节桶，每个桶给出 5 条定点词语目标和 10 条样本词语。

`local_phrase_priority_samples.json` 现在除了样本词语外，也会保留每个桶的 `lookup_code`、`candidate_count`、`demand_weight_sum`、`collision_demand_score` 和本轮 `target_phrases`，便于后续连续输入规则继续复用同一批样本入口。

## 当前筛选原则

生成脚本现在不是简单按 `phrase_frequency` 取前 5，而是先做一层“严格词优先、明显组合片段降权”的筛选。

当前会压制的条目主要包括：

- 明显功能词尾或句法片段，例如以“的、了、过、吗、吧、呢”等结尾的组合
- 一部分常见搭配尾巴，例如“一个、一些、一种、一定的、的时候、之后、以后、的话”
- 一些更弱的尾部片段，例如 3 字以上且以“能、会、要、在、将、给、让”结尾的条目
- 一些明显像句法骨架而不是严格词的“是…”类短语

这一步的目的不是认定这些串“永远不该存在”，而是避免它们在局部词语优先规则里直接占据前 5。

## 当前优先级关系

当前候选结果可以粗略理解成几层叠加：

1. 先按当前输入路径决定是单字查找、词语前缀扩展，还是完整词语命中
2. 再用运行时基础 `sort_weight` 排序
3. 若命中局部词语优先规则，则在该局部路径上给指定词语额外 boost
4. 用户词库和用户调频仍然可以继续影响最终结果

所以这套规则是“局部附加层”，不是替代整个候选排序系统。

## 如何更新

如果你修改了词语筛选策略或想重新覆盖最新高碰撞桶，可运行：

```bash
python tools/generate_local_phrase_priority_baseline.py --write --validate
```

如果只想检查当前仓库里的 rules/samples 是否仍与生成逻辑一致，可运行：

```bash
python tools/generate_local_phrase_priority_baseline.py --validate
```

对应回归测试：

```bash
python -m pytest tests/input_method/test_generate_local_phrase_priority_baseline.py -q
python -m pytest yime/input_method/test_local_phrase_priority_baseline.py -q
```

## 当前边界

这份规则说明只对应当前版本。

目前仍然没有处理的事情包括：

- 更系统的词库净化与严格词/高频组合分层
- 连续输入阶段更长上下文下的词语排序
- 特殊桶的人工白名单或人工覆盖层

因此应把这套规则理解为：

- 当前版本可运行、可生成、可回归的一层局部词语调序
- 不是最终词库标准，也不是最终连续输入排序策略
