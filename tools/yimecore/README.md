# YimeCore 源码构建与实验工具

安装、卸载、重装入口统一为 [installer/simple](../../installer/simple/README.md)。本目录保留引擎、Broker、原生 TSF、语流音变和平台实验的源码构建及隔离验证工具。历史安装事务和恢复链已从当前工作树移除，历史版本可由 Git 查询。

- `build-local-product.ps1`：构建当前产品标识的 x64 runtime 和 x64/x86 TSF，运行隔离检查。
- `build-local-x86-surface.ps1`：构建当前标识的 WOW64 表面。
- `run-platform-experiment.ps1`：已批准平台的隔离源码实验，跨编译不等于实机验收。
- `run-connected-speech-admission.ps1`、`run-connected-speech-product-source.ps1`：语流音变源数据与产品导出。
- `build-system-observation.ps1`：只读系统注册和路径观察，供源码构建及历史只读对照使用。

构建输出先通过检查，再交给 `installer/simple/Build-Package.ps1` 制包。源码实验的机器范围不限制已制成的通用 x64 安装包；安装包运行不需要本目录脚本。

所有 PowerShell 调用使用仓库 checked 入口。源码构建不操作当前已安装产品，用户授权的维护验收另行执行。仅有隔离结果不能声明原生安装或输入成功。
