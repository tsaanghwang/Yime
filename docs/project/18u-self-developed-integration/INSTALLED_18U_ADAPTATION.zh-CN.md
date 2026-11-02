# 独立 18u：复用现有安装流程的最小接入候选

基线：`d5204c46826c4fd8814b5e673f07cd6dbf32a210`。本页是开发候选，不是已通过 Windows 安装或重启验收的交付。

## 复用与新增边界

- 复用 `installer/simple` 的包校验、同用户提升、产品目录归属、卸载／重装、文件占用等待及 Apps 卸载入口。标准 `yimecore` 和 `rime-pime` 保持现有入口。
- 复用 `cmd/yimecore-trial-runtime` 的 Windows Job 和子进程生命周期；同源码以独立构建锁生成 `Yime18uInstalledRuntime.exe`。不新建恢复引擎或云端服务。
- 复用 `YimeTouchRegisteredFormalHostTests` 及已存在的专用 Broker／布局加载器。安装与验收分开：安装不启动测试宿主，不增加启动项。
- 仅增加 `yimecore-18u` x64 产品、受限持久注册工具与显式安装后验收模式。CLSID `6DFACE1F-562E-4773-A9D6-D5753A314711`，profile `1BD904AC-3194-4419-B70A-5574100F18B3`，语言 `0804`。
- 安装目录 `%ProgramFiles%\YimeCore 18u Touch`，用户目录 `%LOCALAPPDATA%\YimeCore 18u Touch`；不复用标准索引、标准/Rime 运行数据。首片 CN/variable，其他模式及任意应用日用输入未验。

## 构建连接（本轮没有执行 Windows 命令）

在固定提交完整源码树、新的独立构建目录中，MSVC x64 配置打开 `YIME_TOUCH_PRODUCT`、`YIME_TOUCH_REGISTERED_FORMAL_HOST` 和 `YIME_18U_PRODUCT_REGISTRATION`；**不要打开**临时注册 probe、MyComputer Stage1 或 registry fixture。只显式编译 DLL、`Yime18uProductRegistration`、`YimeTouchRegisteredFormalHostTests` 三目标，不执行它们。纯规则目标 `Yime18uProductRegistrationPolicyTests` 不访问 Windows 注册表，可以单独离线运行。

Go 分别编译 `./cmd/yimebroker-18u` 为 `YimeBroker18u.exe`，以及 `./cmd/yimecore-trial-runtime` 为 `Yime18uInstalledRuntime.exe`；后者必须带 `-ldflags='-X main.installed18uOnly=1'`。18u 构建裸启动必须拒绝，不得回退标准运行模式。

用 `tools/yimecore/assemble_installed_18u.py` 的显式 `--repo --native --go --data --output --source-commit` 参数，将以上新构建二进制与固定 18u 数据组合成**全新**载荷目录；脚本只复制和读取，不执行载荷。`--data` 必须是该源码的隔离 18u 生成字典目录，绝非标准数据目录。脚本不下载／派生／修改字典，运行时 canonical loader 仍核对专用内容锁。

随后通过既有 `installer/simple/Build-Package.ps1 -Product yimecore-18u -PayloadRoot ... -OutputRoot ... -Version ...` 构造包。PowerShell 开发执行必须走仓库 `tools/powershell/run_checked.py`。

`installed-18u-product.json` 是包内源提交声明、全载荷 SHA-256 与资源范围清单，**不是代码签名或独立发布者证明**；外层包仍需固定发布源码、CI、ZIP 哈希及签名状态。原 `18u-touch-product.json` 的历史未验标记保持，不把新增连接代码当真实安装已通过。

## 将来获准的安装与验收顺序

1. 保留已验证的旧**同产品**安装包，核新包来源、哈希、架构、签名和 `Setup -Action Check`。首次独立 18u 没有旧同产品版本；回退为正常卸除 18u，保留日用标准 pr88/Rime，不将它们当 18u 旧包。
2. 经单独授权，现有 Setup 安装／重装仅该产品。预存非本安装目录身份或未知注册状态停止，不先卸其他输入法。自身正常卸载必须先归属核验，撤销自身 profile/category，最后 COM，并检查残留；任何失败停止，不能继续删程序文件或盲目重装。
3. 保存工作，按另行批准的计划正常重启；安装脚本不重启、不改默认输入法／显示语言／区域，不卸载其他 TIP。
4. 重启后显式运行 `Yime18uInstalledRuntime.exe --installed-18u-check --install-root <已安装目录> --manifest-sha256 <独立交付锚> --evidence-dir <全新包外目录> --confirm once-installed-18u-host`。这只做该自有宿主的一次受控输入验收，不注册／卸载。记录实际激活身份、Broker 单次编辑、宿主读回及子进程退出；失败不循环。它不是任意 Word/Edge 或完整触摸前端接入已验。
5. 正常卸载／重装沿用原维护入口；保留用户数据，本片不开放 `ResetData`。未知残留不泛删，不自动恢复。旧包回退也须正常卸载新版本后再安装旧版，失败停报。

## 当前未验证

Windows/MSVC 构建、实际持久注册、组件初始化、重启后激活、原生宿主读回、正常卸载及残留观察均须后续单独验证。离线模拟与源码审查不能替代这些结果。没有改动用户机器或远端分支，也没有自动继承之前临时 probe 的成败。

源码审阅限制：注册过程部分失败可能保留本产品新记录；本片不承诺自动回滚或自动修复这种状态。发生后停报，不把“重装策略”解释为可跳过未知归属检查。注册表末次查询与逐键删除之间仍非原子，不能并发运行维护或声称竞态已消除。

安装后验收的 180 秒预算只覆盖宿主／Broker 子进程阶段；此前静态文件哈希及 canonical 输入准备不计入该预算，不声称全流程 180 秒硬上限。运行时验证受信清单列出的每个载荷及必需路径，不把安装后的整个目录称为原始包全集合（安装器会添加 `.setup` 和 `.yime-product.json`）；额外文件不作为本次执行或词典路径。打包时的原始 payload 仍要求完整集合与资源锁匹配。
