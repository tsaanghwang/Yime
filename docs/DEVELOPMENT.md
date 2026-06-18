# 开发者指南

## 快速开始

### 环境要求

- **Python**: 3.12.x（Windows 输入法主线）
- **SQLite**: 3.35+
- **Git**

### 安装步骤

#### 1. 克隆仓库

```bash
git clone https://github.com/tsaanghwang/Yime.git
cd Yime
```

#### 2. 安装 Python 依赖

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

#### 3. 数据与运行时

prototype schema 由导入脚本应用，不再使用 `run_db_setup`。见 `docs/project/PINYIN_DATA_MIGRATION.md`。

#### 4. 运行测试

```bash
scripts/run_tests.cmd
```

或：

```bash
pytest
```

---

## 项目结构

```text
YIME/
├── yime/                 # Python 核心引擎
│   ├── syllable_decoder.py    # SyllableDecoder 旧 import 路径（继承 syllable.codec.YinjieDecoder）
│   ├── import_danzi_into_prototype_tables.py  # 兼容入口；真实实现位于 yime/utils/prototype_single_char_import.py
│   ├── import_duozi_into_prototype_tables.py  # 兼容入口；真实实现位于 yime/utils/prototype_phrase_import.py
│   ├── refresh_runtime_yime_codes.py          # 兼容 shim；真实实现位于 yime/utils/runtime_codes_refresh.py
│   └── utils/                # 导入、runtime 刷新等实现
│
├── tools/                # 维护脚本（含 BCC 频表 merge）
├── syllable/             # 音节分析、编解码（Yinjie 真源见 syllable/codec/yinjie.py）
├── docs/                 # 文档
├── tests/                # 测试
├── requirements.txt
└── README.md
```

### 兼容入口约定

- 根目录兼容入口的真实实现应下沉到 `yime/utils/`。
- shim 应尽量显式导出 `__all__`。
- `tools/` 下 orchestration 脚本优先显式 `validate_*` 预检；键盘布局外置仓库路径用 `YIME_KEYBOARD_LAYOUT_REPO`。

补充：旧 JS 原型已外置；本仓库主线为 `yime/` 下 Windows IME Python 实现。拼音 rebuild 见 `docs/project/PINYIN_DATA_MIGRATION.md`。

---

## 开发工作流

### 1. 创建功能分支

```bash
git checkout -b feature/your-feature-name
```

### 2. 编写代码

遵循以下原则：

- 保持代码简洁清晰
- 添加必要的注释
- 遵循 PEP 8
- 编写单元测试

### 3. 运行测试

```bash
scripts/run_tests.cmd
```

### 4. 提交代码

```bash
git add .
git commit -m "feat: 添加新功能描述"
git push origin feature/your-feature-name
```

### 6. 创建 Pull Request

在 GitHub 上创建 Pull Request，填写：

- 功能描述
- 测试结果
- 相关 Issue

### 7. 重建当前编码产物

当你修改了音节切分、首音/干音编码规则，或者希望让 `run_input_method.py` 使用最新编码表时，先重建运行时编码产物，再启动输入法。

推荐直接使用仓库内的一键入口：

```bash
python tools/rebuild_encoding_assets.py
```

如果你在 Windows 虚拟环境里工作，常用命令是：

```bash
.venv\Scripts\python.exe tools\rebuild_encoding_assets.py
```

如果你是在 Git Bash 里执行，同一条命令请改用正斜杠：

```bash
.venv/Scripts/python.exe tools/rebuild_encoding_assets.py
```

这个入口当前会顺序重建（完整清单见 [syllable/README.md](../syllable/README.md)）：

- `syllable/yinyuan/shouyin_codepoint.json`
- `syllable/yinyuan/yinyuan_codepoint.json`
- `internal_data/yinyuan_derived/ganyin_to_yinyuan_sequence.json`
- `syllable/yinyuan/ganyin_to_fixed_length_yinyuan_sequence.json`
- `syllable/codec/yinjie_code.json`
- `yime/code_pinyin.json`

如果这次只想刷新输入法主用编码表，不想反向重建 `yime/code_pinyin.json`，可以执行：

```bash
python tools/rebuild_encoding_assets.py --skip-code-pinyin
```

Git Bash 下对应写法：

```bash
.venv/Scripts/python.exe tools/rebuild_encoding_assets.py --skip-code-pinyin
```

注意：`python run_input_method.py` 本身不会自动重建这些产物；它只会读取现成的 `syllable/codec/yinjie_code.json` 和相关运行时 JSON。所以规则改完但没先执行重建时，启动输入法不会自动带出新编码。

建议配套做一次最小验证：

```bash
python -m pytest tests/syllable_analysis/test_encode_ganyin.py tests/yinjie/test_yinjie_encoder.py
```

---

## 核心概念

### 1. 音元系统

音元系统是 YIME 的理论基础，包含 52 个音元：

- **噪音**（22个）：充当首音
- **乐音**（30个）：构成干音

### 2. 音节结构

```text
音节 = 首音 + 干音
干音 = 呼音 + 韵音
韵音 = 主音 + 末音
```

### 3. 转换流程

当前 rebuild 链（详见 `docs/project/PINYIN_DATA_MIGRATION.md`）：

```text
上游文本 → source_pinyin.db → prototype tables → runtime_candidates（SQLite）
```

---

## 添加新功能

旧 `pinyin/yunmu_to_keys` 规则插件链已随根目录 `legacy/` 移除。当前请在对应现行模块旁添加测试；音节编码与词库相关改动优先跑：

```bash
scripts/run_tests.cmd
pytest tests/yinjie/ -k your_case
```

---

## 数据库操作

### 1. 查看数据库结构

