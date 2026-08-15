# 阶段 1：既有轻声链审计

## 性质与边界

本阶段审计现有词汇固有轻声链，不生成语境轻读候选，不回填深层本调，也不把数字调 `5` 解释为
固定的第五声调或确定的表层调值。

审计器只读取仓库中的规范数据，报告只写入 `.tmp/neutral-tone-chain-audit`。配置结构中没有已安装
PIME 路径或真实用户目录，因此不会访问、部署或改写：

- `C:\Program Files (x86)\YIME`；
- `%APPDATA%\PIME`；
- `%LOCALAPPDATA%\PIME`；
- 用户词库、学习数据和 Rime 用户目录。

用户词库门禁在 `.tmp` 中创建一次性源文件和派生目录，完成后删除。真实 librime 回归使用 Go 测试
临时目录。

## 运行命令

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-neutral-tone-chain.ps1
```

真实 librime 三模式回归默认不运行；显式执行：

```powershell
$env:YIME_RUN_REAL_RIME_TESTS='1'
go test ./input_methods/yime -run TestRealRimeNeutralToneEntryAcrossAllThreeSchemas -count=1 -v
```

第二条命令须在 `go-backend` 目录运行。

## 门禁

审计必须同时证明：

1. `yime_pinyin_codes.tsv` 中全部 `*5` 音节在四音元分解表中存在；
2. 三个乐音位置都使用对应音质组的中调 ID，且布局投影与等长码一致；
3. 标准拼音映射存在并保持不标调；
4. 变长、等长、省键由同一个等长四音元记录派生；
5. 三模式系统词典中的轻声词条文本、权重和派生码一一对应；
6. 三模式反查保持轻声身份；
7. 临时用户词库源拼音保留 `5`，三种派生文件齐全，源文件哈希不变；
8. 规范输入文件审计前后 SHA-256 一致；
9. 运行时语流别名生成数为零；
10. 真实 librime 能在三种方案中由 `zhuo1 zi5` 的对应编码给出“桌子”。

## 报告文件

| 文件 | 内容 |
|---|---|
| `summary.json` | 数量、门禁、问题数、只读哈希和别名生成数 |
| `neutral_syllables.tsv` | `*5` 音节、标准拼音、三模式码和四音元 ID |
| `neutral_lexicon.tsv` | 含轻声音节的既有词条及三模式覆盖 |
| `reverse_lookup.tsv` | 每个轻声音节的三模式反查结果 |
| `code_ambiguities.tsv` | 同码拼音集合及其调类、轻声身份是否保持 |
| `user_lexicon.tsv` | 临时用户词库三模式重建结果 |
| `issues.tsv` | 阻断门禁的问题；通过时只有表头 |
| `baseline_hashes_before.json` | 规范输入审计前哈希 |
| `baseline_hashes_after.json` | 规范输入审计后哈希 |
| `manifest.json` | 输入和确定性输出报告哈希 |

## 2026-08-09 基线

- `*5` 规范音节：303；
- 含轻声音节的系统词典记录：101,928；
- 三模式反查：909；
- 临时用户词库重建检查：3；
- 既有同码组：27；
- 阻断问题：0；
- 运行时语流别名：0；
- 规范输入哈希：审计前后一致；
- 真实 librime：变长、等长、省键全部通过。

27 组同码关系都保持相同调类。部分关系包含 `e/o`、`me/mo`、`le/lo` 等音质差别，单凭编码不能
唯一恢复原拼音。反查实现必须给出确定性结果，同时报告完整歧义集合；不得把选中的一个拼音冒充
唯一语音事实。现已由规范读音来源生成“文本—编码—规范拼音”旁表
`yime_pinyin_reverse_source.tsv`：它只补回正向编码丢失的信息，不改变本阶段的轻声编码，且已纳入
审计前后只读哈希门禁。详见[同编码不同拼音反向映射](../REVERSE_PINYIN_SOURCE_MAPPING.md)。
