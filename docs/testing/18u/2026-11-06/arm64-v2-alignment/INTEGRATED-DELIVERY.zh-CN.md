# ASUS ARM64 .7 最终整合交付

**后续候选已更换：**本页 `.7` 受已知 Broker 启动缺陷影响，仅保留为历史交付及现场归档的身份依据，不作为新一轮验收候选或默认恢复目标。已修复的固定 `.8`（源码 `ac326cba…`、run `42185512418` attempt 2、Artifact `13487852082`）及两层哈希、ASUS 前态重确认和接续范围见[`.8` 验收接续稿](ASUS-ACCEPTANCE.zh-CN.md)。本次仅修订文档，不执行维护或测试，不解除 ARM7-UI-01 的暂停决定；下方原始身份、证据及结果保持。

**后续现场结果：**固定包已在华硕正常升级到 `.7`，本轮部分真实宿主验证及高度遮挡待处理项已[单独归档](ASUS-UPGRADE-RESULT.zh-CN.md)。本页保留交付时的检查与待执行状态；下文“未安装／NOT_RUN”仅描述交付阶段，不覆盖后续结果。归档不改变固定包身份，也不要求重复升级或已通过项目。

**本页交付为 `.7`，固定源码 `9636eaffef79d57e6eb1005101ba81a9a70f8130`。** 共享前端/TIP v2、ARM64 安装合同和完整包已完成；9 项 CI 及实际下载核验全部通过。交付时华硕仍安装原 `.5`，该交付阶段没有执行升级、卸载、产品注册或真实宿主/手指/笔验收。

## 来源与变更

