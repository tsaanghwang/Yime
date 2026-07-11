# 单一等长真源码表阶段准备

## 目标

Yime 的下一阶段恢复为“一个外部真源、三套内部运行产物”：

```text
外部等长音元码表（唯一可导入、可人工维护）
    -> 规则校验与模式转换
    -> 等长 / 变长 / 省键 ASCII 运行码表
    -> Rime 构建、部署和会话重载
```

项目早期只导入一套码表；后续为了验证三种输入模式，逐渐形成三份系统词典和一份同时保存三列结果的拼音编码表。三份结果如果继续独立导入或修补，模式间关系会随规则演进而漂移。

本阶段约束：

- 外部错误只允许来自一份等长真源码表；
- 变长和省键错误必须归因于程序规则，而不是另一份外部码表；
- 三套 Rime 字典仍可保留，但只能是可删除、可重建的内部产物；
- 日常输入仍查询预生成索引，不在按键路径逐词转换。

## 当前已完成的基础

当前工程已经具备大部分外围能力，不应在切换时重写：

1. 三个 Rime schema 已稳定存在：`yime_full`、`yime_variable`、`yime_shorthand`。
2. 用户词库已经采用单一数字标调拼音源文件 `yime_user_phrases.txt`，应用时生成三份 `custom_phrase_{mode}.txt`。
3. `reverselookup.EncodeNumericTonePinyin` 已提供“拼音 -> 当前模式 ASCII 码”的统一调用面。
4. 设置同步、Rime 外部构建、完整 redeploy、活动会话延迟重载和失败提示已经完成。
5. 系统词库审计、用户词库、屏蔽词、诊断和运行时变更通知已有独立包和测试。
6. 候选注释可以统一显示等长 PUA 音元结构；该显示用于解释编码依据，不要求复制当前输入模式。

下一阶段应替换“系统词库的数据来源”，而不是重做输入法宿主、Rime 会话或候选窗。

## 当前多真源风险

当前共享数据包含：

- `yime_full.dict.yaml`
- `yime_variable.dict.yaml`
- `yime_shorthand.dict.yaml`
- `yime_pinyin_codes.tsv` 中的 `full`、`variable`、`shorthand` 三列

这些文件目前都被当作既有事实读取。长期风险包括：

- 同一拼音的三种模式不是由同一版本规则生成；
- 系统词库、用户词库和反查各自观察到不同转换结果；
- 单独替换某一份字典后，候选、反查和用户词条编码不一致；
- ASCII 键位投影的修改被误认为音元模式规则修改；
- 人工补丁无法判断应落在真源、转换规则还是布局投影。

## 权威规则边界

正式移植或重写前，以下实现是对照基准：

- 模式统一入口：`C:\dev\Yime-variable-length\yime\utils\code_modes.py`
- 变长转换：`C:\dev\Yime-variable-length\syllable\codec\variable_length_yinyuan\transform.py`
- 省键中调省略：`C:\dev\Yime-variable-length\syllable\codec\input_shorthand\`
- 干音音质组和调级元数据：`yinjie_runtime_key_symbol_mapping.json` 与 `key_to_symbol.json`

变长规则当前为：先合并相邻且完全相同的音元，再省略虚首音。省键规则在此基础上，还依据干音音质组和调级元数据省略同音质连续段的中调。

`C:\dev\Yime-python-prototype\syllable\codec\yinjie_jianpin_draft.py` 明确是草稿兼容实现，不得作为正式省键规则真源。

必须分开以下三个层次：

```text
等长语义音元码
    -> 模式转换（等长 / 变长 / 省键）
    -> 键盘布局投影
    -> ASCII Rime 编码
