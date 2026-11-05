# MSI 后续收包身份：main test.12

日期：2026-11-06（Asia/Shanghai）。目标机器：MSI `WIN-JTKUT7KBVN7`，原生 Windows AMD64。本记录补齐后续引用，不是本轮安装或验收指令；当前仅已完成开发端下载和静态核验。

## 唯一固定包

- 产品/版本：独立 `yimecore-18u`，`0.1.0-18u-test.12`。
- 源码 SHA：`36ca828b3531d6c61740e02b6835aa930442b97a`，PR #100 合入 main 的实际提交。
- [完整包下载](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13399696130)：main push run `41993377945`，artifact `13399696130`。
- Artifact 名称：`installed-18u-x64-test-package-36ca828b3531d6c61740e02b6835aa930442b97a`。
- [同源 CI 证据下载](https://github.com/tsaanghwang/Yime/actions/runs/41993377945/artifacts/13400010403)，以及已保存在源码中的 [receipt](ci-36ca828b/package-receipt.json)、[机器可读身份](delivery.json)和 [逐文件验证结果](download-verification.json)。
- 包 artifact 到期：**2026-11-19 16:22:31（+08:00）**；到期后需明确的新交付记录，不能使用同名包代替。

| 待核对对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 下载的外层 Artifact ZIP | 192248008 | `d1465596f8aa7a66a9d378eba38ceaa107736a81f4364ad37448caca4508753c` |
| 内层 `YimeCore-18u-0.1.0-18u-test.12-windows-amd64.zip` | 192209192 | `0dfe9845679a7914cbd530ab6da3ba07aaa976724b3b57149406983bbaa0dc5e` |
| 前端 `payload/frontend/YimeTouchKeyboard.exe` | 7956992 | `d9a15e1e7d6da30d21db32813a92ee2c50df03b8855e0cc05f9f1482b0ffecbe` |
| 专用 TIP `payload/x64/YimeTextService18u.dll` | 714240 | `9193311f4a5b3aaa6e09d8e6b23adb84235444f6bea8610620fd04aaac6c1a7d` |

## 后续使用时的核对顺序

1. 引用以上固定 main SHA、run 和 artifact。PR 临时合并源码 `df3d9351…` 的 artifact `13391537298` 是另一包；test.11 `aed81162…` 保持历史身份。仅同步源码或看到 `test.12` 文件名不能证明收到了本包。
2. 收包时先核对外层大小/哈希，再核对内层大小/哈希和 46 文件清单；核验脚本只读 ZIP，不运行其中的安装脚本、EXE 或 DLL。完整命令接口为 `verification/verify_package.py --artifact-zip <外层ZIP> --artifact-metadata github/artifacts-main.json --ci-receipt ci-36ca828b/package-receipt.json --source-commit 36ca828b3531d6c61740e02b6835aa930442b97a --output <不存在的新输出目录>`，路径相对于本记录目录，使用 Python 执行。依赖的历史核验引擎也在同一源码树中。
3. 前端/TIP 必须整包配套：v2、`Yime18u.Frontend.v2.`、`installed-tsf-auto-focus`、干净同源 manifest。不得只取 EXE/DLL 替换旧安装，或修改 receipt、manifest 使不匹配文件通过。
4. 以后若另行安排安装或真人测试，报告应引用上述源码及内层哈希，单独记录实际机器、已安装状态、宿主和物理输入结果；源码回归与开发端静态核验不能填成 MSI 安装/触控通过。

## 已有证据与未执行范围

五项同源 main CI 全部 success；构建工作流的三个显式注册/语言探针保持关闭。开发端实际核验两层 ZIP、全部 46 文件、六个 AMD64 PE、资源投影和 v2 配套，六项 CI 签名观察均为 `NotSigned`。详见 [完整交付记录及 PR/main 对照](DELIVERY.zh-CN.md)。

本轮未在 MSI 或开发机执行包内程序、安装、注册、默认输入法或用户数据变更；未观察 MSI 当前安装，也未发起重测。旧会话取消、未知结果锁定及禁止旧提交重放的源码合同保留。真实宿主、手指和笔验收必须另记，不沿用 test.11 或旧包结论；标准 YimeCore、Rime/PIME 及其数据不在本交付范围内。
