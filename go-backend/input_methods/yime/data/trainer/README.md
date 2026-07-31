# Yime 练习课程

这里保存随 Yime 发布的练习课程数据。练习器本身是独立进程，不进入
PIME/TSF 输入链路。

课程中的音节使用规范数字标调拼音，运行时通过当前有效的
`yime_pinyin_codes.tsv` 生成变长、等长和省键编码；键位题通过当前
`yime_yinyuan_layout.json` 解析。课程不得复制、硬编码三种输入方案的
目标编码。

`yinyuan_catalog.json` 保存 57 个稳定 Yinyuan ID 的教学名称、类别、乐音调级、
覆盖的五度片音层级和可选听觉锚点。它不保存物理键；物理键始终由当前
`yime_yinyuan_layout.json` 解析。`audio` 缺省时，文字和键位练习必须继续可用。

当前课程格式版本为 `1.2`，支持：

- `keymap`：用 `yinyuan_id` 解析当前物理键；
- `syllable_association`：从标准拼音音节解析首音、呼音、主音、末音的四音元序列；
- `syllable_contrast`：用 `syllable` 生成当前模式编码；
- `common_words`：用 `syllables` 生成连续词语编码。

`syllable_association` 只在课程中保存规范数字标调拼音。运行时从
`yime_syllable_decomposition.tsv` 读取标准标调拼音和四个 Yinyuan ID，再从当前布局
解析键位。课程不得手写音元序列。课程题目和音元目录均可使用相对于各自 JSON
文件的可选 `audio` 路径；文件暂缺只禁用播放，不阻止课程加载。
