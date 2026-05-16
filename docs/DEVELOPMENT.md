# 开发者指南

## 快速开始

### 环境要求

- **Python**: 3.10 或更高版本
- **Node.js**: 16 或更高版本（前端开发）
- **SQLite**: 3.35 或更高版本
- **Git**: 用于版本控制

### 安装步骤

#### 1. 克隆仓库

```bash
git clone https://github.com/tsaanghwang/YIME.git
cd YIME
```

#### 2. 安装 Python 依赖

```bash
# 创建虚拟环境（推荐）
python -m venv venv
# 或
venv\Scripts\activate  # Windows

# 安装依赖
pip install -r requirements.txt
```

#### 3. 安装前端依赖

```bash
npm install
```

#### 4. 初始化数据库

```bash
python yime/run_db_setup.py
```

这条命令现在只是 legacy shim；真实兼容实现位于 `yime/legacy/pending_removal/run_db_setup.py`。

#### 5. 运行测试

```bash
# Python 测试
pytest

# 前端测试
npm test
```

---

## 项目结构

```text
YIME/
├── yime/                 # Python 核心引擎
│   ├── syllable_decoder.py    # legacy shim，公开兼容导入路径
│   ├── syllable_structure.py  # legacy shim，公开兼容导入路径
│   ├── import_danzi_into_prototype_tables.py  # 兼容入口；真实实现位于 yime/utils/prototype_single_char_import.py
│   ├── import_duozi_into_prototype_tables.py  # 兼容入口；真实实现位于 yime/utils/prototype_phrase_import.py
│   ├── refresh_runtime_yime_codes.py          # 兼容 shim；真实实现位于 yime/utils/runtime_codes_refresh.py
│   ├── utils/legacy_pinyin_tables/            # 保留的旧拼音参考表链与兼容实现
│   └── legacy/pending_removal/                # legacy-compatible 旧数据库接口归档
│       └── db_manager.py                      # 旧数据库管理入口
│
├── pinyin/               # 拼音处理模块
│   ├── yunmu_to_keys.py       # 韵母转换
│   ├── constants.py           # 常量定义
│   └── test/                  # 测试文件

### 兼容入口约定

当前仓库对主包根目录的兼容入口采用下面约定：

- 如果 `yime/` 根目录文件只为保留公开导入路径或历史脚本路径，则真实实现应下沉到 `yime/utils/`、`yime/utils/legacy_pinyin_tables/` 或 `yime/legacy/pending_removal/`。
- 这类根目录兼容入口应尽量显式导出 `__all__`；若需要动态透传整模块，才使用 `__getattr__` / `__dir__`。
- 仍保留脚本入口的 shim，应统一用 `raise SystemExit(main())`；若真实实现本身是 `None` 返回的应用入口，则 shim 只负责调用，不强行包成整数返回值。

对 `tools/` 下的 orchestration 脚本，当前也采用统一约定：

- 凡是会调用外部脚本、外部仓库或系统程序的入口，优先显式拆出 `validate_*` 预检函数。
- 如果外部键盘布局资产已迁到 `..\Yime-keyboard-layout`，默认路径应与 `YIME_KEYBOARD_LAYOUT_REPO` 环境变量保持一致，不再回退到主仓库旧 `releases/` 目录。
- `main()` 优先返回整型退出码，再由 `raise SystemExit(main())` 统一退出。
│
├── syllable/             # 音节分析模块
│   └── analysis/              # 音节分析工具
│
├── docs/                 # 文档
│   ├── API.md                 # API 文档
│   ├── DEVELOPMENT.md         # 开发者指南（本文件）
│   └── FAQ.md                 # 常见问题
│
├── tests/                # 测试文件
├── .github/workflows/    # CI/CD 配置
├── requirements.txt     # Python 依赖
└── README.md            # 项目说明
```

补充说明：旧的 JS / React 输入法原型链已经迁出主仓库，当前正式外置位置为单独的 `Yime-js-prototype` 仓库。
本仓库当前开发主线以 `yime/` 下的 Windows IME Python 实现为准。
拼音数据当前主线 rebuild 链请改看 `docs/project/PINYIN_DATA_MIGRATION.md`，不要再把 `db_manager.py` 视为默认入口；`hanzi_db_manager.py` 已退场。

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
- 遵循 PEP 8（Python）或 ESLint（JavaScript）规范
- 编写单元测试

### 3. 运行测试

```bash
# 运行所有测试
pytest

# 运行特定测试
python -m unittest tests.test_pinyin_zhuyin

# 运行带覆盖率的测试
pytest --cov=yime --cov-report=html
```

### 4. 代码检查

```bash
# Python 代码格式化
black yime/ pinyin/ syllable/

# Python 代码检查
flake8 yime/ pinyin/ syllable/

# 前端代码检查
npm run lint
```

### 5. 提交代码

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

这个入口当前会顺序重建：

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

```text
标准拼音 → 数字标调拼音 → 音元拼音 → 音元编码
```

---

## 添加新功能

### 示例：添加新的转换规则

#### 1. 定义规则

在 `pinyin/yunmu_to_keys.py` 中添加：

```python
new_rule = ConversionRule(
    condition=lambda k: k == "your_yunmu",
    action=lambda v: "converted_value",
    description="新规则描述",
    priority=10
)
```

#### 2. 添加到规则列表

```python
def _get_default_rules(self) -> List[ConversionRule]:
    rules = [
        # 现有规则...
        new_rule,
    ]
    return rules
```

#### 3. 编写测试

