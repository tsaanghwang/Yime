# Yime 构建、交付与签名

当前安装工程是 [installer/simple](../installer/simple/README.md)。YimeCore 与 Rime/PIME 各自完整制包；可单选，也可用共同菜单选择两套。简版工程没有正式签名发布流水线，CI 绿色不表示签名发行包已经生成。

## 开发构建

按 `tools/toolchain.lock.json` 准备工具链，执行 `python tools/verify_toolchain_lock.py`。Win32 PIMELauncher 使用固定的 `stable-i686-pc-windows-msvc` host 工具链与 Corrosion v0.6.1。Go EXE 版本来自 `version.txt`，构建保持 `-trimpath -buildvcs=false`；依赖来源及资源哈希按现有构建入口验证。

Rime/PIME 从根目录 `Build.ps1` 构建并制包；YimeCore 先用 `tools/yimecore/build-local-product.ps1` 构建独立载荷，再交给 `installer/simple/Build-Package.ps1`。仓库内 PowerShell 均通过 `tools/powershell/run_checked.py` 执行。包清单是各产品的 `product-package.json`，不能继续使用已退役的 NSIS 清单或事务收据。

每套包应包含自己的运行程序、所需依赖、字典、语流资产、私有字体和 x64/x86 注册组件。不得从另一套已安装产品取文件。安装根分别为 `C:\Program Files\YimeCore` 和 `C:\Program Files\Yime Rime-PIME`。

## 分支交付

开发端构建、验证后推送；对应 CI 成功再通知测试端。说明、测试数据和报告通过 [分支交接](../installer/simple/HANDOFF.md) 提交。完整安装包使用 GitHub Actions artifact 或 Release asset，分支内记录真实下载地址、文件名、大小、SHA-256、安装脚本提交和运行载荷来源。不要把仅有源码或只有单产品的 CI 制品称为完整双产品包。

开发包使用明确的 `-dev` 标识。复用已验收载荷时逐项说明来源，不能以新的安装脚本提交冒充全部程序的构建来源。产物失效或尚未上传时明确标记未交付，由开发端补发，测试端不自行制包。

## 正式签名发行

公开发行前需要受 Windows 信任的代码签名，覆盖实际启动和加载的内部 EXE/DLL。现有 Go 构建保留 `YIME_SIGN_CERT_SHA1`、`YIME_SIGNTOOL_EXE`、`YIME_TIMESTAMP_URL` 及 `YIME_RELEASE_SIGNING_REQUIRED` 支持；这不等于完整简版包已签名。正式发布前应实现并验证整包签名流程，记录验证结果；不要宣称 `v*` 标签现已自动完成该流程。

未签名包限当前开发与受控测试使用。版本资源和自签名证书不能替代公开发行所需的信任。保管签名凭据，不提交私钥、PFX 或密码。

## 安装验收与维护

依据 [测试指南](YIME_TESTING_GUIDE.md) 检查构建和安装文件一致、原生注册、实际组字/候选/上屏及重启后输入。单套维护时确认另一套仍可输入；两套选择应分别报告完成与失败。

文件占用时让用户保存并退出应用、重试或取消；必要时正常重启后维护。更换版本使用所需完整包重新安装。默认保留本产品用户数据，显式 `-ResetData` 可清空测试数据；生产数据迁移与自动备份恢复另行规划。
