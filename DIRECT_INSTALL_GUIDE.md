# Python 3.12 直接安装指南

本文件适用于一种非常具体的情况：你不打算先装 `conda`，而是准备直接把 Python 3.12 安装到 Windows，再在仓库里创建 `venv312`。

如果你还没决定走哪条路线，先看 `INSTALLATION_GUIDE.md`。

## 适用场景

适合：

- 本机还没有 Python 3.12
- 你不想额外引入 `conda`
- 你希望保留一条最直接的系统安装路径

不适合：

- 你已经在使用 `conda yime_env`
- 你只想快速跑起仓库，且不关心系统 Python 管理

## 步骤 1：安装系统级 Python 3.12

官方下载页：

- [Python 3.12.8 下载页](https://www.python.org/downloads/release/python-3128/)

建议下载：

- `python-3.12.8-amd64.exe`

安装时至少确认：

- 勾选 `Add Python to PATH`
- 安装 `pip`
- 安装 `py launcher`

## 步骤 2：验证安装

打开新的终端执行：

```bash
py -3.12 --version
```

预期输出：

- `Python 3.12.x`

如果没有这个命令，再检查是否安装了 `py launcher`，或是否需要重开终端。

## 步骤 3：在仓库目录创建虚拟环境

```bash
cd "c:\Users\Freeman Golden\OneDrive\Yime"
py -3.12 -m venv venv312
```

## 步骤 4：激活虚拟环境

在 `cmd` 中：

```bat
venv312\Scripts\activate.bat
```

在 PowerShell 中：

```powershell
venv312\Scripts\Activate.ps1
```

激活后确认：

```bash
python --version
```

预期仍然是：

- `Python 3.12.x`

## 步骤 5：安装仓库依赖

```bash
python -m pip install --upgrade pip
pip install -r requirements_py312.txt
```

这会安装当前 Windows 输入法原型所需的关键依赖，包括：

- `pywin32`
- `pynput`
- `pytest`
- `coverage`

## 步骤 6：验证关键依赖

```bash
python -c "import win32api; import pynput; print('pywin32 + pynput OK')"
```

如果这里失败，先不要启动输入法，先把依赖问题解决干净。

## 步骤 7：启动输入法原型

推荐使用：

```bash
python -m yime.input_method.app
```

也可以：

```bash
python run_input_method.py
```

## 可用辅助脚本

仓库里已提供：

- `activate_py312.bat`

它适合在 `venv312` 已经存在时做快速检查。

## 常见问题

### 1. `py -3.12` 找不到

优先排查：

- Python 3.12 是否真的安装成功
- 安装时是否勾选 `Add Python to PATH`
- 是否安装了 `py launcher`

必要时可直接用完整路径创建环境：

```bash
"C:\Program Files\Python312\python.exe" -m venv venv312
```

### 2. 激活后版本不对

执行：

```bash
python --version
where python
```

如果版本不是 `3.12.x`，说明当前终端并没有真正进入 `venv312`。

### 3. `pywin32` 安装失败

先确认：

```bash
python --version
```

如果不是 `3.12.x`，先修正解释器环境，再执行：

```bash
pip install --force-reinstall pywin32
```

### 4. 启动成功，但行为不像系统级输入法

这不是安装失败。

当前仓库运行的是 Windows 桌面输入法原型，不是完整 TSF / IMM32 安装包。

## 与其他安装文档的关系

- `INSTALLATION_GUIDE.md`：主安装入口
- `PYTHON312_INSTALLATION_GUIDE.md`：Python 3.12 环境选择说明
- 本文：系统级直装 Python 3.12 的最短路径
