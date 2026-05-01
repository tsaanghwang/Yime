# 键盘布局重建指南

这页保留当前有效的重建路径：布局真源生成 `.klc`、MSKLC GUI 打包、MSI 安装、必要时回滚。

更短的版本见 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)。

## 先理解一个历史命名

- `internal_data/manual_key_layout.json` 仍是当前布局真源。
- 文件名里的 `manual` 只是历史命名，不表示 manual install，也不表示需要走手工编译链路。

## 标准重建流程

### 1. 从布局真源生成 `yinyuan.klc`

```bash
python tools/run_layout_pipeline.py --on-warning continue --open-msklc never --export-visual-table
```

期望结果：

- 更新 `internal_data/manual_key_layout.resolved.json`
- 更新 `internal_data/klc_layout_visual_table.md`
- 更新 `yinyuan.klc`

### 2. 用 MSKLC GUI 打包 DLL 和安装包

```bash
python tools/run_msklc_packaging_pipeline.py
```

然后在 MSKLC 中执行：

1. `File -> Load Source File -> yinyuan.klc`
2. `Project -> Build DLL and Setup Package`

期望结果同步到外部键盘布局仓库：

- `C:/dev/Yime-keyboard-layout/releases/msklc-package/`
- `C:/dev/Yime-keyboard-layout/releases/msklc-amd64/`
- `C:/dev/Yime-keyboard-layout/releases/msklc-wow64/`

### 3. 安装 MSI

```bash
python tools/run_msklc_install_pipeline.py --install-mode msi
```

如果只想把布局加入当前用户键盘列表，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\Yime-keyboard-layout\releases\msklc-package\enable-yinyuan-for-current-user.ps1
```

### 4. 必要时回滚或清理

回滚当前用户键盘项：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\Yime-keyboard-layout\releases\msklc-package\restore-default-chinese-keyboards.ps1
```

彻底清理机器级注册：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\dev\Yime-keyboard-layout\releases\msklc-package\unregister-yinyuan-machine.ps1
```

## 重建前的最小检查

1. 确认布局真源 `internal_data/manual_key_layout.json` 已是你要发布的版本。
2. 先跑 [MSKLC_PRECOMPILE_CHECKLIST.md](MSKLC_PRECOMPILE_CHECKLIST.md) 里的检查。
3. 不要手改最终 `yinyuan.klc` 的空行、编码或记录顺序。
4. 不要把旧候选 `.klc` 或旧目录里的 DLL 直接复制成最终发布产物。

## 安装成功后的验证

1. `Win + Space` 能看到 `Chinese (Simplified) - Yinyuan`。
2. “设置 -> 时间和语言 -> 语言和区域 -> 中文（简体） -> 选项”里能看到 Yinyuan。
3. 需要时注销并重新登录一次，让 Text Services Framework 刷新。

## 失败时优先检查什么

1. 是否真的从当前布局真源重新生成了 `yinyuan.klc`。
2. 是否在 MSKLC 里重新执行了 `Build DLL and Setup Package`。
3. `C:/dev/Yime-keyboard-layout/releases/msklc-package/` 是否已经被这次新的 GUI 打包输出覆盖。
4. 是否仍残留旧的机器级注册；有冲突时先运行 `unregister-yinyuan-machine.ps1`。

## 一句话顺序

1. `run_layout_pipeline.py`
2. `run_msklc_packaging_pipeline.py`
3. `run_msklc_install_pipeline.py --install-mode msi`
4. 需要回滚时运行 `restore-default-chinese-keyboards.ps1` 或 `unregister-yinyuan-machine.ps1`
