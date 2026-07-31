# Yime 音元指法练习组件

## 定位

练习器是 Yime 主仓库内的独立 Win32 工具，生成
`go-backend/yime-trainer.exe`。它由“工具箱 → 指法练习”启动，但不进入
PIME、TSF、Rime 会话或候选窗口进程。

原独立 Python 原型提供的三类题型和 JSON 课程边界已经迁入。发布版本不依赖
Python，也不再维护第二套拼音到编码映射。

## 数据来源

- 课程：`go-backend/input_methods/yime/data/trainer/*.json`
- 音元键位：当前有效的 `yime_yinyuan_layout.json`
- 三模式音节编码：当前有效的 `yime_pinyin_codes.tsv`

如果用户已经应用完整的个人布局覆盖，练习器从用户目录读取布局和编码；课程
本身仍从只读安装目录加载。题目只保存稳定的音元 ID 或规范数字标调拼音，不
保存派生的变长、等长、省键目标码。

## 当前题型

### `keymap`

必填 `yinyuan_id`。运行时从当前布局解析物理键。

### `syllable_contrast`

必填 `syllable`，采用 `ma1` 形式的数字标调拼音。运行时按所选输入方案生成
编码。

### `common_words`

必填 `text` 和逐字对应的 `syllables`。课程加载时校验字数和音节数，运行时
生成连续输入编码。

## 输入与安全边界

练习输入框只对自身解除输入法上下文，以便接收原始键串；它不切换系统输入法，
不写入 PIME 安装目录、Rime 用户目录或学习数据。当前成绩仅保存在本次进程内。

候选选择练习尚未加入。后续实现时必须保持 Yime 的既定规则：裸数字始终是
组成键，候选序号只能使用 `Shift+1` 至 `Shift+9`。
