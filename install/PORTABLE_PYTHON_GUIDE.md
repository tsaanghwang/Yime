# 便携版 Python 3.12 安装指南（无需管理员权限）

本文件说明在没有管理员权限的情况下，如何为当前 Windows 桌面输入法原型准备可用的 Python 3.12 环境。

这份文档的目标不是提供“退化可用”的旧绕行方案，而是给出一条仍然符合当前主线的无管理员权限安装路径。

当前主线仍然是：

- Python 3.12.x
- `pywin32`
- `requirements.txt`
- `python -m yime.input_method.app`

## 什么时候看这份文档

适合以下场景：

- 你没有管理员权限，不能安装系统级 Python 3.12
- 你也不方便使用已有的 `conda`
- 你仍然想保持与当前仓库主安装路线一致

如果你有管理员权限，或者已经能正常使用 `conda yime_env`，优先看 `INSTALLATION_GUIDE.md`。

## 推荐顺序

无管理员权限时，推荐优先级如下：

1. 便携式 Python Embedded 3.12
2. WinPython 3.12
3. 已存在的用户级 `conda` 环境

不再推荐：

- `Python 3.14 + pynput` 作为主方案

那个方向只能算历史上的临时退化路径，不应继续作为当前文档结论。

## 方案一：Python Embedded 3.12

### 1. 下载

官方下载目录：

- [Python 3.12.8 Embeddable Packages](https://www.python.org/ftp/python/3.12.8/)

常用文件：

- `python-3.12.8-embed-amd64.zip`

### 2. 解压到项目目录

```bash
cd /d <你的 Yime 仓库目录>
mkdir python312
```

例如仓库放在 `C:\dev\Yime` 时，可写成：`cd /d C:\dev\Yime`

然后把压缩包解压到 `python312\`，解压后应能看到：

```text
Yime/
├── python312/
│   ├── python.exe
│   ├── pythonw.exe
│   ├── python312.dll
│   └── ...
└── ...
```

### 3. 启用 `site` 和 `pip`

Embedded 版本默认不带完整包管理能力，需要补两步：

1. 编辑 `python312\python312._pth`
1. 取消注释这一行：

```text
import site
```

1. 下载 `get-pip.py`

```bash
curl -o python312\get-pip.py https://bootstrap.pypa.io/get-pip.py
```

1. 安装 `pip`

```bash
python312\python.exe python312\get-pip.py
```

### 4. 创建虚拟环境

```bash
cd /d <你的 Yime 仓库目录>
python312\python.exe -m venv venv312
```

### 5. 激活虚拟环境

在 `cmd` 中：

```bat
venv312\Scripts\activate.bat
```

在 PowerShell 中：

```powershell
venv312\Scripts\Activate.ps1
```

### 6. 安装依赖

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 7. 验证安装

```bash
python --version
python -c "import win32api; import pynput; print('pywin32 + pynput OK')"
```

预期：

- Python 版本为 `3.12.x`
- `win32api` 可正常导入

### 8. 启动输入法原型

```bash
python -m yime.input_method.app
```

或：

```bash
python run_input_method.py
```

## 方案二：WinPython 3.12

如果你不想手工配置 Embedded 版，WinPython 会省事一些。

### 1. 下载

- [WinPython 官网](https://winpython.github.io/)

选择可用的 3.12 x64 版本。

### 2. 创建虚拟环境

```bash
WinPython\python-3.12.x\python.exe -m venv venv312
```

### 3. 激活并安装依赖

```bat
venv312\Scripts\activate.bat
pip install -r requirements.txt
```

### 4. 启动

```bash
python -m yime.input_method.app
```

## 如果你已经有用户级 conda

如果你的机器虽然没有管理员权限，但已经可以使用自己的 Miniconda / conda，那么优先改走主安装文档里的 `yime_env` 路线，不必坚持便携 Python。

## 仓库现有辅助脚本

仓库已提供：

- `scripts/setup_portable_python.bat`
- `scripts/activate_py312.bat`

用途分别是：

- `scripts/setup_portable_python.bat`：检查便携 Python 是否齐备，并创建 `venv312`
- `scripts/activate_py312.bat`：激活 `venv312` 后检查 `pywin32` 和 `pynput`

## 快速步骤

如果你只想最短路径执行：

```bash
curl -o python312\get-pip.py https://bootstrap.pypa.io/get-pip.py
python312\python.exe python312\get-pip.py
python312\python.exe -m venv venv312
venv312\Scripts\activate.bat
pip install -r requirements.txt
python -m yime.input_method.app
```

前提是你已经把 Embedded 版 Python 解压到 `python312\`，并启用了 `import site`。

## 常见问题

### 1. `python312\python.exe -m venv venv312` 失败

先确认：

- `python312\python.exe` 存在
- `python312\python312._pth` 已启用 `import site`
- `pip` 已通过 `get-pip.py` 装好

### 2. 便携 Python 装好了，但 `pywin32` 失败

先看版本：

```bash
python --version
```

必须是 `3.12.x`。然后再执行：

```bash
pip install --force-reinstall pywin32
```

### 3. 为什么不再推荐旧的 `Python 3.14 + pynput` 路线

因为当前仓库已经有明确的 Windows 桌面输入法原型主入口：

- `python -m yime.input_method.app`
- `python run_input_method.py`

旧的 `Python 3.14 + pynput` 方案代表的是另一阶段的临时退化路径，不应再作为无管理员权限场景下的默认启动方式。

## 对应文档关系

- `INSTALLATION_GUIDE.md`：主安装入口
- `PYTHON312_INSTALLATION_GUIDE.md`：解释为什么当前统一到 Python 3.12
- 本文：无管理员权限下的便携 Python 路线

如果后续有管理员权限，建议还是回到 `INSTALLATION_GUIDE.md` 的主路线。
