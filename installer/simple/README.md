# 双独立产品安装与卸载

当前安装入口为本目录。支持 x64 Windows 上的 YimeCore、Rime/PIME 单独安装、单独卸载，以及一次选择安装或卸载两套；x86 指 WOW64 应用支持。ARM64 安装包尚未交付。

## 使用完整包

将完整包解压到本地目录，从 Explorer 打开 `Install-Uninstall.cmd`，选择安装或卸载，再选择 YimeCore、Rime/PIME 或两套。此入口旁必须各有一个所选产品的解压目录，目录内包含 `Setup.ps1` 和 `product-package.json`。不绑定机器名、用户名或仓库路径；使用端不需要 Python、Git 或另一套已安装产品。

选择两套时会先检查两个包，然后逐套执行；第一项失败就停止，明确报告已完成和未执行项目。单产品包仍可直接运行 `Setup.cmd`，或通过 Windows 应用列表卸载已安装产品。

- `Setup.cmd -Action Check`：检查包，不修改系统。
- `Setup.cmd`：安装或重装本产品。
- `Setup.cmd -Action Uninstall`：卸载本产品。
- 显式加 `-ResetData`：同时清空本产品用户数据；默认保留。

安装前保存文档并退出使用该输入法的应用，包括仍在托盘运行的应用。占用提示出现后，释放文件再点击重试；取消会停止当前操作。必要时正常重启后重新运行。安装器不强制关闭文档应用。

两套各自拥有安装目录、私有字体、运行程序、注册项和用户状态；不删除系统字体、不清理另一产品，不改变默认输入法。安装失败后可用完整包重新执行，无需恢复票据或历史进程记录。

## 开发构包

`Build-Package.ps1` 接收 `Product`、`PayloadRoot`、全新的 `OutputRoot` 和 `Version`，只从产品载荷生成完整包；`Build-RimePackage.ps1` 从本仓库构建输出制作 Rime/PIME 包。根目录 `Build.ps1` 先构建再制 Rime/PIME 包。YimeCore 源码构建入口为 `tools/yimecore/build-local-product.ps1`，其输出再交给 `Build-Package.ps1`。

仓库内 PowerShell 操作通过 `python tools/powershell/run_checked.py --script <脚本> --edition ps5 --params-file <UTF-8参数JSON>` 执行。

`Test-Manage.ps1` 检查单套/双套选择和失败停止；`Test-Startup.ps1` 检查临时系统启动项；`Test-Product.ps1` 使用真实包在隔离目录检查文件归属、私有字体占用和重装。它们不代替真实安装、输入和重启验收。

## 交付顺序

开发端本地检查、卸载重装及实际输入验收 → 提交推送 → 对应 CI 成功 → 测试端独立环境安装和卸载验收。使用端只接受完整包，失败由开发端修复后重新交付。生产数据迁移和自动备份恢复留待后续，不作为当前安装前置条件。

本机已通过两套卸载、重装、文件哈希、x64/x86 注册及运行路径检查；用户已确认重启前后两套输入正常。测试端本轮维护验收尚未执行。详见 [本轮交接](HANDOFF.md)。
