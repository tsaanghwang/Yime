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

### Python 代码
- 遵循 PEP 8 风格指南
- 推荐使用类型注解 (Type Hints)
- 重要函数需包含 docstring
- 推荐使用 [black](https://black.readthedocs.io/) 自动格式化

### JavaScript/TypeScript 代码
- 遵循 ESLint 配置
- 使用 TypeScript 严格模式
- React 组件使用函数式组件
- 推荐使用 [prettier](https://prettier.io/) 自动格式化

### 文档规范
- 推荐使用 Markdown 编写文档，结构清晰、语法规范
- 图片请统一放在 docs/Assets 或 images/ 目录，命名简明
- 文档内容建议包含：背景、用途、示例、注意事项等

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


## Pull Request 流程与审查标准

1. Fork 主仓库并创建分支
2. 确保通过所有测试：
	```bash
	npm test
	pytest
	```
3. 更新 CHANGELOG.md（如有重要变更）
4. 提交 Pull Request 到主仓库 dev 分支
5. PR 审查标准：
	- 必须通过 CI 自动测试和格式检查
	- 需有至少一位维护者或核心开发者审核通过
	- 代码需无明显安全/性能/兼容性问题
	- 文档和注释需齐全
6. 重大变更或新功能建议先在 Discussions 或 Issues 区发起讨论，达成共识后再开发


## 报告问题

请在 GitHub Issues 区提交问题报告，内容包括：
1. 问题描述
2. 复现步骤
3. 预期与实际行为
4. 环境信息（操作系统、Python/Node 版本等）
5. 如有截图、日志、相关文件请一并附上


## 社区准则

所有贡献者需遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)，保持专业、尊重和包容的交流氛围。


## 鸣谢

感谢所有贡献者为项目做出的努力！您的名字将被记录在 [CONTRIBUTORS.md](CONTRIBUTORS.md) 中。

---

如有疑问，欢迎在 Issues 区提问或联系核心团队。
