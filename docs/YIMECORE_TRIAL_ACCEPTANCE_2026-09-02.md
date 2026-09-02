# YimeCore 试验版安装态验收（2026-09-02）

## 结论

提交 `1059d259498aa4b6ae100456e32bac5e179149c1` 的干净 E6-C 包已使用 `Upgrade-YimeCore-Trial.cmd /norestart` 完成当前用户升级。试验版的安装、COM、Runtime/Broker、Word x64 真实输入以及 x64/x86 注册宿主门禁通过，生产 Rime/PIME 注册和安装未改变。

本轮修复了英文模式下 `Shift+字母/符号` 后误切回中文的问题。下文“最终 Rime 对照”记录的是优化前的历史结果，已由后续双轮优化和主流/超前双档复核更新：当前正确性、交互预算和内存预算通过，老旧档退出发布阻塞，E3 仅保留微秒级逐轮比例告警。当前 AMD64 机器仍不能替代真实 ARM64 Windows 桌面宿主；在签名、实体机宿主矩阵和回退演练完成前不得批准 E7 切换，也不得宣称已经独立替换生产 Rime/PIME。

可信签名安装包：签名证书正在申请，等候审批，暂缓相关事项。

## 安装与运行证据

- 安装根：`C:\Program Files\YimeCore Experimental Trial\yimecore-e6c-1059d259498a-c4c2c860`
- 包清单 SHA-256：`c4c2c860c1d0000259a5b0c883100c1566c35bc3525ddbdb9585ef855d115e36`
- Word PID 7200 实际加载：`x64\YimeTextServiceExperiment.dll`
- 已加载 DLL SHA-256：`89c075f86a42f6e8cad8461fd3e86daab7fe8934fc49e40364d28035cdd49913`
- x64/x86 COM 视图均指向同一安装根；Broker PID 13348 的父进程为 `YimeCoreTrialRuntime.exe` PID 32092；包内 Broker 哈希通过。
- staged/install 共 62 个包文件逐项路径、大小和 SHA-256 一致。安装器生成的 `install-metadata.json` 不属于 staged package 清单，单独记录其 SHA-256。
- E6-C 包证据确认 `production_rime_pime_changed=false`、`bare_digit_selection_rules_changed=false`。
- 安装后审计发现当前用户 Run 值仍指向旧根 `yimecore-e6c-d43eb58adca4-b193c545`。已使用 `repair-e6c-trial-autostart.ps1` 收敛到当前根，并立即以 `-ValidateOnly` 读取真实注册表值复核通过；当前 Runtime SHA-256 为 `c54a30cc839b5e3a72692a6b421a29d278e3053fb386049d399f77467f7639e7`。随后 `verify-e6c-trial-runtime.ps1` 完整通过。该偏差已修复，不再是当前 live-host blocker，但以后每次人工升级仍必须执行最终 `-ValidateOnly`，不能只看运行中的进程。

机械证据目录：

- `.tmp/yimecore-experiment/e6c/local-2211-5971/summary.json`
- `.tmp/yimecore-experiment/e6b8/installed-word-20260902-131007/summary.json`
- `.tmp/yimecore-experiment/installed-acceptance/1059d259-20260902/`

## Word x64 新会话验收

Word 启动后先通过 Windows 输入法选择按钮物理选择“Yime 自研栈试验版”；没有修改用户默认输入法。验证结果：

- 裸数字 `2` 建立 composition 并显示候选，没有被当作候选序号直接提交；候选标签显示为 `⇧1` 等。
- 打开 Word File 后台使宿主结束旧 composition，返回文档后再次输入 `2` 能建立新会话；`Shift+1` 提交首项“其”。
- 输入 `tf-cN` 显示“它们/他们/她们”，`Shift+1` 正确提交“它们”。
- 单击 Shift 切到英文后，`Shift+T` 输出 `T`，继续输入 `hey` 没有切回中文；随后 `Shift+1` 输出 `!`，再输入 `a` 仍保持英文。
- 验收文档保存为 `.tmp/yimecore-experiment/installed-acceptance/1059d259-20260902/word-fresh-acceptance.docx`。

