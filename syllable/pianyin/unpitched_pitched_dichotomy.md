# 旧分类说明（兼容入口）

本文原先用 *unpitched / pitched sound dichotomy* 解释项目的“噪音类／乐音类”。这个说法容易被理解成普通声学意义上的“没有／具有基频”，因而不再作为定义使用。

现行定义见：

- [噪音类与乐音类：分类说明](../../docs/ZAOYIN_YUEYIN_CLASSIFICATION.md)
- [Zaoyin and Yueyin: Classification Specification](../../docs/ZAOYIN_YUEYIN_CLASSIFICATION_EN.md)

简要地说：

- `zaoyin`：音质参与区别；音高可以不存在、不确定、不稳定，或存在但不参与当前编码区别。
- `yueyin`：音质与指定音高共同参与区别。

旧名 `UnpitchedPianyin`、`PitchedPianyin` 只保留为代码兼容别名。新代码使用 `ZaoyinPianyin`、`YueyinPianyin`。
