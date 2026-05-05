# Python 3.12 安装方案

本文件只回答一个问题：怎样为当前 Windows 输入法原型准备可用的 Python 3.12 运行环境。

如果你只想直接照做，请先看 `INSTALLATION_GUIDE.md`。本文档更适合以下情况：

- 本机已有多个 Python 版本，需要明确切到 3.12
- 你想在 `conda`、`venv`、系统直装之间做选择
- 你要排查 `pywin32` 为什么没装好

## 当前结论

当前仓库的 Windows 输入法主线应以以下组合为准：

- Python 3.12.x
- `pywin32`
- `requirements.txt`
- `python -m yime.input_method.app`

推荐优先级：

1. `conda` 环境 `yime_env`
2. `venv312`
3. 系统 Python 3.12 直装后再手工维护环境

不建议把 `pyenv-win` 作为默认路线。它可以用，但对这个仓库来说只是可选工具，不应成为安装前提。

## 方案一：conda 环境（推荐）

### 1. 创建环境

```bash
conda create -n yime_env python=3.12
```

### 2. 激活环境

在 `bash` 中：

```bash
source C:/ProgramData/miniconda3/etc/profile.d/conda.sh
conda activate yime_env
```

在 `cmd` 或 PowerShell 中：

```powershell
conda activate yime_env
```

### 3. 安装依赖

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 4. 验证

```bash
python --version
python -c "import win32api; import pynput; print('pywin32 + pynput OK')"
```

预期：

- Python 版本为 `3.12.x`
- `win32api` 可正常导入

## 方案二：venv312

如果你已经安装了系统级 Python 3.12，这是最直接的隔离方案。

### 1. 创建虚拟环境

```bash
py -3.12 -m venv venv312
```

### 2. 激活虚拟环境

在 `cmd` 中：

```bat
venv312\Scripts\activate.bat
```

在 PowerShell 中：

```powershell
venv312\Scripts\Activate.ps1
```

### 3. 安装依赖

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 4. 使用仓库辅助脚本检查

```bat
scripts\activate_py312.bat
```

该脚本会检查：

- 当前 Python 版本
- `pywin32`
- `pynput`

## 方案三：先安装系统级 Python 3.12

如果本机还没有 Python 3.12，可直接从官方安装：

- [Python 3.12.8 下载页](https://www.python.org/downloads/release/python-3128/)

安装时至少确认：

- 勾选 `Add Python to PATH`
- 安装 `pip`
- 安装 `py launcher`

安装完成后先验证：

```bash
py -3.12 --version
```

然后再回到方案二创建 `venv312`。

## 启动当前输入法原型

环境准备完成后，推荐这样启动：

```bash
python -m yime.input_method.app
```

或：

```bash
python run_input_method.py
```

常用参数：

```bash
python -m yime.input_method.app --copy-only
python -m yime.input_method.app --font-family "Microsoft YaHei"
```

## 常见问题

### 1. `pywin32` 无法导入

先确认你当前就在 Python 3.12 环境中：

```bash
python --version
```

再执行：

```bash
pip install --force-reinstall pywin32
python -c "import win32api; print('pywin32 OK')"
```

### 2. 明明装了依赖，启动仍然退化为手动模式

优先排查：

- 当前终端是否真的激活了 `yime_env` 或 `venv312`
- `python --version` 是否仍为 `3.12.x`
- `win32api` 是否能导入

不要先把这个问题归因到码表、数据库或候选数据。

### 3. 为什么本文不再默认推荐 pyenv-win

因为它增加了一层版本管理复杂度，而当前仓库已经有更直接的两条主线：

- `conda yime_env`
- `venv312`

只有在你本机确实长期维护多个 Python 版本、并且明确需要 `pyenv-win` 时，再考虑它。

## 对应文档关系

- `INSTALLATION_GUIDE.md`：主安装入口
- `DIRECT_INSTALL_GUIDE.md`：系统级 Python 3.12 直装细节
- `../project/INPUT_METHOD_SOLUTION.md`：当前原型实现边界

如果你只是第一次装环境，优先读 `INSTALLATION_GUIDE.md`，不要从本文件单独开始。
