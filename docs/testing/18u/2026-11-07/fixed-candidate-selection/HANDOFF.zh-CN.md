# x64 与 ASUS ARM64 固定候选选择（2026-11-07）

**后续 x64 使用 main `51fe9788` 的固定发布包；ASUS ARM64 使用 PR #116 已固定的 `.9`。** 这是候选身份与交接入口的统一，不是安装、升级、注册或现场测试指令。旧包、旧计划和原始证据全部保留，不将任何历史结果改记到新包。

| 后续对象 | 选定候选与实际构建源码 | 固定下载 |
| --- | --- | --- |
| 原生 x64 | `0.1.0-18u-test.13`；`51fe9788665d7780a2561d27d5491e361010ecc8` | [main 固定 x64 完整包](https://github.com/tsaanghwang/Yime/releases/download/test-18u-main-51fe9788-20261106/Yime-18u-main-51fe9788-x64-artifact-13502811763.zip) |
| ASUS 原生 ARM64 | `0.2.0-18u-arm64.9`；`0738914afb4e0e9a6c3db5c0f4971a87b915daa8`，基线为上述 main | [PR #116 固定 ARM64 `.9` 完整包](https://github.com/tsaanghwang/Yime/actions/runs/42221809363/artifacts/13503328617) |
| main ARM64 原始归档 | `0.2.0-18u-arm64.8`；`51fe9788665d7780a2561d27d5491e361010ecc8` | [保留原 main ARM64 包](https://github.com/tsaanghwang/Yime/releases/download/test-18u-main-51fe9788-20261106/Yime-18u-main-51fe9788-arm64-artifact-13503075548.zip)，用于固定主线来源对照，不作为 ASUS 下一候选或 `.9` 不可用时的自动替代 |

PR #116 尚未合并（本次核对时 head 为 `eeaa9df1bd99845da75b2e096a9dc830ddab5764`）；这不改变其中已交付 `.9` 的固定源码，也不把它说成 main `51fe9788` 的原字节包。后续文档提交和同名 CI 产物均不更换本页选定对象。

## 两组包的实际差别

`51fe9788 → 0738914a` 共 15 个文件有差异：ARM64 包版本 `.8 → .9`、包内 README/帮助说明、相应版本断言、该分支的 CI 触发，以及交付文档和离线记录。**Go/C++ 的 Runtime、Broker、共享前端、TIP、安装维护脚本和锁定资源没有源码差异。** `.9` 没有在 main `51fe9788` 之上另加运行或维护算法修复。

main `51fe9788` 的双架构包与 `.9` 都包含 PR #113 的 READY 启动编排、Go 构建环境隔离、ARM64 输出路径边界及旧启动项 `EnumValues` 检查。两者保持相同的 READY 含义和首次 `open` 资源检查方式，不引入跨架构回退。不能把这些说成 `.9` 相对 main 包新增的修复；旧 `ac326cba` 的固定 `.8` 才是早于这些后续变化的包。

选择 `.9` 作为 ASUS 后续候选，是为了沿用已有独立版本、完整固定交付及专门接续安排，消除两种 `.8` 的歧义；不是认定 main ARM64 `.8` 缺少上述修复。x64 无需为配齐 ARM64 版本另行制包。重新构建会改变来源标记、清单和二进制哈希，即使运行源码相同，也不承诺字节相同，更不能混装两个包的文件。

逐项对照已有完整核验清单，两份 ARM64 包均为 46 个成员，其中 33 个文件的大小和 SHA-256 相同，包括三份维护脚本、字体、布局、词典及锁。13 个文件不同：六个 PE、包根 README，以及六份来源/版本/哈希元数据；六个 PE 均不能互换。产品 CLSID/profile、描述符 schema、原生 ARM64 架构、CN/variable、`autostart=false` 及前端/TIP v2 协议保持一致。

## x64 唯一接续身份

- 发布 tag：[`test-18u-main-51fe9788-20261106`](https://github.com/tsaanghwang/Yime/releases/tag/test-18u-main-51fe9788-20261106)，指向完整源码 `51fe9788665d7780a2561d27d5491e361010ecc8`；源码 tree 为 `184c0ae0390803cfaa0e6078c48f660cd4af752d`。
- 来源 CI：run `42218452243`、attempt `1`、artifact `13502811763`。Release 资产保留原始 Actions 外层 ZIP 字节。
- 内层文件名：`YimeCore-18u-0.1.0-18u-test.13-windows-amd64.zip`。

| 核验对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 下载的外层 ZIP | 192259508 | `5d873d1ae691dfebaa22f6d4f3f51145656b6c2bd97cd2b835ccc8b5d01a0bb3` |
| 内层完整安装 ZIP | 192220289 | `8eb60b61866f15731b04f69ca72704465784fe8873d4f5f2e9c14e43bf541252` |
| `payload/installed-18u-product.json` | 7383 | `0ebff212c0b7e297588b6b28fc9fa7bf659f13c001b4d1045e6ffebb71c99c24` |
| `package-evidence.json` | 8229 | `00287c8e0ceae2fdc7fe0db05fb22536d515ee86bfca1323a8ef3034326ab43e` |

[发布回执](https://github.com/tsaanghwang/Yime/releases/download/test-18u-main-51fe9788-20261106/delivery.json)、[两层哈希清单](https://github.com/tsaanghwang/Yime/releases/download/test-18u-main-51fe9788-20261106/SHA256SUMS.txt)和[完整核验证据](https://github.com/tsaanghwang/Yime/releases/download/test-18u-main-51fe9788-20261106/Yime-18u-main-51fe9788-verification-evidence.zip)固定了两包各 46 文件、39 载荷、38 描述符条目、六个对应架构 PE、同源前端/TIP v2、维护源码及资源锁检查。证据 ZIP 的 SHA-256 为 `0223de662d93266b2caeb800b82c0e1412be67ff46494180ad459a8266612bc3`。

## ASUS ARM64 唯一接续身份

- 实际构建源码：`0738914afb4e0e9a6c3db5c0f4971a87b915daa8`；不可改记为 main、PR head 或本次文档提交。
- 来源 CI：run `42221809363`、attempt `1`、artifact `13503328617`；制包回执 artifact `13504256836`。
- 内层文件名：`YimeCore-18u-0.2.0-18u-arm64.9-windows-arm64.zip`。

| 核验对象 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 下载的外层 ZIP | 191295875 | `ee2a44e784182801123f440e504a2c6fd9bc662b4e7678170c1da7fc1b9b8adc` |
| 内层完整安装 ZIP | 191254961 | `a2005167942adec6bc69e972fed0fe662aabe9243bf799bf9d68f3dc06d54ff3` |
| `payload/installed-18u-product.json` | 7397 | `0eae014b7dd51a69b3d46dd366f9fbdc2af42ca83f33eee136f20deb1c35bf50` |
| `package-evidence.json` | 8243 | `f0de7a6b8a256ba0420c2adb6be1db0bbc8b70dfd7c5eafb51b5883b1808690c` |

沿用[原 `.9` 完整交付记录](../../2026-11-06/arm64-dot9-delivery/DELIVERY.zh-CN.md)、[固定身份 JSON](../../2026-11-06/arm64-dot9-delivery/delivery.json)与[完整静态核验](../../2026-11-06/arm64-dot9-delivery/evidence/package-verification.json)。本次核对固定 artifact 尚可取得，平台标注到期时间为 **2026-11-20 21:06:08（Asia/Shanghai）**；下载不可用、已过期或哈希不符时停止，重新交接，不自动使用 main `.8` 或另一份 `.9`，也不把这一时间承诺为提前不会被清理。

## 同名历史对象必须分开保存

| 保留对象 | 固定源码／来源 | 内层 ZIP SHA-256 | 本轮定位 |
| --- | --- | --- | --- |
| main ARM64 `.8` | `51fe9788665d7780a2561d27d5491e361010ecc8`；run `42218452243` attempt `1`，artifact `13503075548` | `9d457e5592eedd335f57bfec6d996778b0613a391a6f8b1e7dcb58d63d4d5b9c` | 保留主线双架构原始发布，含 PR #113 后续修复；ASUS 接续选 `.9` |
| 较早固定 ARM64 `.8` | `ac326cbae438fc129e2e2a493b0342a8b8dbd479`；run `42185512418` attempt `2`，artifact `13487852082` | `85191b5c9926c5090ddabc5117fe7e1d43e3981527903c68f3051906cfb50a6c` | 历史候选，不追认后来修复；[原 `.8` 计划](../../2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)不再是当前执行入口 |
| 较早本地 x64 `test.13` | `ff1a3d9269c0061c0582bb2f707cfc2d8a68a6bb`；本地独立交付 | `51d61513811eb1080f2aba30cd01555c52cab5498307cd4d47e720b01cd12a22` | 保留[原候选、独立宿主及 D1/D2 计划](../../2026-11-06/test13-host-font-fixes/DELIVERY.zh-CN.md)，不能与 main 同名包互换 |

main ARM64 `.8` 的外层 ZIP 为 `191295784` 字节，SHA-256 `7568477f3078b486bd287255d8f0da1181235110bd1b4626f3cd1305d4026e69`；内层 `191254763` 字节。其描述符 SHA-256 为 `20ab9e45f5834071f40b98d99d8bb4bedf33691ad1bf110f510130a70cc63854`，与 `.9` 及较早 `ac326cba` 固定 `.8` 的描述符不同。完整清单见同一 main 发布的回执与证据，不以版本号单独识别。

所有候选至少同时核对：架构、完整源码 SHA、run/attempt、artifact 或固定 Release 资产、两层 ZIP 哈希、描述符及完整载荷。独立目录保留各包原文件名和原字节，不覆盖旧目录、不单换 Broker/前端/TIP/Setup，不修改清单或旧宿主门禁使新包勉强匹配。D1/D2 宿主与计划仍绑定原候选；后续如需新包上的 D1/D2，另行明确范围及其固定身份，不自动复用旧计划。

## 验证和后续操作边界

本次比较源码与既有完整包报告，复核固定下载元数据和证据，不重新制包、不执行包内 `Check` 或任何产品程序。两个源码提交各自已有原生 x64/ARM64 的 12 项 Broker 必需离线测试，main 原始日志及 `.9` 来源证据分别保存；不互相继承结果。两份候选均为未签名开发包，完整性核验不建立发布者签名信任。

后续只采用上表的固定候选准备单独操作方案。实际安装、升级、卸载、注册、真实 TIP/宿主及手指/笔验收均未因本页获得执行授权；默认输入法和用户数据保持。ASUS 仍需届时核对真实前态，不能由历史 `.7` 记录推断现在安装了哪个版本。ARM7-UI-01 暂不修改、不继续交互验收的决定保持。

旧 `.7` 成功反馈和未执行项保留[原现场归档](../../2026-11-06/arm64-v2-alignment/ASUS-UPGRADE-RESULT.zh-CN.md)；其执行前方案见[固定 `591cc422` 历史版本](https://github.com/tsaanghwang/Yime/blob/591cc4229915b0c1b481d0e61001df7d63260671/docs/testing/18u/2026-11-06/arm64-v2-alignment/ASUS-ACCEPTANCE.zh-CN.md)。这些记录不是新候选的现场验收，也不要求重跑旧轮次成功项目。
