# MSI main test.12 静态收包报告

2026-11-06（Asia/Shanghai），测试机 **WIN-JTKUT7KBVN7**，Windows 11 `10.0.26300`，AMD64。

**通过：仅静态收包核验，未安装、未注册、未做输入验收。** 固定产品为独立 YimeCore 18u `0.1.0-18u-test.12` / Windows AMD64。下载完成时间为 2026-11-06 07:50:20（+08:00），静态核验器退出码 `0`，状态 `passed`。

## 源码同步与本地工作保留

已先阅读仓库 `AGENTS.md`，检查原工作区分支、提交和未提交内容，再执行普通 `git fetch origin main`。同步到的实际源码提交为 **`1fe1baa49ab1c46f7b73b4a6d7d7e3a2bc1ad2e6`**，即 PR #102 合并提交，祖先检查通过。

原 `C:/dev/Yime` 保留在分支 `codex/msi-18u-test-preparation-20261103`、提交 `1c5b49fe2fce7a8bb1525b56bd5efd0d336d9334`，该分支原有 1 个未推送提交。5 个已修改文件、未跟踪的报告和测试文件均留在原位；本轮前后 Git 状态一致，记录的 **26 个本地文件**大小和 SHA-256 全部不变。未 reset、未 stash、未覆盖或整理历史报告。

为保留这些本地工作，新建独立工作树 `C:/dev/Yime-msi-test12-receipt`，分支 `codex/msi-test12-receipt-20261106`，从已 fetch 的 `origin/main` 创建。本次收包报告位于该工作树；原工作区没有切换到 main。见 [源码同步记录](raw/source-sync.json)、[原状态](raw/original-worktree-before.json)及[字节保留检查](raw/original-worktree-preservation.json)。

已阅读同步树中的 `installer/simple/HANDOFF.md`、[固定交付记录](../main-test12-delivery/DELIVERY.zh-CN.md)和 [MSI 交接](../main-test12-delivery/MSI-HANDOFF.zh-CN.md)。源码同步提交与下述固定包源码提交是两种身份；本次没有替换固定包。

## 固定下载及实测身份

- 包源码 SHA：`36ca828b3531d6c61740e02b6835aa930442b97a`。
- CI run：`41993377945`；artifact：`13399696130`。
- [固定完整包下载](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130)。
- Artifact 名称：`installed-18u-x64-test-package-36ca828b3531d6c61740e02b6835aa930442b97a`。
- GitHub 实时返回 `expired=false`，到期值 `2026-11-19T08:22:31Z`（北京时间 2026-11-19 16:22:31）；与交付目录固定元数据一致。见[实时 API 数据](raw/github-artifacts-live.json)。
- 经 GitHub 连接器下载指定 artifact，并将返回的原始 ZIP 字节保存到本机新目录，未重新压缩。未使用 PR #100 临时合并包 `df3d9351…` / artifact `13391537298`，也未使用 PR #102 或后续 main 构建产物。

| 实测对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 外层 `artifact-13399696130.zip` | 192248008 | `d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c` |
| 内层 `YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip` | 192209192 | `0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e` |
| `payload/frontend/YimeTouchKeyboard.exe` | 7956992 | `d9a15e1e7d6da30d21db32813a92ee2c50df03b8855e0cc05f9f1482b0ffecbe` |
| `payload/x64/YimeTextService18u.dll` | 714240 | `9193311f4a5b3aaa6e09d8e6b23adb84235444f6bea8610620fd04aaac6c1a7d` |

四项均与用户固定身份匹配。两层 ZIP 原字节均保留，来源下载记录见 [download.json](raw/download.json)。

## 静态核验结果

使用同步树交付目录的原有 `verification/verify_package.py`，配套 `github/artifacts-main.json` 和 `ci-36ca828b/package-receipt.json`；显式传入完整包源码 SHA `36ca828b3531d6c61740e02b6835aa930442b97a`，输出目录执行前不存在。未修改核验脚本、清单或 receipt。完整实参和退出码见 [verification-command.json](raw/verification-command.json)，[标准输出](raw/verification.stdout.log)和[标准错误](raw/verification.stderr.log)按原字节保留。

| 核验项 | 结果 |
| --- | --- |
| 外层 ZIP | 大小、SHA-256、GitHub digest 和 CRC 全部匹配；唯一内层 ZIP 名称正确 |
| 内层 ZIP | 大小、SHA-256 与 CI receipt 匹配；CRC 通过 |
| 完整清单 | 全部 46 文件的路径、大小和 SHA-256 通过；无缺失或额外文件 |
| 六个 PE | 全部 AMD64 `0x8664` / PE32+ `0x020b`；六项记录哈希与实际成员匹配 |
| 锁定资源 | 四个锁定数据文件、三模式词典、前端和宿主资源投影、resources.lock 全部匹配 |
| 同源前端/TIP | 元数据 v2，`Yime18u.Frontend.v2.`；前端 ASCII 与 TIP UTF-16LE v2 标记存在，无 v1 标记 |
| 前端模式与来源 | `installed-tsf-auto-focus`、`sourceChanges=false`、`sendInputFallback=false`；manifest、descriptor、receipt 和 CI 绑定固定源码及 run |
| CI 签名观察 | 六项均 `NotSigned`、签名者指纹为空；CI 和包内 signatures JSON 内容一致 |

详细结果见[静态核验原始报告](raw/download-verification.json)及[46 文件清单](raw/verified-file-inventory.json)。签名记录是 CI 已有观察，本机仅静态比对，未调用包内程序或本机 Authenticode 检查。**SHA-256 一致仅固定文件身份，发布者签名信任未建立（`publisherTrust=not-established`）。** CI 和包内 signatures 原字节分别保存，不统一其换行。

## 本机保存位置

- 新建下载目录：`C:/dev/Yime-deliveries/msi-test12-receipt-20261106/`。
- 原始外层：`C:/dev/Yime-deliveries/msi-test12-receipt-20261106/artifact-13399696130.zip`。
- 核验输出：`C:/dev/Yime-deliveries/msi-test12-receipt-20261106/verification/`。
- 原始内层：`C:/dev/Yime-deliveries/msi-test12-receipt-20261106/verification/YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip`。
- 原始完整结果：`C:/dev/Yime-deliveries/msi-test12-receipt-20261106/verification/download-verification.json`。
- 源码报告：`C:/dev/Yime-msi-test12-receipt/docs/testing/18u/2026-11-06/msi-test12-receipt/`。

报告目录只保存小型证据副本及[SHA-256 索引](evidence-index.json)，两层大 ZIP 留在上述独立目录。`raw/**` 使用本目录 `.gitattributes` 的 `-text`，保留原始证据字节；包内产品文件没有展开到可运行的安装目录。

## 本轮范围

**仅静态收包核验，未安装、未注册、未做输入验收。** 未运行包内 Setup、Check Package、启动器、EXE 或 DLL；未安装、升级、启动输入法或改变默认输入法、用户数据及现有安装。未执行真实宿主、手指或笔验收，未继承 test.11 的验收结论。当前安装状态未检查，不据此推断其版本或可用性。本轮结束于收包记录，不自动进入安装阶段。
