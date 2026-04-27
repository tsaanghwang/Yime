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
source venv/bin/activate  # Linux/Mac
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

#### 5. 运行测试

```bash
# Python 测试
pytest

# 前端测试
npm test
```

---

## 项目结构

```
YIME/
├── yime/                 # Python 核心引擎
│   ├── pinyin_converter.py    # 拼音转换器
│   ├── syllable_decoder.py    # 音节解码器
│   ├── syllable_structure.py  # 音节结构
│   ├── db_manager.py          # 数据库管理
│   ├── pinyin_db_manager.py   # 拼音数据库管理
│   └── hanzi_db_manager.py    # 汉字数据库管理
│
├── pinyin/               # 拼音处理模块
│   ├── yunmu_to_keys.py       # 韵母转换
│   ├── constants.py           # 常量定义
│   └── test/                  # 测试文件
│
├── syllable/             # 音节分析模块
│   └── analysis/              # 音节分析工具
│
├── src/                  # React 前端
│   ├── App.tsx                # 主应用
│   ├── components/            # React 组件
│   ├── core/                  # 核心功能
│   └── services/              # 服务层
│
├── docs/                 # 文档
│   ├── API.md                 # API 文档
│   ├── DEVELOPMENT.md         # 开发者指南（本文件）
│   └── FAQ.md                 # 常见问题
│
├── tests/                # 测试文件
├── .github/workflows/    # CI/CD 配置
├── requirements.txt     # Python 依赖
├── package.json         # Node.js 依赖
└── README.md            # 项目说明
```

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
pytest yime/test_pinyin_converter.py

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

---

## 核心概念

### 1. 音元系统

音元系统是 YIME 的理论基础，包含 52 个音元：
- **噪音**（22个）：充当首音
- **乐音**（30个）：构成干音

### 2. 音节结构

```
音节 = 首音 + 干音
干音 = 呼音 + 韵音
韵音 = 主音 + 末音
```

### 3. 转换流程

```
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

在 `pinyin/test/test_yunmu_to_keys.py` 中添加：

```python
def test_new_rule(self):
    """测试新规则"""
    result = self.converter.convert({"your_yunmu": ""})
    self.assertEqual(result["your_yunmu"], "converted_value")
```

#### 4. 运行测试

```bash
pytest pinyin/test/test_yunmu_to_keys.py::test_new_rule
```

---

## 数据库操作

### 1. 查看数据库结构

```bash
sqlite3 yime/pinyin_hanzi.db
.tables
.schema "音元拼音"
```

### 2. 添加新表

在 `yime/db_manager.py` 中：

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

### 3. 数据迁移

创建迁移脚本：

```python
# yime/migrations/migration_001.py
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
CREATE INDEX idx_frequency ON "汉字频率"("绝对频率" DESC);
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

A: 使用 `PinyinMapper` 类：

```python
from yime.pinyin_mapping import PinyinMapper

mapper = PinyinMapper()
mapper.add_mapping("pinyin1", "yinyuan1")
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
