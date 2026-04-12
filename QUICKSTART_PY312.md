# Python 3.12 快速开始

本文件只保留最短路径，目标是在最少阅读量下把当前 Windows 桌面输入法原型启动起来。

如果你需要完整说明，请看：

- `INSTALLATION_GUIDE.md`
- `PYTHON312_INSTALLATION_GUIDE.md`
- `DIRECT_INSTALL_GUIDE.md`
- `PORTABLE_PYTHON_GUIDE.md`

## 推荐路径：conda

```bash
conda create -n yime_env python=3.12
conda activate yime_env
python -m pip install --upgrade pip
pip install -r requirements_py312.txt
python -m yime.input_method.app
```

## 备选路径：本地 venv312

```bash
py -3.12 -m venv venv312
venv312\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements_py312.txt
python -m yime.input_method.app
```

## 无管理员权限路径

如果你不能安装系统级 Python，请改看：

- `PORTABLE_PYTHON_GUIDE.md`

## 启动成功的最小验证

```bash
python --version
python -c "import win32api; print('pywin32 OK')"
python -m yime.input_method.app
```

预期：

- Python 版本为 `3.12.x`
- `win32api` 可以导入
- 应用启动后出现键盘监听或手动输入模式提示

## 当前默认入口

优先使用：

```bash
python -m yime.input_method.app
```

也可以：

```bash
python run_input_method.py
```

不再推荐：

- `run_input_method_v2.py`
- `pyenv-win` 作为默认安装路径

## 这份文档不回答什么

本文件不展开说明：

- 为什么统一到 Python 3.12
- 没有管理员权限时的便携 Python 细节
- 当前输入法原型的实现边界

这些内容请分别看对应文档，不要继续把本文件扩展回一份冗长安装手册。
