# PR #83 省略号双候选固定CI交付

2026-10-30。两份完整包来自[成功CI run41018028276](https://github.com/tsaanghwang/Yime/actions/runs/41018028276)，均已实际下载。它们是本次固定的PR CI构建；最终main合并未自动重新构建或替换本表身份。

| 身份 | 提交 |
|---|---|
| PR头提交 | `7136cba1c9cececc339fb19da2d81e6789b14617` |
| **包内实际sourceCommit（PR测试合并提交）** | `f01326e6c1976a4e67c9ff59693effc0e1110b1a` |
| 最终main合并提交 | `bbf64dd85a4618c95b03980e61b7b5acab166371` |

manifest须为`sourceChanges:false`。测试结果绑定包内实际sourceCommit与exe哈希，不能把三个提交号互换。

| 目标 | 下载 | ZIP SHA-256 | YimeTouchKeyboard.exe SHA-256 |
|---|---|---|---|
| ARM64原生Windows | [完整ZIP，artifact 12960955078](https://github.com/tsaanghwang/Yime/actions/runs/41018028276/artifacts/12960955078) | `6275aa0fe02f666c31653539386ca374ed70847de51c7cd45223e77b8c0a785d` | `db0a2b141218fa569ad95c71310ba44f53e954bcb9c78c84abf3a0b99b39cf9f` |
| x64 Windows台式机 | [完整ZIP，artifact 12960636900](https://github.com/tsaanghwang/Yime/actions/runs/41018028276/artifacts/12960636900) | `34491c3a8c77e887507f8dd40913eedc66394cf347ee08bb63b8888e948ca2ef` | `0e24a31e2088c5b19e39bae8ac78adcc28a9cb258d2f0034b2addac1ec8cbc07` |

两份ZIP的下载字节哈希与GitHub digest一致，CRC、精确文件集合、manifest内各31个载荷哈希全部核对。PE分别为ARM64 `0xaa64`、amd64 `0x8664`；预览/宿主触屏入口均已核对。本次只做静态下载核验，没有在本机执行这两份新包，不声称ARM64原生或真人验收。

[机器可读身份](package-identity.json)、[ARM64 manifest](ci-arm64-manifest.json)、[x64 manifest](ci-amd64-manifest.json)保留。CI x64资源与三模式检查见[原报告](ci-amd64-package-check.json)，与接收机器自己的Check Package及实际输入结果分开。

ARM64产物到期：`2026-11-13T07:09:16Z`；x64产物到期：`2026-11-13T07:09:05Z`（UTC，约北京时间2026-11-13 15:09）。下载GitHub artifact通常需要已登录、有仓库访问权限的账号；打开链接后下载完整ZIP，临时转存地址不作为交付链接。到期或换构建时更新链接、源码和哈希，不静默换包。

按[执行要求](EXECUTION_REQUIREMENTS.zh-CN.md)先B00—B03，再E01—E12和Word/WOW64；[ARM任务文字](TASK_ARM64.zh-CN.md)、[台式机任务文字](TASK_AMD64.zh-CN.md)可分别复制到接收机器已有任务。各自结果模板为[ARM64](RESULT_ARM64_TEMPLATE.json)、[x64](RESULT_AMD64_TEMPLATE.json)。当前模板全待测，任务准备不等于接收端已执行。

当前没有32位键盘exe交付；x86若指32位应用，使用x64 Windows上的amd64键盘测试WOW64宿主。各机重新量尺，不复制58.8参数。旧包/本机结果不继承，不安装产品、不改默认输入法、用户数据、字体或全局音频设备。
