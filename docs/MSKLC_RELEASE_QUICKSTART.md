# MSKLC 发布速记

这页只保留当前可用的最短路径：生成 `.klc`、用 MSKLC 打包、用 MSI 安装、必要时回滚。

补充说明：外部键盘布局仓库默认按主仓库同级目录理解，即 `..\Yime-keyboard-layout`；如果实际位置不同，可先设置 `YIME_KEYBOARD_LAYOUT_REPO`，再运行下面这些包装脚本。

## 0. 先理解一个历史命名

- `internal_data/manual_key_layout.json` 仍是当前布局真源。
- 文件名里的 `manual` 只是历史命名，不表示 manual install，也不表示现在要走手工编译链路。

## 1. 生成正式的 `yinyuan.klc`

```bash
python tools/run_layout_pipeline.py --on-warning continue --open-msklc never --export-visual-table
```

期望结果：

- 更新 `internal_data/manual_key_layout.resolved.json`
- 更新 `internal_data/klc_layout_visual_table.md`
- 更新 `yinyuan.klc`

## 2. 用 MSKLC GUI 打包

```bash
python tools/run_msklc_packaging_pipeline.py
```

说明：主仓库里的这个命令现在只是转发到外部 `Yime-keyboard-layout` 仓库中的同名脚本。

然后在 MSKLC 里执行：

1. `File -> Load Source File -> yinyuan.klc`
2. `Project -> Build DLL and Setup Package`

期望结果同步到外部键盘布局仓库：

- `..\Yime-keyboard-layout\releases\msklc-package\`
- `..\Yime-keyboard-layout\releases\msklc-amd64\`
- `..\Yime-keyboard-layout\releases\msklc-wow64\`

## 3. 用 MSI 安装

```bash
python tools/run_msklc_install_pipeline.py --install-mode msi
```

如需把布局加入当前用户键盘列表，再运行：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\enable-yinyuan-for-current-user.ps1')
```

## 4. 回滚当前用户键盘项

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\restore-default-chinese-keyboards.ps1')
```

## 5. 彻底清理机器级注册

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\unregister-yinyuan-machine.ps1')
```

用途：

- 重新编译前清理旧名字/旧描述冲突
- 删除 HKLM 下的 Yinyuan 注册项和系统 DLL

## 6. 一句话顺序

1. `run_layout_pipeline.py`
2. `run_msklc_packaging_pipeline.py`
3. `run_msklc_install_pipeline.py --install-mode msi`
4. 需要回滚时运行 `restore-default-chinese-keyboards.ps1` 或 `unregister-yinyuan-machine.ps1`
