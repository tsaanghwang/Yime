# pywin32 安装说明

## 问题

尝试安装 pywin32 时遇到问题：
```
ERROR: No matching distribution found: pywin32
```

## 原因

**Python 版本**: 3.14.3

Python 3.14 是非常新的版本，pywin32 官方尚未发布支持 Python 3.14 的预编译包。

## 当前解决方案

### 已安装的替代方案

1. **pynput 1.8.1** ✅
   - 跨平台键盘监听
   - 可以监听全局按键
   - 不能拦截按键

2. **pywin32-ctypes 0.2.3** ✅
   - pywin32 的纯 Python 实现
   - 不提供完整的 pywin32 API
   - 不支持全局钩子

## 功能对比

| 功能 | pywin32 | pynput | pywin32-ctypes |
|------|---------|--------|----------------|
| 全局监听 | ✅ | ✅ | ❌ |
| 按键拦截 | ✅ | ❌ | ❌ |
| Python 3.14 | ❌ | ✅ | ✅ |

## 当前状态

**使用 pynput 进行键盘监听**

- ✅ 可以监听全局按键
- ❌ 不能拦截按键
- ✅ 适合手动输入模式

## 安装 pywin32 的方法

### 方法1: 等待官方支持

等待 pywin32 发布支持 Python 3.14 的版本。

关注: https://github.com/mhammond/pywin32/releases

### 方法2: 从源码编译

```bash
# 克隆仓库
git clone https://github.com/mhammond/pywin32.git
cd pywin32

# 编译安装
python setup.py install
```

注意：需要 Visual Studio Build Tools。

### 方法3: 使用 Python 3.12 或更早版本

pywin32 支持 Python 3.12 及更早版本：

```bash
# 创建 Python 3.12 虚拟环境
python3.12 -m venv venv312
venv312\Scripts\activate
pip install pywin32
```

### 方法4: 使用预编译 wheel（如果有）

从以下地址查找预编译包：
- https://github.com/mhammond/pywin32/releases
- https://www.lfd.uci.edu/~gohlke/pythonlibs/#pywin32

## 推荐方案

### 当前最佳方案

**继续使用 pynput**

优势：
- ✅ 已安装并正常工作
- ✅ 支持 Python 3.14
- ✅ 跨平台兼容
- ✅ 足够用于手动输入模式

劣势：
- ❌ 不能拦截按键
- ❌ 不能实现真正的输入法功能

### 完整功能方案

**使用 Python 3.12 + pywin32**

如果需要完整的输入法功能（按键拦截），建议：

1. 安装 Python 3.12
2. 创建 Python 3.12 虚拟环境
3. 安装 pywin32

```bash
# 使用 pyenv-win 或直接安装 Python 3.12
py -3.12 -m venv venv312
venv312\Scripts\activate
pip install pywin32 pynput
```

## 应用使用说明

### 当前配置（pynput）

```bash
# 启动应用
python run_input_method.py

# 使用方式
# 1. 在候选框中手动输入编码
# 2. 查看候选词
# 3. 选择候选词
# 4. 自动复制到剪贴板
```

### 完整功能配置（pywin32）

如果安装了 pywin32：

```bash
# 启动应用
python run_input_method.py

# 使用方式
# 1. 在任何应用中输入编码
# 2. 自动拦截并解码
# 3. 选择候选词
# 4. 自动替换输入
```

## 总结

### 当前状态

✅ **应用可以正常使用**

- 使用 pynput 进行键盘监听
- 手动输入模式工作正常
- 所有核心功能可用

### 功能限制

⚠️ **不能拦截按键**

- 需要在候选框中手动输入
- 不能自动替换其他应用中的输入

### 建议

1. **短期**: 继续使用 pynput，功能足够
2. **长期**: 等待 pywin32 支持 Python 3.14，或使用 Python 3.12

## 相关链接

- pywin32 GitHub: https://github.com/mhammond/pywin32
- pywin32 Releases: https://github.com/mhammond/pywin32/releases
- pynput 文档: https://pynput.readthedocs.io/
- Python 下载: https://www.python.org/downloads/
