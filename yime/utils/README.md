# Yime Utils

`yime/utils/` 保存仍被 `yime/` 主线模块直接复用的内部辅助逻辑。

当前包括：

- `pinyin_normalizer.py`：拼音标准化核心逻辑与 CLI。
- `pinyin_zhuyin.py`：拼音到注音符号转换工具。

原先顶层 `utils/` 中已经没有活动消费者的演示、算法试验与样例数据库对象，仍保留在 `legacy/utils_prototypes/`；这两个仍有活动导入关系的模块则进一步内聚到 `yime/utils/`，避免继续占用顶层目录。
