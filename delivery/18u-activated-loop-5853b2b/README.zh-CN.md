# 18u 受保护激活闭环：固定开发测试包交付

这不是安装器、稳定产品或四机通用测试包。只供 **MyComputer 原生 x64** 后续受控验证；EXE/DLL 均未签名。发布/下载不等于授权运行或管理员注册；不得绕过安全保护。

## 固定下载与身份

- [开发预发布 Release](https://github.com/tsaanghwang/Yime/releases/tag/test-18u-activated-loop-5853b2b)
- [唯一命名 ZIP](https://github.com/tsaanghwang/Yime/releases/download/test-18u-activated-loop-5853b2b/Yime18uActivatedLoop-x64.zip)
- 发布工作流成功前，上述链接可能尚不存在；本文件不是发布成功收据。不得改用同名未知包。
- ZIP：`Yime18uActivatedLoop-x64.zip`，**92,104,071 bytes**。
- ZIP SHA-256：`99e0bf8358e5edb54450436cb561a5d49f3efe53f2130455b90af4c6eae204ed`。
- 包内 `manifest.json` SHA-256：`2b455439aa5dd1a2455bc44aa9f58e264ea8481151e903fd7783a1b1c4381013`。
- 包源码：`5853b2bcb0ac0878987e9ca97f4f3a8461a6714f`；实现基线 `e3962604d333df098f31ad689e11801c8b1622c5`。
- [原构建 run 41400229173](https://github.com/tsaanghwang/Yime/actions/runs/41400229173)，artifact `13121197246`。原字节转存，不重建、不改包内清单。外层 Actions ZIP 不是上述内层 ZIP，哈希不可混用。
- 自动生成的 Source code ZIP 只含源码，不是此测试包。克隆本交付分支也不会下载 ZIP。
- 完整机器可读身份见 [package.json](package.json)。实际 Release 资产必须与本页 SHA 匹配。

## 各机当前任务

| 机器 | 本次范围 |
|---|---|
| MyComputer | 可取得命名 ZIP 并核大小、SHA；运行前再确认本轮操作范围。保留旧目录/证据，解压须新独立目录不覆盖。 |
| “计算机”旧 x64 | 待命，不因看到链接自动注册或重复已过测试。 |
| MSI x64 | 待命，不派发本包或笔专项。 |
| ASUS ARM64 | 此包不是原生 ARM64 包，不以仿真运行替代适配验证。 |

没有自动领取/执行任务；不安装调度器，不改既有任务 JSON。

## 执行边界（本页不授权执行）

包内入口需要现有 Python 3.12+。默认 `prepare` 仅静态核包并在全新包外目录生成本地路径清单，不启动 EXE；`preflight` 是另一个显式模式，会启动只读预检进程；`register` 是第三个显式模式，须单独确认管理员注册、真实激活编辑、正常撤销及独立残留核验的范围。不会自动提权或从预检串联注册。

异常/超时停止，保留本次报告与 DPAPI 账本，不重试、不自动恢复，不上传私有账本。恢复仍需单独授权。当前包真实注册/编辑/清理未运行；不能把编译及模拟测试通过视为完整输入、安装或物理验收通过。旧 v2 残留处理不得由本页推定获准。

## 发布机制

交付分支仅通过一次明确确认的 `ci.yaml` 手动入口，将固定 run/artifact 的已核 ZIP 转存为非 latest 预发布。其余 Build/注册/语言任务在本交付分支均跳过；推送不发布、不执行包。

只上传该一个 ZIP，不上传私人日志或账本。先验所有原字节哈希，再创建草稿、上传并读回验证后公开；已有同名 tag/Release 拒绝覆盖。中途失败可能保留草稿，先核查，不自动重跑、删除或覆盖。发布 job 仅使用本次短期 `GITHUB_TOKEN` 的 contents:write/actions:read，不变更仓库全局权限或长期凭据。