如果你只是维护已归档的旧 `pinyin` helper，可在 `legacy/pinyin_package/test/test_yunmu_to_keys.py` 中添加：

```python
def test_new_rule(self):
    """测试新规则"""
    result = self.converter.convert({"your_yunmu": ""})
    self.assertEqual(result["your_yunmu"], "converted_value")
```

#### 4. 运行测试

```bash
pytest legacy/pinyin_package/test/test_yunmu_to_keys.py::test_new_rule
```

---

## 数据库操作

### 1. 查看数据库结构

```bash
sqlite3 yime/pinyin_hanzi.db
.tables
.schema "音元拼音"
```

`音元拼音` 表的定位：

- 它是一个保留的音节结构表，不是当前 runtime 主线候选表。
- 它保存的是按音元分析法拆开的单音节结构结果，用来承载 `全拼 -> 简拼` 与 `全拼 -> 首音/干音/呼音/主音/末音/间音/韵音` 这两类结构信息。
- 其中 `全拼` 指完整音元编码；`简拼` 是在完整音节结构上做机械压缩得到的缩写结果，可作为后续简拼输入实验的基础层。
- `首音`、`干音`、`呼音`、`主音`、`末音`、`间音`、`韵音` 这些列用于从不同观察角度保留同一个音节的拆分结果，方便做结构分析、简拼规则验证与旧库排障。
- 当前运行时主线仍然是 `source_pinyin.db -> prototype tables -> refresh_runtime_yime_codes -> runtime_candidates`，不会直接读取这个表来出候选。

### 2. 添加新表

如果你是在维护 legacy-compatible 中文表结构，才在 `yime/legacy/pending_removal/db_manager.py` 中修改；
如果你是在维护当前主线 rebuild/runtime 链，应优先修改：

- `yime/create_prototype_schema_additions.sql`
- `yime/import_danzi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_single_char_import.py`）
- `yime/import_duozi_into_prototype_tables.py`（兼容入口；真实实现位于 `yime/utils/prototype_phrase_import.py`）
- `yime/refresh_runtime_yime_codes.py`（兼容入口；真实实现位于 `yime/utils/runtime_codes_refresh.py`）

legacy-compatible 表结构示例：

```python
表结构 = {
    '新表名': '''
        CREATE TABLE IF NOT EXISTS "新表名" (
            "编号" INTEGER PRIMARY KEY,
            "字段1" TEXT NOT NULL,
            "字段2" INTEGER
        )
    ''',
    # 其他表...
}
```

如果你维护的是 `音元拼音` 这张保留结构表，请优先把它理解为“结构分析与简拼基础层”，而不是当前 runtime 主线的编码真源。
真到需要给外部接口、跨语言工具或 ORM 提供更稳定命名时，再考虑在此表之上增加 ASCII 视图或别名层；当前仓库内逻辑仍以现有中文表名为准。

### 3. 数据迁移

创建迁移脚本：

注意：下面仅演示迁移脚本结构。旧的 legacy-compatible 迁移辅助脚本已从仓库移除，不属于当前主线 rebuild 流程，也不参与当前包构建与分发。

```python
# migration_001.py
import sqlite3

def upgrade(conn):
    cursor = conn.cursor()
    cursor.execute('ALTER TABLE "音元拼音" ADD COLUMN "新字段" TEXT')
    conn.commit()

def downgrade(conn):
    cursor = conn.cursor()
    # SQLite 不支持 DROP COLUMN，需要重建表
    pass
```

---

## 前端开发

### 1. 启动开发服务器

```bash
npm run dev
```

### 2. 添加新组件

创建 `src/components/NewComponent.tsx`：

```typescript
import React from 'react';

interface NewComponentProps {
  title: string;
}

export const NewComponent: React.FC<NewComponentProps> = ({ title }) => {
  return (
    <div className="new-component">
      <h2>{title}</h2>
    </div>
  );
};
```

### 3. 添加组件测试

创建 `src/components/NewComponent.test.tsx`：

```typescript
import { render, screen } from '@testing-library/react';
import { NewComponent } from './NewComponent';

describe('NewComponent', () => {
  test('renders title', () => {
    render(<NewComponent title="Test" />);
    expect(screen.getByText('Test')).toBeInTheDocument();
  });
});
```

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
CREATE INDEX idx_pinyin ON "音元拼音"("全拼");
CREATE INDEX idx_char_frequency ON char_inventory(char_frequency_abs DESC);
```

#### 查询优化

```python
# 使用参数化查询
cursor.execute('SELECT * FROM table WHERE field = ?', (value,))

# 避免 SELECT *
cursor.execute('SELECT field1, field2 FROM table')
```

### 3. 前端性能优化

#### 使用 React.memo

```typescript
const MyComponent = React.memo(({ data }) => {
  return <div>{data}</div>;
});
```

#### 懒加载

```typescript
const LazyComponent = React.lazy(() => import('./LazyComponent'));
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

### 3. 前端调试

```typescript
// 使用 React DevTools
// 使用 console.log
console.log('Debug info:', data);

// 使用 debugger
debugger;
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

A: 当前主线不要再直接维护旧短表名映射接口。
如果你是在维护资料层拼音对照，请修改 `pinyin_yime_code` 来源并重跑：

```python
from yime.utils.legacy_pinyin_tables.Initialize_pinyin_mapping import rebuild_mappings_from_db

count = rebuild_mappings_from_db()
print(count)
```

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

本项目采用 MIT 许可证。详见 [LICENSE](../LICENSE) 文件。
