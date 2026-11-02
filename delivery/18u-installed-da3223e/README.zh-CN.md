# 独立 18u 安装测试包 da3223e

这是现有 CI 产物的原字节下载交付，不重建、不执行。不是稳定版本，也不是旧 9d3ab3a 激活身份诊断包。旧 prerelease 保持不变。

## 固定下载身份

- 源提交：`da3223e5674b34a998397abdae3c960c7df6468e`
- 构建：[41489164563](https://github.com/tsaanghwang/Yime/actions/runs/41489164563)，artifact `13163697007`
- 新 prerelease 标签：`test-18u-installed-da3223e`
- 唯一资产：[YimeCore-18u-0.1.0-18u-test.3-windows-amd64.zip](https://github.com/tsaanghwang/Yime/releases/download/test-18u-installed-da3223e/YimeCore-18u-0.1.0-18u-test.3-windows-amd64.zip)
- 大小：`92389894` bytes
- SHA-256：`3c0071396dade94a8e3743d68efc8856bba0eec74ee9c52a1c240876dec84328`
- `package-evidence.json` SHA-256：`7a67cbc3992cc671230604e015cded9a876bd6768c874858b1ae649b55bcbd01`
- `payload/installed-18u-product.json` SHA-256：`1106cc8efaa0ecc877eb81baa9ecabb7b04773a4d2e05a2a38982087009dad7e`

此文档是固定发布计划，不是发布成功收据；只有工作流完成并核对实际 Release/资产后，链接才可视为交付完成。不要下载自动生成的 Source code ZIP 代替测试包。

## 范围与停止边界

仅 MyComputer 原生 x64 先行；其它机器待命，ARM64 不适用。五个 PE 均为 CI 只读观察的 `NotSigned`，哈希不是数字签名或发布者认证。

已核 23 个包文件、16 个安装载荷、独立身份、完整资源锁、PE 架构及签名字节对应；编译与非注册测试通过。不代表安装、注册、重启、真实已安装 TSF 激活或一次编辑读回已经通过。

**当前发布/下载授权不包括运行或安装。不要双击 Setup.cmd 或执行 Setup.ps1：默认 Action=Install，可能请求管理员提权。** 不运行注册工具、宿主或 runtime。安装、重启、安装后一次宿主验收分别等待明确步骤和授权；异常停止，不自动重试。

包内 README 说明后续 Check/Install/Uninstall 语义及独立目录。Check 也会写日志，不是本次自动执行项。Setup 不自动运行验收，不设置 18u 开机常驻。该包尚非完整日用触摸界面，不声称 Word/Edge 或全量物理输入覆盖。

18u CLSID `{6DFACE1F-562E-4773-A9D6-D5753A314711}`，Profile `{1BD904AC-3194-4419-B70A-5574100F18B3}`；语言 0804、CN variable。标准自研版、Rime/PIME 及各自用户数据保持独立。不新增备份/恢复体系；将来回退沿用旧包重装，个人数据保留。

## test.3 范围

本版基于诊断提交 583aa751；da3223e 仅更新版本和恢复静态制包。新增固定枚举的 Action/Poll 拒绝、焦点/会话世代、传输/Broker 分类及宿主脱敏失败响应记录，不记录正文或候选内容，不改变输入语义、身份/焦点门、重试或安装策略。

保留 test.1 与 test.2。test.2 在 MyComputer 安装和重启已由用户回报成功，但宿主在 connected 后出现 engine input E_ABORT；本版用于区分拒绝分支，**不是已确认根因或已验证修复**。此前机器结果不自动继承为 test.3 实机验收。完整流程仍待另行授权验证，不安排其他三机安装。
