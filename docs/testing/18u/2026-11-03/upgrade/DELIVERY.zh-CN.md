# test.5 固定交付

这是已保留的历史包。实际卸载暴露 TSF 同进程枚举缓存问题，test.5 未安装；后续改用 test.6。

- 源码：[fb6e02d1c1f6672eea67ec6585cbf8998b5feb2b](https://github.com/tsaanghwang/Yime/commit/fb6e02d1c1f6672eea67ec6585cbf8998b5feb2b)。
- 专用编译/制包 CI：[41561771397](https://github.com/tsaanghwang/Yime/actions/runs/41561771397)，成功。
- 通用 CI：[41561771447](https://github.com/tsaanghwang/Yime/actions/runs/41561771447)，成功后才执行实机维护。
- 完整包 artifact：[13197431105](https://github.com/tsaanghwang/Yime/actions/runs/41561771397/artifacts/13197431105)。
- 文件：`YimeCore-18u-0.1.0-18u-test.5-windows-amd64.zip`，92,394,077 字节。
- ZIP SHA-256：`a461d4bffbcac1e9471c1e45014483de0b6b9dd9fb3a7194d44f1130ce609d70`。
- 包证据 SHA-256：`fa21aa1e98bebdd159930850ea6d51cbc599456e0bab15e18b0a19dc097425d7`。
- installed descriptor SHA-256：`25068bacdd6f396ae8af6c604dbaa64ac5a3e499b45a314e248cf0816fb29718`。
- 下载目录：`C:\dev\Yime-deliveries\18u-test5-fb6e02d1`；维护入口在 `package\Setup.ps1`。
- 旧 test.2 包保留在 `C:\dev\Yime\installed-18u-bb7-r1\package`，未改写。

GitHub artifact 外层 ZIP 摘要 `8e94539fb846933290c0ae09928e48853122a5126dbcfe946a08cb89d568634d`
与下载字节一致；内层 ZIP 与独立 CI receipt 一致，包内 22 个证据成员逐项一致。
`Action Check` 已通过；五个 PE 的 CI 签名观察均为 `NotSigned`，不声明发布者认证。

机器：MYCOMPUTER，Windows x64；仅独立 `YimeCore 18u Touch`，保留用户数据。
维护前基线在 `C:\dev\Yime-evidence\18u-upgrade-20261103\before.json`：
标准 YimeCore 72 个文件、Rime/PIME 167 个文件，各自注册和默认输入覆盖设置；
独立 18u 用户数据目录存在且为空。维护后比较相同范围，不以其他产品运行状态代替文件/注册证据。

本机维护执行器为同一证据目录下 `maintain.py`，只依次调用受检 PowerShell 的正常
`Check`、`Uninstall`、`Install`，验证旧注册移除、新载荷/注册及保护基线。
其 `maintenance-complete.json` 只证明卸载/安装阶段，`rebootPending=true` 不代表已经重启。
正常重启后，由 `verify_after_reboot.py` 只读验证新 boot time、载荷、注册和保护基线，
生成 `reboot-verified.json` 才可报告重启核验完成。两者均不重新执行旧 test.2 输入用例。
