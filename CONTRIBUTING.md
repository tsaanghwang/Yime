# 音元输入法贡献指南

欢迎参与音元输入法(YIME)项目开发！本指南将帮助您了解如何为项目做出贡献。

## 贡献方式

我们接受以下类型的贡献:

- 代码改进与新功能开发
- 文档完善与翻译
- Bug报告与修复
- 测试用例补充
- 用户体验优化

## 开发环境配置

1. 克隆仓库:

```bash
git clone https://github.com/huangchang/yinyuan-input-method.git
```

1. 安装依赖:

```bash
# Python依赖
pip install -r requirements.txt

# 前端依赖
npm install
```

1. 配置开发环境:

```bash
npm run setup
```

## 代码规范

### Python代码

- 遵循PEP 8风格指南
- 使用类型注解(Type Hints)
- 重要函数需包含docstring

### JavaScript/TypeScript代码

- 遵循ESLint配置
- 使用TypeScript严格模式
- React组件使用函数式组件

## 提交规范

````markdown

1. 创建特性分支:

```bash
```
git checkout -b feat/your-feature
```

2. 提交信息格式：
```
类型(范围): 简要描述

详细描述(可选)

关联问题: #123
```

**类型说明**:
- feat: 新功能
- fix: Bug修复
- docs: 文档变更
- style: 代码格式
- refactor: 代码重构
- test: 测试相关
- chore: 构建/依赖更新

## Pull Request流程

1. Fork主仓库并创建分支
2. 确保通过所有测试：
```bash
npm test
pytest
```
3. 更新CHANGELOG.md
4. 提交Pull Request到主仓库的dev分支
5. 等待代码审查

## 报告问题

请在GitHub Issues中提交问题报告，包含：
1. 问题描述
2. 重现步骤
3. 预期行为
4. 实际行为
5. 环境信息

## 社区准则

所有贡献者需遵守[行为准则](CODE_OF_CONDUCT.md)，保持专业和尊重的交流氛围。

## 鸣谢

感谢所有贡献者为项目做出的努力！您的名字将被记录在[CONTRIBUTORS.md](CONTRIBUTORS.md)中。
