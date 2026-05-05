# 安装包发布指南

这份指南对应当前比 portable 目录更像“给朋友发安装包”的发布形态：

- 先用 PyInstaller 生成 `dist/Yime/`
- 再用 Inno Setup 把它包成一个 `Setup.exe`
- 安装后会在开始菜单创建启动入口，可选创建桌面快捷方式

说明：

- 这仍然是“Windows 桌面输入法原型应用”，不是系统级 TSF 输入法安装包。
- 程序运行后的用户数据默认写到 `%LOCALAPPDATA%/Yime/user_lexicon.db`，不写回安装目录。

## 先决条件

1. Python 环境里已能执行 portable 构建。
2. 本机已安装 Inno Setup 6。

当前仓库约定的编译器优先级是：

1. 环境变量 `ISCC`
2. `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`
3. `C:\Program Files\Inno Setup 6\ISCC.exe`

如果你的 `ISCC.exe` 在别处，先手动设置：

```bat
set ISCC=C:\path\to\ISCC.exe
```

## 构建命令

仓库已提供：

- `scripts/build_setup_release.bat`
- `yime_setup.iss`

最短路径：

```bat
scripts\build_setup_release.bat
```

它会自动：

1. 从 `pyproject.toml` 读取版本号。
2. 先重建 `dist/Yime/` portable 目录。
3. 调用 Inno Setup 生成安装包。

## 构建结果

成功后产物位于：

- `dist/setup/Yime-Setup-<version>.exe`

例如当前版本 `0.1.0` 时，文件名会是：

- `dist/setup/Yime-Setup-0.1.0.exe`

## 建议验收

发包前至少做这几步：

1. 卸载本机旧的安装版，避免误判升级行为。
2. 双击新的 `Setup.exe`，走完安装向导。
3. 从开始菜单启动，确认待命图标能出现。
4. 验证 hotkey 模式可唤起候选框。
5. 加一条用户词库，确认 `%LOCALAPPDATA%/Yime/user_lexicon.db` 已生成。
6. 卸载后确认应用目录被移除，用户数据是否保留符合你的预期。

如果你现在的目标不是“正式发布”，而只是先发给朋友试装，优先直接照着：

- `friend-trial-checklist.md`
- `friend-trial-message-template.md`
- `friend-trial-one-page.md`

前者只保留试装前最值钱的一轮检查；第二份是一段可以直接发给朋友的说明模板；第三份是一页给试用者看的最小操作说明与键位对照。

## 当前边界

这套 setup 发布当前解决的是：

- 给朋友一个标准的 `Setup.exe`
- 安装目录、开始菜单入口、卸载入口
- 与 portable 发布共用同一套可执行文件目录

这套 setup 发布当前还没有覆盖：

- 自动检查更新
- 数字签名
- 系统级输入法注册
- 安装期间迁移旧用户数据

如果后面要继续往“更像正式产品”的方向推，下一步最值钱的是给 `Setup.exe` 做数字签名，以及补一条升级安装验证清单。
