# 安装指南

本文件说明当前仓库下 Windows 桌面输入法原型的实际安装方式。

这不是早期的“pynput 临时可用”报告，也不是 Web 前端启动说明。当前可用主线是：

- Windows
- Python 3.12
- `pywin32` 全局键盘钩子
- `python -m yime.input_method.app` 或 `python run_input_method.py`

如果你要了解当前原型的能力边界和运行方式，先看 `../project/INPUT_METHOD_SOLUTION.md`。

## 适用范围

本指南适用于以下场景：

- 在 Windows 上启动当前桌面输入法原型
- 启用全局键盘监听与候选框
- 使用仓库中的 Python 运行时与 SQLite 候选回退链路

本指南不覆盖以下内容：

- TSF / IMM32 系统级输入法安装
- 自定义系统词库部署
- Web 原型或 Node.js 前端开发流程

## 当前推荐方案

推荐优先级如下：

1. `conda` 环境 `yime_env` + Python 3.12
2. 本地 `venv312` + Python 3.12
3. 仅安装 `pynput` 的退化模式

如果你没有管理员权限，优先不要再看旧的临时绕行文档，直接改看：

- `PORTABLE_PYTHON_GUIDE.md`

说明：

- `pywin32` 是当前完整输入法体验的关键依赖。
- 只有 `pynput` 时，应用通常只能退化为手动输入/监听模式，不能稳定提供完整拦截体验。
- 当前仓库已经验证过 `python -m yime.input_method.app` 可以在 Windows 上启动。
- 如果你只想执行最短启动路径，可直接看 `QUICKSTART_PY312.md`。

## 环境要求

- Windows 10 或 Windows 11
- Python 3.12.x
- `pip`
- 可选：`conda` 或 Miniconda
- 可选：Git LFS

说明：

- 仓库里有一些历史文档提到其他 Python 版本，但当前 Windows 输入法主线应以 Python 3.12 为准。
- 即使未拉取完整 Git LFS 数据，当前运行时也可以回退到 SQLite 视图 `runtime_candidates` 取候选，不是安装阻塞项。

## 依赖

当前 Python 依赖主文件为：

- `requirements.txt`

其中关键依赖包括：

- `pywin32`
- `pynput`
- `pytest`
- `coverage`
- `tqdm`
- `colorama`

## 方案一：使用 conda 环境（推荐）

如果本机已有 Miniconda / Anaconda，优先使用这个方案。

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

### 4. 验证关键依赖

```bash
python -c "import win32api; import pynput; print('pywin32 + pynput OK')"
```

## 方案二：使用本地 venv312

如果不想使用 conda，可以直接在仓库目录下建立 Python 3.12 虚拟环境。

### 1. 安装 Python 3.12

可参考：

- `PYTHON312_INSTALLATION_GUIDE.md`
- `DIRECT_INSTALL_GUIDE.md`

### 2. 创建虚拟环境

```bash
py -3.12 -m venv venv312
```

### 3. 激活虚拟环境

在 `cmd` 中：

```bat
venv312\Scripts\activate.bat
```

在 PowerShell 中：

```powershell
venv312\Scripts\Activate.ps1
```

### 4. 安装依赖

```bash
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 5. 用仓库脚本快速检查

仓库已提供：

- `scripts/activate_py312.bat`

它会检查：

- Python 版本
- `pywin32`
- `pynput`

## 启动方式

推荐两种等价入口：

```bash
python -m yime.input_method.app
```

或：

```bash
python run_input_method.py
```

`run_input_method.py` 本质上会再调用：

```bash
python -m yime.input_method.app
```

### 常用参数

```bash
python -m yime.input_method.app --copy-only
python -m yime.input_method.app --font-family "Microsoft YaHei"
```

参数说明：

- `--copy-only`：只复制候选，不自动回贴到之前的窗口
- `--font-family`：指定候选框字体

## 启动后预期行为

正常情况下，启动后你应看到以下之一：

- `键盘监听已启动，按ESC退出`
- `键盘监听未启用，将使用手动输入模式`

如果启用了 SQLite 回退链路，还可能看到：

- `[Decoder] 运行时候选已回退到 SQLite 数据库视图 runtime_candidates`

这些输出都属于当前实现允许的正常路径。

## 快速自检

安装完成后，建议依次检查：

### 1. Python 版本

```bash
python --version
```

预期：`Python 3.12.x`

### 2. pywin32

```bash
python -c "import win32api; print('pywin32 OK')"
```

### 3. 应用是否可启动

```bash
python -m yime.input_method.app
```

## 常见问题

### 1. `启动键盘监听失败`

先确认当前解释器真的是 Python 3.12：

```bash
python --version
```

再确认 `pywin32` 已安装：

```bash
python -c "import win32api; print('ok')"
```

如果 `pywin32` 导入失败，重新安装：

```bash
pip install --force-reinstall pywin32
```

### 2. 只能进入手动输入模式

通常原因有：

- 当前环境没有 `pywin32`
- Python 版本不对
- Windows 钩子未成功初始化

先不要把这当成数据层错误。优先排查运行环境与钩子依赖。

### 3. 候选词数据不完整

这不一定是安装失败。

当前实现支持两条来源：

- JSON 导出文件
- SQLite `runtime_candidates` 回退视图

如果仓库中的运行时 JSON 只是 Git LFS 指针文件，程序仍可能通过 SQLite 正常工作。

### 4. 启动了，但没有“系统级输入法”效果

这是当前实现边界，不是安装步骤漏了。

本仓库现在运行的是 Windows 桌面输入法原型，具备：

- 全局监听
- 候选框
- 复制/回贴
- 待上屏文本

但它还不是完整的 TSF / IMM32 系统级 IME 安装包。

## 不再推荐的旧说法

以下旧结论不应继续作为本文件依据：

- “当前主要方案是 `pynput`”
- “当前文档重点是解决监听器安装失败”
- “安装完成后主要通过 npm / Web 界面使用”

这些说法已经不能准确描述当前仓库状态。

## 建议阅读顺序

如果你是第一次接手这个仓库，建议按这个顺序阅读：

1. `INSTALLATION_GUIDE.md`
2. `../project/INPUT_METHOD_SOLUTION.md`
3. `../CODEPOINT_POLICY.md`
4. `../SOURCE_AND_ARTIFACTS.md`

其中：

- 本文档负责“怎么装、怎么起”
- `../project/INPUT_METHOD_SOLUTION.md` 负责“现在做到哪一步了”
- `../CODEPOINT_POLICY.md` 负责“哪些设计约束不能绕过”

## 最短可执行流程

如果你只想最快跑起来，按下面执行：

```bash
conda create -n yime_env python=3.12
conda activate yime_env
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m yime.input_method.app
```

如果你不使用 conda，则改为：

```bash
py -3.12 -m venv venv312
venv312\Scripts\activate.bat
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m yime.input_method.app
```
