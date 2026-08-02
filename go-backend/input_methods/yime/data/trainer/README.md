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
- `syllable_composition`：不静态保存题目；按当前四音元分解表生成首音和干音分组；
- `syllable_practice`：界面名“编码练习”；不静态保存题目，把正式编码表中的 1729 个音节按 24 个首音分组；
- `word_practice`：界面名“字词练习”；每次启动从系统运行库高频部分按双音、三音、四音、单音顺序各随机抽取五题；
- `sentence_practice`：界面名“短句练习”；每次启动从系统运行库高频部件可动态组成的短句中随机抽取五题；
- `syllable_association`：兼容旧课程中少量静态音节分解题，基础课程不再单独显示；
- `syllable_contrast`：用 `syllable` 生成当前模式编码；
- `common_words`：用 `syllables` 生成连续词语编码。

`word_practice` 和 `sentence_practice` 不允许静态填写 `items`。二者只读安装目录中的
`yime_full.dict.yaml`，不读取用户词典、学习频次或 Rime 会话状态，也不向 PIME
和 Rime 写入任何内容。随机题组在进程启动时确定，切换输入方案只改变答案投影，
不会重新抽题。

`syllable_association` 只在课程中保存规范数字标调拼音。运行时从
`yime_syllable_decomposition.tsv` 读取标准标调拼音和四个 Yinyuan ID，再从当前布局
解析键位。课程不得手写音元序列。课程题目和音元目录均可使用相对于各自 JSON
文件的可选 `audio` 路径；文件暂缺只禁用播放，不阻止课程加载。

`syllable_composition` 的首音分组复用 `yinyuan_groups.json` 中六组首音。干音
按主音与末音的音质组合从 `yime_syllable_decomposition.tsv` 动态归为 18 类，
排除 `[m+m]` 类，并在每类中按高高高、低中高、低低低、高中低四种调型分组。
只采用当前规范分解表中存在的干音，不为缺失声调虚构音节或编码。
`ong/ueng` 是同一三音元序列的条件形式：与首音相拼显示 `ong`，独立成音节时
显示标准形式 `ueng`（音节拼写为 `weng`）。练习题始终并列说明两者，不因当前
词典缺少某个 `weng` 声调实例而省略 `ueng` 形式，也不把它重复生成为另一道题。

`syllable_practice` 的范围以当前 `yime_pinyin_codes.tsv` 为准。每个正式编码音节
必须能在规范分解表中取得稳定音元 ID，三种答案必须与当前编码表一致；仅在分解
来源表存在、尚未进入运行码表的记录不生成练习题。题面按原型的两段式流程先显示
“首音分析”，再显示由呼音、主音、末音构成的“干音分析”，最后合成完整音元
拼音；不采用难以解释的整体音节直接四分法。
