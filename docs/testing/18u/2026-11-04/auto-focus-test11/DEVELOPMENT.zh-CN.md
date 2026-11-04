# test.11 完整包准备：自动跟随与 v2 配套

日期：2026-11-04（Asia/Shanghai）。产品：独立 YimeCore 18u，原生 Windows AMD64。

用户授权合并 PR #99 到 MSI 准备分支，基于合并源码生成新版本完整测试包并交付下载链接和 SHA-256；不安装、不修改输入法注册或默认设置、不重复 test.8 实测。

[PR #99](https://github.com/tsaanghwang/Yime/pull/99) 已合并至 `codex/msi-18u-test-preparation-20261103`，合并提交为 `c0e67e47cbd7128461ac502f7449a2b5146e7fe2`，已验证的 PR head 为 `f3056aab403bd72430ca34357bd4c60631bfefcf`。合并提交不触发旧 test.10 版本打包；后续 test.11 版本提交运行完整 CI 和安装包离线构建。

本次仅更新完整前端包版本为 `0.1.0-18u-test.11`，明确前端自动跟随模式及 v2 协议声明，并在打包时拒绝缺失、旧版或错配协议组件。无前端的历史 test.6 路径、产品 CLSID/profile、标准版与 Rime/PIME 边界保持原合同。

配套证据由同一干净源码提交、前端 manifest、包内清单与逐文件哈希、前端 ASCII/TIP UTF-16LE v2 管道标记及 CI 原生内存协议测试共同构成；二进制字符串检查本身不等于真实宿主协议验收。`installed-18u-product.json` 保留既有严格字段集合。

最终交付记录将固定版本提交、CI run/artifact、外层下载 ZIP 和内层产品 ZIP 的 SHA-256，并验证完整包中的前端、TIP、Broker、Runtime、注册维护工具、资源和安装脚本。构建产物与安装脚本均不在本机执行。

自动跟随的源码行为、安全合同和本地回归见[实现说明](../../../../project/18u-self-developed-integration/AUTO_FOCUS_FRONTEND.zh-CN.md)。未知结果锁定、旧会话取消和禁止重放合同继续保留。

本地离线包装验证：前端配套测试 9 项、无前端历史包装测试 12 项、产品身份测试 3 项通过；既有组装测试 15 项中 14 项通过，`test_linked_input` 在创建测试符号链接时因账户权限返回 WinError 1314，未进入组装逻辑。本轮不修改系统权限、不删除或跳过该检查；现有 CI 仍要求全部 15 项无跳过通过。测试临时目录仅通过进程级 TMP/TEMP 指向本工作树，不修改系统环境。
