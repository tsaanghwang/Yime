# 独立 18u 安装测试包 bb7cc13

这是现有 CI 产物的原字节下载交付，不重建、不执行。不是稳定版本，也不是旧 9d3ab3a 激活身份诊断包。旧 prerelease 保持不变。

## 固定下载身份

- 源提交：`bb7cc136c284a5d5ee3a764749119b0b423da482`
- 构建：[41472435711](https://github.com/tsaanghwang/Yime/actions/runs/41472435711)，artifact `13156106297`
- 新 prerelease 标签：`test-18u-installed-bb7cc13`
- 唯一资产：[YimeCore-18u-0.1.0-18u-test.2-windows-amd64.zip](https://github.com/tsaanghwang/Yime/releases/download/test-18u-installed-bb7cc13/YimeCore-18u-0.1.0-18u-test.2-windows-amd64.zip)
- 大小：`92365687` bytes
- SHA-256：`8e3dd31fd74df54a091afa3cf2e1806422f5d1e15b1a4fcb8260e43fb6ca1ea3`
- `package-evidence.json` SHA-256：`e133ea4531139cdddfa48213481c83ee11172aa9fcc1f6213a6ff03c584b0484`
- `payload/installed-18u-product.json` SHA-256：`89928fe4c4496462d9198e4be9be28b72ddb9816594b6eab7986fac766844adf`

此文档是固定发布计划，不是发布成功收据；只有工作流完成并核对实际 Release/资产后，链接才可视为交付完成。不要下载自动生成的 Source code ZIP 代替测试包。

## 范围与停止边界

仅 MyComputer 原生 x64 先行；其它机器待命，ARM64 不适用。五个 PE 均为 CI 只读观察的 `NotSigned`，哈希不是数字签名或发布者认证。

已核 23 个包文件、16 个安装载荷、独立身份、完整资源锁、PE 架构及签名字节对应；编译与非注册测试通过。不代表安装、注册、重启、真实已安装 TSF 激活或一次编辑读回已经通过。

**当前发布/下载授权不包括运行或安装。不要双击 Setup.cmd 或执行 Setup.ps1：默认 Action=Install，可能请求管理员提权。** 不运行注册工具、宿主或 runtime。安装、重启、安装后一次宿主验收分别等待明确步骤和授权；异常停止，不自动重试。

包内 README 说明后续 Check/Install/Uninstall 语义及独立目录。Check 也会写日志，不是本次自动执行项。Setup 不自动运行验收，不设置 18u 开机常驻。该包尚非完整日用触摸界面，不声称 Word/Edge 或全量物理输入覆盖。

18u CLSID `{6DFACE1F-562E-4773-A9D6-D5753A314711}`，Profile `{1BD904AC-3194-4419-B70A-5574100F18B3}`；语言 0804、CN variable。标准自研版、Rime/PIME 及各自用户数据保持独立。不新增备份/恢复体系；将来回退沿用旧包重装，个人数据保留。

## test.2 范围

本版基于已验证的维护生命周期候选6ab6c6b，bb7cc13仅更新版本和恢复静态制包。保留旧399f/test.1。33项Python、PS5/PS7各11项文件系统夹具、Go非注册测试和MSVC编译通过；不代表MyComputer现有残留已经处理或安装故障已实机修复。不要双击Setup；正常维护/重装/重启另行确认。不安排其他三机安装。