```

外部真源优先保存语义音元码。如果首版只能接收等长 ASCII，必须在格式元数据中固定布局版本，并在导入时验证其语义映射。模式转换不得直接依赖某一版物理键位字符。

## 目标数据所有权

| 数据 | 所有者 | 是否允许人工修改 |
|---|---|---:|
| 外部等长真源码表 | 数据维护者 | 是 |
| 模式转换规则和版本 | 程序代码 | 通过代码评审修改 |
| 键盘布局投影和版本 | 程序数据 | 通过代码评审修改 |
| 三套系统 `dict.yaml` | 生成器 | 否 |
| `yime_pinyin_codes.tsv` 派生列 | 生成器 | 否 |
| Rime `.bin` / build 目录 | Rime | 否 |
| 用户数字标调拼音词库 | 用户 | 是 |
| 三套 `custom_phrase_{mode}.txt` | 生成器 | 否 |

生成文件必须记录源文件 SHA-256、规则版本、布局版本，并标记 `GENERATED FILE - DO NOT EDIT`。

## 实施阶段

### 阶段 0：冻结与审计（当前阶段）

- 冻结当前三套系统字典和 `yime_pinyin_codes.tsv` 作为比较基准；
- 记录文件 SHA-256、条目数、重复项和无法反查项；
- 不改变当前安装包、schema 列表和运行时选择逻辑；
- 建立“现有结果 vs 权威规则生成结果”的差异报告格式。

### 阶段 1：离线单源生成器

- 输入只接受一份等长真源码表；
- 在临时目录生成三套系统字典和拼音编码映射；
- 输出缺失音节、非法等长码、转换冲突、布局投影缺失和重复词条报告；
- 不自动覆盖已安装数据；
- 用当前三套文件逐条对照，所有差异必须分类，不能静默接受。

### 阶段 2：导入、原子替换与回滚

- 设置工具只暴露一个“导入等长真源码表”入口；
- 完成解析、校验、转换和 Rime 试构建后才替换；
- 同盘临时目录生成，成功后原子替换；
- 保留上一个有效版本和生成清单；
- 失败时继续使用原运行数据，并提供可复制的错误摘要；
- 成功后发出一次 lexicon + redeploy 修订通知，由现有延迟重载链处理活动会话。

### 阶段 3：取消三套外部导入

- 删除或隐藏三种模式的独立系统词库导入入口；
- 三套字典只作为内部缓存和安装包产物存在；
- 诊断工具显示唯一真源哈希、规则版本、布局版本和最后成功生成时间；
- 发布测试禁止安装包携带无法追溯到同一清单的三套字典。

## 差异报告最低字段

```text
entry_type
text
numeric_pinyin
canonical_full_code
existing_full_ascii
generated_full_ascii
existing_variable_ascii
generated_variable_ascii
existing_shorthand_ascii
generated_shorthand_ascii
difference_class
source_file
source_line
```

`difference_class` 至少区分：`source_error`、`variable_rule_change`、`shorthand_rule_change`、`layout_projection_change`、`legacy_manual_patch`、`pinyin_segmentation_difference`、`missing_mapping` 和 `weight_only_difference`。

## 切换前验收门槛

没有满足以下条件，不得取消现有三套运行产物：

1. 等长真源可重复生成完全相同的产物（确定性构建）。
2. 所有差异均已分类，并有采纳旧值或新规则的明确决定。
3. 三个 schema 均能选择、输入、翻页、提交并保持 Rime 自有候选分页。
4. 用户词库和系统生成器使用同一规则版本。
5. 反查、标准拼音注释、等长 PUA 音元注释和键位序列均通过回归测试。
6. 导入失败、Rime 构建失败和进程占用时不会破坏当前可用版本。
7. 安装包中的三套字典、映射表和生成清单具有同一源 SHA-256。
8. 已安装二进制和数据经过重新打包、安装及进程重启验证。

## 暂不实施

- 不把完整 Python 音节分析体系迁入 Go；
- 不在每次按键或候选枚举时逐词转换；
- 不改变 native Rime 的候选分页所有权；
- 不合并三个 Rime schema；
- 不改变候选注释统一显示等长 PUA 音元结构的现状；
- 不把草稿省键实现当作正式规则。

## 下一阶段唯一入口

下一次实现从“阶段 0 差异审计工具”开始。它只读当前数据和原型规则，生成报告，不覆盖源码字典、不部署 Rime。报告稳定后，再决定把规则移植到 Go，还是继续由 Python 原型生成、Go 负责校验和部署。
