# Windows KLC Workflow

日期：2026-04-10

这份短文档只保留当前有效的最小流程：布局真源生成 `.klc`、MSKLC GUI 打包、MSI 安装、必要时清理机器状态。

## 先理解一个历史命名

- `internal_data/manual_key_layout.json` 仍是当前布局真源。
- 文件名里的 `manual` 是历史命名，不表示 manual install，也不表示需要走手工编译链路。

## 推荐顺序

### 步骤 1：运行 `tools/run_layout_pipeline.py`

作用：

- 检查布局侧与运行时私用区字符生成侧是否一致
- resolve 布局真源
- 生成 `yinyuan.klc`
- 导出可视化表格

推荐命令：

```bash
python tools/run_layout_pipeline.py --on-warning continue --open-msklc never --export-visual-table
```

### 步骤 2：运行 `tools/run_msklc_packaging_pipeline.py`

作用：

- 以已经生成好的 `yinyuan.klc` 为输入
- 提示你在 GUI 里执行 `Build DLL and Setup Package`
- 检测 GUI 打包输出目录
- 把输出同步回 `releases/msklc-package/`、`releases/msklc-amd64/`、`releases/msklc-wow64/`

推荐命令：

```bash
python tools/run_msklc_packaging_pipeline.py
```

然后在 MSKLC 中执行：

1. `File -> Load Source File -> yinyuan.klc`
2. `Project -> Build DLL and Setup Package`

### 步骤 3：运行 `tools/run_msklc_install_pipeline.py`

作用：

- 用 `releases/msklc-package/` 里的产物执行安装阶段
- 支持 `auto` / `msi` 两种模式
- 安装统一走 MSKLC 生成的 MSI 产物
- 可选把 Yinyuan 加到当前用户键盘项里

推荐命令：

```bash
python tools/run_msklc_install_pipeline.py --install-mode msi
```

### 步骤 4：需要重装前清理时，运行 `tools/reset_msklc_install_state.py`

作用：

- 清掉旧的 HKLM 注册
- 清掉旧 DLL
- 恢复当前用户默认中文键盘状态
- 可选清理临时安装目录

推荐命令：

```bash
python tools/reset_msklc_install_state.py
```

## 可选的当前用户启用与回滚

把 Yinyuan 作为单独键盘项加入当前用户：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File releases\msklc-package\enable-yinyuan-for-current-user.ps1
```

恢复默认中文键盘：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File releases\msklc-package\restore-default-chinese-keyboards.ps1
```

彻底清理机器级注册：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File releases\msklc-package\unregister-yinyuan-machine.ps1
```

## 一句话顺序

- `run_layout_pipeline.py`：先把 `.klc` 生对
- `run_msklc_packaging_pipeline.py`：再把 MSKLC 打包产物整理好
- `run_msklc_install_pipeline.py`：最后再装进系统
- `reset_msklc_install_state.py`：需要重来时，把机器状态清干净
