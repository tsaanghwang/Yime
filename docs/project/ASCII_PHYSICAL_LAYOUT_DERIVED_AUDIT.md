# 新 ASCII 布局的离线派生审计

日期：2026-10-09。范围：新布局分支的离线投影审计；当前键盘实验仅使用规范词库。
用户选择本轮完成基础键盘实验，融合儿化载体另行设计，暂不替换正式输入法。
本记录不批准新的音变、候选范围、载体共享或运行模块开关。

## 已完成的派生更新

- `internal_data/yime_syllable_decomposition.tsv` 从正式音节库存和结构化编码器重新生成，
  保留全部 1,737 条规范音节及其四音元语义。新投影涉及 1,733 条既有键码变化。
- `hm5`、`m1`、`m2`、`m4` 使用停用的 M25–M27；审计行保持拼音、规则、符号、
  四个稳定 ID 和别名信息，标记 `disabled_by_layout`，`layout_code` 为空。
  这不是编码器失败，也没有从规范库存删除这些音节。
- `internal_data/connected_speech/erhua_lexical_annotations.json` 和
  `erhua_input_aliases.json` 从既有 PSC 显式授权来源重新生成。仍为 131 条已准入记录、
  1 条明确排除记录；`runtime_enabled` 继续为 false。
- 儿化 bundle 与 Git 基线比较：除生成时间和 `layout_key_code` 外，所有字段完全相同；
  音元 ID、缩码位置、符号、融合特征改写、文字、来源和准入范围均未变化。

新增回归用一个完整 ASCII 置换布局重算全部 131 条记录的三种码制，验证只有布局字符
改变，规范 ID、码长、缩码结果及融合特征仍相同。另验证四条停用音节保留完整语义且不
输出输入码。针对两组派生物的检查结果：`9 passed, 1 skipped`；跳过项为需要外部
统一来源数据库的 omission 审计，不是布局或儿化测试失败。

```text
python -X utf8 -m pytest tests/yime/test_explicit_erhua_lexicon.py tests/yime/test_syllable_decomposition_audit.py -q
```

## 融合儿化的 15 个已证实载体冲突

旧儿化载体由
[`erhua_sound_key_projection.json`](connected_speech/erhua_sound_key_projection.json:37)
显式定义；这些大写字符在新盘面上全部已经承担基础音元：

| 旧专用 ASCII | 新基础音元 | 载体源文件行 |
| --- | --- | --- |
| F | M05 | 39 |
| D | M11 | 45 |
| S | N18 | 51 |
| R | N27 | 57 |
| E | M16 | 63 |
| W | M24 | 69 |
| Y | M08 | 75 |
| T | M14 | 81 |
| Q | N26 | 87 |
| V | M07 | 93 |
| C | N17 | 99 |
| X | M23 | 105 |
| P | M19 | 111 |
| A | M10 | 117 |
| Z | N16 | 123 |

既有生成器在
[`erhua_sound_projection.go`](../../go-backend/input_methods/yime/connectedspeech/erhua_sound_projection.go:133)
拒绝 dedicated key 与基础投影重叠。按新布局执行生成入口，实际得到：

```text
erhua key class ERHUA-KEY-A-RHOTIC-HIGH dedicated key "F" collides with the base layout
```

复现命令（工作目录 `go-backend`）：

```text
go run ./cmd/yime-erhua-mixed-derive --repo-root .. --aliases ../internal_data/connected_speech/erhua_input_aliases.json --annotations ../internal_data/connected_speech/erhua_lexical_annotations.json --data-dir ../.generated/ascii-keyboard/data --output-dir ../.generated/ascii-keyboard/erhua-blocked-audit
```

拒绝发生在 runtime 生成函数的投影校验阶段，早于创建输出目录或写词典。
本轮保留这一保护；没有重分配大写载体，没有把 dedicated 类改成未经决定的共享类，
也没有停用正式产品的儿化模块。新布局的融合儿化三模式真实 Rime 验收因此尚未进行。
不能用旧词典/旧布局的 Rime 通过结果替代这个未解决项目。

## 后续语流迁移检查点

原 N12/N26 共键已拆成 N12=`'`、N26=`Q`。历史阶段 6D manifest 的
`shared_key_candidate_count=1061` 是旧布局结果；未来重新投影“啊”的既有审定路线时，
这些记录可能从同键不物化变成需要实际附加条目。必须在既有来源范围内重新生成三模式
报告、碰撞审计和隔离真实 Rime 回归，不能沿用旧共键计数而漏掉并行路径。

上述语流迁移与 15 个儿化载体设计均列入后续工作。当前 lab 的规范词库闭环、独立
ANSI 输入和概念键盘点击验收不表示这些运行别名已经迁移。
