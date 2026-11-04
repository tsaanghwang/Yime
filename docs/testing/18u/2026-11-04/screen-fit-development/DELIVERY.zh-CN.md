# test.9 完整包：启动自动适应屏幕

日期：2026-11-04。固定源码 `785724e8b0ed62f15994ed96da774b7a2b1c779b`，分支 `codex/msi-18u-test-preparation-20261103`。实现提交 `6ce2d25a`，CI 屏幕尺寸测试修正 `785724e8`。

安装版默认在当前屏幕工作区等比尽量放大，含候选与控制栏，靠底居中、避开任务栏；设置新增“适应屏幕”。分辨率／DPI／工作区变化或跨屏移动结束后重新适配。手动毫米校准独立，手动校准可切回实测尺寸。见[开发与验证](DEVELOPMENT.zh-CN.md)及[操作说明](../../../../../prototypes/touch-terminal/desktop/INSTALLED_TSF.zh-CN.md)。

## 下载

[完整 test.9 GitHub Artifact](https://github.com/tsaanghwang/Yime/actions/runs/41791202363/artifacts/13302979732)，名称 `installed-18u-x64-test-package-785724e8b0ed62f15994ed96da774b7a2b1c779b`，保留至 `2026-11-18T07:22:06Z`。外层 ZIP 仅包含下面的产品 ZIP。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| Artifact 外层 ZIP | 192202748 | `47ae8479188fb6ffca1eccdbde3829dae42a6f1938bc729ee4586b7853e59374` |
| `YimeCore-18u-0.1.0-18u-test.9-windows-amd64.zip` | 192163821 | `126b998ad1be899846cb7b2c8b748abc7e76ed8a1b9392bf8fb7aa2e3df18d11` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7882752 | `cea71a987081c3ac25dab8ef6fb9756e2408ce09aff930ba3f1b88f6d4ffd6c5` |

本机已下载到 `C:/dev/Yime/.generated/screen-fit-development/YimeCore-18u-0.1.0-18u-test.9-windows-amd64.zip`，按同源包证据逐项核验 46 个成员。详见[下载核验](download-verification.json)、[包证据](ci-785724e8/package-evidence.json)、[原始回执](ci-785724e8/package-receipt.json)和[证据哈希](evidence-index.json)。该路径是本机位置，公开交付以上方 Artifact 为准。未执行包内程序或安装脚本。

## 验证

- [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/41791202397)：success。
- [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/41791202363)：success。
- [Build](https://github.com/tsaanghwang/Yime/actions/runs/41791202460)：success。

本地完整前端／TSF 客户端／touchkeyboard 回归、7 项前端包装器检查、完整前端构建通过；六种工作区尺寸及实际隐藏 Win32 窗口位置检查通过。原生离屏盘面、九候选和设置已检查，当前屏幕渲染为 2880 × 1103 px，宽度占满可用工作区，保留盘面原比例。证据见[本地验证](local-validation.json)及[CI 环境修正复验](ci-correction.json)。首次 CI 失败记录保留于开发说明，不追认为通过。

## 本机接续

当前安装仍为 test.8。用户已确认重启后选择输入法、绑定和声音正常；本次源码与制包工作未更换已安装文件、默认输入法或用户数据。test.9 的自动适配尚未获得本机安装后实测结论。

本包供后续正常维护升级使用，须使用完整匹配包，不单独覆盖 EXE。维护后只需观察启动盘面是否自动铺满可用宽度且无裁切；必要时点“设置→适应屏幕”。新版本的字号与触点仍以用户实际体验为准，不要求重复已经成功的安装／重启／自有宿主验收。
