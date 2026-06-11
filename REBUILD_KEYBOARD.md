# 键盘布局重建指南

这页只保留比 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md) 多出来的展开说明：重建前检查、安装后验证、失败时优先排查项。

如果你只是要按当前主线最快做完一次打包/安装，直接看前者；标准执行顺序不再在这页重复展开。

补充说明：外部键盘布局仓库默认按主仓库同级目录理解，即 `..\Yime-keyboard-layout`；如果实际位置不同，可先设置 `YIME_KEYBOARD_LAYOUT_REPO`。

## 进入这页前，先看哪几页

1. 最短执行顺序： [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md)
2. 打包前一致性检查： [MSKLC_PRECOMPILE_CHECKLIST.md](MSKLC_PRECOMPILE_CHECKLIST.md)
3. 生成链分层和文件职责： [KEYBOARD_LAYOUT_PIPELINE.md](KEYBOARD_LAYOUT_PIPELINE.md)

## 先理解一个历史命名

- `internal_data/manual_key_layout.json` 仍是当前布局真源。
- 文件名里的 `manual` 只是历史命名，不表示 manual install，也不表示需要走手工编译链路。

## 当前主线只记一个顺序

1. `run_layout_pipeline.py`
2. `run_msklc_packaging_pipeline.py`
3. 在 MSKLC GUI 里执行 `Build DLL and Setup Package`
4. `run_msklc_install_pipeline.py --install-mode msi`

如果只想把布局加入当前用户键盘列表，再运行：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\enable-yinyuan-for-current-user.ps1')
```

## 必要时回滚或清理

回滚当前用户键盘项：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\restore-default-chinese-keyboards.ps1')
```

彻底清理机器级注册：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\unregister-yinyuan-machine.ps1')
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
3. `..\Yime-keyboard-layout\releases\msklc-package\` 是否已经被这次新的 GUI 打包输出覆盖。
4. 是否仍残留旧的机器级注册；有冲突时先运行 `unregister-yinyuan-machine.ps1`。
