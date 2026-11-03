# MyComputer 独立 18u 正常升级

## 09:53 正常卸载暴露的新阻塞及修复

test.5 同源完整 CI 已通过并交付，实际执行 `Action Uninstall`，文件释放检查通过。
五项 UnregisterCategory 和 UnregisterProfile 均 S_OK，持久 TIP 已移除；
同一进程最终枚举仍为 5 categories / 1 profile，触发 `final-API-absence-before-COM` 的
`0x8000FFFF`，退出 1。COM、全部旧文件和卸载项保留；没有执行 Install。

随后独立新进程只读 status 为 `com_registered=true`、`tip_registered=false`、
`profile_count=0`、`categories_registered_count=0`。这确认本次为进程内 TSF 枚举缓存滞后，
不是 DLL 占用或权限。旧文件树与两个标准产品文件树仍与维护前完全相同。

修复正常卸载：新增 `unregister-tip` 完成有所有权的持久 TIP 注销，明确报告 COM 保留、
仍需完成。Setup 随后启动独立 `unregister` 进程，重新验证安装绑定/所有权、
持久状态和最终 API 缺失，最后删除 COM；最后仍执行 `verify-absent`。
没有放宽 FinalApiAbsent、没有通用注册表清理、没有隐藏失败/轮询/整次自动重试。
任一阶段失败停止。安装和标准产品路径不变。

新完整候选包改为 test.6；test.5 包及失败证据保留。
新增 PS5/PS7 实际 Setup 函数的模拟调用顺序及各阶段失败回归；
native CLI policy 覆盖新操作，生命周期静态契约保护 COM 保留和最终缺失门槛。
须待 test.6 同源 CI、完整包交付后再从已确认的部分卸载状态正常续行。

原始证据目录 `C:\dev\Yime-evidence\18u-upgrade-20261103`：
`uninstall.stdout.log`、`uninstall.stderr.log`、`uninstall-exit.json`、
`post-uninstall-failure-status.stdout.log` 和 `maintenance-failure.json`。
安装器原日志 `C:\Users\tsaan\Yime Setup Logs\0f7bdf715dfc4b8baa7259b15ec2545a.admin.log`。

以下为首次准备与已完成的历史阶段，不能把 test.5 写成已安装。

本轮接续 PR #95。用户已明确授权修复、正常卸载、升级和必要的正常重启；
不重复请求同一授权。保留 test.2 旧包、用户数据、标准 YimeCore/Rime 和此前成功证据。
不得强杀系统或文档宿主、放宽权限、通用清理注册表或覆盖加载中的 DLL。

## 已核对

- 01:40 的 test.3 安装在文件独占读写检查停止，尚未注销或复制新版。
  原日志 `C:\Users\tsaan\Yime Setup Logs\08f5becfdd704afaad4d1519cfbff0ae.admin.log` 保留。
- 当前安装 test.2，16 个清单载荷和维护资源校验通过；COM 路径及卸载版本一致。
- 07:26 已正常启动过系统。09:43 管理员只读探测：DLL 独占读写打开成功，
  未写入字节；Restart Manager 和管理员模块枚举均未检出占用者。
  原始结果 `C:\dev\Yime-evidence\18u-upgrade-20261103\admin-precheck.json`。
- 当前 ACL 未见异常。原失败日志丢失错误码和进程快照，无法追认当时具体占用者；
  非管理员 error 5 不能用于解释原管理员失败。当前无需修改权限或关闭系统进程。
- 原 test.2 DLL/Broker + 修复开发宿主的成功输入读回证据保留，不重复排查。

## 修复与验证

`Product.psm1` 保留文件释放门槛及注销/删除/复制顺序。失败时输出完整路径、
原始异常类型、HRESULT、Win32 代码，分辨共享/锁冲突、拒绝访问及其他错误。
拒绝访问可能来自 ACL 或映射镜像，不能只凭 error 5 判定权限问题。
Restart Manager 仅查询 PID、进程开始时间、应用/服务和 session，不调用关闭/重启接口。
查询失败或没有结果均不放行文件打开失败。

本地 PS5、PS7 隔离回归通过：真实共享锁、同名不同路径、原始错误码、只读属性拒绝、
加载私有 DLL 副本、释放后通过、查询失败仍拒绝、文件缺失；没有触及已安装产品。
另通过 6 项生命周期源码契约、12 项制包测试、11 项所有权用例、日志和 profile 移除失败回归。
CI 增加上述检查；新完整包版本 test.5，包含 PR #95 宿主修复，不修改旧包。

## 获准的执行顺序

1. 提交并推送，等待同一源码的 CI 和完整 test.5 artifact；核对下载 ZIP、清单、签名记录及载荷哈希。
2. 记录标准产品、独立 18u 用户数据、注册及默认输入设置基线。
3. 使用 test.5 的正常 Setup `Action Uninstall` 移除旧 test.2；不传 ResetData。
   确认独立 18u 注册和安装目录移除，用户数据及其他产品未改变。
4. 使用同一完整包正常 `Action Install`，核对新版本、注册、所有载荷及维护入口。
5. 保存阶段记录和接续入口，正常重启（不用强制关闭应用）。
   重连后核对实际启动时间、新版安装身份和注册；新包实际输入检查单独记为新证据。

若维护时再次占用，保留原错误和查询结果，正常退出具体文档应用；系统宿主持有时
取消维护并正常重启后续行。单独卸载也使用相同文件门槛，不以卸载绕过占用检查。
若出现权限、身份、哈希或其他新错误，按实际原因处理，不能反复运行或静默重装。
源码/CI 通过不代表安装或重启验收通过；阶段结果在交付后补充。
