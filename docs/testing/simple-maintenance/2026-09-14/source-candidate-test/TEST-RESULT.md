# 源码候选包测试机接收记录

状态：分支同步、完整包接收与 Check 完成；实际安装、输入、重启待用户执行。不得计为已安装或实机验收通过。

- 测试分支：perf/i7-7820x-local；由 8456c419 快进至交接提交 2155f556，无冲突。
- 候选代码提交：a4fa6f7616b41658361a9f5b14ea3c96311ed8b0。
- CI：https://github.com/tsaanghwang/Yime/actions/runs/34856928836，接收时通过 GitHub API 核实 head_sha 匹配、completed/success。
- 包：https://github.com/tsaanghwang/Yime/releases/download/test-simple-source-a4fa6f76/Yime-Source-Candidate-20260914.zip。
- 实际大小：256617810 字节；实际 SHA-256：8474875273b42404e8d1e6a29206216a329aca44e6b01499a0e749170ae3021d，与交接一致。
- 本地入口：C:/Users/Golde/Yime Simple Test Archives/source-candidate-a4fa6f76/extracted/Install-Uninstall.cmd。
- 机器：计算机；本次 Check 日志 Windows NT 版本以原始日志为准。
- 安装前目录：接收时 C:/Program Files/YimeCore 与 C:/Program Files/Yime Rime-PIME 均不存在；未读用户数据，未独立检查安装条目或注册状态。
- 经仓库 run_checked.py 显式 PS5 调用完整包 Manage-Products.ps1 -Action Check -Product both；两个包均 PASS，进程退出 0。原始 Check 日志与来源记录附 raw。
- BUILD-PROVENANCE.json 保留构包时 58e360a5 基础提交及 pending 状态的原始字节；当前开发验收和候选 CI 状态以交接提交内 DEVELOPMENT.md 与本次 CI 查询为准。

## 后续实际验收

1. 保存工作、关闭宿主、切换英文键盘，从资源管理器运行本地入口，Action 1 / Product 3：待执行。
2. 两套分别在 Word 和本机另一常用应用输入并上屏：待执行，实际应用名称待记录。
3. 正常重启登录后两套分别输入：待执行。
4. 本轮结束保留两套安装，不重复历史维护矩阵或做最终卸载。

若安装失败，保留本次父子日志；文件占用或 0x800700B7 按 HANDOFF.md 的限定重试流程处理，不能把重试成功计为首次成功。当前仅完成接收与只读检查，未触发 UAC、安装或注册操作。
