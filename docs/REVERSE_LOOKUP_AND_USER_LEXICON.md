# 反查编码与用户词库操作说明

本文档说明当前输入法原型中两类常用操作：

- 在输入框中输入或粘贴汉字后，如何反查首选拼音和编码
- 如何把缺词加入持久用户词库，并理解它为什么会排到前面

如果你只想看最短操作路径，请先看：

- [REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md](REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md)

本文对应当前主线实现：

- 启动入口：`python run_input_method.py`
- 反查查询脚本：[../tools/query_phrase_code.py](../tools/query_phrase_code.py)
- 用户词库写入脚本：[../tools/add_user_phrase.py](../tools/add_user_phrase.py)
- 用户词库管理脚本：[../tools/manage_user_lexicon.py](../tools/manage_user_lexicon.py)
- 候选调序诊断脚本：[../tools/diagnose_candidate_order.py](../tools/diagnose_candidate_order.py)
- 用户词库数据库：`yime/user_lexicon.db`
- 用户词库种子文件：`yime/user_lexicon_seed.json`

## 1. 汉字反查首选拼音和编码

### 适用场景

当你手里已经有一个汉字或词语，但不知道它当前是否在词库里、首选读音是什么、音元编码是什么时，可以直接用输入法 UI 或命令行工具反查。

### 在输入法 UI 中反查

1. 启动输入法：

```bash
python run_input_method.py
```

1. 在候选框输入框中直接输入或粘贴汉字词语，例如：`日`、`日本`、`今日`
1. 当前实现会优先按“汉字反查”路径处理，而不是按码元解码处理
1. 如果运行时库或用户词库中能找到该词，拼音标签会显示首选结果，格式类似：

```text
rì běn / ri4 ben3 | <音元编码>
```

1. 如果当前运行时库和用户词库都没有该词，会提示未找到

补充说明：

- 当前反查显示的是首选读音和对应编码，不显示全部多音读法
- 词语优先查用户词库，再查运行时词库
- 单字仍主要查运行时单字词库

### 用脚本查询字词和编码

如果你想直接在终端里看 source、runtime、user 三层数据，可用：

```bash
python tools/query_phrase_code.py 日本
python tools/query_phrase_code.py 今日
python tools/query_phrase_code.py 日
```

模糊查询可加：

```bash
python tools/query_phrase_code.py 日 --like
```

当前输出会分成三段：

- `Source 词语 / Source 单字`：源词库里有没有
- `Runtime 词语编码 / Runtime 单字编码`：当前运行时主库里有没有
- `User 词语编码`：用户词库里有没有，以及用户频率是多少

`User 词语编码` 这一段会显示：

- `phrase`
- `marked`
- `numeric`
- `yime`
- `note`
- `freq`
- `last_used`
- `updated`

其中：

- `freq` 表示用户持久选词频率
- `last_used` 表示最近一次通过选词调序写入用户频率的时间

所以当一个用户词排到前面时，你可以直接通过这个输出判断，是“因为它在用户词库里存在”，还是“因为它在用户词库里被长期选中过很多次”。

## 2. 把缺词加入用户词库

### 目标

当像 `日本`、`今日` 这类词不在当前主词库里，或你希望强制保留自己的读音和编码时，可以把它写入持久用户词库。

用户词库特点：

- 使用单独数据库文件：`yime/user_lexicon.db`
- 重启后仍然保留
- 主库重建或刷新时不会自动丢失
- 运行时会和主库候选一起合并排序

### 在输入法 UI 中加入用户词库

1. 启动输入法
2. 在输入框中放入一个汉字词语，例如 `日本`
3. 右键输入框，选择 `加入用户词库`
4. 按提示输入：
   - 数字标调拼音，例如 `ri4 ben3`
   - 标准拼音，例如 `rì běn`，可留空
   - 词内拼音必须按音节用空格分开，例如 `duo1 ri4` 或 `duō rì`；不要写成 `duo1ri4` 或 `duōrì`
5. 写入成功后，状态栏会显示：

```text
已加入用户词库: 日本 | rì běn / ri4 ben3 | <音元编码>
```

如果该词原来已经在用户词库中，则会显示：

```text
已更新用户词库: 日本 | rì běn / ri4 ben3 | <音元编码>
```

补充说明：

- 当前 UI 入口只支持“当前输入框中的汉字词语”
- 当前最小实现主要支持词语，不是单字专用用户库界面
- 如果数字标调拼音无法自动推导出音元编码，写入会被拒绝
- 如果第一栏没有按音节加空格，系统可能无法识别为合法拼音并拒绝写入

### 用命令行直接加入用户词库

如果你更喜欢脚本方式，可直接执行：

```bash
python tools/add_user_phrase.py 日本 "ri4 ben3" --marked-pinyin "rì běn"
python tools/add_user_phrase.py 今日 "jin1 ri4" --marked-pinyin "jīn rì"
```

如果你已经知道编码，也可以手工指定：

```bash
python tools/add_user_phrase.py 日本 "ri4 ben3" --marked-pinyin "rì běn" --yime-code "<音元编码>"
```

当前脚本会把词条写入 `user_lexicon.db`，并打印：

- 用户库路径
- 词语
- 数字标调拼音
- 标准拼音
- 音元编码
- 本次状态

