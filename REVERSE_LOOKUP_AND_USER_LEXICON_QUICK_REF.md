# 反查编码与用户词库速查

这是一页速查版，只保留最常用操作。

完整说明见：

- [REVERSE_LOOKUP_AND_USER_LEXICON.md](REVERSE_LOOKUP_AND_USER_LEXICON.md)

相关脚本：

- `python tools/manage_user_lexicon.py ...`
- `python tools/diagnose_candidate_order.py ...`

## 1. 反查拼音和编码

### 在输入法 UI 中

1. 启动：

```bash
python run_input_method.py
```

1. 在输入框中输入或粘贴汉字词语，例如：`日`、`日本`、`今日`
1. 如果能查到，拼音标签会显示：

```text
rì běn / ri4 ben3 | <音元编码>
```

### 在终端里

```bash
python tools/query_phrase_code.py 日本
python tools/query_phrase_code.py 今日
python tools/query_phrase_code.py 日 --like
```

重点看三段：

- `Source`：源词库
- `Runtime`：当前运行时主库
- `User`：用户词库和用户频率

## 2. 加入用户词库

### 在输入法 UI 中

1. 在输入框中放入一个汉字词语，例如 `日本`
1. 右键输入框，选择 `加入用户词库`
1. 输入：
   - 数字标调拼音，例如 `ri4 ben3`
   - 标准拼音，例如 `rì běn`，可留空
   - 词内拼音要按音节加空格，例如 `duo1 ri4` 或 `duō rì`，不要写成 `duo1ri4` 或 `duōrì`

成功后状态提示类似：

```text
已加入用户词库: 日本 | rì běn / ri4 ben3 | <音元编码>
已更新用户词库: 日本 | rì běn / ri4 ben3 | <音元编码>
```

### 在终端里

```bash
python tools/add_user_phrase.py 日本 "ri4 ben3" --marked-pinyin "rì běn"
python tools/add_user_phrase.py 今日 "jin1 ri4" --marked-pinyin "jīn rì"
```

用户词库存放在：

```text
yime/user_lexicon.db
```

### 常用维护命令

```bash
python tools/manage_user_lexicon.py list-recent --limit 10
python tools/manage_user_lexicon.py export backups/user_lexicon_backup.json
python tools/manage_user_lexicon.py import backups/user_lexicon_backup.json
python tools/manage_user_lexicon.py init-db
python tools/manage_user_lexicon.py check
python tools/manage_user_lexicon.py repair-all
```

带数字声调的连写拼音现在也会自动整理，例如 `ri4ben3 -> ri4 ben3`。

如果要生成可随安装包分发的 seed 用户词库：

```bash
python tools/manage_user_lexicon.py export yime/user_lexicon_seed.json --no-frequency
```

首次启动时，如果目标机器的用户词库为空且尚未导入过 seed，程序会自动导入这个 `yime/user_lexicon_seed.json`。

## 3. 为什么它会排前面

查：

```bash
python tools/query_phrase_code.py 日本
```

看 `User 词语编码` 这一段里的：

- `persisted_reorder_frequency`：持久选词频率
- `last_recorded_at`：最近使用时间

如果看到：

```text
persisted_reorder_frequency=3
```

通常说明这个词不只是“存在于用户词库”，而且最近被你持续选中过，所以会长期排前。

如果要直接看某个编码下的实际候选排序：

```bash
python tools/diagnose_candidate_order.py --numeric-pinyin "ri4 ben3" --limit 10
```

## 4. 一句话判断

- 查不到：先用 `query_phrase_code.py`
- 想补词：右键 `加入用户词库` 或用 `add_user_phrase.py`
- 想备份/迁移：用 `manage_user_lexicon.py export / import / init-db / list-recent`
- 想知道为什么排前：先看 `User` 段里的 `freq` 和 `last_used`，再用 `diagnose_candidate_order.py`
