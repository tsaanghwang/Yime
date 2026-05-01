# Windows KLC Workflow

日期：2026-04-10

这页不再重复完整操作链。当前主入口应以 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md) 为准；这页只保留分流关系和少数需要额外记住的清理入口。

补充说明：外部键盘布局仓库默认按主仓库同级目录理解，即 `..\Yime-keyboard-layout`；如果实际位置不同，可先设置 `YIME_KEYBOARD_LAYOUT_REPO`。

## 文档分工

- 最短操作入口： [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)
- 打包前检查单： [MSKLC_PRECOMPILE_CHECKLIST.md](MSKLC_PRECOMPILE_CHECKLIST.md)
- 展开版重建说明： [REBUILD_KEYBOARD.md](REBUILD_KEYBOARD.md)
- 生成链分层解释： [KEYBOARD_LAYOUT_PIPELINE.md](KEYBOARD_LAYOUT_PIPELINE.md)

## 当前最小顺序

1. 运行 `python tools/run_layout_pipeline.py --on-warning continue --open-msklc never --export-visual-table`
2. 运行 `python tools/run_msklc_packaging_pipeline.py`
3. 在 MSKLC GUI 中执行 `Build DLL and Setup Package`
4. 运行 `python tools/run_msklc_install_pipeline.py --install-mode msi`

如果只是正常走一遍当前发布链，到这里就够了。更细的前置检查、产物分层和回滚说明请分别看上面的配套页。

## 什么时候需要额外看这页

- 你需要记住“先看哪一页，再看哪一页”时。
- 你需要完整清理机器级安装残留时。
- 你需要把当前用户键盘项回滚到默认状态时。

## 当前用户启用与回滚

把 Yinyuan 作为单独键盘项加入当前用户：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\enable-yinyuan-for-current-user.ps1')
```

恢复默认中文键盘：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\restore-default-chinese-keyboards.ps1')
```

## 机器级清理入口

需要彻底清理 HKLM 注册项、系统 DLL 和旧名字冲突时，优先运行：

```bash
python tools/reset_msklc_install_state.py
```

如需直接调用外部仓库里的脚本：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\unregister-yinyuan-machine.ps1')
```

## 一句话定位

- 想最快做完：看 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)
- 想先排错再打包：看 [MSKLC_PRECOMPILE_CHECKLIST.md](MSKLC_PRECOMPILE_CHECKLIST.md)
- 想理解为什么文件要这样分层：看 [KEYBOARD_LAYOUT_PIPELINE.md](KEYBOARD_LAYOUT_PIPELINE.md)
- 想完整重走一遍并逐项核对：看 [REBUILD_KEYBOARD.md](REBUILD_KEYBOARD.md)

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
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\enable-yinyuan-for-current-user.ps1')
```

恢复默认中文键盘：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\restore-default-chinese-keyboards.ps1')
```

彻底清理机器级注册：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\unregister-yinyuan-machine.ps1')
```

## 一句话顺序

- `run_layout_pipeline.py`：先把 `.klc` 生对
- `run_msklc_packaging_pipeline.py`：再把 MSKLC 打包产物整理好
- `run_msklc_install_pipeline.py`：最后再装进系统
- `reset_msklc_install_state.py`：需要重来时，把机器状态清干净