## 3. 维护、备份与迁移用户词库

当前仓库已经提供一个专门的维护脚本：`python tools/manage_user_lexicon.py ...`

### 查看最近加入或更新的词条

```bash
python tools/manage_user_lexicon.py list-recent --limit 20
```

适合快速确认最近补了哪些词，或检查某次导入后有没有写进去。

### 导出当前用户词库备份

```bash
python tools/manage_user_lexicon.py export backups/user_lexicon_backup.json
```

如果你只想导出词条，不想带上个人调序频率，可用：

```bash
python tools/manage_user_lexicon.py export backups/user_lexicon_seed.json --no-frequency
```

这条形式也正好适合生成可分发的 `seed 用户词库`。

### 导入用户词库备份

```bash
python tools/manage_user_lexicon.py import backups/user_lexicon_backup.json
```

如果要先清空当前用户词库，再用备份完整覆盖：

```bash
python tools/manage_user_lexicon.py import backups/user_lexicon_backup.json --replace-existing
```

如果只想导入词条，不恢复旧机器上的调序频率：

```bash
python tools/manage_user_lexicon.py import backups/user_lexicon_backup.json --no-frequency
```

### 显式创建空用户词库文件

```bash
python tools/manage_user_lexicon.py init-db
```

如果你要给安装包或目标机器预先放一个空库，也可以指定路径：

```bash
python tools/manage_user_lexicon.py init-db --db-path path/to/user_lexicon.db
```

这条命令会确保 SQLite 文件已经创建好，即使里面还没有任何用户词条。

## 4. 调序诊断工具

如果你想知道“为什么这个词排到前面”，而不是只看 `freq`，可以直接用：

```bash
python tools/diagnose_candidate_order.py --numeric-pinyin "ri4 ben3" --limit 10
```

它会输出：

- 当前 `lookup_code`
- 原始候选数和去重排序后的候选数
- 每个候选的 `entry_type`
- `sort_weight`
- `user_freq`
- 最终参与排序的 `sort_key`

如果你已经知道规范码，也可以直接按码诊断：

```bash
python tools/diagnose_candidate_order.py --canonical-code "<规范码>" --limit 10
```

这比单看 `query_phrase_code.py` 更适合排查“候选顺序为什么这样排”。

## 5. seed 用户词库流程

如果你要做安装包，想让目标机器第一次启动时就带一份初始化用户词库，可以按下面的约定：

1. 在打包机上先准备好一份可分发词库：

```bash
python tools/manage_user_lexicon.py export yime/user_lexicon_seed.json --no-frequency
```

1. 打包时把这个 `yime/user_lexicon_seed.json` 一起带上。
2. 不要同时把开发机正在使用的 `yime/user_lexicon.db` 原样塞进安装包。
3. 目标机器首次启动 `python run_input_method.py` 时，如果当前用户词库为空且还没有导入过 seed，程序会自动创建用户词库并导入这份 seed 文件。
4. 导入完成后，目标机器后续新增的词和调序频率都继续写进它自己的 `yime/user_lexicon.db`，不再回写 seed 文件。

仓库中也提供了一个最小示例文件：`yime/user_lexicon_seed.json`，可直接作为打包参考。

如果你想在发安装包前做一次“首次启动自动落 seed”的自验，可直接运行：

```bash
python tools/verify_seed_install_flow.py
```

这条脚本会在临时目录里模拟三种安装侧场景：

- 安装目录里还没有 `user_lexicon.db`，首次启动自动导入 seed
- 安装目录里已经有一个空的 `user_lexicon.db`，首次启动仍然自动导入 seed
- 第二次启动时不重复导入 seed

这样可以把“初始化推荐词条”和“用户后续私有数据”分开管理。

补充说明：

- 即使安装包里已经预先放了一个空的 `yime/user_lexicon.db`，只要这个库里还没有用户数据，也仍然会自动导入 seed。
- 如果目标机器已经有自己的用户词条或调序频率，自动 seed 导入会跳过，不会覆盖现有内容。

## 6. 用户词频为什么会长期调序

当前实现不只是“把词存进去”，还会把用户的选词频率持久写入用户库。

也就是说：

1. 你把词加入用户词库后，它已经能参与候选
2. 你后续反复选择它时，系统会把对应 `lookup_code + text` 的频率写入用户库
3. 下次重启时，decoder 会重新加载这份频率
4. 所以候选顺序会长期保留，而不是只在本次运行内有效

你可以用下面的命令观察：

```bash
python tools/query_phrase_code.py 日本
```

如果 `User 词语编码` 里看到：

```text
freq=3
```

通常就说明这个词最近被你持续选中过，因此它排前并不是偶然。

## 7. 当前边界

当前这套最小实现的边界是：

- 主要支持词语用户库，不是完整的单字用户库编辑器
- 反查默认显示首选拼音和编码，不展示全部多音候选
- `query_phrase_code.py` 主要用于检查“有没有、编码是什么、频率是多少”，不是交互式维护工具
- 用户词频目前按 `(lookup_code, text)` 维度持久化

如果后面继续扩展，最自然的方向通常有两个：

1. 给用户词库加删除、修改和列表管理入口
2. 把用户词频也纳入更明确的可视化诊断输出
