# 使用说明

本文档说明当前仓库中的 Windows 桌面输入法原型应如何启动、如何使用，以及它现在的交互边界是什么。

这不是 Web 原型说明，也不是旧版“快捷键唤出输入框”方案说明。与本文冲突的旧使用文档都应视为过时。

## 适用范围

本文适用于以下情况：

- 你已经按 `docs/install/INSTALLATION_GUIDE.md` 完成环境准备
- 你要启动当前 Python 3.12 + `pywin32` 的桌面输入法原型
- 你想了解候选框、选字、待上屏文本和回贴的实际交互方式

本文不负责解释：

- 如何安装 Python 3.12
- 无管理员权限时如何准备便携 Python
- 为什么当前实现还不是系统级 IME

这些内容请分别看：

- `docs/install/INSTALLATION_GUIDE.md`
- `docs/install/PORTABLE_PYTHON_GUIDE.md`
- `docs/project/INPUT_METHOD_SOLUTION.md`

## 当前默认入口

推荐入口：

```bash
python -m yime.input_method.app
```

等价入口：

```bash
python run_input_method.py
```

常用参数：

```bash
python -m yime.input_method.app --copy-only
python -m yime.input_method.app --font-family "Microsoft YaHei"
```

参数说明：

- `--copy-only`：只复制候选到剪贴板，不自动回贴到外部窗口
- `--font-family`：指定候选框字体

## 启动后会看到什么

正常情况下，启动后会出现以下输出之一：

- `键盘监听已启动，按ESC退出`
- `键盘监听未启用，将使用手动输入模式`

如果运行时候选从数据库回退，还可能看到：

- `[Decoder] 运行时候选已回退到 SQLite 数据库视图 runtime_candidates`

这几类提示都属于当前实现允许的正常路径。

## 当前交互模型

当前原型的目标流程是：

```text
在外部窗口输入码元
-> 全局键盘钩子接收按键
-> 组合态下拦截普通码元按键
-> 解码候选词
-> 在光标附近显示候选框
-> 选择候选或编辑待上屏文本
-> 回贴到外部窗口
```

这意味着当前原型已经不再是“先手动唤出再输入”的旧流程。

## 基本使用流程

### 1. 启动应用

```bash
python -m yime.input_method.app
```

### 2. 在外部窗口测试输入

建议先在这些应用测试：

- 记事本
- VS Code 普通文本编辑区
- 其他标准输入框

先不要上来就在权限复杂或快捷键很多的应用里测试。

### 3. 输入码元

在当前实现中：

- 普通码元输入会进入组合态
- 组合键如 Ctrl、Alt、Win 默认放行
- 候选框会在光标附近显示候选

### 4. 选择候选

可用方式包括：

- 数字键选择当前页候选
- Enter 提交首选候选或提交待上屏文本
- Space 提交首选候选或提交待上屏文本
- 鼠标点击候选词

### 5. 上屏方式

当前存在两种常见上屏路径：

- 选中候选后直接复制并回贴到外部窗口
- 先把多个字累积到待上屏文本，再整段提交

## 候选框当前能力

当前候选框不仅是显示列表，还承担一部分编辑职责。

已实现能力包括：

- 非激活浮动显示
- 在需要时进入可聚焦手工编辑模式
- 分页显示候选词
- 累积待上屏文本
- 撤销一个待上屏字
- 清空待上屏文本
- 从剪贴板读取编码
- 隐藏到待命状态而不是立刻退出

## 常用操作

如果你要做“反查当前字词的拼音和编码”或“把缺词加入持久用户词库”，请同时参考：

- `docs/REVERSE_LOOKUP_AND_USER_LEXICON.md`
- `docs/REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md`

### 清空或退出

- `ESC`：在多数场景下用于退出当前组合或结束运行
- 关闭按钮：关闭应用并停止监听

### 编辑组合输入

- `Backspace`：删除组合缓冲中的最后一个码元
- 数字键：选择候选
- `Enter` / `Space`：提交首选或提交待上屏文本

### 手工编辑模式

在候选框进入可聚焦编辑状态时：

- 你可以直接编辑输入框内容
- 也可以从剪贴板读取编码
- 这时按键优先交给输入框自身处理，不继续强拦截

### 汉字反查与用户词库

当前输入框还支持一条额外路径：

- 如果输入或粘贴的是汉字词语，系统会尝试反查首选拼音和编码
- 你可以右键输入框，把当前汉字词语加入持久用户词库

更完整的实际操作步骤、脚本用法和频率说明，请看：

- `docs/REVERSE_LOOKUP_AND_USER_LEXICON.md`
- `docs/REVERSE_LOOKUP_AND_USER_LEXICON_QUICK_REF.md`

如果你需要迁移、备份或诊断用户词库，还可以直接用：

- `python tools/manage_user_lexicon.py list-recent --limit 10`
- `python tools/manage_user_lexicon.py export backups/user_lexicon_backup.json`
- `python tools/manage_user_lexicon.py import backups/user_lexicon_backup.json`
- `python tools/diagnose_candidate_order.py --numeric-pinyin "ri4 ben3" --limit 10`

## 当前限制

以下限制仍然存在，使用时要有预期：

1. 当前实现不是系统级 IME
2. 不保证所有 Windows 应用行为完全一致
3. 自动回贴在不同窗口中的手感仍需继续打磨
4. 词频排序和用户自适应能力仍处于原型阶段

因此，不要把它理解成“已经完成系统级输入法安装”的状态。

## 常见问题

### 1. 启动后提示手动输入模式

先检查：

```bash
python --version
python -c "import win32api; print('pywin32 OK')"
```

如果 `pywin32` 不可用，应用可能回到退化模式。

### 2. 候选词为空或结果不完整

当前实现支持多级回退：

- 运行时 JSON
- SQLite `runtime_candidates` 视图
- 静态候选表

所以这不一定意味着安装失败。优先看启动日志确认当前解码来源。

### 3. 为什么和旧文档写的不一样

因为旧文档描述的是更早阶段：

- 只能用 `pynput`
- 只能快捷键唤出输入框
- 不能在外部窗口直接走组合输入

这些判断现在都不能再代表仓库真实状态。

### 4. 无管理员权限怎么办

改看：

- `docs/install/PORTABLE_PYTHON_GUIDE.md`

不要再回退到旧的 `Python 3.14 + pynput` 路线。

## 推荐阅读顺序

建议按这个顺序理解当前原型：

1. `docs/install/INSTALLATION_GUIDE.md`
2. `docs/install/QUICKSTART_PY312.md`
3. `docs/project/INPUT_METHOD_SOLUTION.md`
4. `FAQ.md`

其中：

- 本文负责“怎么用”
- `docs/project/INPUT_METHOD_SOLUTION.md` 负责“现在做到哪里了”
- `FAQ.md` 负责常见安装与使用问题

## 相关文档

- [安装指南](install/INSTALLATION_GUIDE.md)
- [Python 3.12 快速开始](install/QUICKSTART_PY312.md)
- [便携版 Python 3.12 安装指南（无需管理员权限）](install/PORTABLE_PYTHON_GUIDE.md)
- [输入法实现方案](project/INPUT_METHOD_SOLUTION.md)
- [常见问题](FAQ.md)
- [开发者指南](DEVELOPMENT.md)
