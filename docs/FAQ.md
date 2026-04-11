# 常见问题解答 (FAQ)

## 目录

- [安装与配置](#安装与配置)
- [使用问题](#使用问题)
- [技术问题](#技术问题)
- [性能问题](#性能问题)
- [开发问题](#开发问题)
- [错误排查](#错误排查)

---

## 安装与配置

### Q1: 系统要求是什么？

**A**: YIME 支持以下系统环境：

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Python | 3.10 | 3.12+ |
| Node.js | 16 | 18+ |
| SQLite | 3.35 | 3.40+ |
| 操作系统 | Windows 10, macOS 10.15, Ubuntu 20.04 | 最新版本 |

---

### Q2: 如何安装 YIME？

**A**: 按照以下步骤安装：

```bash
# 1. 克隆仓库
git clone https://github.com/tsaanghwang/YIME.git
cd YIME

# 2. 安装 Python 依赖
pip install -r requirements.txt

# 3. 安装前端依赖
npm install

# 4. 初始化数据库
python yime/run_db_setup.py
```

---

### Q3: 安装时出现依赖冲突怎么办？

**A**: 建议使用虚拟环境：

```bash
# 创建虚拟环境
python -m venv venv

# 激活虚拟环境
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows

# 安装依赖
pip install -r requirements.txt
```

---

### Q4: 如何验证安装成功？

**A**: 运行测试验证：

```bash
# 运行 Python 测试
pytest

# 运行前端测试
npm test

# 检查数据库
python -c "import sqlite3; conn = sqlite3.connect('yime/pinyin_hanzi.db'); print('数据库正常')"
```

---

## 使用问题

### Q5: YIME 是什么？

**A**: YIME（音元输入法编辑器）是一个基于音元理论的汉语拼音输入法系统，特点：

- **52音元系统**：22个噪音 + 30个乐音
- **高效转换**：标准拼音 → 音元编码
- **智能候选**：基于频率和上下文的候选词排序
- **多平台支持**：Python 后端 + React 前端

---

### Q6: 如何使用 YIME 进行拼音转换？

**A**: 使用核心 API：

```python
from pinyin.yunmu_to_keys import YunmuConverter
from pinyin.constants import YunmuConstants

# 创建转换器
converter = YunmuConverter()
constants = YunmuConstants()

# 准备韵母字典
yunmu_dict = {yunmu: "" for yunmu in constants.REQUIRED_FINALS}

# 执行转换
result = converter.convert(yunmu_dict)

# 查看结果
print(result["ao"])   # 输出: au
print(result["ü"])    # 输出: v
```

---

### Q7: 支持哪些拼音格式？

**A**: YIME 支持多种拼音格式：

| 格式 | 示例 | 说明 |
|------|------|------|
| 标准拼音 | zhōng | 带声调符号 |
| 数字标调 | zhong1 | 数字表示声调 |
| 音元拼音 | zhong | 音元编码 |

---

### Q8: 如何添加自定义词汇？

**A**: 使用字典树 API：

```python
from yime.dictionary_trie import DictionaryTrie

trie = DictionaryTrie()

# 添加词汇
trie.insert("自定义词", {"frequency": 100})

# 查询词汇
if trie.search("自定义词"):
    print("词汇已添加")
```

---

### Q9: 如何查看转换统计信息？

**A**: 使用统计 API：

```python
converter = YunmuConverter()
result = converter.convert(yunmu_dict)

# 获取统计信息
stats = converter.get_stats()
print(f"成功率: {stats['success_rate']:.2f}%")
print(f"总转换数: {stats['total_conversions']}")
```

---

## 技术问题

### Q10: 什么是音元系统？

**A**: 音元系统是 YIME 的理论基础：

**音元分类**：
- **噪音**（22个）：充当首音，如 b, p, m, f, d, t, n, l, g, k, h, zh, ch, sh, r, z, c, s, j, q, x, y
- **乐音**（30个）：构成干音，如 a, o, e, i, u, ü 等

**音节结构**：
```
音节 = 首音 + 干音
干音 = 呼音 + 韵音
韵音 = 主音 + 末音
```

---

### Q11: 转换算法是如何工作的？

**A**: 转换流程：

1. **输入验证**：检查拼音格式
2. **规则匹配**：应用转换规则
3. **编码生成**：生成音元编码
4. **结果验证**：确保编码有效

**转换规则优先级**：
1. 舌尖元音替换（-i → ir）
2. ao 韵母转换（ao → au）
3. ü 元音替换（ü → v）
4. 其他规则...

---

### Q12: 数据库结构是怎样的？

**A**: 主要数据表：

| 表名 | 说明 | 主要字段 |
|------|------|---------|
| 音元拼音 | 音元拼音数据 | 编号, 全拼, 简拼, 首音, 干音 |
| 数字标调拼音 | 数字标调拼音 | 编号, 全拼, 声母, 韵母, 声调 |
| 拼音映射 | 拼音映射关系 | 音元拼音, 数字标调拼音, 标准拼音 |
| 汉字 | 汉字数据 | 编号, 字符, Unicode码点, 画数 |
| 词汇 | 词汇数据 | 编号, 词汇, 频率 |

---

### Q13: 如何理解音节结构？

**A**: 音节结构示例：

```python
from yime.syllable_structure import SyllableStructure

# 创建音节
syllable = SyllableStructure(
    initial="zh",    # 首音
    ascender="o",    # 呼音
    peak="n",        # 主音
    descender="g"    # 末音
)

# 查看属性
print(syllable.ganyin)  # 干音: ong
print(syllable.rime)    # 韵音: {'ascender': 'o', 'peak': 'n', 'descender': 'g'}
```

---

## 性能问题

### Q14: 如何优化转换性能？

**A**: 性能优化建议：

**1. 批量处理**：
```python
# 推荐：批量转换
yunmu_dict = {k: "" for k in constants.REQUIRED_FINALS}
result = converter.convert(yunmu_dict)

# 不推荐：逐个转换
for yunmu in constants.REQUIRED_FINALS:
    result = converter.convert({yunmu: ""})
```

**2. 使用缓存**：
```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def cached_convert(yunmu):
    return converter.convert({yunmu: ""})
```

**3. 数据库优化**：
```sql
-- 创建索引
CREATE INDEX idx_pinyin ON "音元拼音"("全拼");
CREATE INDEX idx_frequency ON "汉字频率"("绝对频率" DESC);
```

---

### Q15: 处理大量数据时性能下降怎么办？

**A**: 优化策略：

**1. 分批处理**：
```python
batch_size = 1000
for i in range(0, len(data), batch_size):
    batch = data[i:i+batch_size]
    process_batch(batch)
```

**2. 使用字典树**：
```python
trie = DictionaryTrie()
for word, data in word_list:
    trie.insert(word, data)

# 高效前缀查找
results = trie.get_all_with_prefix("prefix")
```

**3. 数据库批量操作**：
```python
cursor.executemany('INSERT INTO table VALUES (?, ?)', data_list)
```

---

### Q16: 内存占用过高怎么办？

**A**: 内存优化：

**1. 使用生成器**：
```python
def generate_data():
    for item in large_dataset:
        yield process(item)

for result in generate_data():
    save(result)
```

**2. 及时释放资源**：
```python
with 数据库管理器(db_path) as conn:
    # 操作数据库
    pass  # 自动关闭连接
```

**3. 限制缓存大小**：
```python
@lru_cache(maxsize=100)  # 限制缓存大小
def cached_function(param):
    return expensive_operation(param)
```

---

## 开发问题

### Q17: 如何运行测试？

**A**: 运行测试：

```bash
# 运行所有测试
pytest

# 运行特定测试文件
pytest yime/test_pinyin_converter.py

# 运行特定测试
pytest yime/test_pinyin_converter.py::TestPinyinConverter::test_convert_all

# 运行带覆盖率的测试
pytest --cov=yime --cov-report=html
```

---

### Q18: 如何添加新的转换规则？

**A**: 添加规则步骤：

**1. 定义规则**：
```python
from pinyin.yunmu_to_keys import ConversionRule

new_rule = ConversionRule(
    condition=lambda k: k == "your_yunmu",
    action=lambda v: "converted_value",
    description="新规则描述",
    priority=10
)
```

**2. 添加到规则列表**：
```python
def _get_default_rules(self) -> List[ConversionRule]:
    rules = [
        # 现有规则...
        new_rule,
    ]
    return rules
```

**3. 编写测试**：
```python
def test_new_rule(self):
    result = self.converter.convert({"your_yunmu": ""})
    self.assertEqual(result["your_yunmu"], "converted_value")
```

---

### Q19: 如何调试代码？

**A**: 调试方法：

**1. 使用日志**：
```python
import logging

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

logger.debug("调试信息")
logger.info("一般信息")
logger.error("错误信息")
```

**2. 使用断点**：
```python
import pdb; pdb.set_trace()  # Python 3.6及以下
breakpoint()  # Python 3.7+
```

**3. 数据库调试**：
```python
import sqlite3
sqlite3.enable_callback_tracebacks(True)

cursor.execute('EXPLAIN QUERY PLAN your_query')
print(cursor.fetchall())
```

---

### Q20: 如何贡献代码？

**A**: 贡献流程：

1. **Fork 仓库**：在 GitHub 上 fork 项目
2. **创建分支**：`git checkout -b feature/your-feature`
3. **编写代码**：遵循代码规范
4. **运行测试**：确保测试通过
5. **提交代码**：`git commit -m "feat: 功能描述"`
6. **创建 PR**：在 GitHub 上创建 Pull Request

**代码规范**：
- Python: 遵循 PEP 8
- JavaScript: 遵循 ESLint 配置
- 提交信息: 遵循约定式提交

---

## 错误排查

### Q21: 出现 "ModuleNotFoundError" 怎么办？

**A**: 检查导入路径：

```python
# 错误示例
from constants import YunmuConstants  # ❌

# 正确示例
from pinyin.constants import YunmuConstants  # ✅
# 或相对导入
from .constants import YunmuConstants  # ✅
```

---

### Q22: 数据库连接失败怎么办？

**A**: 排查步骤：

**1. 检查数据库文件**：
```bash
ls yime/pinyin_hanzi.db
```

**2. 检查数据库路径**：
```python
from pathlib import Path
db_path = Path("yime/pinyin_hanzi.db")
print(db_path.exists())
```

**3. 检查数据库权限**：
```bash
chmod 644 yime/pinyin_hanzi.db
```

**4. 使用内存数据库测试**：
```python
import sqlite3
conn = sqlite3.connect(":memory:")
```

---

### Q23: 测试失败怎么办？

**A**: 排查步骤：

**1. 查看错误信息**：
```bash
pytest -v  # 详细输出
pytest -s  # 显示打印输出
```

**2. 单独运行失败测试**：
```bash
pytest yime/test_file.py::test_function -v
```

**3. 检查测试环境**：
```python
import sys
print(sys.path)  # 检查 Python 路径
```

**4. 清理缓存**：
```bash
find . -type d -name "__pycache__" -exec rm -rf {} +
find . -type f -name "*.pyc" -delete
```

---

### Q24: 前端构建失败怎么办？

**A**: 排查步骤：

**1. 检查 Node.js 版本**：
```bash
node --version  # 应该 >= 16
```

**2. 清理依赖**：
```bash
rm -rf node_modules
rm package-lock.json
npm install
```

**3. 检查 TypeScript 错误**：
```bash
npm run type-check
```

**4. 检查 ESLint 错误**：
```bash
npm run lint
```

---

### Q25: 性能测试不通过怎么办？

**A**: 优化建议：

**1. 检查性能瓶颈**：
```python
import time

start = time.time()
# 执行操作
end = time.time()
print(f"耗时: {end - start:.2f}秒")
```

**2. 使用性能分析工具**：
```bash
python -m cProfile your_script.py
```

**3. 优化数据库查询**：
```sql
EXPLAIN QUERY PLAN your_query;
```

**4. 使用缓存**：
```python
from functools import lru_cache

@lru_cache(maxsize=1000)
def expensive_function(param):
    return result
```

---

## 其他问题

### Q26: 如何获取帮助？

**A**: 获取帮助的方式：

1. **查阅文档**：
   - [API 文档](API.md)
   - [开发者指南](DEVELOPMENT.md)
   - [README](../README.md)

2. **GitHub Issues**：
   - 搜索现有问题
   - 创建新问题（提供详细信息）

3. **GitHub Discussions**：
   - 参与讨论
   - 分享经验

---

### Q27: 如何报告 Bug？

**A**: 报告 Bug 步骤：

1. **搜索现有 Issues**：避免重复报告
2. **收集信息**：
   - Python 版本：`python --version`
   - 操作系统：Windows/Mac/Linux
   - 错误信息：完整的错误堆栈
   - 复现步骤：详细的操作步骤

3. **创建 Issue**：
   - 标题：简洁描述问题
   - 内容：包含上述信息
   - 标签：bug, help wanted

---

### Q28: 如何建议新功能？

**A**: 建议功能步骤：

1. **搜索现有 Issues**：避免重复建议
2. **描述功能**：
   - 功能描述
   - 使用场景
   - 预期效果
   - 可能的实现方式

3. **创建 Issue**：
   - 标题：以 "Feature Request:" 开头
   - 标签：enhancement

---

### Q29: 项目路线图是什么？

**A**: 查看 ROADMAP.md 了解：
- 已完成功能
- 进行中功能
- 计划中功能
- 未来愿景

---

### Q30: 如何参与社区？

**A**: 参与方式：

1. **Star 项目**：支持项目发展
2. **Fork 项目**：贡献代码
3. **报告问题**：帮助改进质量
4. **完善文档**：帮助其他用户
5. **分享经验**：在 Discussions 中分享

---

## 联系方式

- **GitHub**: https://github.com/tsaanghwang/YIME
- **Issues**: https://github.com/tsaanghwang/YIME/issues
- **Discussions**: https://github.com/tsaanghwang/YIME/discussions

---

## 更新日志

查看 [CHANGELOG.md](../CHANGELOG.md) 了解版本更新历史。
