# DP1-F：Rime/PIME 全量构包前复制暂存

日期：2026-09-06。影响产品为独立的 Rime/PIME；YimeCore 是必须保持不变的另一产品。本批只建立源码／已编译构建输入到仓内 `.tmp` 隔离暂存树的合同，没有运行安装器、卸载器、native registration probe、已安装 Runtime 或真实应用，也没有读写注册表、Profile、真实进程或用户数据。

## 本批结果

当前 `x86,x64` 构包 profile 的 175 个复制输入已全部显式化：166 个持久安装命名空间文件与 9 个 `$PLUGINSDIR` bootstrap helper。166 项中包括 148 项 Go 构建树文件、顶层 metadata／许可证、x86 launcher 以及 x86／x64 TextService；9 项为 5 个 PowerShell 维护 helper 和 4 个注册／TextService PE。暂存复制不使用 wildcard，源 Go 树会在 spec 封存后做 exact-set 复核，新增非 PE、备份、日志或其他目录文件均拒绝。

[`rime-pime-package-staging.ps1`](../../tools/dual-product/rime-pime-package-staging.ps1)将生成前 spec、可移植 copied-content manifest 和本机 observation 分开。spec／manifest 不含时间、绝对路径或 file ID；内容树用长度分帧 SHA-256。observation 单独保存 stage 路径和本机 file ID，不能充当跨复制内容身份。PS 5.1 与 PS 7 对真实树生成相同的 spec SHA-256 `f52d6dc33b73f4ccbc1550dcdbbe5884a414b5d0d349d42ac982fdd8922ba78d`、manifest SHA-256 `1f260bd73ba0307782c302e88312f3557ce8d706f30369c512ee3d289ef4625b` 和 content-tree SHA-256 `bec8f30e0d85c854dda9da3b70e26bd6b752fcd89684bbe6572038ab291151b2`；两个仍同时存在的副本具有不同 local-observation 摘要，证明后者没有混入可移植身份。

目录策略固定为 `derived-nonempty-only-v1`：只创建文件实际需要的 16 个非空祖先目录，两个命名空间根另计；源构建树中的空目录不会进入 stage，stage 中额外空目录会失败。复制后的 175 个文件共 161,138,955 字节，均复核路径大小写、bytes、SHA-256、唯一 file ID、link count=1、仅 `::$DATA`，并完成两遍闭树比较。

这仍不是最终 payload closure。`Uninstall.exe` 作为唯一待生成特殊输出，必须在本阶段不存在；没有零字节占位，也没有用调用方提供的裸 hash 假装可信身份。只有后续构包期生成、独立 Authenticode／VERSIONINFO 验证及 receipt 绑定后，它才可进入最终 manifest。

## 实际发现并处理的回归

1. **DP1-PACKAGE-ADS-01（完整根重建复核待办）**：第一次真实 spec 封存拒绝 `go-backend/build/go-backend/input_methods/yime/icons/yin.png`，因为可丢弃构建副本继承了一个名为 `Zone.Identifier`、大小 128 字节的备用数据流。只读取了流名称和大小，没有读取内容。仓库源文件的主数据 SHA-256 为 `ca61581f0d13d0a4e1281dbe602ad55a02697d52318a541cc6f492ab05d2b275`，源文件及其流未改。`go-backend/build.bat` 现在在 `xcopy` 后仅对可丢弃构建副本执行 `Unblock-File`；stage 仍拒绝所有残留 ADS。本次精确清理当前构建副本后，两版 shell 的真实 stage 通过；尚未为这一小改动重跑完整根构建，因此不把 full rebuild 记为完成。
2. **DP1-STAGE-PS51-02（已关闭）**：Windows PowerShell 5.1 在参数默认表达式中取得空 `$PSScriptRoot`，runner 尚未读源就退出。默认 plan 路径改为参数绑定后解析，随后 PS 5.1 真实 175 项 stage 通过。
3. **DP1-STAGE-JSON-03（已关闭）**：PS 5.1 与 PS 7 的 `ConvertTo-Json` 排版不同，导致同一 spec／manifest 的文件 hash 不同；内容树 digest 本身相同。新 staging 链改用确定性、整数限定、UTF-8 无 BOM、LF 结尾的 JSON 写入器；重跑后 spec、manifest 和内容树三种 digest 跨 shell 全部一致。

## 回归证据

[`test-rime-pime-package-staging.ps1`](../../tools/dual-product/test-rime-pime-package-staging.ps1)在 PS 5.1 与 PS 7 各通过 21/21。负例覆盖：闭合源树新增／缺失文件、源 hash 漂移、错误外部 seal、case-fold 目标冲突、stage 多／少／改文件、额外空目录、伪造 `Uninstall.exe` 占位、缺／旧 sidecar、hardlink、ADS、二遍插入竞态、非新鲜 stage 以及 canonical JSON 字节稳定性。所有夹具都在全新的 `.tmp/dual-product` 根中；没有 silent skip。

真实当前树在两个 shell 中各独立复制一次，均为 175 文件、16 个声明目录、161,138,955 字节，spec／manifest／内容摘要完全一致。源码基线同步扩大为 94 个明确来源，37/37 纯合同测试通过；`test-build-guards.ps1 -SkipPackagedRime` 通过，并固定构建副本的 Zone.Identifier 规范化源锚点。精确文件、路径、摘要与布尔边界见[结构化证据](../testing/dual-product/2026-09-06-dp1-f.json)。

## 下一顺序与硬阻断

下一项是从 sealed manifest 确定性生成分调用点的 NSIS `File` 宏，让 `installer.nsi` 只读 stage，移除产品载荷的 `File /r` 与仓库相对 `File`；build wrapper 在 `makensis` 前后复核同一 stage。随后才对新构包做静态解包 exact-set 比较，并单独建立可信 `Uninstall.exe` 生成／签名／验身份合同。

在完成上述接线、完整 compiler-input 闭包、持久 prepared／commit journal、精确 removal／recovery、crash replay 和签名流程之前，installer／uninstaller 四处运行时硬阻断及 tagged-release 阻断必须保留。当前 NSIS 尚未消费本 stage；已有 unsigned disabled installer 不能因本批结果获得新身份，也没有被运行。

## 已安装与用户边界

当前日用 YimeCore local.12、生产 Rime/PIME、默认输入法、用户正文、设置、学习及冻结历史载荷均未读取、启动或修改。local.13 未安装。本批不宣称 DP1、DP2、DP3、L5 或 L6 完成。
