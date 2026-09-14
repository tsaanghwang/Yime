# YimeCore 产品构包约定

当前安装协议由 [installer/simple](../../installer/simple/README.md) 定义。每包携带自己的运行文件、字典、语流音变资产、私有字体、x64/x86 TSF 和所需注册工具。

源码描述由 `tools/yimecore/local-product.json` 定义；源码构建保持原生产品身份和文件完整性检查。源码包清单与安装包 `product-package.json` 各自描述其实际文件，不能将旧事务或恢复目录作为新包依赖。

安装目录、运行端点、注册标识和可写数据归本产品独有。卸载不删除另一产品或系统字体。显式数据重置仅作用于本产品，正常重装默认保留数据。

通过源码构包或隔离检查不等于安装验收。完整验收包含安装、输入、卸载、重装以及重启后的实际输入，按 [双产品计划](YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md) 执行。
