# Windows KLC Workflow

日期：2026-04-10

这份短文档只回答一个问题：现在在 Windows 上处理音元布局时，脚本应该按什么顺序运行。

## 推荐顺序

1. 先运行 `tools/run_layout_pipeline.py`

作用：

- 检查布局侧与运行时私用区字符生成侧是否一致
- resolve 手工布局
- 生成 `yinyuan.klc`
- 可选导出可视化表格
- 可选打开 `MSKLC.exe`

推荐命令：

```bash
"c:/Users/Freeman Golden/OneDrive/Yime/.venv/Scripts/python.exe" tools/run_layout_pipeline.py --on-warning continue --open-msklc ask
```

1. 再运行 `tools/run_msklc_packaging_pipeline.py`

作用：

- 以已经生成好的 `yinyuan.klc` 为输入
- 可选打开 MSKLC
- 提示你在 GUI 里执行 `Build DLL and Setup Package`
- 检测 GUI 打包输出目录
- 把输出同步回 `releases/msklc-package/`、`releases/msklc-amd64/`、`releases/msklc-wow64/`

推荐命令：

```bash
"c:/Users/Freeman Golden/OneDrive/Yime/.venv/Scripts/python.exe" tools/run_msklc_packaging_pipeline.py
```

1. 最后运行 `tools/run_msklc_install_pipeline.py`

作用：

- 用 `releases/msklc-package/` 里的产物执行安装阶段
- 支持 `auto` / `msi` / `manual` 三种安装模式
- MSI 失败时可以自动回退到 manual install
- 可选把 Yinyuan 加到当前用户键盘项里

推荐命令：

```bash
"c:/Users/Freeman Golden/OneDrive/Yime/.venv/Scripts/python.exe" tools/run_msklc_install_pipeline.py --install-mode auto
```

1. 如需在重装前清理旧状态，再运行 `tools/reset_msklc_install_state.py`

作用：

- 清掉旧的 HKLM 注册
- 清掉旧 DLL
- 恢复当前用户默认中文键盘状态
- 可选清理临时安装目录

推荐命令：

```bash
"c:/Users/Freeman Golden/OneDrive/Yime/.venv/Scripts/python.exe" tools/reset_msklc_install_state.py
```

## 一句话记忆

- `run_layout_pipeline.py`：先把 `.klc` 生对
- `run_msklc_packaging_pipeline.py`：再把 MSKLC 打包产物整理好
- `run_msklc_install_pipeline.py`：最后再装进系统
- `reset_msklc_install_state.py`：需要重来时，把机器状态清干净

## 为什么先写这份文档

因为现在前三段流程已经稳定分层：

- 生成阶段
- 打包阶段
- 安装阶段

现在第 4 个脚本也已经独立出来，所以生成、打包、安装、重置四段边界都已经明确，不需要把错误恢复逻辑塞回前 3 个脚本里。

## 第 4 个脚本

独立的清理 / 重装脚本是：

- `tools/reset_msklc_install_state.py`

它应该只负责：

- 清掉旧的 HKLM 注册
- 清掉旧 DLL
- 清理当前用户键盘引用
- 为重新编译或重新安装恢复干净环境

它不应和“打包阶段”或“安装阶段”混在一个脚本里。
