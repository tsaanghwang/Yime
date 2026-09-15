# CI 固定 7-Zip 准备修复（2026-09-09）

影响范围：Rime/PIME 的 CI 工具准备。产品 Runtime、候选 EXE、既有工具链锁、安装与验收结论均未改变。

## 已确认的失败

提交 `75f27b6353daa9d79ae6e1addc977ad0df4aef90` 的 [Build 34355291018](https://github.com/tsaanghwang/Yime/actions/runs/34355291018) 在 [nsis-preflight 的准备步骤](https://github.com/tsaanghwang/Yime/actions/runs/34355291018/job/102478737342) 失败：`NSIS preparation 7-Zip input differs from the repository-pinned record.`

原脚本直接读取 runner 预装的 `C:\Program Files\7-Zip\7z.exe` 和 `7z.dll`，但要求它们与仓库锁定的 26.02 文件完全一致。CI 没有先准备这些固定文件。日志证明文件不匹配，未记录实际预装版本，因此不推断具体版本。此时尚未解压或编译候选安装包。

本次 native-build、rust-i686-host、go-tests、real-rime-tests、go-race-msys2、lexicon-offline-tooling 和 build-contract 均成功。后续合同与打包被依赖门禁跳过，installer-package/core-build 的失败为汇总结果；不是新的原生编译失败。

## 修复

共享 `prepare-pinned-nsis` action 下载 [官方 7-Zip 26.02 发布资产](https://github.com/ip7z/7zip/releases/tag/26.02)，交给独立准备脚本：

| 输入 | 字节 | SHA256 |
| --- | ---: | --- |
| 独立解压工具 `7zr.exe` | 602112 | `56b8cc9f4971cef253644fafe54063ed7fdca551d4dee0f8c6baa81b855acd72` |
| 仅作为压缩档案读取的 `7z2602-x64.exe` | 1657896 | `6745fa76dc2ea031596d8678f6f6b99c3c1b435b4164a63485adbbc7b8d82ef0` |

两个输入均须先通过固定长度和摘要检查，随后仅执行独立 `7zr.exe`，将精确的 `7z.exe`、`7z.dll` 提取到新的仓库临时目录。输出继续匹配原工具链锁的 EXE/DLL 摘要；NSIS 准备接收该目录并重新持有原始文件读锁，不接受调用者自定摘要，不退回 PATH 或 runner 预装工具。

不执行 7-Zip 或 NSIS 安装程序，不替换系统安装的 7-Zip。NSIS 自身仍按既有 303 文件、17 目录的完整固定树验证；只在 GitHub-hosted runner 内保留原 action 的 NSIS 暂存/重命名流程。本地回归仅操作 `.tmp` 中自有目录。

## 验证

- PS5/PS7：固定 7-Zip 准备各 38/38；使用新解压链的 NSIS 准备各 41/41，共各 79 项。
- 包含同长度篡改 bootstrap、setup、`7z.exe`、`7z.dll` 的拒绝，缺失/重解析输入、已有或非法输出目录保持不变，以及 PATH 不可用时真实解压成功。
- 工作流合同 11/11，actionlint 与构建入口合同通过；双产品来源基线 262 项、77/77 测试、8 项 pending 保持原义。
- 原始结果路径、摘要及最终源码摘要见[证据索引](../testing/dp1/ci-sevenzip-fix-20260909.json)。失败日志原样保留在本机 `.tmp/ci-sevenzip-fix-20260909/failed-nsis-preflight.log`。

本记录的本地成功不代替后续提交的 CI 结果。未重建或重签上轮可执行候选，未运行安装器/卸载器、修改注册、启动产品 Runtime，未触碰 YimeCore local.12、生产 Rime/PIME、默认输入法或用户数据。完整工具链闭包和产品实装验收字段未提升。
