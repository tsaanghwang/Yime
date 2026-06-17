# Yime Utils

`yime/utils/` 保存仍被 `yime/` 主线模块直接复用的内部辅助逻辑。

当前包括：

- `pinyin_normalizer.py`：拼音标准化核心逻辑与 CLI。
- `pinyin_zhuyin.py`：拼音到注音符号转换工具。

这两个模块进一步内聚到 `yime/utils/`，避免继续占用顶层目录。
