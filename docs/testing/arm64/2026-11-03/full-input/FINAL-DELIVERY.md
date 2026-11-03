# ARM64 三产品最终测试包

源码与维护程序提交：`6c1c01220b77406cfa5a90df111ea914882fa372`。
该提交 CI 为 19 项成功、3 项预期的历史手动任务跳过、0 失败；命名测试无跳过。
见 [Build](https://github.com/tsaanghwang/Yime/actions/runs/41653532297) 与 [ARM64 complete input contracts](https://github.com/tsaanghwang/Yime/actions/runs/41653532148)，原始记录为 `final-source-ci.json`。

三个完整包已在[固定测试发行版](https://github.com/tsaanghwang/Yime/releases/tag/test-arm64-complete-6c1c0122-20261103)发布，逐包核对 GitHub 远端大小、SHA-256 和 uploaded 状态后才转为公开预发布。远端回执为 `final-delivery-receipt.json`。未发布的 af92 草稿仍是旧候选，不作为安装来源。

| 产品 | ZIP | 大小（bytes） | SHA-256 |
| --- | --- | ---: | --- |
| 标准 YimeCore | `YimeCore-0.1.0-local.13-main64a785a7-arm64-maint.1-6c1c01220b77.zip` | 168192962 | `a1f6aa2eee5c0f3fd473de81a2218b02557c2b7445a91e47e9d254ac7beb8c6f` |
| 标准 Rime/PIME | `yime-rime-pime-windows-arm64-6c1c01220b77.zip` | 179501174 | `5f01d3e55f24e88075550eea584546319a50c88c6a89aaa0486173d9cd8c3185` |
| 18u 触摸输入 | `yime-yimecore-18u-windows-arm64-6c1c01220b77.zip` | 219896457 | `81ebca8d0c699090765004d78049e766a0516217522df3571d4739e9e1c50da8` |

标准 YimeCore 的 69 个运行时载荷逐字节保留主线 `64a785a7ede5fb2a53e2560b873075950160668b` 构建；其安装/维护代码来自上述 `6c1c0122`，不将运行时来源写为新提交。maint.1 修复旧安装器从管理员子进程启动常驻运行时的问题。原普通用户父进程必须核对 marker、manifest 和全部载荷后启动；直接管理员调用不会冒充普通用户启动。旧 main 安装包保留为历史，当前测试使用 maint.1。

标准 YimeCore 与 Rime/PIME 包含 ARM64 原生运行时、ARM64X 64 位 TSF 与 x86 TSF。18u 当前只提供原生 ARM64 TSF，不能据此宣称 x64/x86/ARM64EC 宿主已兼容。三个产品的身份、布局字典、目录、运行时和用户数据相互独立。

标准版从普通用户 PowerShell 运行包内 `Setup.ps1 -Action Install`。Rime/PIME 与 18u 从普通用户进程运行各自 `YimeMaintenance.exe -action Install`，由维护程序处理同账号 UAC。两个原生维护包各自携带固定的 ARM64 PowerShell 完整依赖，不依赖另一产品或 Store 更新路径。裸运行维护入口默认 Check。

本次已交付的是开发实测包。安装后的实际权限、注册宿主输入、登录/重启及手指/笔结果另记，不从打包或 CI 通过推断。开发 PE 没有公共发行的可信签名。本轮不更改默认输入法，不重置已有用户数据，不自动重启。

项目继续开发价值在于已经落地的编码/词典工具链、独立输入运行时和可复用的故障回归。下一阶段优先测真实应用稳定性与 18u 连续输入体验；多产品、多架构、多语言维护组合已经较大，应由实际误触、故障与输入收益决定新增功能的优先级。18u 当前尚无持久学习，普通标准键盘兼容通过也不代表触摸布局效率通过。
