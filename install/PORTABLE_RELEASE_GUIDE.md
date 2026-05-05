# 便携版发布指南

这份指南对应当前最小可发给朋友试用的 Windows 发布形态：

- 不要求目标机器预装 Python
- 产物是一个 `dist/Yime/` 独立目录
- 双击其中的 `Yime.exe` 即可启动

说明：

- 这还是“Windows 桌面输入法原型应用”，不是系统级 TSF 输入法安装包。
- 当前默认会把用户词库写到 `%LOCALAPPDATA%/Yime/user_lexicon.db`，避免装到只读目录时写失败。

## 先决条件

在打包机器上：

```bash
python -m pip install -e .[portable]
```

如果你已经在项目虚拟环境里，也可以只装：

```bash
python -m pip install pyinstaller
```

## 构建命令

仓库已提供：

- `yime_portable.spec`
- `scripts/build_portable_release.bat`

最短路径：

```bat
scripts\build_portable_release.bat
```

等价命令：

```bash
python -m PyInstaller --noconfirm yime_portable.spec
```

## 构建结果

成功后产物位于：

- `dist/Yime/Yime.exe`

你可以把整个 `dist/Yime/` 目录打包给朋友；不要只单独拷 `Yime.exe`。

## 建议验收

发包前至少做这几步：

1. 在打包机上删除旧的 `dist/` 与 `build/` 后重打一次。
2. 双击 `dist/Yime/Yime.exe`，确认右下角待命图标能出现。
3. 验证 hotkey 模式能正常唤起候选框。
4. 加一条用户词库，确认 `%LOCALAPPDATA%/Yime/user_lexicon.db` 已生成。
5. 关闭后再次启动，确认用户词库仍能读回。

## 当前边界

这套 portable 发布当前解决的是：

- 无需 Python 的独立运行
- 无控制台窗口启动
- 发布目录只读时仍可写用户数据

这套 portable 发布当前还没有覆盖：

- 安装向导
- 开始菜单快捷方式
- 卸载入口
- 系统级输入法注册

如果后面要给朋友一个更像正式应用的交付物，下一步应是在此基础上再套一层 Inno Setup 安装器。
