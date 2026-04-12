# 安装与部署说明

本页是文档中心里的安装入口摘要。当前仓库的实际安装主线已经切换为 Windows 桌面输入法原型，而不是早期的 Web / Node 启动流程。

## 当前主线

请按以下组合准备环境：

- Windows 10 / 11
- Python 3.12.x
- `pywin32`
- `requirements_py312.txt`

推荐入口：

- [../INSTALLATION_GUIDE.md](../INSTALLATION_GUIDE.md)

## 推荐步骤

```bash
conda create -n yime_env python=3.12
conda activate yime_env
pip install -r requirements_py312.txt
python -m yime.input_method.app
```

如果不使用 `conda`，请改走：

- [../DIRECT_INSTALL_GUIDE.md](../DIRECT_INSTALL_GUIDE.md)

如果你需要先理解为什么仓库现在统一使用 Python 3.12，请看：

- [../PYTHON312_INSTALLATION_GUIDE.md](../PYTHON312_INSTALLATION_GUIDE.md)

## 当前说明边界

本页不再把以下路径作为默认安装主线：

- `requirements.txt` + `npm install`
- `npm run dev`
- 浏览器端原型启动

这些内容在仓库中可能仍有历史痕迹，但不应作为当前输入法原型的首选安装方式。

## 相关文档

- [../INSTALLATION_GUIDE.md](../INSTALLATION_GUIDE.md)
- [../INPUT_METHOD_SOLUTION.md](../INPUT_METHOD_SOLUTION.md)
- [DEVELOPMENT.md](DEVELOPMENT.md)
