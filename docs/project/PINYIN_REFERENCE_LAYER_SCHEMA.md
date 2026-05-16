# 拼音资料层 Schema

## 结论

当前仓库的资料层规范表为 `多式拼音映射关系`。

原因：

- 这张表的真实定位更接近“资料层 / 对照层 / 反查层”，用于保存多种拼音表示法之间的关系，而不是输入法运行时的最小真源。
- `多式拼音映射关系` 比 `各式拼音映射关系` 更像一个数据库对象名，也更准确地表达“多种表示法之间的映射”。

当前建议分层如下：

- runtime 主线层：继续使用 `pinyin_yime_code`、`mapping_yime_code`、`音元拼音` 等窄表。
- 资料层：使用 `多式拼音映射关系` 及其配套表，承载数字调拼音、标准拼音、音元拼音、注音、国际音标、历史拼写等多制式关系。

## 推荐版设计

推荐不要只把旧表重命名，而是顺手拆成三层：

1. `拼音表示法`
2. `拼音形式项`
3. `多式拼音映射关系`

这样资料层就不再是“仿 JSON 的大字典表”，而是可扩展、可加元数据、可审计的关系模型。

### 1. 拼音表示法

用于定义“这是哪一种系统”。

建议字段：

```sql
CREATE TABLE IF NOT EXISTS "拼音表示法" (
    "表示法编号" INTEGER PRIMARY KEY AUTOINCREMENT,
    "表示法名称" TEXT NOT NULL UNIQUE,
    "表示法标识" TEXT NOT NULL UNIQUE,
    "书写系统" TEXT,
    "是否运行时主线" INTEGER NOT NULL DEFAULT 0 CHECK ("是否运行时主线" IN (0, 1)),
    "备注" TEXT,
    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

建议样例：

- 数字标调拼音 / numeric_pinyin
- 标准拼音 / hanyu_pinyin
- 音元拼音 / yinyuan_pinyin
- 注音符号 / bopomofo
- 国际音标 / ipa
- 历史拼写 / historical_pinyin

### 2. 拼音形式项

用于定义“某个系统里的某个具体形式”。

建议字段：

```sql
CREATE TABLE IF NOT EXISTS "拼音形式项" (
    "形式编号" INTEGER PRIMARY KEY AUTOINCREMENT,
    "表示法编号" INTEGER NOT NULL REFERENCES "拼音表示法"("表示法编号") ON DELETE CASCADE,
    "形式值" TEXT NOT NULL,
    "规范值" TEXT,
    "声调信息" TEXT,
    "时期标签" TEXT,
    "数据来源" TEXT,
    "备注" TEXT,
    "最近更新" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE ("表示法编号", "形式值")
);
```

说明：

- `形式值`：原始可见字符串，比如 `a1`、`ㄓㄨ`、`t͡ʂu˥`。
- `规范值`：若有需要，可存标准化结果。
- `时期标签`：用于历史资料，比如“上古拟音”“中古音”“近代注音”。

### 3. 多式拼音映射关系

这是资料层的核心关系表，用来表示“形式 A 与形式 B 存在何种关系”。

建议字段：

```sql
CREATE TABLE IF NOT EXISTS "多式拼音映射关系" (
    "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
    "原形式编号" INTEGER NOT NULL REFERENCES "拼音形式项"("形式编号") ON DELETE CASCADE,
    "目标形式编号" INTEGER NOT NULL REFERENCES "拼音形式项"("形式编号") ON DELETE CASCADE,
    "关系类型" TEXT NOT NULL,
    "是否可逆" INTEGER NOT NULL DEFAULT 1 CHECK ("是否可逆" IN (0, 1)),
    "置信度" REAL,
    "数据来源" TEXT,
    "版本号" TEXT,
    "时期标签" TEXT,
    "备注" TEXT,
    "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE ("原形式编号", "目标形式编号", "关系类型", "数据来源")
);
```

`关系类型` 建议枚举示例：

- 对应
- 近似对应
- 历史来源
- 反查候选
- 音值对齐
- 书写变体

这样以后你不止能做“数字调 -> 音元”这种单一映射，也能做：

- 标准拼音 -> 注音符号
- 标准拼音 -> 国际音标
- 历史拼写 -> 现代标准拼音
- 音元拼音 -> 数字调拼音

## 最小迁移版

当前已落地的最小可行方案是：

1. 使用 `多式拼音映射关系` 作为资料层核心表
2. 保留原有列结构
3. 额外补两个字段：`关系类型`、`时期标签`

建议最小版结构：

```sql
CREATE TABLE IF NOT EXISTS "多式拼音映射关系" (
    "映射编号" INTEGER PRIMARY KEY AUTOINCREMENT,
    "原拼音类型" TEXT NOT NULL,
    "原拼音" TEXT NOT NULL,
    "目标拼音类型" TEXT NOT NULL,
    "目标拼音" TEXT NOT NULL,
    "关系类型" TEXT NOT NULL DEFAULT '对应',
    "时期标签" TEXT,
    "数据来源" TEXT,
    "版本号" TEXT,
    "备注" TEXT,
    "创建时间" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE("原拼音类型", "原拼音", "目标拼音类型", "目标拼音", "关系类型", "数据来源")
);
```

这个版本的优点：

- 迁移成本低
- 现有导入逻辑最容易改
- 足够先把“资料层”语义立住

缺点：

- 仍然会有字符串重复
- 不如推荐版适合长期扩展到历史注音和音标资料

## 与当前主线的边界

无论采用推荐版还是最小迁移版，都建议明确下面这条边界：

- `多式拼音映射关系` 是资料层，不是 runtime 主线真源。
- runtime 主线仍然应从更窄、更可重建的表读取：

  - `pinyin_yime_code`
  - `mapping_yime_code`
  - `音元拼音`

换句话说：

- 资料层负责“看全貌、做反查、做人工校对、存历史资料”。
- 主线层负责“高效、稳定、可重建地支撑输入法运行”。

## 演进建议

建议后续按下面顺序继续演进：

1. 保持代码和 schema 只使用 `多式拼音映射关系` 这一规范名。
2. 若需要更多元数据，再决定是否从“最小迁移版”升级到“推荐版”三表结构。
3. 在整个过程中，不要让 runtime 主线重新依赖这张资料层表。

## 当前仓库的着手点

如果开始落地，最先需要看的文件是：

- `yime/legacy/pending_removal/db_manager.py`
  - 当前隔离后的 legacy schema 定义入口
- `yime/utils/legacy_pinyin_tables/Initialize_pinyin_mapping.py`
  - 三表生成链的初始化脚本，现已只建并写入 `多式拼音映射关系`
- `yime/utils/legacy_pinyin_tables/split_numeric_pinyin.py`
  - 数字标调拼音导入逻辑，现已只把 `多式拼音映射关系` 作为资料层来源

下一步重点是评估是否把当前最小版进一步提升为推荐版三表结构。
