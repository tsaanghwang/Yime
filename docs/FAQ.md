# 常见问题解答

本文档只保留当前仓库主线最常见的问题与答案。

当前主线是：

- Windows
- Python 3.12
- `pywin32`
- `python -m yime.input_method.app`

如果某个旧答案仍在别处描述 `npm run start`、`run_input_method_v2.py`、`Python 3.14 + pynput` 或 Web 原型优先，请视为过时。

## 安装与环境

### Q1：当前推荐的运行环境是什么？

当前推荐环境：

- Windows 10 / 11
- Python 3.12.x
- `pywin32`
- `requirements_py312.txt`

可选但不是硬前提：

- `conda`
- Git LFS

说明：即使没有完整拉取 Git LFS，当前实现也可以通过 SQLite 回退链路取候选。

### Q2：最短安装路径是什么？

如果你只想最快跑起来：

```bash
conda create -n yime_env python=3.12
conda activate yime_env
python -m pip install --upgrade pip
pip install -r requirements_py312.txt
python -m yime.input_method.app
```

更完整的安装路径请看：

- [../INSTALLATION_GUIDE.md](../INSTALLATION_GUIDE.md)
- [../QUICKSTART_PY312.md](../QUICKSTART_PY312.md)

### Q3：我没有管理员权限怎么办？

不要退回旧的 `Python 3.14 + pynput` 路线。

直接看：

- [../PORTABLE_PYTHON_GUIDE.md](../PORTABLE_PYTHON_GUIDE.md)

该文档说明如何使用便携版 Python 3.12 继续沿当前主线部署。

### Q4：如何确认安装成功？

运行以下命令：

```bash
python --version
python -c "import win32api; print('pywin32 OK')"
python -m yime.input_method.app
```

正常情况下，你应看到以下输出之一：

- `键盘监听已启动，按ESC退出`
- `键盘监听未启用，将使用手动输入模式`

### Q5：为什么文档里仍然会提到 Git LFS？

因为仓库里某些运行时 JSON 文件历史上由 Git LFS 管理。

但当前实现已经具备：

- JSON 读取
- SQLite `runtime_candidates` 回退
- 静态候选兜底

所以缺少 Git LFS 文件并不等于应用无法运行。

## 启动与使用

### Q6：当前默认启动方式是什么？

推荐：

```bash
python -m yime.input_method.app
```

等价入口：

```bash
python run_input_method.py
```

不再推荐：

- `python run_input_method_v2.py`

### Q7：当前到底是“输入框工具”还是“输入法原型”？

当前更准确的描述是：

**Windows 桌面输入法原型**。

它已经具备：

- 全局低层键盘钩子
- 组合态输入
- 浮动候选框
- 候选分页
- 待上屏文本
- 复制/回贴到外部窗口

但它仍然不是系统级 TSF / IMM32 IME。

### Q8：现在的基本使用流程是什么？

当前推荐流程：

1. 启动应用
2. 在记事本等简单外部窗口输入码元
3. 候选框在光标附近出现
4. 使用数字键、Enter、Space 或鼠标选择候选
5. 直接回贴，或先累积待上屏文本再整段提交

更完整说明请看：

- [USAGE.md](USAGE.md)
- [../INPUT_METHOD_SOLUTION.md](../INPUT_METHOD_SOLUTION.md)

### Q9：有哪些常用参数？

```bash
python -m yime.input_method.app --copy-only
python -m yime.input_method.app --font-family "Microsoft YaHei"
```

说明：

- `--copy-only`：只复制候选，不自动回贴
- `--font-family`：指定候选框字体

### Q10：为什么现在的交互和旧文档写的不一样？

因为旧文档描述的是更早阶段：

- 只能依赖 `pynput`
- 只能快捷键唤出输入框
- 不能在外部窗口直接走组合输入

这些判断现在都不再代表仓库真实状态。

## 故障排查

### Q11：启动后提示“将使用手动输入模式”怎么办？

优先检查：

```bash
python --version
python -c "import win32api; print('pywin32 OK')"
```

如果 `pywin32` 不可用，应用可能退回到较弱模式。

### Q12：候选词为空或结果不完整怎么办？

先不要立刻认定为安装失败。

当前解码有多级回退：

- 运行时 JSON
- SQLite `runtime_candidates` 视图
- 静态候选表

优先看启动日志确认当前使用的是哪一层。

### Q13：为什么某些应用里行为不稳定？

因为当前实现仍然是桌面原型，不是系统级 IME。

常见影响因素包括：

- 焦点恢复
- 窗口权限差异
- 特殊快捷键处理
- 特定应用对回贴或键盘钩子的兼容差异

建议先在记事本、普通输入框、VS Code 文本区等简单环境测试。

### Q14：`ImportError` 或模块导入问题怎么办？

不要直接运行包内部文件。

正确方式：

```bash
python -m yime.input_method.app
```

或：

```bash
python run_input_method.py
```

### Q15：测试失败时先看哪里？

当前最应该先排查的是：

1. Python 环境是否真的是 3.12
2. `pywin32` 是否可用
3. 测试是否误写数据库或误改运行时产物文件
4. 是否把语义层问题错误地下沉成字符层问题

如果测试失败，不应直接去手改数据库字符编码或运行时映射文件。

## 架构与数据

### Q16：`N01-N24` 和 `M01-M33` 到底是什么？

它们是系统的语义槽位层，不是可删的临时中间产物。

当前约束是：

- 语义层：`N/M`
- 规范层：`PUA-B`
- 平台层：`BMP PUA`

详见：

- [CODEPOINT_POLICY.md](CODEPOINT_POLICY.md)

### Q17：哪些文件是“真源”，哪些只是产物？

当前原则是：

- `manual_key_layout.json`、`key_to_symbol.json` 更接近真源层
- `yinjie_code.json`、各类 `*_codepoint.json`、`yinyuan.klc` 更接近生成产物层
- 数据库是消费端产物，不应承担字符系统真源职责

详见：

- [SOURCE_AND_ARTIFACTS.md](SOURCE_AND_ARTIFACTS.md)

### Q18：为什么不应该直接改数据库或字符结果文件？

因为这样会把三个问题混在一起：

1. 语义层是否正确
2. 码点层是否正确
3. 平台投影是否正确

短期可能能“修通测试”，长期会破坏生成链和维护边界。

## 参与与支持

### Q19：下一阶段最重要的方向是什么？

当前优先级大致是：

1. 稳定 Windows 输入法原型
2. 把 `N/M` 语义层恢复为真源
3. 让运行时字符文件退回生成产物层
4. 清理测试体系中的错误假设
5. 继续收口文档

详见：

- [../ROADMAP.md](../ROADMAP.md)

### Q20：去哪里获取帮助或反馈问题？

- [README](../README.md)
- [开发者指南](DEVELOPMENT.md)
- [GitHub 仓库](https://github.com/tsaanghwang/YIME)
- [GitHub Issues](https://github.com/tsaanghwang/YIME/issues)
- [GitHub Discussions](https://github.com/tsaanghwang/YIME/discussions)

如果你要报告问题，至少带上：

- Python 版本
- Windows 版本
- 启动命令
- 完整错误信息
- 复现步骤
