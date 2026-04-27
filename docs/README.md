# YIME 文档中心

欢迎来到 YIME（音元输入法编辑器）文档中心！

---

## 📚 文档导航

### 重要设计约束

- **[码点与中间层策略](CODEPOINT_POLICY.md)** - 说明 `N01-N24`、`M01-M33` 的语义层地位，以及 canonical 与 projection 的分工
- **[真源文件与生成产物清单](SOURCE_AND_ARTIFACTS.md)** - 区分哪些文件是设计真源，哪些文件只是可重建产物
- **[音元系统术语说明](YINYUAN_TERMINOLOGY.md)** - 说明“时段”“片音”“音元”等核心术语的中英文定义与相互关系
- **[Terminology of the Yinyuan System](YINYUAN_TERMINOLOGY_EN.md)** - The English counterpart of the terminology note for external readers
- **[片音与语音技术单位的对应关系](PIANYIN_TECH_BRIDGE.md)** - 说明片音如何与语音识别、语音合成中的技术单位建立对应关系
- **[Correspondence Between Pianyin and Speech-Technology Units](PIANYIN_TECH_BRIDGE_EN.md)** - English note on how pianyin relates to units used in speech recognition and synthesis

### 快速开始

- **[安装指南](../INSTALLATION_GUIDE.md)** - 当前 Windows 桌面输入法原型的主安装入口
- **[MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)** - 最短的 Windows 键盘生成、打包、安装、回滚路径
- **[Python 3.12 快速开始](../QUICKSTART_PY312.md)** - 最短启动路径，适合已理解当前主线后快速跑起原型
- **[无管理员权限安装](../PORTABLE_PYTHON_GUIDE.md)** - 使用便携版 Python 3.12 的无管理员权限安装路径
- **[使用说明](USAGE.md)** - 基本使用方法和示例
- **[快速入门](../README.md)** - 项目概述和快速开始

### 核心文档

- **[输入法实现方案](../INPUT_METHOD_SOLUTION.md)** - 当前 Windows 桌面输入法原型的实现状态、边界和后续方向
- **[API 参考手册](API.md)** - 完整的 API 文档和示例
- **[开发者指南](DEVELOPMENT.md)** - 开发环境配置和最佳实践
- **[常见问题](FAQ.md)** - 常见问题解答

### 技术文档

- **[音元理论](THEORY.md)** - 音元系统理论基础
- **[理论索引](THEORY_INDEX.md)** - 理论文档总入口与实现约束入口
- **[架构设计](ARCHITECTURE.md)** - 系统架构和设计说明
- **[数据库设计](DATABASE.md)** - 数据库结构和设计

### 项目管理

- **[路线图](../ROADMAP.md)** - 项目发展路线图
- **[更新日志](../CHANGELOG.md)** - 版本更新历史
- **[贡献指南](../CONTRIBUTING.md)** - 如何贡献代码

---

## 🚀 快速导航

### 我是新用户

1. 阅读 [安装指南](../INSTALLATION_GUIDE.md)
2. 只想最短路径启动时，阅读 [Python 3.12 快速开始](../QUICKSTART_PY312.md)
3. 如果没有管理员权限，改看 [无管理员权限安装](../PORTABLE_PYTHON_GUIDE.md)
4. 阅读 [使用说明](USAGE.md)
5. 查看 [常见问题](FAQ.md)

### 我是开发者

1. 阅读 [开发者指南](DEVELOPMENT.md)
2. 查看 [API 文档](API.md)
3. 阅读 [贡献指南](../CONTRIBUTING.md)

### 我遇到了问题

1. 查看 [常见问题](FAQ.md)
2. 搜索 [GitHub Issues](https://github.com/tsaanghwang/YIME/issues)
3. 创建新 Issue

---

## 📖 文档概览

### API 参考手册

完整的 API 文档，包含：

- 核心模块 API
- 数据库 API
- 工具函数
- 异常处理
- 性能优化建议

**[查看 API 文档 →](API.md)**

### 开发者指南

开发者必读，包含：

- 环境配置
- 项目结构
- 开发工作流
- 测试指南
- 发布流程

**[查看开发者指南 →](DEVELOPMENT.md)**

### 常见问题

30+ 常见问题解答，包含：

- 安装与配置
- 使用问题
- 技术问题
- 性能问题
- 错误排查

**[查看 FAQ →](FAQ.md)**

---

## 🎯 按主题浏览

### 安装与配置

- [系统要求](FAQ.md#q1-系统要求是什么)
- [安装步骤](FAQ.md#q2-如何安装-yime)
- [依赖冲突解决](FAQ.md#q3-安装时出现依赖冲突怎么办)
- [验证安装](FAQ.md#q4-如何验证安装成功)

### 核心功能

- [拼音转换](API.md#1-韵母转换器-yunmuconverter)
- [音节解码](API.md#4-音节解码器-syllabledecoder)
- [数据库操作](API.md#数据库-api)

### 开发指南

- [项目结构](DEVELOPMENT.md#项目结构)
- [开发工作流](DEVELOPMENT.md#开发工作流)
- [添加新功能](DEVELOPMENT.md#添加新功能)
- [测试指南](DEVELOPMENT.md#测试指南)

### 性能优化

- [Python 性能优化](DEVELOPMENT.md#1-python-性能优化)
- [数据库优化](DEVELOPMENT.md#2-数据库优化)
- [前端性能优化](DEVELOPMENT.md#3-前端性能优化)
- [性能问题排查](FAQ.md#q14-如何优化转换性能)

### 错误排查

- [ModuleNotFoundError](FAQ.md#q21-出现-modulenotfounderror-怎么办)
- [数据库连接失败](FAQ.md#q22-数据库连接失败怎么办)
- [测试失败](FAQ.md#q23-测试失败怎么办)
- [前端构建失败](FAQ.md#q24-前端构建失败怎么办)

---

## 🔗 外部资源

- **GitHub 仓库**: [tsaanghwang/YIME](https://github.com/tsaanghwang/YIME)
- **问题追踪**: [tsaanghwang/YIME issues](https://github.com/tsaanghwang/YIME/issues)
- **讨论区**: [tsaanghwang/YIME discussions](https://github.com/tsaanghwang/YIME/discussions)
- **发布页面**: [tsaanghwang/YIME releases](https://github.com/tsaanghwang/YIME/releases)

---

## 📝 文档贡献

发现文档错误或想改进文档？

1. Fork 项目
2. 修改文档
3. 提交 Pull Request

文档遵循 [Markdown 规范](https://www.markdownguide.org/)。

---

## 📋 文档清单

| 文档 | 状态 | 最后更新 |
| --- | --- | --- |
| [API.md](API.md) | ✅ 完成 | 2026-04-11 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | ✅ 完成 | 2026-04-11 |
| [FAQ.md](FAQ.md) | ✅ 完成 | 2026-04-11 |
| INSTALL.md | 📝 计划中 | - |
| USAGE.md | 📝 计划中 | - |
| THEORY.md | 📝 计划中 | - |
| ARCHITECTURE.md | 📝 计划中 | - |
| DATABASE.md | 📝 计划中 | - |

---

## 💡 提示

- 使用左侧目录快速导航
- 点击链接跳转到相关文档
- 使用 Ctrl+F 搜索关键词
- 查看 FAQ 解决常见问题

---

## 📞 获取帮助

无法找到答案？

1. **搜索 Issues**: 在 GitHub Issues 中搜索
2. **创建 Issue**: 提供详细信息和复现步骤
3. **参与讨论**: 在 Discussions 中提问

---

**最后更新**: 2026-04-11
**文档版本**: 1.0.0
