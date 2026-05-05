# 键盘布局流程

这份文档只保留当前仍有效的生成链，和 [MSKLC 发布速记](MSKLC_RELEASE_QUICKSTART.md) 保持同一口径。
它的职责是解释生成链各层分工，不是当前键盘布局打包/安装的首选操作入口。

补充说明：外部键盘布局仓库默认按主仓库同级目录理解，即 `..\Yime-keyboard-layout`；如果实际位置不同，可先设置 `YIME_KEYBOARD_LAYOUT_REPO`。

## 设计约束

在阅读本流程前，请先阅读 [码点与中间层策略](CODEPOINT_POLICY.md)。

当前流程依赖四个前提：

1. `N01-N24` 与 `M01-M33` 是语义槽位层，不是可以删除的临时中间结果。
2. `internal_data/manual_key_layout.json` 是历史文件名，当前语义应理解为布局真源，不表示 manual install 或手工编译。
3. 布局真源只负责“物理键位 -> 语义槽位”的关系，不负责决定长期 canonical 码点。
4. Windows 当前发布链统一走 `BMP PUA projection -> yinyuan.klc -> MSKLC GUI -> MSI`，不要再绕回旧的 DLL 直装路径。

## 当前有效的生成链

```text
拼音/音元语义 -> 槽位与字符映射 -> 布局真源 manual_key_layout.json -> yinyuan.klc -> MSKLC 打包输出 -> MSI 安装
```

## 各层职责

### 1. 语义与映射层

- `N01-N24` / `M01-M33`：语义槽位层
- `internal_data/key_to_symbol.json`：槽位到规范字符的映射
- `internal_data/bmp_pua_trial_projection.json`：Windows 当前使用的 BMP PUA 投影

这几层决定字符系统，不应该通过手改安装产物来反向修复。

### 2. 布局真源层

- `internal_data/manual_key_layout.json`

它决定：

- 哪个物理键承载哪个 `Nxx/Mxx`
- Base / Shift / AltGr 各层如何分配

它不决定：

- 具体 DLL 内容
- MSI 内容
- 机器上最终注册状态

### 3. 生成产物层

- `internal_data/manual_key_layout.resolved.json`
- `internal_data/klc_layout_visual_table.md`
- `yinyuan.klc`
- `..\Yime-keyboard-layout\releases\msklc-package\` 下的 MSI、setup、DLL
- `..\Yime-keyboard-layout\releases\msklc-amd64\`、`..\Yime-keyboard-layout\releases\msklc-wow64\` 下的同步 DLL

这些都应重建，不应手工长期维护。

## 标准流程

### 步骤1：从布局真源生成 `yinyuan.klc`

```bash
python tools/run_layout_pipeline.py --on-warning continue --open-msklc never --export-visual-table
```

期望结果：

- 更新 `internal_data/manual_key_layout.resolved.json`
- 更新 `internal_data/klc_layout_visual_table.md`
- 更新 `yinyuan.klc`

### 步骤2：用 MSKLC GUI 打包

```bash
python tools/run_msklc_packaging_pipeline.py
```

然后在 MSKLC 中执行：

1. `File -> Load Source File -> yinyuan.klc`
2. `Project -> Build DLL and Setup Package`

期望结果同步到外部键盘布局仓库：

- `..\Yime-keyboard-layout\releases\msklc-package\`
- `..\Yime-keyboard-layout\releases\msklc-amd64\`
- `..\Yime-keyboard-layout\releases\msklc-wow64\`

### 步骤3：安装 MSI

```bash
python tools/run_msklc_install_pipeline.py --install-mode msi
```

如需把布局加入当前用户键盘列表，再运行：

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\enable-yinyuan-for-current-user.ps1')
```

## 什么时候需要回滚或清理

只保留两种官方清理方式：

1. 回滚当前用户键盘项

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\restore-default-chinese-keyboards.ps1')
```

1. 清理机器级注册和系统 DLL

```powershell
$klcRepo = if ($env:YIME_KEYBOARD_LAYOUT_REPO) { $env:YIME_KEYBOARD_LAYOUT_REPO } else { (Resolve-Path ..\Yime-keyboard-layout).Path }
& (Join-Path $klcRepo 'releases\msklc-package\unregister-yinyuan-machine.ps1')
```

## 不应该再做的事

1. 不要把旧候选 `.klc` 直接复制成正式 `yinyuan.klc`。
2. 不要直接复制 DLL 到系统目录来替代当前 MSI 流程。
3. 不要通过手改 `releases/` 下历史目录来猜测当前发布状态。
4. 不要把 `manual_key_layout.json` 误解成“手工安装流程”的一部分。

## 出问题时优先检查什么

1. 当前 `yinyuan.klc` 是否确实从最新布局真源重新生成。
2. 是否在 MSKLC GUI 里重新执行了 `Build DLL and Setup Package`。
3. `..\Yime-keyboard-layout\releases\msklc-package\` 是否已被这次 GUI 产物完整覆盖。
4. 是否残留旧机器级注册；如有冲突，先运行 `unregister-yinyuan-machine.ps1`。

## 一句话顺序

1. `run_layout_pipeline.py`
2. `run_msklc_packaging_pipeline.py`
3. `run_msklc_install_pipeline.py --install-mode msi`
4. 需要回滚时运行 `restore-default-chinese-keyboards.ps1` 或 `unregister-yinyuan-machine.ps1`
