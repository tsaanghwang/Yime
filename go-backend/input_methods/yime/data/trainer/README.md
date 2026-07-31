# Yime 练习课程

这里保存随 Yime 发布的练习课程数据。练习器本身是独立进程，不进入
PIME/TSF 输入链路。

课程中的音节使用规范数字标调拼音，运行时通过当前有效的
`yime_pinyin_codes.tsv` 生成变长、等长和省键编码；键位题通过当前
`yime_yinyuan_layout.json` 解析。课程不得复制、硬编码三种输入方案的
目标编码。

当前格式版本为 `1.1`，支持：

- `keymap`：用 `yinyuan_id` 解析当前物理键；
- `syllable_contrast`：用 `syllable` 生成当前模式编码；
- `common_words`：用 `syllables` 生成连续词语编码。
