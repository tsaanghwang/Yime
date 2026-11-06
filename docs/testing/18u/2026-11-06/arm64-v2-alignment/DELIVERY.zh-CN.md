# ASUS ARM64 共享前端 v2 完整包交付

源码开发、原生 ARM64 构建与隔离运行、配套制包、CI 和下载核验已完成。**当前安装仍为旧 `.5`；新 `.6` 尚未安装，真实宿主自动跟随、升级/回退和手指/笔验收均未执行。**

## 固定身份

- 影响产品：独立 `yimecore-18u` / `YimeCore 18u Touch`。
- 固定开发基线：main `39bfc4a34566220af4aba5d7799d12432d8d4013`；分支 `codex/18u-arm64-frontend-v2-20261106`。
- 本次交付的安装器、前端和原生组件源码：`cc6a8d18dd2b78fe7b651f168a690f2c2cd6c96e`。[PR #113](https://github.com/tsaanghwang/Yime/pull/113) 尚未合并；后续文档提交不改变此包身份，也不将后续自动产物替换成本次固定包。
- 版本：`0.2.0-18u-arm64.6`；目标 `windows-arm64` / `native-arm64`；新安装 descriptor 为九字段 `installed-18u-product-v1`，前端通信为 `Yime18u.Frontend.v2.`。两种版本号属于不同合同。
- 五份盘面及编码资源继续使用主线锁；共享自动跟随、屏幕适应、翻页位置和设置暂停实现不另起 ARM 分支。

## 下载与核验

[固定 ARM64 完整包 artifact](https://github.com/tsaanghwang/Yime/actions/runs/42173103035/artifacts/13480869581) 来自 [push CI 42173103035](https://github.com/tsaanghwang/Yime/actions/runs/42173103035)，artifact ID `13480869581`。GitHub 外层 ZIP 内只有下表所列完整安装 ZIP；不要用自动生成的 Source code ZIP 或 x64 包替代。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| GitHub artifact 外层 ZIP | 190631404 | `b6e168efba9646236216d166fa6d1166a9c5147a6732e72d35c1b36f84322de5` |
| `YimeCore-18u-0.2.0-18u-arm64.6-windows-arm64.zip` | 190590785 | `38d8ad3931dc1aaf846040f9dcc6f78307981ccedc59d3620454c1fec1b2a406` |
| 包内 `payload/installed-18u-product.json` | 7397 | `c1baf1105b82a226ce9a8e4a15e804bf21b089868502cbb05761bc481fa6ad14` |

artifact 标注到期时间为 **2026-11-20 14:16:29（Asia/Shanghai）**。已实际下载的本机持久副本和完整解包目录在 `C:\dev\Yime-deliveries\18u-arm64-v2-cc6a8d18-20261106`；内层 ZIP、`package/`、包外 `delivery-verification.json` 与 `params/check.json`、`params/install.json` 分开保存。Git checkout 本身不包含大包。

已核验全部 46 个 ZIP 文件及证据清单、39 项产品载荷、38 项安装 descriptor 载荷、前端清单来源/逐资源哈希、六个 PE 均为 `0xaa64`，前端和 TIP 同源 v2 标记存在且无旧 v1 标记。下载包在本机经系统原生 PS5 的 `Read-Package` / `Assert-PackageHost` 及包内 `Setup.ps1 -Action Check` 均通过；后者仅新增检查日志，没有执行 Install/Uninstall、注册或产品进程。见[下载核验回执](evidence/final-ci-package-cc6a8d18.json)、[包检查记录](evidence/final-setup-check.log)和[证据哈希索引](evidence/final-delivery-evidence-index.json)。

六个程序签名观测均为 `NotSigned`，本包是开发测试交付，未建立发布者签名信任；是否可在具体主机策略下加载须由现场结果确认。

## 构建与测试证据

源码 `cc6a8d18` 的 7 项触发流程全部成功，快照见[CI 状态](evidence/final-ci-status-cc6a8d18.json)：

| 触发 | 流程 | 结果 |
| --- | --- | --- |
| push | [Build](https://github.com/tsaanghwang/Yime/actions/runs/42173103199) | PASS |
| push | [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/42173103035) | PASS；本次固定包来源 |
| PR | [Build](https://github.com/tsaanghwang/Yime/actions/runs/42173108928) | PASS |
| PR | [Installed 18u compile and offline checks](https://github.com/tsaanghwang/Yime/actions/runs/42173109098) | PASS |
| PR | [Touch terminal prototype](https://github.com/tsaanghwang/Yime/actions/runs/42173108921) | PASS |
| PR | [18u async route contracts](https://github.com/tsaanghwang/Yime/actions/runs/42173108718) | PASS |
| PR | [CI retention tests](https://github.com/tsaanghwang/Yime/actions/runs/42173108757) | PASS |

CI 保留 x64 并新增 ARM64 交叉编译、完整前端/TIP/安装制包合同；装配的 15 项检查（含本机权限不足而未能创建的符号链接夹具）在 CI 全量通过。总 Build 的安装器、Go/race、native、Rust i686 host、三分片真实 Rime 和离线工具链通过；条件性 one-shot 注册探针未启用，不记为执行。

ASUS 原生 ARM64 的 Go 合同、六组 C++ 隔离回归、完整资源输入，以及 PS5/PS7 文件/安装合同结果见[开发记录](DEVELOPMENT.zh-CN.md)与 [validation.json](validation.json)。这些是源码级或隔离运行证据，不是已安装 TIP 或真实宿主验收。最后修订仅补旧测试夹具初始化及记录，原生产品代码与 `2b34a22f` 相同。

`cc6a8d18` 也在 ASUS 原生工具链重新制作了本地完整包，大小 190970438 字节、SHA-256 `b26528d6cf66acedf6e8942949b12e29e3c5710bdd96e9aa7aa53774dae62092`，见[本地构包回执](evidence/final-native-package-cc6a8d18.json)及[范围](evidence/final-native-build-scope-cc6a8d18.json)。本地包与 CI 包分别保留；上述下载核验和后续现场步骤绑定 CI 包，不把原生源码测试描述为该 CI 二进制已经在真实宿主运行。

## 旧包与下一阶段

当前已安装 `.5` 声明源码 `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`，20 项载荷在本轮只读复核一致；同名候审 `.5`（`e9b9a456`）仍未安装。首轮 `2b34a22f` 的 `.6` 本地/CI 候选保留原哈希和总 CI 失败记录，不作为最终交付。不要仅凭 `.5`/`.6` 文件名判断身份。

正常升级负责严格识别旧 ARM 清单、移除旧包拥有的 `bin` 前端和精确匹配的旧 Runtime Run 项，部署同源 `frontend/` 与 ARM64 TIP；校准、用户数据、标准 YimeCore、Rime/PIME 和默认输入保持。新前端显式启动，无开机常驻承诺。旧版直接覆盖新目录不是已验证回退。

接续按 [ASUS 现场步骤](ASUS-ACCEPTANCE.zh-CN.md)：正常维护与安装核对 → 明确选中专用 profile → 原生真实宿主自动跟随 → 分别记录手指、笔、显示/DPI/旋转与标尺。包检查已通过，实际 Install/Uninstall、已安装宿主加载/编辑、升级/回退、重启、自动跟随及物理验收全部 **NOT_RUN**。本次源码与交付工作不自动启动这些现场操作。