Computer Use 不能把 Word 辅助功能树中可见的任务栏输入指示器当作独立任务栏界面输入，且合成 `Alt+Space` 可能打开 Word 系统菜单。这是自动化界面附着限制，不是 Yime/Word 阻塞。物理选择试验输入法已成功；关闭 Word 后，安装态 x64/x86 注册宿主均返回 `registered_language_bar_accepted=true`。不得因为新开 Word 未自动激活试验 TIP 而误报输入法失败，也不得为了自动化通过修改用户默认输入法。

## Shift 与候选键覆盖

- x64/x86 安装 DLL 的 contract 测试通过；契约逐项确认裸 `0` 至 `9` 为 composition 键，只有 `Shift+1` 至 `Shift+9` 映射为候选 ordinal 1 至 9。
- x64/x86 TSF composition 各验证 64 个英文 Shift 组合，覆盖 A-Z、0-9、OEM 标点、导航/控制键以及 Ctrl/Alt 组合；两者均报告 `english_shift_passthrough_chords_verified=64`。
- x64/x86 安装态注册宿主均通过语言栏、候选提交、焦点、鼠标、异步编辑失败恢复及停用后语言栏对象保留门禁。

## 初次最终 Rime 对照（优化前历史结果）

E1 至 E4 的候选、组句、学习、遗忘、持久化和四模块 17,622 条路径正确性通过。以下相对 Rime 的性能/内存门槛失败是当时的基线，不再作为当前结论：

- E1：三模式 p95 比值约 `8.38–10.03`，Working Set 比值约 `1.32–1.77`。
- E2：三模式 p95 比值约 `14.88–30.22`，Working Set 比值约 `1.25–1.56`。
- E3：学习前后 p95 开销比 `1.619`，超过 `1.10` 门槛。
- E4：三模式 p95 比值约 `8.55–13.10`，Working Set 比值约 `1.22–1.60`。

证据位于 `.tmp/yimecore-experiment/final-rime-compare/`。后续优化把无配额 full E1 p95 从 41.50 ms 降至 1.26 ms、E2 从 129.16 ms 降至 6.64 ms；主流/超前双档模拟的正确性、交互和内存预算全部通过。E3 五轮中位数为 full `1.077`、variable `1.090`、shorthand `1.063`，最大绝对 p95 增量 `1.50 µs`；逐轮 `1.10` 未稳定通过只保留告警，不再阻塞原 Go 方案。当前判定以 [YimeCore 主流/超前机台性能剖析、优化与模拟测试](project/YIMECORE_PERFORMANCE_TIERS_2026-09-02.md) 为准。

E7 是否可提出切换由 `run-e7-cutover-readiness.ps1` 统一判定；不能再引用本节旧倍数直接宣称必须改写 C++，也不能因性能优化通过就跳过签名、ARM64/实体机宿主和回退门禁。

## ARM64 与其它限制

- x86、x64、ARM64 构件已打包；PE machine 分别为 `0x014C`、`0x8664`、`0xAA64`。
- 当前主机为 AMD64，不能执行真实 ARM64 Word/TSF 桌面宿主验收。真实 ARM64 Windows 机器是准确的外部宿主门禁；编译和 PE 校验不能替代它。
- Go 全量 `test`、`vet`、`build` 通过。本轮重跑 race 时，CGO 关闭会报 `-race requires cgo`；启用 CGO 后当前 Go 1.26.4/MSYS2 GCC 16.1 环境在 `runtime/cgo` 阶段以 `cgo.exe exit status 2` 失败。这是当前验证环境限制，不能写成本轮 race 已通过。

## 明确暂缓范围

- 可信签名安装包：签名证书正在申请，等候审批，暂缓相关事项。
- 试验版暂不迁移 Rime 的“同步数据/重新部署”入口；联网自动同步、离线手动同步 UI 等到试验版通过独立替换门禁并进入独立版本后再设计。
- 语境音变继续保持为独立、可删除、带来源的词/短语级输入别名方案；在独立替换是否成立前不接入运行时，不改写规范词典读音和基础音节编码。
