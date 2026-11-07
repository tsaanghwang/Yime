# 独立 18u 持久安装开发候选包

版本：0.1.0-18u-test.12；仅原生 Windows x64，安装后检查仍为中文 variable；触控前端支持三模式和 CN/EN。
这是复用 installer/simple 的独立 18u 产品，不是标准键盘版、Rime/PIME、
PR87 预览包或临时注册诊断包。保留原产品与各自数据、注册身份。

CI 仅构建与静态制包，下载、解压不代表已通过实机验收。
在已获授权的设备上，按固定交付说明执行正常卸载、安装和重启；
同一任务已有的授权不需重复确认。其他设备的安装仍需对应授权。
注意 Setup 默认 Action=Install，会请求 UAC 提权；没有参数不等于只读。
维护操作语义：
- Setup.ps1 的 -Action Check：核对包和原生宿主架构；会写安装日志，
  不是注册/激活验收。
- -Action Install：管理员持久安装独立 18u 及注册，不能当静态检查。
- -Action Uninstall：按所有权移除独立 18u，保留个人数据；不支持 ResetData。
这些操作应经仓库受检 PowerShell 入口和固定交付步骤执行。

固定安装目录：%ProgramFiles%\YimeCore 18u Touch
独立用户数据目录：%LOCALAPPDATA%\YimeCore 18u Touch
Setup 日志：%USERPROFILE%\Yime Setup Logs
CLSID：{6DFACE1F-562E-4773-A9D6-D5753A314711}
Profile：{1BD904AC-3194-4419-B70A-5574100F18B3}；语言 0804。
不要把标准版或 Rime 的安装目录、配置和数据复制进此目录。

维护顺序：先核对固定交付哈希及签名状态，再运行获准的维护操作；
Install 内部依次注销旧版、移除旧载荷、复制并注册新版。
注销 TIP 后，由独立的新进程复核 API 缺失并完成 COM 注销，避免同进程 TSF 枚举缓存误报；
任一阶段失败均保留文件，不跳过最终缺失检查。
需要独立卸载时使用 Action Uninstall，保留旧包及用户数据后再 Install。
安装日志和退出状态须明确。文件占用时取消，保存工作后正常重启，再维护；
不强杀系统或文档宿主、不放宽权限、不覆盖已加载 DLL。
日志记录完整路径、HRESULT/Win32 错误及 Restart Manager 占用查询；
拒绝访问不自动等同 ACL 错误，未查到进程也不能放行失败的文件检查。
重启沿用任务授权，Setup 本身不会自动重启。
重启后先确认仍为同一固定安装、中文输入环境和独立 18u 身份，
再按授权显式启动一次新包的已安装宿主验收，使用全新包外证据目录。
未知、残留、身份不符或验收失败时保留证据，不自动重试或重装。
Setup 不自动启动验收或开机常驻。本包新增 frontend/ 完整触控 UI 与 TSF 接入候选；不包含 Word/Edge 或物理验收通过结论。

包中的安装后验证入口仅供以后明确授权：Yime18uInstalledRuntime.exe
显式 installed-18u-check 模式，使用独立清单哈希和全新证据目录。
该流程使用真实已安装 TSF 实例、自有宿主、一次 Broker 编辑及独立读回；
这里描述的是实现目标，不是本次已执行或已通过的实机结果。
正常结束仅停止本轮进程，不卸载持久安装的 profile。

package-evidence.json 记录源码提交及所有其他文件的大小、SHA-256；
signatures.json 是 Windows Get-AuthenticodeSignature 对六个 PE 的只读结果。
非 PE 文件未做 Authenticode 验证，不能视为已签名。哈希不是发布者签名；
即使某项 Valid，也不意味着整个开发包或安装体验已获得认证。
包清单本身的 SHA-256 与 ZIP SHA-256 应从独立交付记录核对。

本轮不建立新的备份/恢复系统。后续回退沿用旧包重装，保留用户数据；
首次独立 18u 没有旧版时只能按获准说明卸载独立 18u，不影响标准/Rime。
安装失败需保留证据并停止，不能承诺自动回滚或重复注册。

安装完成后，从安装目录 frontend/Start Installed Touch Keyboard.cmd 启动。完整语义和限制见 frontend/USER_GUIDE.zh-CN.md。

本包前端与专用 TIP 同源配套使用 v2 协议，不与旧 v1 组件混用。选择专用18u输入法并在宿主正文放置光标后，键盘自动跟随，无需日常手动绑定。
焦点变化会取消旧组合与触点；未知提交结果保持锁定。核对正文后点“核对后继续”只接受新输入，旧提交永不重放。
