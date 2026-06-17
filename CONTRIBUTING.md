# 音元输入法贡献指南

欢迎参与音元输入法 (YIME) 项目开发。

## 贡献方式

- 代码改进与新功能
- 文档完善
- Bug 报告与修复
- 测试用例补充

## 开发环境

1. 克隆仓库：

```bash
git clone https://github.com/tsaanghwang/Yime.git
cd Yime
```

2. 创建 Python 3.12 虚拟环境并安装依赖：

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

3. 验证：

```bash
scripts/run_tests.cmd
python run_input_method.py
```

当前主线是 **Windows + Python 3.12 + pywin32** 桌面输入法原型，不再使用 npm / Web 前端链。历史 JS 原型已外置到单独仓库。

## 代码规范

- Python 遵循 PEP 8，推荐使用类型注解
- 重要函数包含 docstring
- 文档使用 Markdown

## 提交与 Pull Request

```bash
git checkout -b feat/your-feature
# ... 修改 ...
scripts/run_tests.cmd
git commit -m "feat: 简要描述"
```

PR 前请确保 `scripts/run_tests.cmd` 或等价的 pytest/unittest 通过。

提交信息类型：`feat` / `fix` / `docs` / `refactor` / `test` / `chore`。

## 报告问题

在 GitHub Issues 中提供：问题描述、复现步骤、预期与实际行为、Python 版本与相关日志。

## 授权说明

向本仓库提交内容即表示同意按 [LICENSE](LICENSE) 与非商用/商用授权策略发布。