[PR #113](https://github.com/tsaanghwang/Yime/pull/113)，分支 `codex/18u-arm64-frontend-v2-20261106`。从固定 main `39bfc4a3` 开发后，兼容合入 `45be140e528c4a4e818a2bca6717f187a0fcd2b5`（PR #114）的共享私有字体生命周期及检查宿主注册表长度修复。新版本升为 `0.2.0-18u-arm64.7`，不覆盖已固定的 [`.6` 交付](DELIVERY.zh-CN.md)或其哈希。后续交付文档提交不改变包的源码身份，不使用随后自动生成的同名产物替代它。

影响产品仅为独立 `yimecore-18u`。共享屏幕适应、翻页位置、自动跟随和暂停交互保持主线实现；五份盘面/编码资源、18u 几何与标准产品数据不变。ARM 原生前端与 TIP 直连 v2；新安装清单仍为九字段 `installed-18u-product-v1`，不能与通信协议版本混淆。旧 `.5` 清单只用于严格维护，不放宽新注册/前端的来源和架构校验。

## 固定完整包

[下载 ARM64 完整包 artifact](https://github.com/tsaanghwang/Yime/actions/runs/42174743553/artifacts/13483101764)，来自 [push run 42174743553](https://github.com/tsaanghwang/Yime/actions/runs/42174743553)，artifact ID `13483101764`。外层 ZIP 内只有一个完整安装 ZIP；源码 ZIP 和 x64 包不代替它。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| GitHub artifact 外层 ZIP | 190632448 | `ed9e9103a162b49768985d659b35c0229eba42e07b5d3a719417962a5ecc6bd6` |
| `YimeCore-18u-0.2.0-18u-arm64.7-windows-arm64.zip` | 190591694 | `78f4492c561bf91d81adab5d2ddb1a07ab6bee5fcbab6416359b44bcfeb1bfc9` |
| `payload/installed-18u-product.json` | 7397 | `44b995fcd56f3c96b140bef6d821da60dc61d37e59d15c49723329247691dceb` |

artifact 标注到期时间：**2026-11-20 14:32:07（Asia/Shanghai）**。实际下载的内层 ZIP、完整 `package/`、回执及包外参数位于 `C:\dev\Yime-deliveries\18u-arm64-v2-9636eaff-20261106`；该持久本地副本独立于 artifact 到期。Git checkout 不等于收到大包。

已逐文件核验全部 46 文件、39 项产品载荷、38 项安装 descriptor 载荷、前端清单来源/资源哈希、六个 `0xaa64` PE、同源 v2 标记及旧 v1 标记缺失。包内 `Setup.ps1 -Action Check` 经 `run_checked.py --edition ps5` 在华硕通过，退出 0，仅新增诊断日志。详见[下载回执](evidence/arm7-9636eaff/ci-package.json)、[包检查](evidence/arm7-9636eaff/setup-check.log)和[证据哈希索引](evidence/arm7-9636eaff/index.json)。

六个 PE 的签名观测均为 `NotSigned`；这是开发测试包，未建立发布者签名信任。静态架构/哈希及 Check 通过不证明当前主机策略已允许真实宿主加载它。

## 已完成验证

源码 `9636eaff` 的 9 项 CI 全部成功，原始状态见 [CI 快照](evidence/arm7-9636eaff/ci-status.json)：

| 流程 | push | PR |
| --- | --- | --- |
| Build | [PASS 42174743530](https://github.com/tsaanghwang/Yime/actions/runs/42174743530) | [PASS 42174749820](https://github.com/tsaanghwang/Yime/actions/runs/42174749820) |
| Installed 18u compile and offline checks | [PASS 42174743553](https://github.com/tsaanghwang/Yime/actions/runs/42174743553) | [PASS 42174749944](https://github.com/tsaanghwang/Yime/actions/runs/42174749944) |
| Touch terminal prototype | [PASS 42174743528](https://github.com/tsaanghwang/Yime/actions/runs/42174743528) | [PASS 42174749862](https://github.com/tsaanghwang/Yime/actions/runs/42174749862) |
| 18u async route contracts | [PASS 42174743524](https://github.com/tsaanghwang/Yime/actions/runs/42174743524) | [PASS 42174749815](https://github.com/tsaanghwang/Yime/actions/runs/42174749815) |
| CI retention tests | 无此触发 | [PASS 42174749798](https://github.com/tsaanghwang/Yime/actions/runs/42174749798) |

包括原有 x64、ARM64 交叉构建、完整制包/混包拒绝、全部 15 项装配检查（含符号链接夹具）、安装器、Go/race、native、Rust i686 host、三分片真实 Rime 和离线工具链。条件性 one-shot 注册探针未启用，不算执行。CI ARM job 在 x64 runner 上交叉构建，不能作为原生运行或现场证据。

ASUS 原生 ARM64 开发验证见[开发记录](DEVELOPMENT.zh-CN.md)、[初始合同验证](validation.json)和[本次主线整合增量证据](evidence/main45be140e/index.json)。增量前端 31 个顶层/54 个 test/subtest 全通过，包含真实 GDI `FR_PRIVATE` 字体加载/释放三轮 GC 压力；未启动产品窗口或安装系统字体。新增两个检查宿主测试源以独立离线 CMake 在 ARM64 编译并运行通过；正式 Phase A 真实宿主仍保留 x64 门禁。TIP、安装证明和注册工具产品源与此前已测 `cc6a8d18` 无差异。

同一 `9636eaff` 在本机原生工具链重制的完整包为 190971705 字节，SHA-256 `fe6d368953bac6375cf5e8022b9851ffc9939d30ac0ca3f41211f427a89a6489`；[本地回执](evidence/arm7-9636eaff/native-package.json)与[构建范围](evidence/arm7-9636eaff/native-build-scope.json)分别保留。后续现场操作绑定上表的 CI 下载包；原生源码测试不描述为该 CI 二进制已在真实宿主运行。

## 现场接续

2026-11-06 14:31（Asia/Shanghai）只读复核确认已安装版本仍为 `.5`、源码 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`，20 项载荷一致，descriptor SHA-256 `d536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be`，见[原安装核对](evidence/arm7-9636eaff/installed-arm5-readonly.json)。同名候审 `.5`（`e9b9a456`）及本轮 `.6` 均未安装，历史身份不混用。

接续入口为 [ASUS .7 现场步骤](ASUS-ACCEPTANCE.zh-CN.md)：正常 Install 升级及载荷/注册核对 → 明确选择专用 profile → 原生真实宿主自动跟随 → 分开记录手指、笔、屏幕适应/DPI/旋转和标尺。包外 `params/check.json` 与 `params/install.json` 已准备；已执行的是 Check，Install 未执行。

正常维护只处理独立18u，精确识别旧启动项并将旧 `bin` 前端迁到配套 `frontend/`，保留校准、用户数据、默认输入和其他产品。新前端显式启动，无开机常驻承诺。回退需按新包自身正常卸载后再恢复原 `.5` 完整包安排，未验证、不自动执行。

实际升级/回退、安装态宿主加载与编辑、重启、自动跟随及手指/笔仍为 **NOT_RUN**。本次完整包交付不自动执行这些现场操作，也不将鼠标、合成触摸或隔离 EDIT 结果提升为物理验收。
