# 高频新词扫描

该模块只读取 Rime “同步数据”生成的 `*.userdb.txt` 一致快照，对照当前
schema 的系统词典，发现系统库未收录但用户已经重复提交的汉字词条。

默认门禁：

- 提交次数不少于 3；
- 长度为 2～16 个汉字；
- 只包含汉字；
- 当前系统词典中尚不存在相同字串；
- 最多输出 5,000 条，按提交次数和 Rime 学习权重排序。

输出位于用户目录的 `promotion_scan`：

- `yime_lexicon_promotion_candidates.json`：供 AI、测试和后续云端聚合程序读取；
- `yime_lexicon_promotion_candidates.tsv`：供人工审查和表格分析。

报告明确记录 `offline_only: true` 和 `upload_performed: false`。本模块没有网络
代码，不上传词条、句子或用户标识。云端聚合、跨用户阈值、隐私保护和正式词库
晋升属于后续阶段。

运行前应在 Yime 语言栏执行“设置 → 数据维护 → 同步数据”。扫描器会尝试使用
随 Yime 安装的 `rime_dict_manager.exe` 刷新快照；若活动 LevelDB 被 librime
锁定，则安全回退到最近同步快照，不会直接读取或修改活动数据库。
