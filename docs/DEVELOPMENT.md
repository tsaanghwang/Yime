# 开发者文档（DEVELOPMENT.md）

本说明面向开发者，介绍项目结构、主要模块、开发流程、调试方法等。

## 1. 目录结构

- src/           前端源码（JS/TS/React）
- yime/          核心 Python 逻辑
- docs/          项目文档
- tests/         单元测试
- config/        配置与映射表
- data_json_files/  主要数据文件

## 2. 主要模块说明

- yinjie_encoder.py / yinjie_decoder.py：音节编码与解码核心
- pinyinModule.js / hanziModule.js：拼音与汉字查找
- input-method.js：输入法主逻辑
- config/ 下 json：键音映射、参数配置

## 3. 开发环境搭建

- 建议使用 VS Code
- Python 推荐虚拟环境（venv）
- 前端建议 Node.js 16+，支持热重载

## 4. 调试与测试

- Python：pytest 或 unittest
- 前端：npm run test
- 推荐配置 ESLint、Prettier、black

## 5. 前后端联调

- 前端通过 API/数据文件与 Python 后端交互
- 可用 mock 数据进行界面开发

## 6. 贡献建议

- 遵循 [CONTRIBUTING.md](../CONTRIBUTING.md)
- 新功能建议先提 Issue 或 Discussion

---

如需数据结构说明，请参考 [DATAFILES.md](DATAFILES.md)。
