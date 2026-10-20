# Windows 桌面触摸键盘：18u 完整中文便携包

P1–P4 已随 #71–#73 合并。P5 提供包内完整三模式词典、私有字体、盘面、默认中文启动入口和资源身份校验。18u 主区为唯一主动开发基准，17u / 23u 仍冻结。安装、默认输入法和用户词库不属于此实验的修改范围。

## 使用

P6 验收准备已完成。使用[18u 本机执行说明](ACCEPTANCE_18U.zh-CN.md)固定的 #74 CI 包，按其中结果模板分别记录真人手指、触控笔和真实应用；当前尚无该包的真人通过结论。

完整解压匹配架构的 CI 包，双击 `Start Keyboard.cmd` 或 exe。默认 18u、100 键、342.90 mm，先在目标文本区放置光标，再点“绑定目标”。完整步骤见[中文指南](USER_GUIDE.zh-CN.md)。

`Start Preview.cmd` 只写窗口内文本；`Start English Only.cmd` 保留旧英文入口。原全盘和左右区域提供同源中文入口，冻结的 17u / 23u 启动器保持旧英文行为。旧 CI 英文包不追溯升级。

程序从自身目录解析全部资源，与当前工作目录无关，不需要源码 checkout、开发工具、网络或已安装产品。启动时验证编译绑定的 `resources.json` 与资源 SHA-256；词典还由共享 `keyboardlab` 验证投影和模式身份。缺失、篡改、混包或指定外部 root/data 时直接失败，不搜索其他目录。哈希只用于身份和完整性，不等于签名。

```text
YimeTouchKeyboard.exe --check-package --data-report package-check.json
YimeTouchKeyboard.exe --preview
YimeTouchKeyboard.exe --english-only
YimeTouchKeyboard.exe --screen-width-mm 597.73 --ruler-observed-mm 98.5
```

`--check-package` 不开窗口、不发送 OS 输入：验证所有资源并在三模式内存会话中，从包内 canonical ID 表和实验投影派生 ni3，再确认“你”。正常退出清理临时索引；强制终止可能留下本程序临时目录，不宣称崩溃清理已完成。

所有中文宿主发送沿用 P4 显式绑定、世代失效和失败停止规则。SendInput 不能原子绑定 HWND；发送计数不是实际宿主接受。手指、笔、真实应用和 ARM64 原生结果须分别观察。

## 构建与 CI 输入

唯一可编辑编码源仍为实验室 `encoding/manual_key_layout.json`。词典来自既有完整隔离派生数据，不修改或借用产品字典。`resources.lock.json` 固定一个本仓库 prerelease 的派生词典 ZIP：归档大小/哈希、每文件大小/哈希、原始数据身份、投影和来源提交均可追踪。CI 不读取外部原始数据库，也不导入其他 Git 仓库数据。

```text
python -X utf8 tools/touch_keyboard_resources.py fetch --output-dir .generated/touch-keyboard-resources
python -X utf8 tools/build_touch_keyboard_desktop.py --output-dir .generated/touch-keyboard-new
python -X utf8 tools/check_touch_keyboard_package.py --package .generated/touch-keyboard-new --report .generated/touch-keyboard-check/package-check.json
python -X utf8 tools/build_touch_keyboard_desktop.py --arch arm64 --output-dir .generated/touch-keyboard-new-arm64
```

构建输出必须是 `.generated/` 下的新空目录，避免混入旧包。资源恢复可重复执行，但发现旧文件哈希不同会拒绝覆盖。离线时可给 fetch 加 `--archive <已核对的 ZIP>`。只有构建机下载资源需要 GitHub CLI，最终包不需要。

资源更新需按既有 canonical 链重新派生、验证并创建新 tag/asset/锁，不替换当前固定资源。当前归档包含三份完整主词典（已合入既有 reviewed overlays）及原实验清单；不包含原始数据库或用户词库。

`.github/workflows/touch-terminal.yml` 获取并验证锁定资源，构建 x64，复制到仓库外含中文/空格的临时路径，从空 cwd 执行三模式及损坏/缺失/外部资源拒绝检查，再交叉构建 ARM64。CI 上传两个完整包和独立验证报告。

`manifest.json` 记录源码、dirty 状态、架构、CI run、资源归档和包内文件 SHA-256；GitHub artifact ZIP 哈希以对应 PR 交付记录为准。ARM64 的构建成功不得标作原生执行或硬件验收。

## 本地受控原生检查

```text
python -X utf8 tools/check_touch_keyboard_package.py --package .generated/touch-keyboard-new --report .generated/touch-keyboard-check/package-check.json --render --native-edit
```

这会在临时副本中渲染预览并运行自有 EDIT 测试。目标提供器在全部恢复绑定期间限制为该测试自己的窗口；若未取得前台则失败，不给其他应用发送。结果是开发证据，不是手指、笔或 Word/记事本验收。CI 默认不运行有输入的自检。

## 源码开发入口

源码构建仍要求显式 root 和完整实验 data-dir，与便携构建的自身目录默认行为不同：

```text
go -C go-backend run ./cmd/yime-touch-keyboard --root .. --numeric-zones none --remove-gutters --preview --data-dir ../.generated/ascii-keyboard-134/data
go -C go-backend run ./cmd/yime-touch-keyboard --root .. --numeric-zones none --remove-gutters --host-input --data-dir ../.generated/ascii-keyboard-134/data
go -C go-backend test ./cmd/yime-touch-keyboard ./internal/touchkeyboard ./internal/keyboardlab ./cmd/yime-keyboard-lab ./internal/asciicodemode ./input_methods/yime/codemode
```

主区固定 18u；原全盘 24.75u，保留一侧 21u。显示换算与几何分别处理，不自动缩键。17u/23u 来源、配置和回归保持原样；没有实施未定义的“缩短 1 毫米”。详细阶段和待记录项见[计划](DEVELOPMENT_PLAN_18U.md)与[交接](HANDOFF.md)。
