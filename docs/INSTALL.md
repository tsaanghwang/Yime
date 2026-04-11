# 安装与部署说明（INSTALL.md）

本说明介绍 YIME 项目的安装、依赖、平台兼容性及常见问题排查。

## 1. 环境要求

- Python 3.14+（核心引擎）
- Node.js 16+（前端）
- npm 8+
- 现代浏览器（Chrome/Firefox/Edge）

## 2. 安装步骤

```bash
# 克隆仓库
git clone https://github.com/tsaanghwang/YIME.git
cd YIME

# 安装 Python 依赖
pip install -r requirements.txt

# 安装前端依赖
npm install
```

## 3. 启动开发环境

```bash
npm run dev
```

## 4. 常见问题

- 依赖安装失败：请检查 Python/Node 版本，或尝试使用国内镜像。
- 端口冲突：如 3000 端口被占用，可在 package.json 中修改。
- Windows 下编码问题：请确保终端为 UTF-8。

## 5. 平台兼容性

- Windows、macOS、Linux 均支持。
- 推荐使用最新版 Node.js 和 Python。

## 6. 依赖说明

- Python 依赖详见 requirements.txt
- 前端依赖详见 package.json

---

如需详细开发环境搭建，请参考 [DEVELOPMENT.md](DEVELOPMENT.md)。
