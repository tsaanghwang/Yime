# 完整旧版升级隔离回归

基线：PR #95 `cf4f371984acc4265305f70c751c11457109eae9`。固定 test.6 原始记录见 [TEST6.zh-CN.md](TEST6.zh-CN.md)；其中真实卸载从 test.5 留下的部分卸载状态开始，不能证明完整旧 profile/category 在场时的正常升级。

`Test-18uUnregisterSequence.ps1` 从实际 `Setup.ps1` 提取 `Set-Registration`，用有状态原生调用替身，从旧 COM、TIP、1 个 profile、5 个 category 全部存在的状态测试注销顺序、独立调用、COM 最后删除、最终不存在核验，以及随后注册新版本。它注入 TIP 注销失败、最终注销失败、模拟新进程 API 仍报告旧状态、最终不存在核验失败、新版本注册失败，并断言后续步骤停止。模型同时保留旧载荷、原始失败证据和独立用户数据的标记。`test_installed_18u_lifecycle.py` 检查实际 Setup 中所有权核验、用户数据重置禁令、卸载先于删除与复制、独立原生调用，以及日志追加路径。

运行：

```text
python tools/powershell/run_checked.py --script installer/simple/tests/Test-18uUnregisterSequence.ps1 --edition ps5
python tools/powershell/run_checked.py --script installer/simple/tests/Test-18uUnregisterSequence.ps1 --edition ps7
python -X utf8 -m unittest tools.yimecore.test_installed_18u_lifecycle -v
```

这仍是模拟原生调用和源码合同检查；未执行真实注册表/TSF 注销、文件升级或系统安装。真实 Windows 从完整旧版状态升级的结果仍待单独授权与记录。此前 test.6 安装、重启和自有宿主输入结果保持原结论。

2026-11-03 本机非系统回归：PS5、PS7 隔离夹具各退出 0；Python 8 项合同检查通过；`git diff --check` 无补丁格式错误。这些结果只支持上述模拟与源码合同范围。
