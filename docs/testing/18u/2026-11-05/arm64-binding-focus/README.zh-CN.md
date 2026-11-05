# ASUS 18u Broker 路径：正文焦点线程修复

2026-11-05。本轮修复独立 ARM64 安装版路径的跨线程正文兼容性及绑定错误透传。基线为 `8264e76eb5b7475c64015672717b1958575cb883`，分支为 `codex/18u-binding-diagnostics-20261105`。这是源码与隔离开发验证，不是已安装版本或 ASUS 记事本通过记录。

固定源码提交 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1` 已推送，四条 CI 全部成功：21 个任务成功、3 个既有手动任务跳过、0 失败。见 [CI 回执](ci-receipt.json)、[总构建](https://github.com/tsaanghwang/Yime/actions/runs/42040885767)、[ARM64 完整输入合同](https://github.com/tsaanghwang/Yime/actions/runs/42040885096)、[18u 异步合同](https://github.com/tsaanghwang/Yime/actions/runs/42040885140)及[触摸原型](https://github.com/tsaanghwang/Yime/actions/runs/42040885143)。CI 包含完整三模式资源、Go 竞态、真实 Rime、x64/ARM64 编译及隔离异步检查；编译不等于目标机安装。后续本目录更新只记录此固定源码的结果。

## 当前问题与主线对照

ASUS `.4` 的最新真人结果仍是无法绑定，见[原始汇总](../../2026-11-04/cross-machine-binding/README.zh-CN.md)。本轮更新远端后确认 main 已到 `36ca828b`，MSI 的 Direct TIP 路径已整合；[MSI test.8 后续记录](https://github.com/tsaanghwang/Yime/blob/36ca828b/docs/testing/18u/2026-11-04/msi-test8-upgrade/BINDING-FOLLOWUP.zh-CN.md)报告重开记事本后可绑定和输入，不能继续把 MSI 写为当前仍失败。两条实现不能直接互换载荷。

ASUS 路径存在三个确定的源码限制：`InstalledTouchFrontend` 发现、`DedicatedTouchRoute` 绑定/实际编辑、Go Broker 前台校验都要求顶层 HWND 的线程等于 TIP 线程。正文控件与顶层窗口线程不同的宿主会被拒绝。MSI 主线已有相应窗口结构的记录，但 ASUS 当次失败缺少线程快照，所以本轮不能将其追认为 ASUS 首次失败的唯一根因。

## 修复行为

- 三层统一使用 `GetGUIThreadInfo(0)` 的正文焦点 HWND/TID，保留顶层 HWND、`GA_ROOT` 祖先及两者的 PID 校验，并在查询结束时再次核对前台窗口。顶层和正文允许分属不同线程。
- TIP 与 Broker 租约均保存精确正文 HWND。正文控件、祖先、进程或线程变化时拒绝旧操作；实际 `DoEditSession` 仍复核原 TSF context 和世代，焦点回来不恢复已撤销租约。
- TIP 轮询新增必填 `focus`，旧轮询被拒绝，完成回执不能携带该字段。**后续必须交付同源完整包；不能单独替换 DLL、Broker 或 GUI。**
- Broker 区分 `no-tip-peer`、`no-active-lease`、`foreground-mismatch`、`ambiguous-tip`。GUI 保留收到的底层错误，区分 TIP 拒绝、无效 JSON、身份不符和无效快照；错误文字限制为单行 512 个字符。错误不授予租约、不输出正文、不自动重放。

## 本地验证

机器为原生 Windows ARM64，Go 1.25.14、MSVC 19.44。结果及原始字节索引见 [validation.json](validation.json) 和 [raw/manifest.json](raw/manifest.json)。

| 检查 | 结果与边界 |
| --- | --- |
| 旧源码诊断回归 | 用进程局部 Go overlay 仅加入新测试，不修改旧分支；旧源码确实丢失绑定、TIP 拒绝/格式/身份、操作失败原因 |
| 四个相关 Go 包 | 357 个测试/子测试通过，0 失败，3 个完整词库用例因未提供显式资源目录跳过 |
| 原生 DedicatedAsync | 17 组通过；新增正文线程查询及精确控件变化负例，含六种延迟编辑拒绝条件 |
| 标准产品 FocusCancellation | 36 条检查，0 失败；替身 TSF |
| 专用 DLL 激活 | 生命周期、身份、线程和五种失败路径通过；独立新 DLL、替身 TSF |
| 原生构建 | 专用 DLL、标准 DLL和三个测试程序均构建成功；既有 `TextService.cpp` C4702/C4100 警告保留 |
| 诊断静态合同 | `tools/yimecore/test_input_abort_diagnostic_contract.py` 5 项通过 |
| 独立审阅 | 未发现新增阻断性问题；诊断限制见下文 |

相关 Go 命令：

```text
go test ./cmd/yime-touch-keyboard ./internal/touchbroker ./internal/touchhostbridge ./internal/installed18uhost -count=1 -json
```

原生配置、构建与隔离测试：

```text
cmake -S YimeTextServiceExperiment -B .generated/binding-native -G "Visual Studio 17 2022" -A ARM64 -DYIME_TOUCH_PRODUCT=ON
cmake --build .generated/binding-native --config Release --target YimeDedicatedAsyncTests YimeFocusCancellationTests YimeTextService18u YimeTextServiceExperiment YimeDedicatedActivationTests
YimeDedicatedAsyncTests.exe
YimeFocusCancellationTests.exe
YimeDedicatedActivationTests.exe <本轮隔离 YimeTextService18u.dll 的绝对路径>
```

## 未完成项与接续

没有执行安装、输入法注册、真实应用输入或真人手指/笔复测。标准 YimeCore、Rime/PIME、默认输入法、用户数据、键位及词典未更改；ASUS `.4` 的历史失败原样保留。跨线程回归使用 Win32 API/TSF 替身，不能登记为现代记事本实测。

诊断仅改善已返回错误的透传和绑定筛选阶段。`DedicatedTouchRoute::Failed` 尚未返回详细错误字段，部分原生失败只能显示阶段性通用提示；界面错误未持久保存，最小化等操作仍可能覆盖提示。未声称所有 HRESULT 已贯通或日志持久化问题已解决。

源码 CI 已通过；接续交付同源完整 ARM64 安装包。现有 CI 下载项仅为预览包或构建/测试证据，不能当作安装包单独替换组件。真实应用复测须使用完整包和明确的新安装记录；一次复测记录精确版本、正文与顶层 HWND/TID、完整绑定提示及实际正文。已有实体尺 100 mm 结果无需重复，MSI 已通过的 test.8 步骤也不自动重做。