```bash
sqlite3 yime/pinyin_hanzi.db
.tables
.schema runtime_candidates
```

当前主线表结构见 `yime/create_prototype_schema_additions.sql`。查运行时候选：

```sql
SELECT entry_type, text, yime_code, sort_weight
FROM runtime_candidates
LIMIT 10;
```

如果需要快速理解当前 `yime/pinyin_hanzi.db` 中各类表的职责分层，参见 `docs/PINYIN_HANZI_DB_DOMAINS.md`。

### 2. 添加新表

当前主线 rebuild/runtime 链应修改：

- `yime/create_prototype_schema_additions.sql`
- `yime/import_danzi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_single_char_import.py`）
- `yime/import_duozi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_phrase_import.py`）
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）

prototype 表结构示例见 `yime/create_prototype_schema_additions.sql`。

### 3. 数据迁移

Schema 变更应直接修改 `create_prototype_schema_additions.sql` 并重建/迁移本地 `yime/pinyin_hanzi.db`；旧 `db_manager` 中文表迁移链已删除。

---

## 性能优化

### 1. Python 性能优化

#### 使用缓存

```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def expensive_function(param):
    # 耗时操作
    return result
```

#### 批量处理

```python
# 推荐：批量插入
cursor.executemany('INSERT INTO table VALUES (?, ?)', data_list)

# 不推荐：逐个插入
for data in data_list:
    cursor.execute('INSERT INTO table VALUES (?, ?)', data)
```

### 2. 数据库优化

#### 创建索引

```sql
CREATE INDEX idx_char_yime_code ON char_lexicon(yime_code);
CREATE INDEX idx_char_frequency ON char_inventory(char_frequency_abs DESC);
```

#### 查询优化

```python
# 使用参数化查询
cursor.execute('SELECT * FROM table WHERE field = ?', (value,))

# 避免 SELECT *
cursor.execute('SELECT field1, field2 FROM table')
```

---

## 调试技巧

### 1. Python 调试

```python
import logging

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

logger.debug("调试信息")
logger.info("一般信息")
logger.warning("警告信息")
logger.error("错误信息")
```

### 2. 数据库调试

```python
# 启用 SQL 日志
import sqlite3
sqlite3.enable_callback_tracebacks(True)

# 查看查询计划
cursor.execute('EXPLAIN QUERY PLAN SELECT * FROM table')
print(cursor.fetchall())
```

---

## 测试指南

### 1. 单元测试

```python
import unittest

class TestMyFunction(unittest.TestCase):
    def setUp(self):
        # 测试前准备
        pass

    def tearDown(self):
        # 测试后清理
        pass

    def test_function(self):
        result = my_function(input)
        self.assertEqual(result, expected)
```

### 2. 集成测试

```python
def test_integration(self):
    # 测试多个模块协作
    result1 = module1.function()
    result2 = module2.function(result1)
    self.assertEqual(result2, expected)
```

### 3. 性能测试

```python
import time

def test_performance(self):
    start = time.time()
    # 执行操作
    end = time.time()
    self.assertLess(end - start, 1.0)  # 应在1秒内完成
```

---

## 发布流程

### 1. 版本号管理

遵循语义化版本：

- MAJOR.MINOR.PATCH
- 例如：1.0.0 → 1.0.1（修复）→ 1.1.0（新功能）→ 2.0.0（重大变更）

### 2. 更新 CHANGELOG

```markdown
## [1.1.0] - 2026-04-11
### Added
- 新功能描述

### Fixed
- 修复描述

### Changed
- 变更描述
```

### 3. 创建发布

```bash
# 创建标签
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0

# 构建发布包
python -m build
```

---

## 常见问题

### Q: 如何添加新的拼音映射？

A: 当前主线通过 `source_pinyin.db` 与 prototype 导入链维护；见 `docs/project/PINYIN_DATA_MIGRATION.md`。

### Q: 如何优化转换性能？

A: 使用批量处理和缓存：

```python
# 批量转换
yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}
result = converter.convert(yunmu_dict)

# 使用缓存
@lru_cache(maxsize=1000)
def cached_convert(yunmu):
    return converter.convert({yunmu: ""})
```

### Q: 如何调试数据库问题？

A: 启用 SQL 日志并检查查询计划：

```python
import sqlite3
sqlite3.enable_callback_tracebacks(True)

cursor.execute('EXPLAIN QUERY PLAN your_query')
print(cursor.fetchall())
```

---

## 资源链接

- [API 文档](API.md)
- [常见问题](FAQ.md)
- [安装说明](INSTALL.md)
- [使用说明](USAGE.md)
- [GitHub 仓库](https://github.com/tsaanghwang/YIME)
- [问题追踪](https://github.com/tsaanghwang/YIME/issues)

---

## 贡献指南

我们欢迎所有形式的贡献！

### 贡献方式

1. **报告问题**：在 GitHub Issues 中报告 bug
2. **建议功能**：在 GitHub Issues 中提出新功能建议
3. **提交代码**：创建 Pull Request
4. **完善文档**：改进文档和示例
5. **分享经验**：在 Discussions 中分享使用经验

### 代码规范

- Python: 遵循 PEP 8
- JavaScript/TypeScript: 遵循 ESLint 配置
- 提交信息: 遵循约定式提交

### 审核流程

1. 提交 Pull Request
2. 自动测试运行
3. 代码审核
4. 合并到主分支

---

## 许可证

本项目采用“非商用默认许可，商用需另行授权”的策略。

- 非商用使用请遵守 [LICENSE](../LICENSE) 中的约束。
- 商业使用请先阅读 [COMMERCIAL_LICENSE.md](../COMMERCIAL_LICENSE.md) 并联系作者获取单独授权。
