# syllable.analysis 阅读入口

修改或解释本目录代码前，先读
[片音分析与音元表示：工程阅读概要](../../docs/PIANYIN_ANALYSIS_OVERVIEW.md)和
[噪音类与乐音类：分类说明](../../docs/ZAOYIN_YUEYIN_CLASSIFICATION.md)。

特别注意：

- `Pianyin` 对象是符号化特征段表示，不是音频帧、波形块或等长平顶音段；
- `Yinyuan` 是表示条件片音的抽象变元；
- `M01`、`N01` 等 Yinyuan ID 只是音元的唯一编号，不是实际音值；
- 四元编码位置不表示四个等长语音时间窗；
- 当前生产链从带调拼音生成 Yinyuan ID，并未实现波形切分或片音插值合成。

正式音节编码入口是 `syllable_encoding_pipeline.py`，当前端到端数据链见
[当前实现总览](../../docs/CURRENT_ARCHITECTURE.md)。
