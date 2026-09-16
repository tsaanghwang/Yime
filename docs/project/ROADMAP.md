# 项目路线图入口

2026-09-16 更新。项目现行路线图统一为 [Yime 开发路线图](../YIME_DEVELOPMENT_ROADMAP.md)，当前实现与验证范围见[项目现状](../YIME_PROJECT_ASSESSMENT.md)。本文不再独立维护第二份阶段清单。

原文是 2026 年 7—8 月 Python 原型的规划快照，其中“原型继续运行”“跨仓库交接”和 Weasel 消费路线不适用于当前 Windows 双产品工程。历史文本可在 Git 历史中查阅，不作为现行开发或安装指令。

当前方向是 YimeCore 主开发、Rime/PIME 独立稳定维护。两套共享本仓的规范源数据与离线生成工具，各自携带运行资产并维护自己的用户状态。Python 仅用于离线工具；Yime 不主动或被动读取其他 Git 仓库。

## 候选池动态覆盖闭环（已完成）

2026-07-28 的候选分层、动态覆盖与长串迁移闭环保持已完成状态，见[原始完成记录](../DYNAMIC_CANDIDATE_COVERAGE.md)。R1—R3 残差属于后续持续改进队列，不恢复为尚未完成的删除式清理任务。该历史结论对应当时来源与覆盖基线，不表示所有后续输入质量问题已经解决。

## 当前文档入口

| 需要了解的内容 | 当前入口 |
|---|---|
| 已实现、已验证与未完成事项 | [项目现状](../YIME_PROJECT_ASSESSMENT.md) |
| 后续优先级和完成标准 | [开发路线图](../YIME_DEVELOPMENT_ROADMAP.md) |
| 双产品和共享数据结构 | [架构](../YIME_ARCHITECTURE.md) |
| 词库与音节离线工具 | [离线工具](../../tools/lexicon/README.md) |
| 数据来源隔离规则 | [仓库数据边界](YIME_REPOSITORY_DATA_BOUNDARY.md) |
| 候选语料专项历史与持续维护 | [候选语料路线图](../CANDIDATE_CORPUS_ROADMAP.md) |
| 安装、包交付和测试端任务 | [简版安装器](../../installer/simple/README.md)、[HANDOFF](../../installer/simple/HANDOFF.md) |
