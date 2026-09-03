# 音元拼音：本机候选包

仅限 MYCOMPUTER 原生 x64。可安装不等于已经通过安装、真实宿主或日常使用验收。

不依赖源码仓库、Go/CMake/Python 或预装 Rime/PIME。保留现有试验版的内部标识和用户数据目录，不新增第三个输入法。生产 Rime/PIME 和 Windows 默认输入法不变；冻结的 x86 注册如仍指向旧安装目录，该目录必须保留，不代表 x86 已通过验证。

## 使用

从资源管理器打开普通权限的独立 Windows PowerShell，进入本包目录；不要预先选择“以管理员身份运行”。安装入口自行请求同账户 UAC，并保留原普通用户进程，供运行时安全启动使用。不要在 Codex 等打包应用的终端中安装、卸载、备份或恢复；AppData/注册表虚拟化可能隐藏修改，脚本会拒绝。不要改用其它 Windows 账户提升权限。

- `./Maintain-YimeCore-Local.cmd`：只读安装计划。
- `./Install-YimeCore-Local.cmd`：安装或原位升级，维护阶段请求同账户管理员权限，日常 runtime/Broker 使用普通用户令牌；完成后显示 `PASS` 或 `BLOCKED` 并等待确认，不自动重启。自动化内部调用使用 `/nopause`。
- `./Maintain-YimeCore-Local.cmd -Action Verify`：当前安装包、进程身份和三模式验证。
- `./Maintain-YimeCore-Local.cmd -Action Backup`：关闭 Word 和所有输入法设置工具后，将停写快照保存到用户目录下的 `YimeCore Recovery Archives`。
- `./Maintain-YimeCore-Local.cmd -Action Restore -BackupRoot "完整归档路径"`：对刚完成的备份进行安全恢复演练。若备份后已有新学习、词库或设置变化，将拒绝覆盖；不是任意历史版本的强制回滚入口。归档中保留恢复前原件。
- `./Maintain-YimeCore-Local.cmd -Action Uninstall`：卸载本机 x64 产品，保留用户数据及冻结架构仍引用的旧文件。也可通过 Windows 已安装的应用卸载。

安装独立开发版后，使用本包维护入口；不要混用仓库根目录旧的 `Upgrade-YimeCore-Trial.cmd`，它对应另一种 Trial 构包流程。

备份包含用户数据及当前完整安装包。恢复入口不覆盖当前 runtime 路径、注册或其它诊断状态。空白配置尚无持久化学习日志时，不应将其报告为“日志恢复已通过”；需要先产生正常学习记录。旧归档的 `previous-package` 是原字节恢复材料，含绑定原安装路径的元数据，不可直接当作重打包发行包。

Word 打开后不会自动选中此输入法。请用任务栏输入法按钮选择“音元拼音”；不要选择保留给冻结旧架构的“Yime 自研栈试验版”，也不需要修改默认输入法。Computer Use 的 Alt+Space 可能打开 Word 系统菜单；任务栏跨窗口点击限制须与产品故障分开记录。

裸数字始终用于组字；Shift+1 到 Shift+9 选词。候选标签保持 ⇧1 到 ⇧9。

签名证书正在申请，等候审批，暂缓相关事项。清单哈希只证明文件一致性，不是可信发布者签名。不面向公众发行。ARM64、x86、其它机型、硬件模拟、联网同步及新语境音变规则均冻结或暂缓。
